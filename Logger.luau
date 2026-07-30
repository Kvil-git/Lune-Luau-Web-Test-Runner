--!strict
--
-- REQUIRES
--
-- (none)

--
-- EXPORT TYPES
--
export type LogLevel = "debug" | "info" | "warn" | "error"
export type Logger   = {
    debug:     (self: Logger, message: string, context: {[string]: any}?) -> (),
    info:      (self: Logger, message: string, context: {[string]: any}?) -> (),
    warn:      (self: Logger, message: string, context: {[string]: any}?) -> (),
    error:     (self: Logger, message: string, context: {[string]: any}?) -> (),
    set_level: (self: Logger, level: LogLevel) -> (),
}

--
-- LOCAL FUNCTIONS
--

--
-- Formats a log message with timestamp and context.
--
-- Parameters:
--     level    (LogLevel)           - The log level.
--     message  (string)             - The message to log.
--     context  ({[string]: any}?)   - Optional context data.
--
-- Returns:
--     string - The formatted message.
--
local function Format_Message(level: LogLevel, message: string, context: {[string]: any}?): string
    local timestamp  = os.date("%Y-%m-%d %H:%M:%S")
    local formatted  = ("[%s] %s: %s"):format(timestamp, level:upper(), message)

    if (context ~= nil) then
        local context_parts: {string} = {}

        for key, value in pairs(context) do
            table.insert(context_parts, ("%s=%s"):format(key, tostring(value)))
        end

        if (#context_parts > 0) then
            formatted ..= (" | %s"):format(table.concat(context_parts, ", "))
        end
    end

    return formatted
end

--
-- Creates a new Logger instance.
--
-- Returns:
--     Logger - A new logger.
--
local function Create_Logger(): Logger
    local current_level: LogLevel = "info"

    local LEVELS = {
        debug = (1),
        info  = (2),
        warn  = (3),
        error = (4),
    }

    local function Should_Log(level: LogLevel): boolean
        return LEVELS[level] >= LEVELS[current_level]
    end

    local function Log(level: LogLevel, message: string, context: {[string]: any}?)
        if (not Should_Log(level)) then
            return
        end

        local formatted = Format_Message(level, message, context)

        if (level == "error") then
            error(formatted)
        elseif (level == "warn") then
            warn(formatted)
        else
            print(formatted)
        end
    end

    return {
        debug = function(self: Logger, message: string, context: {[string]: any}?)
            Log("debug", message, context)
        end,

        info = function(self: Logger, message: string, context: {[string]: any}?)
            Log("info", message, context)
        end,

        warn = function(self: Logger, message: string, context: {[string]: any}?)
            Log("warn", message, context)
        end,

        error = function(self: Logger, message: string, context: {[string]: any}?)
            Log("error", message, context)
        end,

        set_level = function(self: Logger, level: LogLevel)
            if (LEVELS[level] ~= nil) then
                current_level = level
            else
                warn(("Invalid log level: %s"):format(level))
            end
        end,
    }
end

--
-- VARIABLES
--
-- Create a singleton logger for the entire application
local logger = Create_Logger()

--
-- RETURN VALUE
--
return logger
