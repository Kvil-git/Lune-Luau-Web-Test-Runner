--!strict
--
-- REQUIRES
--
-- String requires
local Types       = require("./Types")
local Constants   = require("./Constants")
local Test_Loader = require("./Test_Loader")
local Sandbox     = require("./sandbox")
--
-- LOCAL TYPES
--
type TestNode     = Types.TestNode
type SuiteResult  = Types.SuiteResult
type Test_Results = Types.Test_Results
type Counts       = Types.Counts

--
-- LOCAL FUNCTIONS
--
--
-- Recursively count pass/fail/skip from a TestNode tree.
--
-- Parameters:
--     • nodes ({TestNode}) - The test nodes to count.
--
-- Returns:
--     Counts - The aggregated counts.
--
local function Count_Nodes(nodes: {TestNode}): Counts
    local c: Counts = { total = 0, passed = 0, failed = 0, skipped = 0 }
    for _, node in ipairs(nodes) do
        if node.type == "it" then
            c.total += 1
            if node.status == "pass" then
                c.passed += 1
            elseif node.status == "fail" then
                c.failed += 1
            elseif node.status == "skip" then
                c.skipped += 1
            end
        elseif node.type == "describe" and node.children then
            local sub = Count_Nodes(node.children :: {TestNode})
            c.total   += sub.total
            c.passed  += sub.passed
            c.failed  += sub.failed
            c.skipped += sub.skipped
        end
    end
    return c
end

--
-- Sum duration_ms across a tree of nodes (descend into describe children).
--
-- Parameters:
--     • nodes ({TestNode}) - The test nodes.
--
-- Returns:
--     number - Total duration in milliseconds.
--
local function Total_Duration(nodes: {TestNode}): number
    local ms = 0
    for _, node in ipairs(nodes) do
        ms += node.duration_ms
        if node.children then
            ms += Total_Duration(node.children :: {TestNode})
        end
    end
    return ms
end

--
-- VARIABLES
--

local results: Test_Results = {
    total       = 0,
    passed      = 0,
    failed      = 0,
    skipped     = 0,
    last_run_ms = 0,
    is_running  = false,
    suites      = {},
}

local Test_Runner = {
    -- Expose the live results table so Server can serialise it at any time.
    results = results,
}

--
-- MODULE DEFINITION (Event system)

-- Subscribers can listen to events emitted during a test run.
-- event types:
--   run:start   { file_count: number }
--   test:done   { suite: string, name: string, status: string, error: string?, duration_ms: number }
--   suite:done  { suite: SuiteResult }
--   run:done    { total: number, passed: number, failed: number, skipped: number, duration_ms: number }

type EventPayload = {[string]: any}
type Listener = (event: string, payload: EventPayload) -> ()

local listeners: {Listener} = {}

function Test_Runner.on(listener: Listener)
    table.insert(listeners, listener)
end

function Test_Runner.off(listener: Listener)
    for i, l in ipairs(listeners) do
        if l == listener then
            table.remove(listeners, i)
            return
        end
    end
end

local function emit(event: string, payload: EventPayload)
    for _, l in ipairs(listeners) do
        local ok = pcall(l, event, payload)
        if not ok then
            warn(("[Test_Runner] listener error on %s: %s"):format(event, tostring(ok)))
        end
    end
end

--
-- MODULE DEFINITION (Reset)
--

function Test_Runner.Reset()
    results.total       = 0
    results.passed      = 0
    results.failed      = 0
    results.skipped     = 0
    results.last_run_ms = 0
    results.is_running  = false
    results.suites      = {}
end

--
-- MODULE DEFINITION (Main run function)
--

--
-- Run all test files found in TEST_FOLDER.
--
-- This is synchronous — the caller (Server) should spawn it with task.spawn
-- so the HTTP server remains responsive during the run.
--
function Test_Runner.Run_Tests()
    if results.is_running then
        return false, "Tests are already running"
    end

    results.is_running = true
    Test_Runner.Reset()
    Sandbox.clear_cache()

    local TEST_FOLDER = Constants["TEST_FOLDER"]

    -- Discover files
    local file_paths, folder_err = Test_Loader.Find_Test_Files(TEST_FOLDER, true)

    if folder_err then
        -- Emit a synthetic failed suite so the UI shows the error
        local suite: SuiteResult = {
            file        = "Runner Error",
            path        = TEST_FOLDER,
            nodes       = {},
            counts      = { total = 1, passed = 0, failed = 1, skipped = 0 },
            duration_ms = 0,
            load_error  = folder_err,
        }
        table.insert(results.suites, suite)
        results.total      = 1
        results.failed     = 1
        results.is_running = false
        emit("run:done", { total = 1, passed = 0, failed = 1, skipped = 0, duration_ms = 0 })
        return false, folder_err
    end

    if #file_paths == 0 then
        results.is_running = false
        emit("run:done", { total = 0, passed = 0, failed = 0, skipped = 0, duration_ms = 0 })
        return true, "No test files found"
    end

    emit("run:start", { file_count = #file_paths })

    local run_start = os.clock()

    for _, full_path in ipairs(file_paths) do
        -- Extract short filename
        local file_name = full_path:match("[^/\\]+$") or full_path

        emit("suite:start", { file = file_name })

        local suite_start = os.clock()

        -- Per-test event forwarding
        local function on_test_done(node: any)
            emit("test:done", {
                suite       = file_name,
                name        = node.name,
                status      = node.status,
                error       = node.error,
                duration_ms = node.duration_ms,
                seed        = node.seed,
                falsifying  = node.falsifying,
            })
        end

        -- Run through sandbox
        local sr = Sandbox.run(full_path, file_name, on_test_done)

        local suite_ms = (os.clock() - suite_start) * 1000
        local counts   = Count_Nodes(sr.nodes)

        local suite: SuiteResult = {
            file        = file_name,
            path        = full_path,
            nodes       = sr.nodes,
            counts      = counts,
            duration_ms = suite_ms,
            load_error  = if not sr.ok then sr.err else nil,
        }

        -- If the file failed to load/compile, synthesise a failed count
        if not sr.ok then
            suite.counts = { total = 1, passed = 0, failed = 1, skipped = 0 }
        end

        table.insert(results.suites, suite)

        results.total   += suite.counts.total
        results.passed  += suite.counts.passed
        results.failed  += suite.counts.failed
        results.skipped += suite.counts.skipped

        emit("suite:done", { suite = suite })
    end

    results.last_run_ms = (os.clock() - run_start) * 1000
    results.is_running  = false

    emit("run:done", {
        total       = results.total,
        passed      = results.passed,
        failed      = results.failed,
        skipped     = results.skipped,
        duration_ms = results.last_run_ms,
    })

    return true, ("Ran %d tests across %d suites"):format(results.total, #results.suites)
end
--
-- RETURN VALUE
--
return Test_Runner