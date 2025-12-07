--!strict
--
-- REQUIRES
--
local net       = require("@lune/net")
local serde     = require("@lune/serde")
local task      = require("@lune/task")
local fs        = require("@lune/fs")
local luau      = require("@lune/luau")
local Types     = require("./types")
local Constants = require("./constants")
--
-- LOCAL TYPES
--
type Test_Status_HTML_Code = Types  .Test_Status_HTML_Code
type Test_Status           = Types  .Test_Status
type Test_Info             = Types  .Test_Info
--
-- CONSTANTS
--
local TEST_FOLDER   = Constants["TEST_FOLDER"]
local FRONTEND_HTML = Constants["FRONTEND_HTML"]
local PORT          = Constants["PORT"]
--
-- VARIABLES
--
local testResults = {
    total       = 0,
    passed      = 0,
    failed      = 0,
    skipped     = 0,
    tests       = {} :: {Test_Info},
    isRunning   = false,
    lastRunTime = 0
}
--
-- LOCAL FUNCTIONS
--

-- Runs all the tests in the TEST_FOLDER.
local function runTests()
    if testResults.isRunning then
        return false, "Tests are already running"
    end
    
    testResults.isRunning   = true
    testResults.lastRunTime = 0
    
    task.spawn(function()
        --
        -- Clear previous results.
        --
        testResults.tests   = {}
        testResults.total   = 0
        testResults.passed  = 0
        testResults.failed  = 0
        testResults.skipped = 0
        --
        -- Check if test folder exists.
        --
        if not fs.isDir(TEST_FOLDER) then
            testResults.tests = {
                {
                    name               = "Test Runner Error",
                    path_to_test_file  = "System",
                    status             = "Failed running",
                    status_html_code   = "failed",
                    error              = "Test folder not found: " .. TEST_FOLDER,
                    execution_duration = 0,
                }
            }
            testResults.failed = 1
            testResults.total = 1
            testResults.isRunning = false
            return false, "Test folder not found"
        end
        --
        -- Get all test files.
        --
        local entry_paths_list = fs.readDir(TEST_FOLDER)
        local tests_from_test_folder = {}
        local startTime = os.clock()
        --
        -- Load all test modules.
        --
        for _, entry_path in ipairs(entry_paths_list) do
            -- Skip non-luau files.
            if not entry_path:match("%.luau$") and not entry_path:match("%.lua$") then
                continue
            end
            
            local file_path = TEST_FOLDER .. "/" .. entry_path
            local module_content = fs.readFile(file_path)
            
            print(`Module content:\n{module_content}`)

            -- Use pcall to handle loading errors.
            local success, module_returned_func = pcall(function()
                return luau.load(module_content, {
                    debugName = entry_path
                })
            end)
            
            if success and typeof(module_returned_func) == "function" then
                table.insert(tests_from_test_folder, {
                    func = module_returned_func(),
                    name = entry_path:gsub("%.luau$", ""):gsub("%.lua$", ""),
                    path = file_path
                })
            else
                -- Handle invalid test module
                local testResult: Test_Info = {
                    name               = entry_path:gsub("%.luau$", ""):gsub("%.lua$", ""),
                    path_to_test_file  = file_path,
                    status             = "Failed running",
                    status_html_code   = "failed",
                    error              = "Failed to load test module: " .. (module_returned_func or "unknown error"),
                    execution_duration = 0
                }
                table.insert(testResults.tests, testResult)
                testResults.failed += 1
                testResults.total  += 1
            end
        end
        
        if #tests_from_test_folder == 0 then
            if #testResults.tests == 0 then
                -- No tests found
                table.insert(testResults.tests, {
                    name               = "No Tests Found",
                    path_to_test_file  = TEST_FOLDER,
                    status             = "Skipped",
                    status_html_code   = "skipped",
                    error              = "No valid test modules found in the test folder",
                    execution_duration = 0
                })
                testResults.skipped = 1
                testResults.total   = 1
            end
            testResults.lastRunTime = 0
            testResults.isRunning   = false
            return false, "No valid test modules found in the test folder"
        end
        --
        -- Run each test extracted from the test folder.
        --
        for _, test_info in ipairs(tests_from_test_folder) do
            local test_start      = os.clock()
            local success, result = pcall(test_info.func)
            local test_end        = os.clock()
            local duration        = (test_end - test_start) * 1000 -- Convert to milliseconds
            
            local testResult: Test_Info = {
                name               = test_info.name,
                status             = "Passed",
                status_html_code   = "passed",
                execution_duration = math.floor(duration * 100) / 100, -- Round to 2 decimal places
                error              = nil,
                path_to_test_file  = test_info.path
            }
            
            if success then
                --
                -- Test threw no error in pcall? => Get the actual test's
                -- return value by running the test again, this time without a pcall.
                --
                result = test_info.func()
                --
                -- Debug prints.
                --
                print(`Is test execution successful? {success}`)
                print(`Test execution result: {result}`)
                --
                -- Handle the test's return value.
                --
                if result == "Passed" then
                    -- Test returned "Passed".
                    testResult.status           = "Passed"
                    testResult.status_html_code = "passed"
                    testResults.passed += 1
                elseif result == "Failed" then
                    -- Test returned "Failed".
                    testResult.status           = "Failed test conditions"
                    testResult.status_html_code = "failed"
                    testResult.error            = "Test returned 'Failed'"
                    testResults.failed         += 1
                elseif result == "Skipped" then
                    -- Skipped the test.
                    testResult.status            = "Skipped"
                    testResult.status_html_code  = "skipped"
                    testResults.skipped         += 1
                else
                    -- Invalid test return value.
                    testResult.status            = "Failed running"
                    testResult.status_html_code  = "failed"
                    testResult.error             = `Invalid return value: {result}`
                    testResults.failed          += 1
                end
            else
                -- Test threw an error.
                testResult.status           = "Failed running"
                testResult.status_html_code = "failed"
                testResult.error            = result  -- This is the error message from pcall.
                testResults.failed         += 1
            end
            
            table.insert(testResults.tests, testResult)
            testResults.total += 1
        end
        
        local endTime = os.clock()
        testResults.lastRunTime = (endTime - startTime) * 1000 -- Convert to milliseconds
        --
        -- Sort tests by status:
        --
        -- 1) Failed
        -- 2) Skipped
        -- 3) Passed
        --
        table.sort(testResults.tests, function(a, b)
            local statusOrder = {failed = 1, passed = 2, skipped = 3}
            local aOrder = statusOrder[a.status] or 4
            local bOrder = statusOrder[b.status] or 4
            
            if aOrder == bOrder then
                return a.name < b.name
            end
            return aOrder < bOrder
        end)
        
        testResults.isRunning = false
        --
        -- Print summary to console.
        --
        print("\n=== Test Results ===")
        print(string.format("Total: %d",     testResults.total))
        print(string.format("Passed: %d",    testResults.passed))
        print(string.format("Failed: %d",    testResults.failed))
        print(string.format("Skipped: %d",   testResults.skipped))
        print(string.format("Time: %.2f ms", testResults.lastRunTime))
        
        if testResults.failed > 0 then
            print("\nFailed tests:")
            for _, test in ipairs(testResults.tests) do
                if (test.status == "Failed running") or (test.status == "Failed test conditions") then
                    print(string.format("  - %s: %s", test.name, test.error or "No error message"))
                end
            end
        end
        print("==================\n")
    end)
    
    return true, "Successfully ran all the tests."
end

-- Handles the incoming HTTP requests.
local function handleRequest(req): {body: string, headers: {string}?, status: number}
    local path = req.path
    local method = req.method
    
    -- Send the FRONTEND_HTML page to the client.
    if path == "/" and method == "GET" then
        return {
            status = 200,
            headers = {
                ["Content-Type"] = "text/html"
            },
            body = FRONTEND_HTML
        }
    
    -- API: Get current test results.
    elseif path == "/results" and method == "GET" then
        print(serde.encode("json", testResults))
        return {
            status = 200,
            headers = {
                ["Content-Type"] = "application/json"
            },
            body = serde.encode("json", testResults)
        }
    
    -- API: Run tests.
    elseif path == "/run" and method == "POST" then
        local success, message = runTests()
        return {
            status = 200,
            headers = {
                ["Content-Type"] = "application/json"
            },
            body = serde.encode("json", {
                success = success,
                message = message
            })
        }
    
    -- 404 for other routes.
    else
        return {
            status  = 404,
            body    = "Not Found",
            headers = nil,
        }
    end
end

--
-- MODULE OPERATION
--

-- Print debug info about the local webserver.
print(`                                           \
        TestEZ Runner Backend                     \
        ====================                      \
        Server running on http://localhost:{PORT} \
                                                  \
        Endpoints:                                \
        GET  /         - Test runner dashboard    \
        GET  /results  - Get current test results \
        POST /run      - Trigger test execution   \
                                                  \
        Press Ctrl+C to stop                      \
                                                  \
`)
-- Start the local webserver.
local server = net.serve(PORT, handleRequest)