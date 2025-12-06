-- backend.luau
local net = require("@lune/net")
local serde = require("@lune/serde")
local task = require("@lune/task")
local fs = require("@lune/fs")

local luau = require("@lune/luau")
local Test_Folder = "../tests"

-- Configuration
local PORT = 8080

-- State management
local testResults = {
    total       = 0,
    passed      = 0,
    failed      = 0,
    skipped     = 0,
    tests       = {},
    isRunning   = false,
    lastRunTime = nil
}

local function runTests()
    if testResults.isRunning then
        return false, "Tests are already running"
    end
    
    testResults.isRunning = true
    testResults.lastRunTime = nil
    
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
        if not fs.isDir(Test_Folder) then
            testResults.tests = {
                {
                    name = "Test Runner Error",
                    planPath = "system",
                    status = "failed",
                    error = "Test folder not found: " .. Test_Folder,
                    duration = 0
                }
            }
            testResults.failed = 1
            testResults.total = 1
            testResults.isRunning = false
            return
        end
        --
        -- Get all test files.
        --
        local entry_paths_list = fs.readDir(Test_Folder)
        local my_tests = {}
        local startTime = os.clock()
        --
        -- Load all test modules.
        --
        for _, entry_path in ipairs(entry_paths_list) do
            -- Skip non-luau files.
            if not entry_path:match("%.luau$") and not entry_path:match("%.lua$") then
                continue
            end
            
            local file_path = Test_Folder .. "/" .. entry_path
            local module_content = fs.readFile(file_path)
            
            print(`Module content:\n{module_content}`)

            -- Use pcall to handle loading errors.
            local success, module_returned_func = pcall(function()
                return luau.load(module_content, {
                    debugName = entry_path
                })
            end)
            
            if success and typeof(module_returned_func) == "function" then
                table.insert(my_tests, {
                    func = module_returned_func(),
                    name = entry_path:gsub("%.luau$", ""):gsub("%.lua$", ""),
                    path = file_path
                })
            else
                -- Handle invalid test module
                local testResult = {
                    name     = entry_path:gsub("%.luau$", ""):gsub("%.lua$", ""),
                    planPath = file_path,
                    status   = "failed",
                    error    = "Failed to load test module: " .. (module_returned_func or "unknown error"),
                    duration = 0
                }
                table.insert(testResults.tests, testResult)
                testResults.failed += 1
                testResults.total  += 1
            end
        end
        
        if #my_tests == 0 then
            if #testResults.tests == 0 then
                -- No tests found
                table.insert(testResults.tests, {
                    name = "No Tests Found",
                    planPath = Test_Folder,
                    status = "skipped",
                    error = "No valid test modules found in the test folder",
                    duration = 0
                })
                testResults.skipped = 1
                testResults.total   = 1
            end
            testResults.lastRunTime = 0
            testResults.isRunning   = false
            return
        end
        
        -- Run each test
        for _, test_info in ipairs(my_tests) do
            local test_start      = os.clock()
            local success, result = pcall(test_info.func)
            local test_end        = os.clock()
            local duration        = (test_end - test_start) * 1000 -- Convert to milliseconds
            
            local testResult = {
                name     = test_info.name,
                planPath = test_info.path,
                duration = math.floor(duration * 100) / 100 -- Round to 2 decimal places
            }
            
            if success then
                local result = test_info.func()
                print(`Module successfully executed? => {success}`)
                print(`Module execution result? => {result}`)
                if result == "Passed" then
                    
                    testResult.status   = "Passed"
                    testResults.passed += 1
                elseif result == "Failed" then
                    
                    testResult.status = "Failed"
                    testResult.error  = "Test returned 'Failed'"
                    testResults.failed += 1
                elseif result == "Skipped" then
                    
                    testResult.status    = "Skipped"
                    testResults.skipped += 1
                else
                    -- Invalid return value
                    testResult.status   = "Failed"
                    testResult.error    = `Invalid return value: {result}`
                    testResults.failed += 1
                end
            else
                -- Test threw an error
                testResult.status   = "failed"
                testResult.error    = result -- This is the error message from pcall
                testResults.failed += 1
            end
            
            table.insert(testResults.tests, testResult)
            testResults.total += 1
        end
        
        local endTime = os.clock()
        testResults.lastRunTime = (endTime - startTime) * 1000 -- Convert to milliseconds
        
        -- Sort tests by status (failed first, then passed, then skipped)
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
        
        -- Print summary to console
        print("\n=== Test Results ===")
        print(string.format("Total: %d",     testResults.total))
        print(string.format("Passed: %d",    testResults.passed))
        print(string.format("Failed: %d",    testResults.failed))
        print(string.format("Skipped: %d",   testResults.skipped))
        print(string.format("Time: %.2f ms", testResults.lastRunTime))
        
        if testResults.failed > 0 then
            print("\nFailed tests:")
            for _, test in ipairs(testResults.tests) do
                if test.status == "failed" then
                    print(string.format("  - %s: %s", test.name, test.error or "No error message"))
                end
            end
        end
        print("==================\n")
    end)
    
    return true
end

-- Serve the frontend HTML
local frontendHTML = fs.readFile("./front_end.html")

-- HTTP Request Handler
local function handleRequest(req)
    local path = req.path
    local method = req.method
    
    -- Serve frontend HTML
    if path == "/" and method == "GET" then
        return {
            status = 200,
            headers = {
                ["Content-Type"] = "text/html"
            },
            body = frontendHTML
        }
    
    -- API: Get current test results
    elseif path == "/results" and method == "GET" then
        return {
            status = 200,
            headers = {
                ["Content-Type"] = "application/json"
            },
            body = serde.encode("json", testResults)
        }
    
    -- API: Run tests
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
    
    -- 404 for other routes
    else
        return {
            status = 404,
            body = "Not Found"
        }
    end
end

-- Start the server
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

-- Start HTTP server
local server = net.serve(PORT, handleRequest)