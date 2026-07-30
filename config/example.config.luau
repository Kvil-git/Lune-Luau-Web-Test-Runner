--!strict
--
-- test-runner.config.luau — example configuration
--
-- Copy this file to your parent project's root as test-runner.config.luau
-- and adjust the values to match your project's layout.
--
-- All keys are optional.  Missing keys fall back to the defaults
-- defined in Constants.luau.
--

return {
    --
    -- Paths relative to the parent project root (where you run lune from).
    --
    SOURCE_FOLDER    = "./src",
    TEST_FOLDER      = "./tests",
    OUTPUT_FOLDER    = "./tests/Scripts_Copies_With_String_Requires",
    MOCK_LIBS_FOLDER = "./src/Mock_Roblox_Libs",

    --
    -- Place file candidates for game.luau mock.
    -- The mock tries each path in order until it finds an existing file.
    --
    PLACE_PATH_CANDIDATES = {
        "./Clash of Empires - Game.rbxlx",
        "../Clash of Empires - Game.rbxlx",
    },

    --
    -- HTTP server port (server mode only).
    --
    PORT = 8080,
}
