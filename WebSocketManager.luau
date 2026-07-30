--!strict
--
-- WebSocketManager
--
-- Manages WebSocket connections and broadcasting.
-- Separates WebSocket concerns from the main server.
--

--
-- REQUIRES
--
local task      = require("@lune/task")
local serde     = require("@lune/serde")
local Config    = require("./Config")
local EventBus  = require("./EventBus")

--
-- EXPORT TYPES
--
export type WebSocketManager = {
    handle_websocket:       (self: WebSocketManager, socket: any) -> (),
    broadcast:              (self: WebSocketManager, event: string, payload: {[string]: any}) -> (),
    get_connection_count:   (self: WebSocketManager) -> number,
}

--
-- LOCAL FUNCTIONS
--

--
-- Sends a message to a single WebSocket socket.
-- Returns true if the send succeeded, false otherwise.
--
-- Parameters:
--     socket  (any)    - The WebSocket handle.
--     message (string) - The message to send.
--
-- Returns:
--     boolean
--
local function Send_To_Socket(socket: any, message: string): boolean
    local success = pcall(function()
        socket:send(message)
    end)

    return success
end

--
-- Broadcasts an event to all connected WebSocket clients.
-- Dead sockets are pruned during the broadcast.
--
-- Parameters:
--     event   (string)           - The event name.
--     payload ({[string]: any})  - The event data.
--
local function Broadcast_Event(event: string, payload: {[string]: any})
    local msg          = serde.encode("json", { event = event, data = payload })
    local dead_indices: {number} = {}

    for i, socket in ipairs(live_sockets) do
        if (not Send_To_Socket(socket, msg)) then
            table.insert(dead_indices, i)
        end
    end

    -- Remove dead sockets (iterate in reverse to keep indices valid)
    for i = #dead_indices, 1, -1 do
        table.remove(live_sockets, dead_indices[i])
    end
end

--
-- VARIABLES
--
local live_sockets: {any} = {}
local config = Config:get()

--
-- Subscribe to all test runner events
--
EventBus:on("run:start",   function(event: string, payload: {[string]: any}) Broadcast_Event(event, payload) end)
EventBus:on("suite:start", function(event: string, payload: {[string]: any}) Broadcast_Event(event, payload) end)
EventBus:on("test:done",   function(event: string, payload: {[string]: any}) Broadcast_Event(event, payload) end)
EventBus:on("suite:done",  function(event: string, payload: {[string]: any}) Broadcast_Event(event, payload) end)
EventBus:on("run:done",    function(event: string, payload: {[string]: any}) Broadcast_Event(event, payload) end)

--
-- MODULE DEFINITION
--
local function Create_WebSocket_Manager(): WebSocketManager
    return {
        handle_websocket = function(self: WebSocketManager, socket: any)
            -- Register this socket for broadcasts
            table.insert(live_sockets, socket)

            -- Send current results snapshot immediately
            Send_To_Socket(socket, serde.encode("json", {
                event = "snapshot",
                data = {
                    suites     = {},
                    total      = 0,
                    passed     = 0,
                    failed     = 0,
                    skipped    = 0,
                    is_running = false,
                    last_run_ms = 0,
                },
            }))

            -- Keep connection alive with periodic heartbeats
            while true do
                task.wait(config.heartbeat_interval_seconds)

                local send_ok = Send_To_Socket(socket, serde.encode("json", {
                    event = "heartbeat",
                    data  = {},
                }))

                if (not send_ok) then
                    break
                end
            end

            -- Remove from registry when connection dies
            for i, s in ipairs(live_sockets) do
                if (s == socket) then
                    table.remove(live_sockets, i)
                    break
                end
            end
        end,

        broadcast = function(self: WebSocketManager, event: string, payload: {[string]: any})
            Broadcast_Event(event, payload)
        end,

        get_connection_count = function(self: WebSocketManager): number
            return #live_sockets
        end,
    }
end

--
-- RETURN VALUE
--
return Create_WebSocket_Manager()
