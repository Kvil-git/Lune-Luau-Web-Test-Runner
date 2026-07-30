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
    SOURCE_FOLDER    = "./src",
    TEST_FOLDER      = "./tests",
    OUTPUT_FOLDER    = "./tests/Scripts_Copies_With_String_Requires",
    MOCK_LIBS_FOLDER = "./src/Mock_Roblox_Libs",
    PORT             = 8080,
    SPEC_PATTERN     = "**/*.spec.luau",
}

--
-- Try loading the parent project's config file.
-- require resolves relative to this file's directory (test-runner/),
-- so "../test-runner.config" resolves to <project>/test-runner.config.luau.
--
local config: {[string]: any} = {}
local config_ok, config_result = pcall(require, "../test-runner.config")
if config_ok and (type(config_result) == "table") then
    config = config_result :: {[string]: any}
end

--
-- Merge: config values override defaults.
--
local function get_config(key: string, default_value: any): any
    if config[key] ~= nil then
        return config[key]
    end
    return default_value
end

--
-- Resolve a file path relative to the submodule's directory.
-- The submodule is at <project>/test-runner/, so we prepend
-- "./test-runner/" to paths that refer to submodule-internal files.
--
local SUBMODULE_PREFIX = "./test-runner"

local function submodule_path(relative_path: string): string
    return SUBMODULE_PREFIX .. "/" .. relative_path
end

--
-- Build the CONSTANTS table.
--
local SOURCE_FOLDER    = get_config("SOURCE_FOLDER",    DEFAULTS.SOURCE_FOLDER)
local TEST_FOLDER      = get_config("TEST_FOLDER",      DEFAULTS.TEST_FOLDER)
local OUTPUT_FOLDER    = get_config("OUTPUT_FOLDER",    DEFAULTS.OUTPUT_FOLDER)
local MOCK_LIBS_FOLDER = get_config("MOCK_LIBS_FOLDER", DEFAULTS.MOCK_LIBS_FOLDER)
local PORT_VALUE       = get_config("PORT",             DEFAULTS.PORT)

local CONSTANTS = {
    ["TEST_FOLDER"]      = TEST_FOLDER,
    ["SOURCE_FOLDER"]    = SOURCE_FOLDER,
    ["OUTPUT_FOLDER"]    = OUTPUT_FOLDER,
    ["MOCK_LIBS_FOLDER"] = MOCK_LIBS_FOLDER,
    ["FRONTEND_HTML"]    = fs.readFile(submodule_path("Front_End.html")),
    ["PORT"]             = PORT_VALUE,
    ["SPEC_PATTERN"]     = get_config("SPEC_PATTERN", DEFAULTS.SPEC_PATTERN),
}
--
-- RETURN VALUE
--
return CONSTANTS
