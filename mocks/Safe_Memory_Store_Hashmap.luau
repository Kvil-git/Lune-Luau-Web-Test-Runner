--!strict
--
-- Mock Safe_Memory_Store_Hashmap for test environment.
-- Records all calls for test assertions.
--

local storage: {[string]: any} = {}
local get_calls: { {hashmap: any, key: string} } = {}
local set_calls: { {hashmap: any, key: string, value: any, expiration: number} } = {}

local Safe_Memory_Store_Hashmap = {}

function Safe_Memory_Store_Hashmap.Set_Async(hashmap: any, key: string, value: any, expiration: number): ()
    storage[key] = value
    table.insert(set_calls, { hashmap = hashmap, key = key, value = value, expiration = expiration })
end

function Safe_Memory_Store_Hashmap.Get_Yielding(hashmap: any, key: string): (boolean, any)
    table.insert(get_calls, { hashmap = hashmap, key = key })
    local value = storage[key]
    if value ~= nil then
        return true, value
    end
    return false, "Key not found: " .. key
end

function Safe_Memory_Store_Hashmap._clear_calls(): ()
    get_calls = {}
    set_calls = {}
end

function Safe_Memory_Store_Hashmap._get_get_calls(): { {hashmap: any, key: string} }
    return get_calls
end

function Safe_Memory_Store_Hashmap._get_set_calls(): { {hashmap: any, key: string, value: any, expiration: number} }
    return set_calls
end

function Safe_Memory_Store_Hashmap._set_storage(key: string, value: any): ()
    storage[key] = value
end

function Safe_Memory_Store_Hashmap._clear_storage(): ()
    storage = {}
end

return Safe_Memory_Store_Hashmap
