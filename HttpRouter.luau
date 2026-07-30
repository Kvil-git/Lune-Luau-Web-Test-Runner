--!strict
--
-- HttpRouter
--
-- HTTP request routing and handling.
-- Separates HTTP concerns from the main server.
--

--
-- REQUIRES
--
local serde      = require("@lune/serde")
local Frontend   = require("./Frontend")
local Test_Runner = require("./Test_Runner")
local EventBus   = require("./EventBus")

--
-- EXPORT TYPES
--
export type HttpRequest = {
    path: string,
    method: string,
    [string]: any,
}

export type HttpResponse = {
    status: number,
    headers: {[string]: string}?,
    body: string,
}

export type HttpHandler  = (req: HttpRequest) -> HttpResponse
export type HttpRouter   = {
    handle_request: (self: HttpRouter, req: HttpRequest) -> HttpResponse,
}

--
-- LOCAL FUNCTIONS
--

--
-- Creates a JSON response with the given status code and data.
--
local function Create_Json_Response(status: number, data: any): HttpResponse
    return {
        status  = status,
        headers = { ["Content-Type"] = "application/json" },
        body    = serde.encode("json", data),
    }
end

--
-- Creates a plain text response with the given status code and content type.
--
local function Create_Text_Response(status: number, text: string, content_type: string?): HttpResponse
    local resolved_type = content_type or "text/plain"

    return {
        status  = status,
        headers = { ["Content-Type"] = resolved_type },
        body    = text,
    }
end

--
-- Creates the router instance.
--
local function Create_Router(): HttpRouter
    local routes: {[string]: {[string]: HttpHandler}} = {}

    routes["GET"]  = {}
    routes["POST"] = {}

    -- GET / - Serve frontend
    routes["GET"]["/"] = function(req: HttpRequest): HttpResponse
        return {
            status  = 200,
            headers = { ["Content-Type"] = Frontend.get_content_type() },
            body    = Frontend.get_html(),
        }
    end

    -- GET /results - Current test results snapshot
    routes["GET"]["/results"] = function(req: HttpRequest): HttpResponse
        return Create_Json_Response(200, Test_Runner.results)
    end

    -- POST /run - Trigger test run
    routes["POST"]["/run"] = function(req: HttpRequest): HttpResponse
        if (Test_Runner.results.is_running) then
            return Create_Json_Response(409, {
                success = false,
                message = "Tests are already running",
            })
        end

        -- Trigger test run via EventBus
        EventBus:emit("http:run_tests", {})

        return Create_Json_Response(202, {
            success = true,
            message = "Test run started",
        })
    end

    return {
        handle_request = function(self: HttpRouter, req: HttpRequest): HttpResponse
            local method_routes = routes[req.method]

            if (method_routes == nil) then
                return Create_Text_Response(405, "Method Not Allowed", "text/plain")
            end

            local handler = method_routes[req.path]

            if (handler == nil) then
                return Create_Text_Response(404, "Not Found", "text/plain")
            end

            local success, result = pcall(handler, req)

            if (not success) then
                warn(("[HttpRouter] Handler error for %s %s: %s"):format(
                    req.method, req.path, tostring(result)))

                return Create_Text_Response(500, "Internal Server Error", "text/plain")
            end

            return result
        end,
    }
end

--
-- RETURN VALUE
--
return Create_Router()
