--!strict
--
-- Start_Modular
--
-- Entry point for the modular test runner.
-- Replaces the original startup script with the new modular architecture.
--

--
-- REQUIRES
--
local Server = require("./Server_Modular")

--
-- Start the server
--
local server = Server.start()
Server.print_startup_info()

-- Keep the script running
return server
