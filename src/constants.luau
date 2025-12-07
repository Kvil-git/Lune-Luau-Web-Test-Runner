--!strict
--
-- REQUIRES
--
local fs = require("@lune/fs")
--
-- CONSTANTS
--
local CONSTANTS = {
    ["TEST_FOLDER"]   = "../tests",
    ["FRONTEND_HTML"] = fs.readFile("./front_end.html"),
    ["PORT"]          = (8080),
}
--
-- RETURN VALUE
--
return CONSTANTS