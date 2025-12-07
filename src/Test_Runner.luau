--!strict
--
-- REQUIRES
--
local net         = require("@lune/net")
local serde       = require("@lune/serde")

local Types       = require("./Types")
local Constants   = require("./Constants")
local Test_Loader = require("./Test_Loader")
--
-- LOCAL TYPES
--
type Test_Status_HTML_Code = Types  .Test_Status_HTML_Code
type Test_Status           = Types  .Test_Status
type Test_Info             = Types  .Test_Info
type Test_Module           = Types  .Test_Module
--
-- CONSTANTS
--
local TEST_FOLDER   = Constants["TEST_FOLDER"]
local FRONTEND_HTML = Constants["FRONTEND_HTML"]
local PORT          = Constants["PORT"]
--
-- VARIABLES
--
local test_results = {
    total         = 0,
    passed        = 0,
    failed        = 0,
    skipped       = 0,
    tests         = {} :: {Test_Info},
    is_running    = false,
    last_run_time = 0
}
--
-- MODULE DEFINITION
--
local Test_Runner = {}

function Test_Runner.Reset_Results(): ()
    test_results.tests         = {}
    test_results.total         = 0
    test_results.passed        = 0
    test_results.failed        = 0
    test_results.skipped       = 0
    test_results.last_run_time = 0
end

function Test_Runner.Add_Pseudo_Test_For_Error_Output(name: string, path: string, error: string)
    local test_result: Test_Info = {
        status             = "Failed running",
        status_html_code   = "failed",
        name               =  name,
        path_to_test_file  =  path,
        error              =  error,
        execution_duration =  0
    }
    
    table.insert(test_results.tests, test_result)

    test_results.failed += 1
    test_results.total  += 1
end
--
-- Function description:
--    Parses the pcall output from test execution.
--
-- Return value:
--    True  : Test was passed or skipped
--    False : Test execution failed
--
function Test_Runner.Evaluate_Test_Results(success: boolean, result: any, test_result: Test_Info): boolean
    test_results.total += 1

    if not success then
        -- Test threw an error.
        test_result.status           = "Failed running"
        test_result.status_html_code = "failed"
        test_result.error            =  result
        test_results.failed         +=  1
        return false
    end
    
    if result == "Passed" then
        -- Test returned "Passed".
        test_result.status            = "Passed"
        test_result.status_html_code  = "passed"
        test_results.passed          +=  1
        return true
    elseif result == "Failed" then
        -- Test returned "Failed".
        test_result.status            = "Failed test conditions"
        test_result.status_html_code  = "failed"
        test_result.error             = "Test returned 'Failed'"
        test_results.failed          +=  1
        return false
    elseif result == "Skipped" then
        -- Test returned "Skipped".
        test_result.status            = "Skipped"
        test_result.status_html_code  = "skipped"
        test_results.skipped         +=  1
        return true
    else
        -- Invalid test return value.
        test_result.status            = "Failed running"
        test_result.status_html_code  = "failed"
        test_result.error             = `Invalid return value: {result}`
        test_results.failed          +=  1
        return false
    end
end

function Test_Runner.Execute_Test(test_module: Test_Module): Test_Info
    --
    -- Find the duration of test module's execution.
    --
    local testStart       = os.clock()
    local success, result = pcall(test_module.func)
    local testEnd         = os.clock()
    local duration        = testEnd - testStart
    --
    -- Create a table of type Test_Info, to later modify
    -- it's values to the appropriate ones and return it.
    --
    local test_result: Test_Info = {
        status             = "Passed",
        status_html_code   = "passed",
        name               =  test_module.name,
        execution_duration =  duration,
        error              =  nil,
        path_to_test_file  =  test_module.path
    }

    Test_Runner.Evaluate_Test_Results(success, result, test_result)
    
    return test_result
end
--
-- Function description:
--    Tries to load a luau function from a specified file.
--
-- Notes:
--    In the context of this program this function is
--    only used for loading test files.
--
-- Return value:
--    Error?  =>  (false , "Error string")
--    Else    =>  (true  , nil)
--
function Test_Runner.Run_Tests(): (boolean, string?)
    if test_results.is_running then
        return false, "Tests are already running"
    end
    
    test_results.is_running = true
    Test_Runner.Reset_Results()
    
    local test_files, folderError = Test_Loader.Extract_Test_Filenames_From_Folder(TEST_FOLDER)
    
    if folderError ~= nil then
        Test_Runner.Add_Pseudo_Test_For_Error_Output("Test Runner Error", "System", folderError)
        test_results.is_running = false

        return false, folderError
    end
    
    if #test_files == 0 then
        test_results.tests = { {
            name               = "No Tests Found",
            status             = "Skipped",
            status_html_code   = "skipped",
            error              = "No valid test modules found in the test folder",
            path_to_test_file  =  TEST_FOLDER,
            execution_duration =  0
        } }

        test_results.skipped       = 1
        test_results.total         = 1
        test_results.last_run_time = 0
        test_results.is_running    = false

        return false, "No valid test modules found in the test folder"
    end
    
    local start_time = os.clock()
    local test_modules: {Test_Module} = {}
    
    -- Load all test modules
    for _, test_file in ipairs(test_files) do
        local file_path = TEST_FOLDER .. "/" .. test_file
        local test_name = test_file:gsub("%.luau$", ""):gsub("%.lua$", "")
        
        local test_func, error_msg = Test_Loader.Load_Tests_From_File(file_path, test_file)
        
        if test_func then
            table.insert(test_modules, {
                func = test_func,
                name = test_name,
                path = file_path
            })
        else
            Test_Runner.Add_Pseudo_Test_For_Error_Output(test_name, file_path, error_msg or "Unknown error")
        end
    end
    
    -- Execute all tests
    for _, test_module in ipairs(test_modules) do
        local test_result = Test_Runner.Execute_Test(test_module)
        table.insert(test_results.tests, test_result)
    end
    
    local end_time             = os.clock()
    test_results.last_run_time = end_time - start_time
    test_results.is_running    = false
    
    return true, "Successfully ran all tests"
end

--
-- LOCAL FUNCTIONS
--

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
        return {
            status = 200,
            headers = {
                ["Content-Type"] = "application/json"
            },
            body = serde.encode("json", test_results)
        }
    
    -- API: Run tests.
    elseif path == "/run" and method == "POST" then
        local success, message = Test_Runner.Run_Tests()
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