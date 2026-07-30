--!strict
--
-- TestEZ-compatible test API for Lune.
--
-- Usage (factory pattern avoids module-cache state pollution between files):
--
--   local TestEZ_Factory = require("./testez_compat")
--   local testez         = TestEZ_Factory.new()
--   -- inject testez.describe, testez.it, testez.expect ... into the test env
--   -- run the test file
--   local results = testez:get_results()
--
-- Architecture: two-phase execution.
--   Phase 1 (collection) : describe() runs its fn immediately to collect child nodes.
--                          it() registers a node but does NOT run its fn yet.
--   Phase 2 (execution)  : traverse the collected tree; run hooks and test fns in order.
--
-- This matches upstream TestEZ behaviour and means beforeAll/afterAll work correctly
-- even when they are declared after it() calls inside the same describe block.
--

--
-- EXPORT TYPES
--
--
-- Strategy for property-based testing: generates random values and shrinks them
-- on failure toward a minimal failing example.
--
export type Strategy<T> = {
    generate: () -> T,
    shrink:   (value: T) -> {T},
}

--
-- Internal node types (richer than the public result; stripped before export)
--
type Hook = () -> ()

type CollectionNode = {
    type        : "describe" | "it" | "skip_describe" | "skip_it",
    name        : string,
    fn          : Hook?,                 -- test fn (it nodes only)
    children    : {CollectionNode}?,
    before_all  : {Hook}?,
    after_all   : {Hook}?,
    beforeEach  : {Hook}?,
    after_each  : {Hook}?,
    -- written during phase 2:
    status      : "pass" | "fail" | "skip",
    error       : string?,
    duration_ms : number,
    seed        : number?,
    falsifying  : {[string]: any}?,
}

--
-- Public result type (matches Types.luau TestNode)
--
export type TestNode = {
    type        : "describe" | "it",
    name        : string,
    status      : "pass" | "fail" | "skip",
    children    : {TestNode}?,
    error       : string?,
    duration_ms : number,
    seed        : number?,
    falsifying  : {[string]: any}?,
}

--
-- expect() chain
--

-- forward-declare so the type can self-reference
export type Expectation = typeof(setmetatable(
    {} :: {
        to      : Expectation,
        be      : Expectation,
        been    : Expectation,
        is      : Expectation,
        was     : Expectation,
        has     : Expectation,
        have    : Expectation,
        of      : Expectation,
        still   : Expectation,
        never   : Expectation,
        -- matchers (return self for chaining)
        equal   : (any)     -> Expectation,
        equals  : (any)     -> Expectation,
        a       : (string)  -> Expectation,
        an      : (string)  -> Expectation,
        ok      : ()        -> Expectation,
        truthy  : ()        -> Expectation,
        falsy   : ()        -> Expectation,
        throw   : (string?) -> Expectation,
        near    : (number, number?) -> Expectation,
        contain : (any)     -> Expectation,
        above   : (number)  -> Expectation,
        below   : (number)  -> Expectation,
    },
    {} :: { __index: any }
))

--
-- Creates an expect() chain for the given value.
--
local function Make_Expect(value: any): Expectation
    local negated = false

    -- Chain table; matchers are closed over `value` and `negated`.
    local chain = {}

    local function Assert_Check(condition: boolean, msg: string)
        local pass: boolean

        if (negated) then
            pass = not condition
        else
            pass = condition
        end

        negated = false  -- reset after each matcher call

        if (not pass) then
            error(msg, 3)
        end
    end

    -- Chainable no-ops
    local NOOP_KEYS = {
        "to", "be", "been", "is", "was", "has", "have", "of", "still", "and_",
    }

    setmetatable(chain, {
        __index = function(_, k: string): any
            if (k == "never") then
                negated = not negated
                return chain
            end

            for _, nk in ipairs(NOOP_KEYS) do
                if (k == nk) then
                    return chain
                end
            end

            return nil
        end,
    })

    -- equal / equals
    chain.equal = function(expected: any): Expectation
        Assert_Check(
            value == expected,
            ("Expected %s to equal %s"):format(tostring(value), tostring(expected))
        )
        return chain
    end
    chain.equals = chain.equal

    -- a / an  (type check)
    chain.a = function(t: string): Expectation
        Assert_Check(
            type(value) == t,
            ("Expected %s to be a %s, got %s"):format(tostring(value), t, type(value))
        )
        return chain
    end
    chain.an = chain.a

    -- ok (non-nil)
    chain.ok = function(): Expectation
        Assert_Check(
            value ~= nil,
            "Expected value to be non-nil"
        )
        return chain
    end

    -- truthy / falsy
    chain.truthy = function(): Expectation
        local is_truthy = (value ~= nil) and (value ~= false)

        Assert_Check(
            is_truthy,
            ("Expected %s to be truthy"):format(tostring(value))
        )
        return chain
    end

    chain.falsy = function(): Expectation
        local is_falsy = (value == nil) or (value == false)

        Assert_Check(
            is_falsy,
            ("Expected %s to be falsy"):format(tostring(value))
        )
        return chain
    end

    -- throw  (value must be a function)
    chain.throw = function(pattern: string?): Expectation
        if (type(value) ~= "function") then
            error("expect(...).to.throw() requires a function value", 2)
        end

        local call_ok, call_err = pcall(value :: () -> ())
        local threw = not call_ok

        if (pattern ~= nil) and (threw) then
            threw = (tostring(call_err):find(pattern, 1, true) ~= nil)
        end

        Assert_Check(
            threw,
            (function()
                if (pattern ~= nil) then
                    return ("Expected function to throw with message matching %q"):format(pattern)
                end
                return "Expected function to throw"
            end)()
        )
        return chain
    end

    -- near  (numeric approximate equality)
    chain.near = function(expected: number, delta: number?): Expectation
        local d = delta or 1e-7

        Assert_Check(
            math.abs((value :: number) - expected) <= d,
            ("Expected %s to be near %s (+-%s)"):format(
                tostring(value), tostring(expected), tostring(d)
            )
        )
        return chain
    end

    -- contain  (substring or table membership)
    chain.contain = function(item: any): Expectation
        local found = false

        if (type(value) == "string") then
            found = ((value :: string):find(tostring(item), 1, true) ~= nil)
        elseif (type(value) == "table") then
            for _, array_item in ipairs(value :: {any}) do
                if (array_item == item) then
                    found = true
                    break
                end
            end
        end

        Assert_Check(
            found,
            ("Expected %s to contain %s"):format(tostring(value), tostring(item))
        )
        return chain
    end

    -- above  (numeric greater-than)
    chain.above = function(expected: number): Expectation
        Assert_Check(
            (value :: number) > expected,
            ("Expected %s to be above %s"):format(tostring(value), tostring(expected))
        )
        return chain
    end

    -- below  (numeric less-than)
    chain.below = function(expected: number): Expectation
        Assert_Check(
            (value :: number) < expected,
            ("Expected %s to be below %s"):format(tostring(value), tostring(expected))
        )
        return chain
    end

    return chain
end

--
-- Property-based testing: shrink engine
--

--
-- Finds the minimal failing input by repeatedly shrinking each field.
--
-- For each field, tries the strategy's shrink candidates. If a candidate
-- still causes the test body to fail, recurses on that candidate. Continues
-- until no field can be shrunk further.
--
-- Parameters:
--     strategies   ({[string]: Strategy<any>}) - Named strategies for each field
--     body         (({[string]: any}) -> ())    - Test function to run with candidate inputs
--     initial_args ({[string]: any})           - The first failing input
--
-- Returns:
--     {[string]: any} - The minimal failing input found
--
local function Shrink_To_Minimal(
    strategies   : {[string]: Strategy<any>},
    body         : (args: {[string]: any}) -> (),
    initial_args : {[string]: any}
): {[string]: any}
    local current       = initial_args
    local max_iterations = 1000
    local iteration      = 0

    while true do
        iteration += 1

        if (iteration > max_iterations) then
            break
        end

        local improved = false

        for key, strategy in strategies do
            local value      = current[key]
            local candidates = strategy.shrink(value)

            for _, candidate in ipairs(candidates) do
                local new_args: {[string]: any} = {}

                for existing_key, existing_value in current do
                    new_args[existing_key] = existing_value
                end

                new_args[key] = candidate

                local body_ok, _ = pcall(body, new_args)

                if (not body_ok) then
                    current  = new_args
                    improved = true
                    break
                end
            end

            if (improved) then
                break
            end
        end

        if (not improved) then
            break
        end
    end

    return current
end

--
-- Formats a falsifying example into a readable error string.
--
-- Parameters:
--     shrunk    ({[string]: any}) - The minimal failing example
--     seed      (number) - The seed used for generation
--     orig_err  (string) - The original error message from the test body
--
-- Returns:
--     string
--
local function Format_Failure(shrunk: {[string]: any}, seed: number, orig_err: string): string
    local parts: {string} = {}

    for key, current_value in shrunk do
        local value_str = tostring(current_value)
        table.insert(parts, key .. " = " .. value_str)
    end

    local falsifying_str = "{ " .. table.concat(parts, ", ") .. " }"

    return ("Falsifying example: %s\n(seed: %d)\nOriginal error: %s")
        :format(falsifying_str, seed, orig_err)
end

--
-- Factory
--
local TestEZ_Factory = {}

function TestEZ_Factory.new(seed: number?, examples: number?)
    local self = {}

    self.base_seed       = seed or math.floor(os.time() * 10000 + os.clock() * 10000) % 2147483647
    self.examples_count  = examples or 100
    self.given_counter   = 0
    self.last_seed       = nil
    self.last_falsifying = nil

    -- Root-level collection list
    local root_children: {CollectionNode} = {}
    -- Stack of describe nodes currently being collected
    local context_stack: {CollectionNode} = {}

    local function Current_Context(): CollectionNode?
        return context_stack[#context_stack]
    end

    local function Push_Child(node: CollectionNode)
        local ctx = Current_Context()

        if (ctx ~= nil) then
            local kids = ctx.children :: {CollectionNode}
            table.insert(kids, node)
        else
            table.insert(root_children, node)
        end
    end

    --
    -- Collection API
    --

    function self.describe(name: string, fn: () -> ())
        local node: CollectionNode = {
            type        = "describe",
            name        = name,
            fn          = nil,
            children    = {},
            before_all  = {},
            after_all   = {},
            beforeEach  = {},
            after_each  = {},
            status      = "pass",
            error       = nil,
            duration_ms = 0,
        }

        Push_Child(node)
        table.insert(context_stack, node)

        -- Run fn to collect children (phase 1)
        local collect_ok, collect_err = pcall(fn)

        if (not collect_ok) then
            node.status = "fail"
            node.error  = tostring(collect_err)
        end

        table.remove(context_stack)
    end

    -- SKIP variants - register as skip nodes, never execute
    function self.xdescribe(name: string, _fn: () -> ())
        local node: CollectionNode = {
            type        = "skip_describe",
            name        = name,
            fn          = nil,
            children    = {},
            before_all  = nil,
            after_all   = nil,
            beforeEach  = nil,
            after_each  = nil,
            status      = "skip",
            error       = nil,
            duration_ms = 0,
        }

        Push_Child(node)
    end

    function self.it(name: string, fn: () -> ())
        local node: CollectionNode = {
            type        = "it",
            name        = name,
            fn          = fn,
            children    = nil,
            before_all  = nil,
            after_all   = nil,
            beforeEach  = nil,
            after_each  = nil,
            status      = "pass",
            error       = nil,
            duration_ms = 0,
        }

        Push_Child(node)
    end

    function self.xit(name: string, _fn: () -> ()?)
        local node: CollectionNode = {
            type        = "skip_it",
            name        = name,
            fn          = nil,
            children    = nil,
            before_all  = nil,
            after_all   = nil,
            beforeEach  = nil,
            after_each  = nil,
            status      = "skip",
            error       = nil,
            duration_ms = 0,
        }

        Push_Child(node)
    end

    -- Hook registration - only valid inside a describe fn
    function self.beforeAll(fn: () -> ())
        local ctx = Current_Context()

        if (ctx ~= nil) and (ctx.before_all ~= nil) then
            table.insert(ctx.before_all :: {Hook}, fn)
        end
    end

    function self.afterAll(fn: () -> ())
        local ctx = Current_Context()

        if (ctx ~= nil) and (ctx.after_all ~= nil) then
            table.insert(ctx.after_all :: {Hook}, fn)
        end
    end

    function self.beforeEach(fn: () -> ())
        local ctx = Current_Context()

        if (ctx ~= nil) and (ctx.beforeEach ~= nil) then
            table.insert(ctx.beforeEach :: {Hook}, fn)
        end
    end

    function self.afterEach(fn: () -> ())
        local ctx = Current_Context()

        if (ctx ~= nil) and (ctx.after_each ~= nil) then
            table.insert(ctx.after_each :: {Hook}, fn)
        end
    end

    -- Aliases
    self.test = self.it
    self.SKIP = self.xit

    -- expect
    self.expect = Make_Expect

    --
    -- Property-based testing: given()
    --

    --
    -- Generates random examples using the provided strategies and runs the test
    -- body with each. On failure, shrinks the input to find the minimal failing
    -- example and reports it with the seed for reproduction.
    --
    -- Usage:
    --   given({
    --       a = g.integer(1, 100),
    --       b = g.integer(1, 100),
    --   }, function(args)
    --       expect(args.a + args.b).to.be.above(args.a)
    --   end)
    --
    -- Parameters:
    --     strategies ({[string]: Strategy<any>}) - Named strategies keyed by parameter name
    --     body       (({[string]: any}) -> ())     - Test function receiving generated args
    --
    function self.given(strategies: {[string]: Strategy<any>}, body: (args: {[string]: any}) -> ())
        self.given_counter += 1

        local given_seed = self.base_seed + self.given_counter

        for i = 1, self.examples_count do
            math.randomseed(given_seed + i)

            local args: {[string]: any} = {}

            for key, strategy in strategies do
                args[key] = strategy.generate()
            end

            local body_ok, body_err = pcall(body, args)

            if (not body_ok) then
                local shrunk = Shrink_To_Minimal(strategies, body, args)

                self.last_seed       = given_seed
                self.last_falsifying = shrunk

                local message = Format_Failure(shrunk, given_seed, tostring(body_err))
                error(message)
            end
        end
    end

    --
    -- Phase 2: Execution
    --

    -- on_test_done: optional callback called after every it() completes.
    -- Signature: on_test_done(node: CollectionNode)
    local on_test_done_cb: ((CollectionNode) -> ())? = nil

    function self.set_on_test_done(cb: (CollectionNode) -> ())
        on_test_done_cb = cb
    end

    local function Run_Hooks(hooks: {Hook}?)
        if (hooks == nil) then
            return
        end

        for _, h in ipairs(hooks) do
            local hook_ok, hook_err = pcall(h)

            if (not hook_ok) then
                -- Hook errors bubble as a warning but do not abort the suite
                warn(("[testez] hook error: %s"):format(tostring(hook_err)))
            end
        end
    end

    local function Execute_Node(
        node        : CollectionNode,
        inh_before  : {Hook},
        inh_after   : {Hook}
    )
        if (node.type == "skip_describe") or (node.type == "skip_it") then
            -- Already marked skip during collection - nothing to run
            return
        end

        if (node.type == "it") then
            -- Clear property-test state before running
            self.last_seed       = nil
            self.last_falsifying = nil

            -- Compose beforeEach chain
            for _, h in ipairs(inh_before) do
                local hook_ok, hook_err = pcall(h)

                if (not hook_ok) then
                    node.status = "fail"
                    node.error  = ("[beforeEach] %s"):format(tostring(hook_err))
                end
            end

            if (node.status ~= "fail") then
                local t0       = os.clock()
                local test_ok, test_err = pcall(node.fn :: Hook)
                node.duration_ms = (os.clock() - t0) * 1000

                if (not test_ok) then
                    node.status = "fail"
                    node.error  = tostring(test_err)

                    -- Propagate property-test data to the node if set
                    if (self.last_seed ~= nil) then
                        node.seed       = self.last_seed
                        node.falsifying = self.last_falsifying
                    end
                end
            end

            -- afterEach (run even on failure)
            for i = #inh_after, 1, -1 do
                local after_ok, after_err = pcall(inh_after[i])

                if (not after_ok) then
                    -- Do not overwrite original failure message
                    if (node.status ~= "fail") then
                        node.status = "fail"
                        node.error  = ("[afterEach] %s"):format(tostring(after_err))
                    end
                end
            end

            if (on_test_done_cb ~= nil) then
                on_test_done_cb(node)
            end

        elseif (node.type == "describe") then
            -- Run beforeAll once for this scope
            Run_Hooks(node.before_all)

            -- Compose inherited hooks with this scope's hooks
            local new_before: {Hook} = {}

            for _, h in ipairs(inh_before) do
                table.insert(new_before, h)
            end

            if (node.beforeEach ~= nil) then
                for _, h in ipairs(node.beforeEach :: {Hook}) do
                    table.insert(new_before, h)
                end
            end

            local new_after: {Hook} = {}

            for _, h in ipairs(inh_after) do
                table.insert(new_after, h)
            end

            if (node.after_each ~= nil) then
                for _, h in ipairs(node.after_each :: {Hook}) do
                    table.insert(new_after, h)
                end
            end

            for _, child in ipairs(node.children :: {CollectionNode}) do
                Execute_Node(child, new_before, new_after)
            end

            Run_Hooks(node.after_all)

            -- Roll up status from children
            for _, child in ipairs(node.children :: {CollectionNode}) do
                if (child.status == "fail") then
                    node.status = "fail"
                    break
                end
            end
        end
    end

    -- Run the collected tree. Call this after the test file has been executed.
    function self.execute()
        for _, node in ipairs(root_children) do
            Execute_Node(node, {}, {})
        end
    end

    --
    -- Export results (strips internal fields)
    --

    local function Export_Node(node: CollectionNode): TestNode
        local resolved_type: "describe" | "it"

        if (node.type == "skip_describe") then
            resolved_type = "describe"
        elseif (node.type == "skip_it") then
            resolved_type = "it"
        else
            resolved_type = node.type
        end

        local out: TestNode = {
            type        = resolved_type,
            name        = node.name,
            status      = node.status,
            error       = node.error,
            duration_ms = node.duration_ms,
            seed        = node.seed,
            falsifying  = node.falsifying,
            children    = nil,
        }

        if (node.children ~= nil) then
            local exported_kids: {TestNode} = {}

            for _, child in ipairs(node.children :: {CollectionNode}) do
                table.insert(exported_kids, Export_Node(child))
            end

            out.children = exported_kids
        end

        return out
    end

    function self.get_results(): {TestNode}
        local out: {TestNode} = {}

        for _, node in ipairs(root_children) do
            table.insert(out, Export_Node(node))
        end

        return out
    end

    return self
end

--
-- RETURN VALUE
--
return TestEZ_Factory
