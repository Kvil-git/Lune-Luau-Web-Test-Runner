--!strict
--
-- EXPORT TYPES
--
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
    name: string,
    path: string,

    func: () -> string,
}

export type Test_Results = {
    total:       number,
    passed:      number,
    failed:      number,
    skipped:     number,
    tests:      {Test_Info},
    isRunning:   boolean,
    lastRunTime: number?
}
--
-- RETURN VALUE
--
return nil