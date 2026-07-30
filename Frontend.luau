--!strict
--
-- Frontend
--
-- Manages the HTML frontend for the test runner.
-- Separates frontend concerns from server configuration.
--

--
-- REQUIRES
--
local Config = require("./Config")

--
-- EXPORT TYPES
--
export type Frontend = {
    get_html:         () -> string,
    get_content_type: () -> string,
}

--
-- MODULE DEFINITION
--
local Frontend = {} :: Frontend

--
-- Returns the HTML content for the frontend.
--
function Frontend.get_html(): string
    return Config:get_frontend_html()
end

--
-- Returns the content type for the frontend.
--
function Frontend.get_content_type(): string
    return "text/html"
end

--
-- RETURN VALUE
--
return Frontend
