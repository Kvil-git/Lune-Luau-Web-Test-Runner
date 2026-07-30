--!strict
--
-- REQUIRES
--
local fs = require("@lune/fs")

--
-- MODULE DEFINITION
--
-- Responsible only for discovering test files on disk.
-- Loading and executing them is handled by Sandbox.
--
local Test_Loader = {}

--
-- LOCAL FUNCTIONS
--

--
-- Recursively collects all *.spec.luau / *.spec.lua files under `folder`.
-- Also accepts plain *.luau / *.lua as test files (for the flat bundle dir).
--
-- Parameters:
--     folder    (string)  - The folder to scan.
--     recursive (boolean?) - Whether to scan recursively (default: false).
--
-- Returns:
--     ({string}, string?) - Array of full paths and optional error.
--
function Test_Loader.Find_Test_Files(folder: string, recursive: boolean?): ({string}, string?)
    if (not fs.isDir(folder)) then
        return {}, ("Folder \"%s\" does not exist or is not a directory."):format(folder)
    end

    local results: {string} = {}
    local IGNORED_DIRS: {[string]: boolean} = {
        ["Scripts_Copies_With_String_Requires"] = true,
    }

    local function Scan(dir: string)
        local scan_ok, dir_list = pcall(function()
            return fs.readDir(dir)
        end)

        if (not scan_ok) then
            return
        end

        for _, name in ipairs(dir_list) do
            local full_path = dir .. "/" .. name

            if (fs.isDir(full_path)) and (recursive ~= false) and (not IGNORED_DIRS[name]) then
                Scan(full_path)
            elseif (name:match("%.spec%.luau$") ~= nil)
                or (name:match("%.spec%.lua$") ~= nil)
                or (name:match("%.luau$") ~= nil)
                or (name:match("%.lua$") ~= nil)
            then
                table.insert(results, full_path)
            end
        end
    end

    Scan(folder)

    return results, nil
end

--
-- Returns bare filenames (not full paths) for backwards compatibility.
--
-- Parameters:
--     folder (string) - The folder to scan.
--
-- Returns:
--     ({string}, string?) - Array of filenames and optional error.
--
function Test_Loader.Extract_Test_Filenames_From_Folder(folder: string): ({string}, string?)
    if (not fs.isDir(folder)) then
        return {}, ("Folder \"%s\" was not found. Can't possibly load tests from it."):format(folder)
    end

    local entries: {string}
    local read_ok, read_err = pcall(function()
        entries = fs.readDir(folder)
    end)

    if (not read_ok) then
        return {}, tostring(read_err)
    end

    local test_files: {string} = {}

    for _, name in ipairs(entries) do
        local is_luau = (name:match("%.luau$") ~= nil)
        local is_lua  = (name:match("%.lua$")  ~= nil)

        if (is_luau or is_lua) then
            table.insert(test_files, name)
        end
    end

    return test_files, nil
end

--
-- RETURN VALUE
--
return Test_Loader
