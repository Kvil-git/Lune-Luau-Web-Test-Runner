--!strict
--
-- REQUIRES
--
-- (none)

--
-- EXPORT TYPES
--
export type EventPayload   = {[string]: any}
export type EventListener  = (event: string, payload: EventPayload) -> ()
export type EventBus       = {
    on:    (self: EventBus, event: string, listener: EventListener) -> (),
    off:   (self: EventBus, event: string, listener: EventListener) -> (),
    emit:  (self: EventBus, event: string, payload: EventPayload) -> (),
    once:  (self: EventBus, event: string, listener: EventListener) -> (),
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
    local listeners:      {[string]: {EventListener}} = {}
    local once_listeners: {[string]: {EventListener}} = {}

    return {
        on = function(self: EventBus, event: string, listener: EventListener)
            if (listeners[event] == nil) then
                listeners[event] = {}
            end

            table.insert(listeners[event], listener)
        end,

        off = function(self: EventBus, event: string, listener: EventListener)
            local event_listeners = listeners[event]

            if (event_listeners ~= nil) then
                for i, stored_listener in ipairs(event_listeners) do
                    if (stored_listener == listener) then
                        table.remove(event_listeners, i)
                        break
                    end
                end
            end

            local once_event_listeners = once_listeners[event]

            if (once_event_listeners ~= nil) then
                for i, stored_listener in ipairs(once_event_listeners) do
                    if (stored_listener == listener) then
                        table.remove(once_event_listeners, i)
                        break
                    end
                end
            end
        end,

        emit = function(self: EventBus, event: string, payload: EventPayload)
            -- Regular listeners
            local event_listeners = listeners[event]

            if (event_listeners ~= nil) then
                for _, stored_listener in ipairs(event_listeners) do
                    local success = pcall(stored_listener, event, payload)

                    if (not success) then
                        warn(("[EventBus] listener error on %s"):format(event))
                    end
                end
            end

            -- Once listeners (remove after calling)
            local once_event_listeners = once_listeners[event]

            if (once_event_listeners ~= nil) then
                local to_remove: {EventListener} = {}

                for _, stored_listener in ipairs(once_event_listeners) do
                    local success = pcall(stored_listener, event, payload)

                    if (not success) then
                        warn(("[EventBus] once listener error on %s"):format(event))
                    end

                    table.insert(to_remove, stored_listener)
                end

                -- Remove called once-listeners
                for _, listener_to_remove in ipairs(to_remove) do
                    for i, stored_listener in ipairs(once_event_listeners) do
                        if (stored_listener == listener_to_remove) then
                            table.remove(once_event_listeners, i)
                            break
                        end
                    end
                end
            end
        end,

        once = function(self: EventBus, event: string, listener: EventListener)
            if (once_listeners[event] == nil) then
                once_listeners[event] = {}
            end

            table.insert(once_listeners[event], listener)
        end,

        clear = function(self: EventBus)
            listeners      = {}
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
