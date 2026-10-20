--!strict
--
-- Sandbox
--
-- Loads a Luau test file into an isolated environment.
--
-- Handles two authoring styles:
--
--   STYLE A — Legacy "return function" (original prototype style):
--     A file that returns a callable.  The callable is invoked; if it returns
--     "Passed" / "Skipped" the test passes / is skipped; any error or return
--     of "Failed" is a failure.  Wrapped into a single synthetic `it` node.
--
--   STYLE B — TestEZ describe/it:
--     A file that uses the injected describe/it/expect globals.  Produces a
--     full tree of nodes via testez_compat.
--
-- In both styles `require` is replaced with a path-aware implementation that
-- resolves relative paths from the test file's own directory and falls back to
-- Lune's native require for `@lune/...` built-ins.
--

--
-- REQUIRES
--
local fs             = require("@lune/fs")
local luau           = require("@lune/luau")
local task_lib       = require("@lune/task")
local TestEZ_Factory = require("./testez_compat")
local Generators     = require("./generators")
local Constants      = require("./Constants")

--
-- EXPORT TYPES
--
export type SandboxResult = {
    ok    : boolean,
    err   : string?,
    nodes : {TestEZ_Factory.TestNode},
}

--
-- LOCAL FUNCTIONS
--

--
-- Normalises a path by resolving "." and ".." segments.
--
local function Normalise(path: string): string
    local parts: {string} = {}

    for seg in path:gmatch("[^/\\]+") do
        if (seg == "..") then
            local parts_count = #parts

            if (parts_count > 0) and (parts[parts_count] ~= "..") then
                table.remove(parts)
            else
                table.insert(parts, seg)
            end
        elseif (seg ~= ".") then
            table.insert(parts, seg)
        end
    end

    local result = table.concat(parts, "/")

    if (path:sub(1, 1) == "/") then
        result = "/" .. result
    end

    return result
end

--
-- Returns the parent directory of a given path.
--
local function Dirname(path: string): string
    return path:match("^(.*)[/\\][^/\\]*$") or "."
end

--
-- Module cache shared across a single sandbox-run cycle.
--
local module_cache: {[string]: any} = {}

--
-- Clears the module cache (called between test runs).
--
local function Clear_Module_Cache()
    module_cache = {}
end

--
-- Creates a path-aware require function rooted at the given base directory.
--
local function Make_Require(base_dir: string)
    local function Sandbox_Require(mod_path: string): any
        -- Lune built-ins pass through unchanged.
        if (mod_path:sub(1, 6) == "@lune/") then
            return require(mod_path :: any)
        end

        -- Resolve relative to the caller's directory.
        local resolved: string

        if (mod_path:sub(1, 1) == "/") then
            resolved = Normalise(mod_path)
        else
            resolved = Normalise(base_dir .. "/" .. mod_path)
        end

        -- Try with and without extensions.
        local candidates = { resolved, resolved .. ".luau", resolved .. ".lua" }

        local found_path: string? = nil

        for _, candidate in ipairs(candidates) do
            local check_ok, _ = pcall(function()
                if (fs.isFile(candidate)) then
                    found_path = candidate
                end
            end)

            if (check_ok) and (found_path ~= nil) then
                break
            end
        end

        if (found_path == nil) then
            error(("module not found: %s  (resolved to %s)"):format(mod_path, resolved), 2)
        end

        local cache_key = found_path :: string

        if (module_cache[cache_key] ~= nil) then
            return module_cache[cache_key]
        end

        local source       = fs.readFile(cache_key)
        local child_dir    = Dirname(cache_key)
        local child_req    = Make_Require(child_dir)

        local env: {[string]: any} = {
            require      = child_req,
            assert       = assert,   error  = error,   pcall  = pcall,
            xpcall       = xpcall,   type   = type,    typeof = typeof,
            tostring     = tostring, tonumber = tonumber,
            print        = print,    warn   = warn,
            pairs        = pairs,    ipairs = ipairs,  next   = next,
            select       = select,
            rawget       = rawget,   rawset = rawset,  rawequal = rawequal,
            rawlen       = rawlen,
            setmetatable = setmetatable, getmetatable = getmetatable,
            math = math, string = string, table = table, os = os,
            task = task_lib,
            Enum = {
                SortDirection = {
                    Ascending  = "Ascending",
                    Descending = "Descending",
                },
                CompressionAlgorithm = {
                    Zstd = { Name = "Zstd", Value = 0 },
                },
            },
        }

        local compile_ok, chunk_or_err = pcall(function()
            return luau.load(source, { debugName = cache_key, environment = env })
        end)

        if (not compile_ok) then
            error(("compile error in %s: %s"):format(cache_key, tostring(chunk_or_err)), 2)
        end

        local chunk    = chunk_or_err :: () -> any
        local exec_ok, exec_result = pcall(chunk)

        if (not exec_ok) then
            error(("runtime error in %s: %s"):format(cache_key, tostring(exec_result)), 2)
        end

        module_cache[cache_key] = exec_result

        return exec_result
    end

    return Sandbox_Require
end

--
-- MODULE DEFINITION
--
local Sandbox = {}

function Sandbox.clear_cache()
    Clear_Module_Cache()
end

--
-- Runs a single test file in an isolated sandbox.
--
-- Parameters:
--     path          (string)   - Full path to the test file.
--     file_name     (string)   - Short filename for display.
--     on_test_done  (function?) - Optional per-test completion callback.
--
-- Returns:
--     SandboxResult
--
function Sandbox.run(
    path         : string,
    file_name    : string,
    on_test_done : ((any) -> ())?
): SandboxResult
    local source: string
    local read_ok, read_err = pcall(function()
        source = fs.readFile(path)
    end)

    if (not read_ok) then
        return { ok = false, err = tostring(read_err), nodes = {} }
    end

    local base_dir = Dirname(path)

    -- Determine seed for property-based tests
    local configured_seed = Constants["SEED"]
    local seed_value: number

    if (configured_seed ~= nil) then
        seed_value = configured_seed :: number
    else
        seed_value = math.floor(os.time() * 10000 + os.clock() * 10000) % 2147483647
    end

    local examples_value = Constants["EXAMPLES"] or 100

    local testez = TestEZ_Factory.new(seed_value, examples_value)

    if (on_test_done ~= nil) then
        testez.set_on_test_done(on_test_done)
    end

    local env: {[string]: any} = {
        require      = Make_Require(base_dir),
        -- TestEZ globals
        describe     = testez.describe,   xdescribe  = testez.xdescribe,
        it           = testez.it,         test       = testez.it,
        xit          = testez.xit,        SKIP       = testez.xit,
        beforeEach   = testez.beforeEach, afterEach  = testez.afterEach,
        beforeAll    = testez.beforeAll,  afterAll   = testez.afterAll,
        expect       = testez.expect,
        -- Property-based testing globals
        given        = testez.given,
        g            = Generators,
        -- Standard globals
        assert       = assert,   error  = error,   pcall  = pcall,
        xpcall       = xpcall,   type   = type,    typeof = typeof,
        tostring     = tostring, tonumber = tonumber,
        print        = print,    warn   = warn,
        pairs        = pairs,    ipairs = ipairs,  next   = next,
        select       = select,
        rawget       = rawget,   rawset = rawset,  rawequal = rawequal,
        rawlen       = rawlen,
        setmetatable = setmetatable, getmetatable = getmetatable,
        math = math, string = string, table = table, os = os,
        task = task_lib,
        Enum = {
            SortDirection = {
                Ascending  = "Ascending",
                Descending = "Descending",
            },
            CompressionAlgorithm = {
                Zstd = { Name = "Zstd", Value = 0 },
            },
        },
    }

    local load_ok, chunk_or_err = pcall(function()
        return luau.load(source, { debugName = file_name, environment = env })
    end)

    if (not load_ok) then
        return {
            ok    = false,
            err   = ("Compile error in %s: %s"):format(file_name, tostring(chunk_or_err)),
            nodes = {},
        }
    end

    local chunk         = chunk_or_err :: () -> any
    local exec_ok, exec_result = pcall(chunk)

    if (not exec_ok) then
        return {
            ok    = false,
            err   = ("Runtime error collecting %s: %s"):format(file_name, tostring(exec_result)),
            nodes = {},
        }
    end

    -- Style A: legacy "return function()"
    if (type(exec_result) == "function") then
        local t0         = os.clock()
        local call_ok, call_result = pcall(exec_result :: () -> any)
        local dur_ms     = (os.clock() - t0) * 1000

        local status: "pass" | "fail" | "skip"
        local err_msg: string?

        if (not call_ok) then
            status  = "fail"
            err_msg = tostring(call_result)
        elseif (call_result == "Skipped") then
            status = "skip"
        elseif (call_result == "Failed") then
            status  = "fail"
            err_msg = "Test returned 'Failed'"
        else
            -- "Passed", nil, or any other truthy value -> pass
            status = "pass"
        end

        local node: TestEZ_Factory.TestNode = {
            type        = "it",
            name        = file_name:gsub("%.luau?$", ""):gsub("_", " "),
            status      = status,
            error       = err_msg,
            duration_ms = dur_ms,
            children    = nil,
        }

        if (on_test_done ~= nil) then
            on_test_done(node)
        end

        return { ok = true, err = nil, nodes = { node } }
    end

    -- Style B: TestEZ describe/it
    local run_ok, run_err = pcall(function()
        testez.execute()
    end)

    if (not run_ok) then
        return {
            ok    = false,
            err   = ("Execution error in %s: %s"):format(file_name, tostring(run_err)),
            nodes = {},
        }
    end

    return { ok = true, err = nil, nodes = testez.get_results() }
end

--
-- RETURN VALUE
--
return Sandbox
