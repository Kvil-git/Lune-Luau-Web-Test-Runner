--!strict
--
-- REQUIRES
--
-- (none)
--
-- EXPORT TYPES
--
export type EventPayload = {[string]: any}
export type EventListener = (event: string, payload: EventPayload) -> ()
export type EventBus = {
    on: (self: EventBus, event: string, listener: EventListener) -> (),
    off: (self: EventBus, event: string, listener: EventListener) -> (),
    emit: (self: EventBus, event: string, payload: EventPayload) -> (),
    once: (self: EventBus, event: string, listener: EventListener) -> (),
    clear: (self: EventBus) -> (),
}
--
-- LOCAL FUNCTIONS
--
--
-- Creates a new EventBus instance.
--
-- Returns:
--     EventBus - A new event bus.
--
local function Create_Event_Bus(): EventBus
    local listeners: {[string]: {EventListener}} = {}
    local once_listeners: {[string]: {EventListener}} = {}
    
    return {
        on = function(self: EventBus, event: string, listener: EventListener)
            if not listeners[event] then
                listeners[event] = {}
            end
            table.insert(listeners[event], listener)
        end,
        
        off = function(self: EventBus, event: string, listener: EventListener)
            local event_listeners = listeners[event]
            if event_listeners then
                for i, l in ipairs(event_listeners) do
                    if l == listener then
                        table.remove(event_listeners, i)
                        break
                    end
                end
            end
            
            local once_event_listeners = once_listeners[event]
            if once_event_listeners then
                for i, l in ipairs(once_event_listeners) do
                    if l == listener then
                        table.remove(once_event_listeners, i)
                        break
                    end
                end
            end
        end,
        
        emit = function(self: EventBus, event: string, payload: EventPayload)
            -- Regular listeners
            local event_listeners = listeners[event]
            if event_listeners then
                for _, listener in ipairs(event_listeners) do
                    local success = pcall(listener, event, payload)
                    if not success then
                        warn(("[EventBus] listener error on %s"):format(event))
                    end
                end
            end
            
            -- Once listeners (remove after calling)
            local once_event_listeners = once_listeners[event]
            if once_event_listeners then
                local to_remove = {}
                for _, listener in ipairs(once_event_listeners) do
                    local success = pcall(listener, event, payload)
                    if not success then
                        warn(("[EventBus] once listener error on %s"):format(event))
                    end
                    table.insert(to_remove, listener)
                end
                
                -- Remove once listeners
                for _, listener in ipairs(to_remove) do
                    for i, l in ipairs(once_event_listeners) do
                        if l == listener then
                            table.remove(once_event_listeners, i)
                            break
                        end
                    end
                end
            end
        end,
        
        once = function(self: EventBus, event: string, listener: EventListener)
            if not once_listeners[event] then
                once_listeners[event] = {}
            end
            table.insert(once_listeners[event], listener)
        end,
        
        clear = function(self: EventBus)
            listeners = {}
            once_listeners = {}
        end,
    }
end
--
-- VARIABLES
--
-- Create a singleton event bus for the entire application
local event_bus = Create_Event_Bus()
--
-- RETURN VALUE
--
return event_bus
