--!strict
--
-- REQUIRES
--
local net         = require("@lune/net")
local serde       = require("@lune/serde")

local Test_Runner = require("./Test_Runner")
local Constants   = require("./Constants")
--
-- CONSTANTS
--
local FRONTEND_HTML = Constants["FRONTEND_HTML"]
local PORT          = Constants["PORT"]
--
-- MODULE DEFINITION
--
local Server = {}

-- Handles the incoming HTTP requests.
function Server.Handle_Request(req): {body: string, headers: {string}?, status: number}
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
            body = serde.encode("json", Test_Runner.test_results)
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
            body    = "Not Found",
            status  =  404,
            headers =  nil,
        }
    end
end

function Server.Start()
    local server = net.serve(PORT, function(req)
        return Server.Handle_Request(req)
    end)
    
    return server
end

function Server.Print_Startup_Info()
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
end
--
-- REQUIRES
--
return Server