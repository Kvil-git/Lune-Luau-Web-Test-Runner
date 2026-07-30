--!strict
--
-- Start_Tests
--
-- Entry point.  Runs the Python pre-processing pipeline then starts the
-- Lune HTTP/WebSocket server.
--
-- Usage:
--   lune run test_runner/Start_Tests
--

local process   = require("@lune/process")
local Server    = require("./Server")
local Constants = require("./Constants")

-- ─── Step 1: Bundle, rewrite requires, copy mock libs ────────────────────────
print("[1/2] Running test pipeline …")
local r1 = process.exec("python3", {
    "./Parse_Scripts_For_Tests.py",
    Constants["SOURCE_FOLDER"],
    Constants["OUTPUT_FOLDER"],
    "--mocks", Constants["MOCK_LIBS_FOLDER"],
})
if r1.stdout ~= "" then print(r1.stdout) end
if r1.stderr ~= "" then warn(r1.stderr)  end

-- ─── Step 2: Start server ────────────────────────────────────────────────────
print("[2/2] Starting server …")
Server.Print_Startup_Info()
Server.Start()