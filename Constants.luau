--!strict
--
-- REQUIRES
--
local fs = require("@lune/fs")

--
-- CONSTANTS
--
--
-- Default values for all configurable paths.
-- Parent projects can override these by creating test-runner.config.luau
-- at the project root.  That file should return a table with any of the
-- keys below.
--
local DEFAULTS = {
    ["SOURCE_FOLDER"]         = "./src",
    ["EXTRA_SOURCE_FOLDERS"]  = {},
    ["TEST_FOLDER"]           = "./tests",
    ["OUTPUT_FOLDER"]         = "./tests/Scripts_Copies_With_String_Requires",
    ["MOCK_LIBS_FOLDER"]      = "./src/Mock_Roblox_Libs",
    ["PORT"]                  = (8080),
    ["SPEC_PATTERN"]          = "**/*.spec.luau",
    ["SEED"]                  = nil,
    ["EXAMPLES"]              = (100),
}

--
-- Try loading the parent project's config file.
--
local config: {[string]: any} = {}
local config_ok, config_result = pcall(require, "../test-runner.config")

if (config_ok) and (type(config_result) == "table") then
    config = config_result :: {[string]: any}
end

--
-- LOCAL FUNCTIONS
--

--
-- Gets a configuration value, falling back to the default if not set.
--
local function Get_Config(key: string, default_value: any): any
    if (config[key] ~= nil) then
        return config[key]
    end

    return default_value
end

--
-- LOCAL CONSTANTS
--
local SUBMODULE_PREFIX = "./test_runner"

--
-- Builds a path relative to the submodule's directory.
--
local function Submodule_Path(relative_path: string): string
    return SUBMODULE_PREFIX .. "/" .. relative_path
end

--
-- Build the CONSTANTS table.
--
local SOURCE_FOLDER    = Get_Config("SOURCE_FOLDER",    DEFAULTS.SOURCE_FOLDER)
local TEST_FOLDER      = Get_Config("TEST_FOLDER",      DEFAULTS.TEST_FOLDER)
local OUTPUT_FOLDER    = Get_Config("OUTPUT_FOLDER",    DEFAULTS.OUTPUT_FOLDER)
local MOCK_LIBS_FOLDER = Get_Config("MOCK_LIBS_FOLDER", DEFAULTS.MOCK_LIBS_FOLDER)
local PORT_VALUE       = Get_Config("PORT",             DEFAULTS.PORT)

local CONSTANTS = {
    ["TEST_FOLDER"]           = TEST_FOLDER,
    ["SOURCE_FOLDER"]         = SOURCE_FOLDER,
    ["EXTRA_SOURCE_FOLDERS"]  = Get_Config("EXTRA_SOURCE_FOLDERS", DEFAULTS.EXTRA_SOURCE_FOLDERS),
    ["OUTPUT_FOLDER"]         = OUTPUT_FOLDER,
    ["MOCK_LIBS_FOLDER"]      = MOCK_LIBS_FOLDER,
    ["FRONTEND_HTML"]         = fs.readFile(Submodule_Path("Front_End.html")),
    ["PORT"]                  = PORT_VALUE,
    ["SPEC_PATTERN"]          = Get_Config("SPEC_PATTERN", DEFAULTS.SPEC_PATTERN),
    ["SEED"]                  = Get_Config("SEED", DEFAULTS.SEED),
    ["EXAMPLES"]              = Get_Config("EXAMPLES", DEFAULTS.EXAMPLES),
}

--
-- RETURN VALUE
--
return CONSTANTS
