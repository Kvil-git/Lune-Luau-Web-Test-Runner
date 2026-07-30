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

local process = require("@lune/process")

--------------------------------------------------------------------------------
-- Argument parsing                                                             --
--------------------------------------------------------------------------------

local args = process.args

local function has_flag(flag: string): boolean
    for _, v in ipairs(args) do
        if v == flag then return true end
    end
    return false
end

local function flag_value(flag: string): string?
    for i, v in ipairs(args) do
        if v == flag then
            local next_val = args[i + 1]
            if next_val and not next_val:match("^%-") then
                return next_val
            end
        end
    end
    return nil
end

local headless     = has_flag("--headless") or has_flag("--ci")
local json_out     = has_flag("--json")
local no_preproc   = has_flag("--no-preprocess")
local port_str     = flag_value("--port")
local seed_str     = flag_value("--seed")
local examples_str = flag_value("--examples")
local show_help    = has_flag("--help") or has_flag("-h")

--------------------------------------------------------------------------------
-- Help text                                                                    --
--------------------------------------------------------------------------------

local HELP = [[
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

if show_help then
    print(HELP)
    process.exit(0)
end

--------------------------------------------------------------------------------
-- Constants — patch port before Server module is loaded                       --
--------------------------------------------------------------------------------

local Constants = require("./Constants")

if port_str then
    local n = tonumber(port_str)
    if not n or n < 1 or n > 65535 then
        warn(("run: invalid --port value: %q  (expected 1–65535)"):format(port_str))
        process.exit(1)
    end
    Constants["PORT"] = n
end

if seed_str then
    local n = tonumber(seed_str)
    if not n or n < 0 then
        warn(("run: invalid --seed value: %q  (expected a non-negative integer)"):format(seed_str))
        process.exit(1)
    end
    Constants["SEED"] = n
end

if examples_str then
    local n = tonumber(examples_str)
    if not n or n < 1 then
        warn(("run: invalid --examples value: %q  (expected a positive integer)"):format(examples_str))
        process.exit(1)
    end
    Constants["EXAMPLES"] = n
end

--------------------------------------------------------------------------------
-- Step 1: Python preprocessing pipeline                                       --
--------------------------------------------------------------------------------

if not no_preproc then
    print("[1/2] Running test pipeline …")
    local r = process.exec("python3", {
        "./test-runner/Parse_Scripts_For_Tests.py",
        Constants["SOURCE_FOLDER"],
        Constants["OUTPUT_FOLDER"],
        "--project-mocks", Constants["MOCK_LIBS_FOLDER"],
    })
    if r.stdout ~= "" then print(r.stdout) end
    if r.stderr ~= "" then warn(r.stderr)  end
else
    print("[1/2] Skipping Python pipeline (--no-preprocess)")
end

--------------------------------------------------------------------------------
-- Step 2a: Server mode (default)                                              --
--------------------------------------------------------------------------------

if not headless then
    print("[2/2] Starting server …")
    local Server = require("./Server")
    Server.Print_Startup_Info()
    Server.Start()
    return
end

--------------------------------------------------------------------------------
-- Step 2b: Headless / CI mode                                                 --
--------------------------------------------------------------------------------

local fs          = require("@lune/fs")
local serde       = require("@lune/serde")
local Test_Runner = require("./Test_Runner")

local BAR = string.rep("─", 60)

print("[2/2] Running tests (headless) …")
print(BAR)

Test_Runner.on(function(event: string, payload: {[string]: any})

    if event == "run:start" then
        print(("Found %d test file(s)\n"):format(payload.file_count :: number))

    elseif event == "suite:start" then
        print(("  SUITE  %s"):format(payload.file :: string))

    elseif event == "test:done" then
        local status = payload.status :: string
        local name   = payload.name   :: string
        local ms     = payload.duration_ms :: number

        local label = if status == "pass" then "[PASS]"
                      elseif status == "fail" then "[FAIL]"
                      else "[SKIP]"

        print(("    %s  %s  (%.1f ms)"):format(label, name, ms))

        if status == "fail" and payload.error then
            for line in tostring(payload.error):gmatch("[^\n]+") do
                print(("           %s"):format(line))
            end
        end

        -- Display property-test seed and falsifying example when available
        if (payload.seed) then
            print(("           seed: %s"):format(tostring(payload.seed)))
        end

    elseif event == "suite:done" then
        local suite  = payload.suite :: any
        local counts = suite.counts

        -- 1) File-level load / compilation error
        if suite.load_error then
            print(("         ERROR: %s"):format(suite.load_error))
        end

        -- 2) Per-describe / per-it errors that didn't come through test:done
        --    (describe errors are not sent as test:done, only it errors are)
        local function print_node_errors(nodes, indent)
            indent = indent or "         "
            for _, node in ipairs(nodes or {}) do
                if node.status == "fail" and node.error then
                    for line in tostring(node.error):gmatch("[^\n]+") do
                        print(indent .. line)
                    end
                end
                if node.children then
                    print_node_errors(node.children, indent .. "  ")
                end
            end
        end
        if not suite.load_error then
            print_node_errors(suite.nodes, "  ")
        end

        print(("         → %d passed, %d failed, %d skipped\n"):format(
            counts.passed, counts.failed, counts.skipped))

    elseif event == "run:done" then
        local total   = payload.total       :: number
        local passed  = payload.passed      :: number
        local failed  = payload.failed      :: number
        local skipped = payload.skipped     :: number
        local ms      = payload.duration_ms :: number

        print(BAR)
        local verdict = if failed > 0 then "FAILED" else "PASSED"
        print(("%s  |  %d passed  %d failed  %d skipped  %d total  (%.0f ms)"):format(
            verdict, passed, failed, skipped, total, ms))
        print(BAR)
    end

end)

-- Run synchronously (no server needed in headless mode)
Test_Runner.Run_Tests()

-- Write results.json when --json is given
if json_out then
    local ok, err = pcall(function()
        fs.writeFile("results.json", serde.encode("json", Test_Runner.results))
    end)
    if ok then
        print("Wrote results.json")
    else
        warn(("Could not write results.json: %s"):format(tostring(err)))
    end
end

-- Exit 0 = all green, 1 = any failure
process.exit(if Test_Runner.results.failed > 0 then 1 else 0)
