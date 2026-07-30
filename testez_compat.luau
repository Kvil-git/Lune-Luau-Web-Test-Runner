--!strict
--
-- TestEZ-compatible test API for Lune.
--
-- Usage (factory pattern avoids module-cache state pollution between files):
--
--   local TestEZ_Factory = require("./testez_compat")
--   local testez         = TestEZ_Factory.new()
--   -- inject testez.describe, testez.it, testez.expect … into the test env
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

--------------------------------------------------------------------------------
-- Internal node types (richer than the public result; stripped before export) --
--------------------------------------------------------------------------------

type Hook = () -> ()

type CollectionNode = {
    type        : "describe" | "it" | "skip_describe" | "skip_it",
    name        : string,
    fn          : Hook?,               -- test fn (it nodes only)
    children    : {CollectionNode}?,
    before_all  : {Hook}?,
    after_all   : {Hook}?,
    beforeEach : {Hook}?,
    after_each  : {Hook}?,
    -- written during phase 2:
    status      : "pass" | "fail" | "skip",
    error       : string?,
    duration_ms : number,
}

--------------------------------------------------------------------------------
-- Public result type (matches Types.luau TestNode)                            --
--------------------------------------------------------------------------------

export type TestNode = {
    type        : "describe" | "it",
    name        : string,
    status      : "pass" | "fail" | "skip",
    children    : {TestNode}?,
    error       : string?,
    duration_ms : number,
}

--------------------------------------------------------------------------------
-- expect() chain                                                               --
--------------------------------------------------------------------------------

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
    },
    {} :: { __index: any }
))

local function make_expect(value: any): Expectation
    local negated = false

    -- Chain table; matchers are closed over `value` and `negated`.
    local chain = {}

    local function assert_check(condition: boolean, msg: string)
        local pass = if negated then not condition else condition
        negated = false  -- reset after each matcher call
        if not pass then
            error(msg, 3)
        end
    end

    -- Chainable no-ops
    local NOOP_KEYS = {
        "to","be","been","is","was","has","have","of","still","and_",
    }

    setmetatable(chain, {
        __index = function(_, k: string): any
            if k == "never" then
                negated = not negated
                return chain
            end
            for _, nk in ipairs(NOOP_KEYS) do
                if k == nk then return chain end
            end
            return nil
        end,
    })

    -- equal / equals
    chain.equal = function(expected: any): Expectation
        assert_check(
            value == expected,
            ("Expected %s to equal %s"):format(tostring(value), tostring(expected))
        )
        return chain
    end
    chain.equals = chain.equal

    -- a / an  (type check)
    chain.a = function(t: string): Expectation
        assert_check(
            type(value) == t,
            ("Expected %s to be a %s, got %s"):format(tostring(value), t, type(value))
        )
        return chain
    end
    chain.an = chain.a

    -- ok (non-nil)
    chain.ok = function(): Expectation
        assert_check(
            value ~= nil,
            "Expected value to be non-nil"
        )
        return chain
    end

    -- truthy / falsy
    chain.truthy = function(): Expectation
        assert_check(
            value ~= nil and value ~= false,
            ("Expected %s to be truthy"):format(tostring(value))
        )
        return chain
    end

    chain.falsy = function(): Expectation
        assert_check(
            value == nil or value == false,
            ("Expected %s to be falsy"):format(tostring(value))
        )
        return chain
    end

    -- throw  (value must be a function)
    chain.throw = function(pattern: string?): Expectation
        if type(value) ~= "function" then
            error("expect(...).to.throw() requires a function value", 2)
        end
        local ok, err = pcall(value :: () -> ())
        local threw = not ok
        if pattern and threw then
            threw = tostring(err):find(pattern, 1, true) ~= nil
        end
        assert_check(
            threw,
            pattern
                and ("Expected function to throw with message matching %q"):format(pattern)
                or  "Expected function to throw"
        )
        return chain
    end

    -- near  (numeric approximate equality)
    chain.near = function(expected: number, delta: number?): Expectation
        local d = delta or 1e-7
        assert_check(
            math.abs((value :: number) - expected) <= d,
            ("Expected %s to be near %s (±%s)"):format(
                tostring(value), tostring(expected), tostring(d)
            )
        )
        return chain
    end

    -- contain  (substring or table membership)
    chain.contain = function(item: any): Expectation
        local found = false
        if type(value) == "string" then
            found = (value :: string):find(tostring(item), 1, true) ~= nil
        elseif type(value) == "table" then
            for _, v in ipairs(value :: {any}) do
                if v == item then found = true; break end
            end
        end
        assert_check(
            found,
            ("Expected %s to contain %s"):format(tostring(value), tostring(item))
        )
        return chain
    end

    -- above  (numeric greater-than)
    chain.above = function(expected: number): Expectation
        assert_check(
            (value :: number) > expected,
            ("Expected %s to be above %s"):format(tostring(value), tostring(expected))
        )
        return chain
    end

    -- below  (numeric less-than)
    chain.below = function(expected: number): Expectation
        assert_check(
            (value :: number) < expected,
            ("Expected %s to be below %s"):format(tostring(value), tostring(expected))
        )
        return chain
    end

    return chain
end

--------------------------------------------------------------------------------
-- Factory                                                                      --
--------------------------------------------------------------------------------

local TestEZ_Factory = {}

function TestEZ_Factory.new()
    local self = {}

    -- Root-level collection list
    local root_children: {CollectionNode} = {}
    -- Stack of describe nodes currently being collected
    local context_stack: {CollectionNode} = {}

    local function current_ctx(): CollectionNode?
        return context_stack[#context_stack]
    end

    local function push_child(node: CollectionNode)
        local ctx = current_ctx()
        if ctx then
            local kids = ctx.children :: {CollectionNode}
            table.insert(kids, node)
        else
            table.insert(root_children, node)
        end
    end

    ----------------------------------------------------------------------------
    -- Collection API                                                          --
    ----------------------------------------------------------------------------

    function self.describe(name: string, fn: () -> ())
        local node: CollectionNode = {
            type        = "describe",
            name        = name,
            fn          = nil,
            children    = {},
            before_all  = {},
            after_all   = {},
            beforeEach = {},
            after_each  = {},
            status      = "pass",
            error       = nil,
            duration_ms = 0,
        }
        push_child(node)
        table.insert(context_stack, node)

        -- Run fn to collect children (phase 1)
        local ok, err = pcall(fn)
        if not ok then
            node.status = "fail"
            node.error  = tostring(err)
        end

        table.remove(context_stack)
    end

    -- SKIP variants — register as skip nodes, never execute
    function self.xdescribe(name: string, _fn: () -> ())
        local node: CollectionNode = {
            type        = "skip_describe",
            name        = name,
            fn          = nil,
            children    = {},
            before_all  = nil,
            after_all   = nil,
            beforeEach = nil,
            after_each  = nil,
            status      = "skip",
            error       = nil,
            duration_ms = 0,
        }
        push_child(node)
    end

    function self.it(name: string, fn: () -> ())
        local node: CollectionNode = {
            type        = "it",
            name        = name,
            fn          = fn,
            children    = nil,
            before_all  = nil,
            after_all   = nil,
            beforeEach = nil,
            after_each  = nil,
            status      = "pass",
            error       = nil,
            duration_ms = 0,
        }
        push_child(node)
    end

    function self.xit(name: string, _fn: () -> ()?)
        local node: CollectionNode = {
            type        = "skip_it",
            name        = name,
            fn          = nil,
            children    = nil,
            before_all  = nil,
            after_all   = nil,
            beforeEach = nil,
            after_each  = nil,
            status      = "skip",
            error       = nil,
            duration_ms = 0,
        }
        push_child(node)
    end

    -- Hook registration — only valid inside a describe fn
    function self.beforeAll(fn: () -> ())
        local ctx = current_ctx()
        if ctx and ctx.before_all then
            table.insert(ctx.before_all :: {Hook}, fn)
        end
    end

    function self.afterAll(fn: () -> ())
        local ctx = current_ctx()
        if ctx and ctx.after_all then
            table.insert(ctx.after_all :: {Hook}, fn)
        end
    end

    function self.beforeEach(fn: () -> ())
        local ctx = current_ctx()
        if ctx and ctx.beforeEach then
            table.insert(ctx.beforeEach :: {Hook}, fn)
        end
    end

    function self.afterEach(fn: () -> ())
        local ctx = current_ctx()
        if ctx and ctx.after_each then
            table.insert(ctx.after_each :: {Hook}, fn)
        end
    end

    -- Aliases
    self.test = self.it
    self.SKIP = self.xit

    -- expect
    self.expect = make_expect

    ----------------------------------------------------------------------------
    -- Phase 2: Execution                                                      --
    ----------------------------------------------------------------------------

    -- on_test_done: optional callback called after every it() completes.
    -- Signature: on_test_done(node: CollectionNode)
    local on_test_done_cb: ((CollectionNode) -> ())?  = nil

    function self.set_on_test_done(cb: (CollectionNode) -> ())
        on_test_done_cb = cb
    end

    local function run_hooks(hooks: {Hook}?)
        if not hooks then return end
        for _, h in ipairs(hooks) do
            local ok, err = pcall(h)
            if not ok then
                -- Hook errors bubble as a warning but don't abort the suite
                warn(("[testez] hook error: %s"):format(tostring(err)))
            end
        end
    end

    local function execute_node(
        node          : CollectionNode,
        inh_before    : {Hook},
        inh_after     : {Hook}
    )
        if node.type == "skip_describe" or node.type == "skip_it" then
            -- Already marked skip during collection — nothing to run
            return
        end

        if node.type == "it" then
            -- Compose beforeEach chain
            for _, h in ipairs(inh_before) do
                local ok, err = pcall(h)
                if not ok then
                    node.status = "fail"
                    node.error  = ("[beforeEach] %s"):format(tostring(err))
                end
            end

            if node.status ~= "fail" then
                local t0 = os.clock()
                local ok, err = pcall(node.fn :: Hook)
                node.duration_ms = (os.clock() - t0) * 1000
                if not ok then
                    node.status = "fail"
                    node.error  = tostring(err)
                end
            end

            -- afterEach (run even on failure)
            for i = #inh_after, 1, -1 do
                local ok, err = pcall(inh_after[i])
                if not ok then
                    -- Don't overwrite original failure message
                    if node.status ~= "fail" then
                        node.status = "fail"
                        node.error  = ("[afterEach] %s"):format(tostring(err))
                    end
                end
            end

            if on_test_done_cb then
                on_test_done_cb(node)
            end

        elseif node.type == "describe" then
            -- Run beforeAll once for this scope
            run_hooks(node.before_all)

            -- Compose inherited hooks with this scope's hooks
            local new_before: {Hook} = {}
            for _, h in ipairs(inh_before) do table.insert(new_before, h) end
            if node.beforeEach then
                for _, h in ipairs(node.beforeEach :: {Hook}) do
                    table.insert(new_before, h)
                end
            end

            local new_after: {Hook} = {}
            for _, h in ipairs(inh_after) do table.insert(new_after, h) end
            if node.after_each then
                for _, h in ipairs(node.after_each :: {Hook}) do
                    table.insert(new_after, h)
                end
            end

            for _, child in ipairs(node.children :: {CollectionNode}) do
                execute_node(child, new_before, new_after)
            end

            run_hooks(node.after_all)

            -- Roll up status from children
            for _, child in ipairs(node.children :: {CollectionNode}) do
                if child.status == "fail" then
                    node.status = "fail"
                    break
                end
            end
        end
    end

    -- Run the collected tree. Call this after the test file has been executed.
    function self.execute()
        for _, node in ipairs(root_children) do
            execute_node(node, {}, {})
        end
    end

    ----------------------------------------------------------------------------
    -- Export results (strips internal fields)                                 --
    ----------------------------------------------------------------------------

    local function export_node(node: CollectionNode): TestNode
        local out: TestNode = {
            type        = if node.type == "skip_describe" then "describe" else
                          if node.type == "skip_it"       then "it"       else
                          node.type,
            name        = node.name,
            status      = node.status,
            error       = node.error,
            duration_ms = node.duration_ms,
            children    = nil,
        }
        if node.children then
            local kids: {TestNode} = {}
            for _, child in ipairs(node.children :: {CollectionNode}) do
                table.insert(kids, export_node(child))
            end
            out.children = kids
        end
        return out
    end

    function self.get_results(): {TestNode}
        local out: {TestNode} = {}
        for _, node in ipairs(root_children) do
            table.insert(out, export_node(node))
        end
        return out
    end

    return self
end
--
-- RETURN VALUE
--
return TestEZ_Factory