--!strict
--
-- Server
--
-- HTTP + WebSocket server.
--
-- Endpoints:
--   GET  /          -> HTML frontend
--   GET  /results   -> current results.json snapshot
--   POST /run       -> trigger a test run (returns immediately; run is async)
--   GET  /stream    -> WebSocket; receives live run events as JSON messages
--

--
-- REQUIRES
--
local net         = require("@lune/net")
local serde       = require("@lune/serde")
local task        = require("@lune/task")
local Test_Runner = require("./Test_Runner")
local Constants   = require("./Constants")

--
-- CONSTANTS
--
local FRONTEND_HTML = Constants["FRONTEND_HTML"]
local PORT          = Constants["PORT"]

--
-- LOCAL TYPES
--
type Socket = typeof(net.serve(0, {
    handleWebSocket = function(s) return s end,
}).stop)

--
-- VARIABLES
--
-- We store live socket handles so we can broadcast events.
-- Lune's WebSocket handle type is opaque; we use `any` and rely on duck-typing.
local live_sockets: {any} = {}

--
-- LOCAL FUNCTIONS
--

--
-- Broadcasts an event to all connected WebSocket clients.
-- Dead sockets are pruned during the broadcast.
--
-- Parameters:
--     event   (string)           - The event name.
--     payload ({[string]: any})  - The event data.
--
local function Broadcast(event: string, payload: {[string]: any})
    local msg   = serde.encode("json", { event = event, data = payload })
    local dead: {number} = {}

    for i, socket in ipairs(live_sockets) do
        local send_ok = pcall(function()
            socket:send(msg)
        end)

        if (not send_ok) then
            table.insert(dead, i)
        end
    end

    -- Prune closed sockets (iterate in reverse to keep indices valid)
    for i = #dead, 1, -1 do
        table.remove(live_sockets, dead[i])
    end
end

-- Subscribe the broadcaster to all runner events
Test_Runner.on(function(event: string, payload: {[string]: any})
    Broadcast(event, payload)
end)

--
-- MODULE DEFINITION
--
local Server = {}

--
-- LOCAL TYPES
--
type Response = { status: number, headers: {[string]: string}?, body: string }

--
-- LOCAL FUNCTIONS
--

--
-- Creates a JSON response with the given status code and data.
--
local function Json_Response(status: number, data: any): Response
    return {
        status  = status,
        headers = { ["Content-Type"] = "application/json" },
        body    = serde.encode("json", data),
    }
end

--
-- Handles an incoming HTTP request.
--
function Server.Handle_Request(req: any): Response
    local path   = req.path   :: string
    local method = req.method :: string

    -- GET / - serve the frontend
    if (path == "/") and (method == "GET") then
        return {
            status  = 200,
            headers = { ["Content-Type"] = "text/html" },
            body    = FRONTEND_HTML,
        }

    -- GET /results - snapshot of current test results
    elseif (path == "/results") and (method == "GET") then
        return Json_Response(200, Test_Runner.results)

    -- POST /run - kick off a test run asynchronously
    elseif (path == "/run") and (method == "POST") then
        if (Test_Runner.results.is_running) then
            return Json_Response(409, {
                success = false,
                message = "Tests are already running",
            })
        end

        -- Spawn the run so the HTTP response is returned immediately
        task.spawn(function()
            Test_Runner.Run_Tests()
        end)

        return Json_Response(202, {
            success = true,
            message = "Test run started",
        })

    -- 404 for everything else
    else
        return { status = 404, headers = nil, body = "Not Found" }
    end
end

--
-- Handles a new WebSocket connection.
--
function Server.Handle_WebSocket(socket: any)
    -- Register this socket for broadcasts
    table.insert(live_sockets, socket)

    -- Send current results snapshot immediately
    pcall(function()
        socket:send(serde.encode("json", {
            event = "snapshot",
            data  = Test_Runner.results,
        }))
    end)

    -- Keep alive with heartbeat; break on disconnect
    while true do
        task.wait(15)

        local send_ok = pcall(function()
            socket:send(serde.encode("json", { event = "heartbeat", data = {} }))
        end)

        if (not send_ok) then
            break
        end
    end

    -- Remove from registry
    for i, s in ipairs(live_sockets) do
        if (s == socket) then
            table.remove(live_sockets, i)
            break
        end
    end
end

--
-- Starts the HTTP + WebSocket server.
--
function Server.Start()
    return net.serve(PORT, {
        handleRequest   = Server.Handle_Request,
        handleWebSocket = Server.Handle_WebSocket,
    })
end

--
-- Prints startup information to the console.
--
function Server.Print_Startup_Info()
    print(([[

    +----------------------------------------------+
    |          TestEZ Runner - Lune backend         |
    +----------------------------------------------+
    |  http://localhost:%d                           |
    |                                              |
    |  GET  /          Dashboard                   |
    |  GET  /results   JSON snapshot               |
    |  POST /run       Trigger test run            |
    |  WS   /stream    Live event stream           |
    |                                              |
    |  Press Ctrl+C to stop                        |
    +----------------------------------------------+
    ]]):format(PORT))
end

--
-- RETURN VALUE
--
return Server
