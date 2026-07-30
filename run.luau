--!strict
--
-- run
--
-- Unified CLI entry point for the test runner.
-- Supports server mode (default) and headless/CI mode.
--
-- Usage:
--   lune run test-runner/run                      -- server mode  (web UI on :8080)
--   lune run test-runner/run -- --headless        -- headless, terminal output + exit code
--   lune run test-runner/run -- --ci              -- alias for --headless
--   lune run test-runner/run -- --port 9090       -- override port  (server mode only)
--   lune run test-runner/run -- --json            -- headless + write results.json
--   lune run test-runner/run -- --no-preprocess   -- skip Python pipeline step
--   lune run test-runner/run -- --help            -- print this usage
--

--
-- REQUIRES
--
local process = require("@lune/process")

--
-- LOCAL FUNCTIONS
--

--
-- Checks whether a given flag is present in the CLI args.
--
local function Has_Flag(flag: string): boolean
    for _, v in ipairs(process.args) do
        if (v == flag) then
            return true
        end
    end
    return false
end

--
-- Returns the value of a flag that takes an argument (e.g. --port 8080).
--
local function Flag_Value(flag: string): string?
    for i, v in ipairs(process.args) do
        if (v == flag) then
            local next_val = process.args[i + 1]
            if (next_val ~= nil) and (not next_val:match("^%-")) then
                return next_val
            end
        end
    end
    return nil
end

--
-- VARIABLES
--
local headless     = Has_Flag("--headless") or Has_Flag("--ci")
local json_out     = Has_Flag("--json")
local no_preproc   = Has_Flag("--no-preprocess")
local port_str     = Flag_Value("--port")
local seed_str     = Flag_Value("--seed")
local examples_str = Flag_Value("--examples")
local show_help    = Has_Flag("--help") or Has_Flag("-h")

--
-- CONSTANTS
--
local HELP_TEXT = [[
Usage:
  lune run test-runner/run [-- <flags>]

Flags:
  --headless, --ci     Run in terminal mode (no HTTP server).
                        Exits 0 (all pass) or 1 (any failure).
  --port <N>           HTTP server port override (default: 8080). Server mode only.
  --json               Write results.json after the run. Headless mode only.
  --no-preprocess      Skip the Python source-rewriting pipeline.
  --seed <N>           Deterministic seed for property-based tests.
  --examples <N>       Examples per given() block (default: 100).
  --help, -h           Print this message.

Examples:
  lune run test-runner/run                         Server mode on :8080
  lune run test-runner/run -- --headless           CI / terminal mode
  lune run test-runner/run -- --headless --json    CI mode + JSON output file
  lune run test-runner/run -- --port 9090          Server on custom port
  lune run test-runner/run -- --no-preprocess      Skip preprocessing step
  lune run test-runner/run -- --headless --seed 42 Reproducible property tests
]]

if (show_help) then
    print(HELP_TEXT)
    process.exit(0)
end

--
-- Constants — patch port before Server module is loaded
--
local Constants = require("./Constants")

if (port_str ~= nil) then
    local port_number = tonumber(port_str)
    local is_invalid  = (port_number == nil) or (port_number < 1) or (port_number > 65535)

    if (is_invalid) then
        warn(("run: invalid --port value: %q  (expected 1-65535)"):format(port_str))
        process.exit(1)
    end

    Constants["PORT"] = port_number
end

if (seed_str ~= nil) then
    local seed_number = tonumber(seed_str)
    local is_invalid  = (seed_number == nil) or (seed_number < 0)

    if (is_invalid) then
        warn(("run: invalid --seed value: %q  (expected a non-negative integer)"):format(seed_str))
        process.exit(1)
    end

    Constants["SEED"] = seed_number
end

if (examples_str ~= nil) then
    local examples_number = tonumber(examples_str)
    local is_invalid      = (examples_number == nil) or (examples_number < 1)

    if (is_invalid) then
        warn(("run: invalid --examples value: %q  (expected a positive integer)"):format(examples_str))
        process.exit(1)
    end

    Constants["EXAMPLES"] = examples_number
end

--
-- Step 1: Python preprocessing pipeline
--
if (not no_preproc) then
    print("[1/2] Running test pipeline ...")
    local result = process.exec("python3", {
        "./test_runner/Parse_Scripts_For_Tests.py",
        Constants["SOURCE_FOLDER"],
        Constants["OUTPUT_FOLDER"],
        "--project-mocks",
        Constants["MOCK_LIBS_FOLDER"],
    })

    if (result.stdout ~= "") then
        print(result.stdout)
    end

    if (result.stderr ~= "") then
        warn(result.stderr)
    end
else
    print("[1/2] Skipping Python pipeline (--no-preprocess)")
end

--
-- Step 2a: Server mode (default)
--
if (not headless) then
    print("[2/2] Starting server ...")
    local Server = require("./Server")
    Server.Print_Startup_Info()
    Server.Start()
    return
end

--
-- Step 2b: Headless / CI mode
--
local fs          = require("@lune/fs")
local serde       = require("@lune/serde")
local Test_Runner = require("./Test_Runner")

local BAR = string.rep("-", 60)

print("[2/2] Running tests (headless) ...")
print(BAR)

Test_Runner.on(function(event: string, payload: {[string]: any})
    if (event == "run:start") then
        local file_count = payload.file_count :: number
        print(("Found %d test file(s)"):format(file_count))
        print()

    elseif (event == "suite:start") then
        local file_name = payload.file :: string
        print(("  SUITE  %s"):format(file_name))

    elseif (event == "test:done") then
        local status = payload.status     :: string
        local name   = payload.name       :: string
        local ms     = payload.duration_ms :: number

        local label: string
        if (status == "pass") then
            label = "[PASS]"
        elseif (status == "fail") then
            label = "[FAIL]"
        else
            label = "[SKIP]"
        end

        print(("    %s  %s  (%.1f ms)"):format(label, name, ms))

        if (status == "fail") and (payload.error ~= nil) then
            local error_text = tostring(payload.error)
            for line in error_text:gmatch("[^\n]+") do
                print(("           %s"):format(line))
            end
        end

        if (payload.seed ~= nil) then
            print(("           seed: %s"):format(tostring(payload.seed)))
        end

    elseif (event == "suite:done") then
        local suite  = payload.suite :: any
        local counts = suite.counts

        if (suite.load_error ~= nil) then
            print(("         ERROR: %s"):format(suite.load_error))
        end

        -- Per-describe / per-it errors not sent through test:done
        local function Print_Node_Errors(nodes: {any}?, indent: string?)
            local inner_indent = indent or "         "

            for _, node in ipairs(nodes or {}) do
                if (node.status == "fail") and (node.error ~= nil) then
                    local error_text = tostring(node.error)
                    for line in error_text:gmatch("[^\n]+") do
                        print(inner_indent .. line)
                    end
                end

                if (node.children ~= nil) then
                    Print_Node_Errors(node.children, inner_indent .. "  ")
                end
            end
        end

        if (suite.load_error == nil) then
            Print_Node_Errors(suite.nodes, "  ")
        end

        print(("         -> %d passed, %d failed, %d skipped"):format(
            counts.passed, counts.failed, counts.skipped))
        print()

    elseif (event == "run:done") then
        local total   = payload.total       :: number
        local passed  = payload.passed      :: number
        local failed  = payload.failed      :: number
        local skipped = payload.skipped     :: number
        local ms      = payload.duration_ms :: number

        print(BAR)
        local verdict: string
        if (failed > 0) then
            verdict = "FAILED"
        else
            verdict = "PASSED"
        end
        print(("%s  |  %d passed  %d failed  %d skipped  %d total  (%.0f ms)"):format(
            verdict, passed, failed, skipped, total, ms))
        print(BAR)
    end
end)

-- Run synchronously (no server needed in headless mode)
Test_Runner.Run_Tests()

-- Write results.json when --json is given
if (json_out) then
    local write_ok, write_err = pcall(function()
        fs.writeFile("results.json", serde.encode("json", Test_Runner.results))
    end)

    if (write_ok) then
        print("Wrote results.json")
    else
        warn(("Could not write results.json: %s"):format(tostring(write_err)))
    end
end

-- Exit 0 = all green, 1 = any failure
if (Test_Runner.results.failed > 0) then
    process.exit(1)
else
    process.exit(0)
end
