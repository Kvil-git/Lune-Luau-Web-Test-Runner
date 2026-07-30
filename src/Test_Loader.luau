--!strict
--
-- REQUIRES
--
local fs   = require("@lune/fs")
local luau = require("@lune/luau")
--
-- MODULE DEFINITION
--
local Test_Loader = {}

function Test_Loader.Extract_Test_Filenames_From_Folder(folder_with_tests: string): ({string}, string?)
    if not fs.isDir(folder_with_tests) then
        return {}, `Folder "{folder_with_tests}" was not found. Can't possibly load tests from it.`
    end
    
    local entryPaths = fs.readDir(folder_with_tests)
    local testFiles = {}
    
    for _, entryPath in ipairs(entryPaths) do
        --
        -- Skip all files other than "{name}.lua" and "{name}.luau".
        --
        if (not entryPath:match("%.luau$")) and (not entryPath:match("%.lua$")) then
            continue
        end
        
        table.insert(testFiles, entryPath)
    end
    
    return testFiles, nil
end
--
-- Function description:
--    Tries to load a luau function from a specified file.
--
-- Notes:
--    In the context of this program this function is
--    only used for loading test files.
--
-- Return value:
--    Error? =>  (nil           , "Error string")
--    Else   =>  (test_function , nil)
--
function Test_Loader.Load_Tests_From_File(path_to_test_file: string, test_file_name: string): (any, string?)
    local module_content = fs.readFile(path_to_test_file)
    
    local success, result = pcall(function()
        return luau.load(module_content, {
            debugName = test_file_name
        })
    end)
    
    if not success then
        return nil, `Failed to load module: {result or "Unknown error"}.`
    end
    
    if typeof(result) ~= "function" then
        return nil, "Module did not return a function"
    end
    
    return result, nil
end
--
-- RETURN VALUE
--
return Test_Loader