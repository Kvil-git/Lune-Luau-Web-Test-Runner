--!strict
--
-- REQUIRES
--
-- (none)

--
-- EXPORT TYPES
--

-- Legacy flat-list types (kept for backwards-compat with error pseudo-nodes)
export type Test_Status_HTML_Code = "passed" | "skipped" | "failed" | "total"
export type Test_Status           = "Passed" | "Skipped" | "Failed running" | "Failed test conditions"

export type Test_Info = {
    name               : string,
    path_to_test_file  : string,
    status             : Test_Status,
    status_html_code   : Test_Status_HTML_Code,
    error              : string?,
    execution_duration : number,
}

export type Test_Module = {
    name : string,
    path : string,
    func : () -> string,
}

-- Property-based testing strategy: generates random values and shrinks them
-- on test failure toward a minimal failing example.
export type Strategy<T> = {
    generate: () -> T,
    shrink:   (value: T) -> {T},
}

-- Tree node produced by the TestEZ compat layer.
-- Matches testez_compat.TestNode exactly.
export type TestNode = {
    type        : "describe" | "it",
    name        : string,
    status      : "pass" | "fail" | "skip",
    children    : {TestNode}?,
    error       : string?,
    duration_ms : number,
    seed        : number?,          -- seed for reproduction of property-based test
    falsifying  : {[string]: any}?, -- shrunk counterexample from property-based test
}

-- Aggregated counts for one level of the tree
export type Counts = {
    total   : number,
    passed  : number,
    failed  : number,
    skipped : number,
}

-- Top-level result for a single test file / spec suite
export type SuiteResult = {
    file        : string,        -- short filename e.g. "PlayerService.spec.luau"
    path        : string,        -- full path
    nodes       : {TestNode},    -- describe/it tree
    counts      : Counts,
    duration_ms : number,
    load_error  : string?,       -- set when the file failed to even load/compile
}

-- Overall runner results (returned by /results)
export type Test_Results = {
    total       : number,
    passed      : number,
    failed      : number,
    skipped     : number,
    suites      : {SuiteResult},
    is_running  : boolean,
    last_run_ms : number,
}

--
-- RETURN VALUE
--
return nil
