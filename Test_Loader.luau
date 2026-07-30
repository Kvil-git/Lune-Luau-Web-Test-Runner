--!strict
--
-- REQUIRES
--
-- Requires
local fs = require("@lune/fs")
--
-- MODULE DEFINITION
--
-- Responsible only for discovering test files on disk.
-- Loading and executing them is handled by Sandbox.
local Test_Loader = {}

--
-- Recursively collects all *.spec.luau / *.spec.lua files under `folder`.
-- Also accepts plain *.luau / *.lua as test files (for the flat bundle dir).
--
-- Returns:
--     ({string}, string?) - Array of full paths and optional error.
--
function Test_Loader.Find_Test_Files(folder: string, recursive: boolean?): ({string}, string?)
    if not fs.isDir(folder) then
        return {}, (`Folder "{folder}" does not exist or is not a directory.`)
    end

    local results: {string} = {}
    local ignored_dirs: {[string]: boolean} = {
        ["Scripts_Copies_With_String_Requires"] = true,
    }

    local function scan(dir: string)
        local ok, list = pcall(function() return fs.readDir(dir) end)
        if not ok then return end

        for _, name in ipairs(list) do
            local full = dir .. "/" .. name
            if fs.isDir(full) and recursive ~= false and not ignored_dirs[name] then
                scan(full)
            elseif name:match("%.spec%.luau$")
                or name:match("%.spec%.lua$")
                or name:match("%.luau$")
                or name:match("%.lua$")
            then
                table.insert(results, full)
            end
        end
    end

    scan(folder)
    return results, nil
end

--
-- Returns bare filenames (not full paths) for backwards compatibility.
--
-- Parameters:
--     • folder (string) - The folder to scan.
--
-- Returns:
--     ({string}, string?) - Array of filenames and optional error.
--
function Test_Loader.Extract_Test_Filenames_From_Folder(folder: string): ({string}, string?)
    if not fs.isDir(folder) then
        return {}, (`Folder "{folder}" was not found. Can't possibly load tests from it.`)
    end

    local entries: {string}
    local ok, err = pcall(function()
        entries = fs.readDir(folder)
    end)
    if not ok then
        return {}, tostring(err)
    end

    local test_files: {string} = {}
    for _, name in ipairs(entries) do
        if name:match("%.luau$") or name:match("%.lua$") then
            table.insert(test_files, name)
        end
    end

    return test_files, nil
end
--
-- RETURN VALUE
--
return Test_Loader