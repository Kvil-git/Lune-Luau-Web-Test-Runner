--!strict
--
-- Server
--
-- HTTP + WebSocket server.
--
-- Endpoints:
--   GET  /          → HTML frontend
--   GET  /results   → current results.json snapshot
--   POST /run       → trigger a test run (returns immediately; run is async)
--   GET  /stream    → WebSocket; receives live run events as JSON messages
--

local net         = require("@lune/net")
local serde       = require("@lune/serde")
local task        = require("@lune/task")
local Test_Runner = require("./Test_Runner")
local Constants   = require("./Constants")

local FRONTEND_HTML = Constants["FRONTEND_HTML"]
local PORT          = Constants["PORT"]

--------------------------------------------------------------------------------
-- WebSocket subscriber registry                                                 --
--------------------------------------------------------------------------------

type Socket = typeof(net.serve(0, {
    handleWebSocket = function(s) return s end,
}).stop)

-- We store live socket handles so we can broadcast events.
-- Lune's WebSocket handle type is opaque; we use `any` and rely on duck-typing.
local live_sockets: {any} = {}

local function broadcast(event: string, payload: {[string]: any})
    local msg = serde.encode("json", { event = event, data = payload })
    local dead: {number} = {}
    for i, socket in ipairs(live_sockets) do
        local ok = pcall(function()
            socket:send(msg)
        end)
        if not ok then
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
    broadcast(event, payload)
end)

--------------------------------------------------------------------------------
-- HTTP handler                                                                   --
--------------------------------------------------------------------------------

local Server = {}

type Response = { status: number, headers: {[string]: string}?, body: string }

local function json_response(status: number, data: any): Response
    return {
        status  = status,
        headers = { ["Content-Type"] = "application/json" },
        body    = serde.encode("json", data),
    }
end

function Server.Handle_Request(req: any): Response
    local path   = req.path   :: string
    local method = req.method :: string

    -- -------------------------------------------------------------------------
    -- GET / — serve the frontend
    -- -------------------------------------------------------------------------
    if path == "/" and method == "GET" then
        return {
            status  = 200,
            headers = { ["Content-Type"] = "text/html" },
            body    = FRONTEND_HTML,
        }

    -- -------------------------------------------------------------------------
    -- GET /results — snapshot of current test results
    -- -------------------------------------------------------------------------
    elseif path == "/results" and method == "GET" then
        return json_response(200, Test_Runner.results)

    -- -------------------------------------------------------------------------
    -- POST /run — kick off a test run asynchronously
    -- -------------------------------------------------------------------------
    elseif path == "/run" and method == "POST" then
        if Test_Runner.results.is_running then
            return json_response(409, { success = false, message = "Tests are already running" })
        end

        -- Spawn the run so the HTTP response is returned immediately and the
        -- server can continue serving /results polls / WebSocket events while
        -- tests execute.
        task.spawn(function()
            Test_Runner.Run_Tests()
        end)

        return json_response(202, { success = true, message = "Test run started" })

    -- -------------------------------------------------------------------------
    -- 404 for everything else
    -- -------------------------------------------------------------------------
    else
        return { status = 404, headers = nil, body = "Not Found" }
    end
end

--------------------------------------------------------------------------------
-- WebSocket handler                                                              --
--------------------------------------------------------------------------------

function Server.Handle_WebSocket(socket: any)
    -- Register this socket for broadcasts
    table.insert(live_sockets, socket)

    -- Immediately send the current results so a freshly-connected client is
    -- up to date without having to wait for the next event.
    pcall(function()
        socket:send(serde.encode("json", {
            event = "snapshot",
            data  = Test_Runner.results,
        }))
    end)

    -- We only push events to clients; we never need to read from them.
    -- Keep the handler (and therefore the connection) alive by sending a
    -- periodic heartbeat.  When the client disconnects, :send() will error
    -- and we break out of the loop.
    while true do
        task.wait(15)
        local ok = pcall(function()
            socket:send(serde.encode("json", { event = "heartbeat", data = {} }))
        end)
        if not ok then break end
    end

    -- Remove from registry
    for i, s in ipairs(live_sockets) do
        if s == socket then
            table.remove(live_sockets, i)
            break
        end
    end
end

--------------------------------------------------------------------------------
-- Startup                                                                        --
--------------------------------------------------------------------------------

function Server.Start()
    return net.serve(PORT, {
        handleRequest  = Server.Handle_Request,
        handleWebSocket = Server.Handle_WebSocket,
    })
end

function Server.Print_Startup_Info()
    print(([[

    ╔══════════════════════════════════════════════╗
    ║          TestEZ Runner — Lune backend        ║
    ╠══════════════════════════════════════════════╣
    ║  http://localhost:%d                          
    ║                                              ║
    ║  GET  /          Dashboard                   ║
    ║  GET  /results   JSON snapshot               ║
    ║  POST /run       Trigger test run            ║
    ║  WS   /stream    Live event stream           ║
    ║                                              ║
    ║  Press Ctrl+C to stop                        ║
    ╚══════════════════════════════════════════════╝
]]):format(PORT))
end

return Server
