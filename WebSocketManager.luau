--!strict
--
-- WebSocketManager
--
-- Manages WebSocket connections and broadcasting.
-- Separates WebSocket concerns from the main server.
--

local task = require("@lune/task")
local serde = require("@lune/serde")
local Config = require("./Config")
local EventBus = require("./EventBus")

export type WebSocketManager = {
    handle_websocket: (self: WebSocketManager, socket: any) -> (),
    broadcast: (self: WebSocketManager, event: string, payload: {[string]: any}) -> (),
    get_connection_count: (self: WebSocketManager) -> number,
}

local function create_websocket_manager(): WebSocketManager
    local live_sockets: {any} = {}
    local config = Config:get()
    
    local function send_to_socket(socket: any, message: string): boolean
        local success = pcall(function()
            socket:send(message)
        end)
        return success
    end
    
    local function broadcast_event(event: string, payload: {[string]: any})
        local msg = serde.encode("json", { event = event, data = payload })
        local dead_indices: {number} = {}
        
        for i, socket in ipairs(live_sockets) do
            if not send_to_socket(socket, msg) then
                table.insert(dead_indices, i)
            end
        end
        
        -- Remove dead sockets (iterate in reverse to keep indices valid)
        for i = #dead_indices, 1, -1 do
            table.remove(live_sockets, dead_indices[i])
        end
    end
    
    -- Subscribe to all test runner events
    EventBus:on("run:start", function(event: string, payload: {[string]: any})
        broadcast_event(event, payload)
    end)
    
    EventBus:on("suite:start", function(event: string, payload: {[string]: any})
        broadcast_event(event, payload)
    end)
    
    EventBus:on("test:done", function(event: string, payload: {[string]: any})
        broadcast_event(event, payload)
    end)
    
    EventBus:on("suite:done", function(event: string, payload: {[string]: any})
        broadcast_event(event, payload)
    end)
    
    EventBus:on("run:done", function(event: string, payload: {[string]: any})
        broadcast_event(event, payload)
    end)
    
    return {
        handle_websocket = function(self: WebSocketManager, socket: any)
            -- Register this socket for broadcasts
            table.insert(live_sockets, socket)
            
            -- Send current results snapshot immediately
            -- Note: This will need to be connected to Test_Runner results
            -- For now, we'll send a heartbeat
            send_to_socket(socket, serde.encode("json", {
                event = "snapshot",
                data = {
                    suites = {},
                    total = 0,
                    passed = 0,
                    failed = 0,
                    skipped = 0,
                    is_running = false,
                    last_run_ms = 0,
                }
            }))
            
            -- Keep connection alive with periodic heartbeats
            while true do
                task.wait(config.heartbeat_interval_seconds)
                if not send_to_socket(socket, serde.encode("json", { 
                    event = "heartbeat", 
                    data = {} 
                })) then
                    break
                end
            end
            
            -- Remove from registry when connection dies
            for i, s in ipairs(live_sockets) do
                if s == socket then
                    table.remove(live_sockets, i)
                    break
                end
            end
        end,
        
        broadcast = function(self: WebSocketManager, event: string, payload: {[string]: any})
            broadcast_event(event, payload)
        end,
        
        get_connection_count = function(self: WebSocketManager): number
            return #live_sockets
        end,
    }
end

return create_websocket_manager()
