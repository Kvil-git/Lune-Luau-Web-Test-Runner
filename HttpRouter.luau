--!strict
--
-- HttpRouter
--
-- HTTP request routing and handling.
-- Separates HTTP concerns from the main server.
--

local serde = require("@lune/serde")
local Frontend = require("./Frontend")
local Test_Runner = require("./Test_Runner")
local EventBus = require("./EventBus")

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

export type HttpHandler = (req: HttpRequest) -> HttpResponse
export type HttpRouter = {
    handle_request: (self: HttpRouter, req: HttpRequest) -> HttpResponse,
}

local function create_json_response(status: number, data: any): HttpResponse
    return {
        status = status,
        headers = { ["Content-Type"] = "application/json" },
        body = serde.encode("json", data),
    }
end

local function create_text_response(status: number, text: string, content_type: string?): HttpResponse
    return {
        status = status,
        headers = { ["Content-Type"] = content_type or "text/plain" },
        body = text,
    }
end

local function create_router(): HttpRouter
    local routes: {[string]: {[string]: HttpHandler}} = {}
    
    -- Register routes
    routes["GET"] = {}
    routes["POST"] = {}
    
    -- GET / - Serve frontend
    routes["GET"]["/"] = function(req: HttpRequest): HttpResponse
        return {
            status = 200,
            headers = { ["Content-Type"] = Frontend.get_content_type() },
            body = Frontend.get_html(),
        }
    end
    
    -- GET /results - Current test results snapshot
    routes["GET"]["/results"] = function(req: HttpRequest): HttpResponse
        return create_json_response(200, Test_Runner.results)
    end
    
    -- POST /run - Trigger test run
    routes["POST"]["/run"] = function(req: HttpRequest): HttpResponse
        if Test_Runner.results.is_running then
            return create_json_response(409, { 
                success = false, 
                message = "Tests are already running" 
            })
        end
        
        -- Trigger test run via EventBus
        EventBus:emit("http:run_tests", {})
        
        return create_json_response(202, { 
            success = true, 
            message = "Test run started" 
        })
    end
    
    return {
        handle_request = function(self: HttpRouter, req: HttpRequest): HttpResponse
            local method_routes = routes[req.method]
            if not method_routes then
                return create_text_response(405, "Method Not Allowed", "text/plain")
            end
            
            local handler = method_routes[req.path]
            if not handler then
                return create_text_response(404, "Not Found", "text/plain")
            end
            
            local success, result = pcall(handler, req)
            if not success then
                warn(("[HttpRouter] Handler error for %s %s: %s"):format(
                    req.method, req.path, tostring(result)
                ))
                return create_text_response(500, "Internal Server Error", "text/plain")
            end
            
            return result
        end,
    }
end

return create_router()
