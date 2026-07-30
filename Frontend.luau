--!strict
--
-- Frontend
--
-- Manages the HTML frontend for the test runner.
-- Separates frontend concerns from server configuration.
--

local Config = require("./Config")

export type Frontend = {
    get_html: () -> string,
    get_content_type: () -> string,
}

local Frontend = {} :: Frontend

function Frontend.get_html(): string
    return Config:get_frontend_html()
end

function Frontend.get_content_type(): string
    return "text/html"
end

return Frontend
