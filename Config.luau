--!strict
--
-- REQUIRES
--
local fs = require("@lune/fs")

--
-- EXPORT TYPES
--
export type Config = {
    port:                       number,
    test_folder:                string,
    spec_pattern:               string,
    frontend_path:              string,
    heartbeat_interval_seconds: number,
    reconnect_delay_seconds:    number,
}

--
-- LOCAL TYPES
--
-- (none)

--
-- LOCAL CONSTANTS
--
local DEFAULT_CONFIG: Config   = {
    port                       = (8080),
    test_folder                = "../tests",
    spec_pattern               = "**/*.spec.luau",
    frontend_path              = "./Front_End.html",
    heartbeat_interval_seconds = (15),
    reconnect_delay_seconds    = (3),
}

--
-- LOCAL FUNCTIONS
--

--
-- Loads the default configuration.
--
-- Returns:
--     Config - The default configuration.
--
local function Load_Config(): Config
    return DEFAULT_CONFIG
end

--
-- Loads the frontend HTML content from a file.
--
-- Parameters:
--     path (string) - The path to the frontend HTML file.
--
-- Returns:
--     string - The HTML content.
--
local function Load_Frontend_HTML(path: string): string
    local success, content = pcall(fs.readFile, path)

    if (not success) then
        error(("Failed to load frontend HTML from %s: %s"):format(path, tostring(content)))
    end

    return content
end

--
-- Creates a new ConfigManager instance.
--
-- Returns:
--     ConfigManager - A new configuration manager.
--
local function Create_Config_Manager(): ConfigManager
    local config          = Load_Config()
    local frontend_html   = "" :: string
    local frontend_loaded = false

    return {
        get = function(self: ConfigManager): Config
            return config
        end,

        get_frontend_html = function(self: ConfigManager): string
            if (not frontend_loaded) then
                frontend_html   = Load_Frontend_HTML(config.frontend_path)
                frontend_loaded = true
            end

            return frontend_html
        end,

        update = function(self: ConfigManager, updates: {[string]: any})
            for key, value in pairs(updates) do
                if ((config :: any)[key] ~= nil) then
                    (config :: any)[key] = value
                else
                    warn(("Unknown config key: %s"):format(tostring(key)))
                end
            end

            -- Invalidate frontend HTML cache if path changed
            if (updates.frontend_path ~= nil) then
                frontend_loaded = false
            end
        end,
    }
end

--
-- LOCAL TYPES
--
export type ConfigManager = {
    get:               (self: ConfigManager) -> Config,
    get_frontend_html: (self: ConfigManager) -> string,
    update:            (self: ConfigManager, updates: {[string]: any}) -> (),
}

--
-- RETURN VALUE
--
return Create_Config_Manager()
