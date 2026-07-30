--!strict
--
-- REQUIRES
--
local fs     = require("@lune/fs")
local roblox = require("@lune/roblox")
--
-- CONSTANTS
--
--
-- Default place path candidates used when no config provides overrides.
-- Parent projects can supply their own list via test-runner.config.luau.
--
local PLACE_PATH_CANDIDATES = {
    "./*.rbxlx",
    "../*.rbxlx",
}
--
-- LOCAL FUNCTIONS
--
local function resolve_place_path(): string
    --
    -- Try to load place path candidates from the parent project's config.
    -- pcall is used because the config file may not exist.
    --
    local config_ok, config_result = pcall(require, "../test-runner.config")
    if config_ok and (type(config_result) == "table") then
        local candidates = config_result.PLACE_PATH_CANDIDATES
        if (type(candidates) == "table") and (#candidates > 0) then
            for _, candidate in ipairs(candidates :: {string}) do
                local ok, is_file = pcall(function()
                    return fs.isFile(candidate)
                end)
                if ok and is_file then
                    return candidate
                end
            end
        end
    end

    -- Fall back to default candidates
    for _, candidate in ipairs(PLACE_PATH_CANDIDATES) do
        local ok, is_file = pcall(function()
            return fs.isFile(candidate)
        end)
        if ok and is_file then
            return candidate
        end
    end

    error(("Unable to locate place file."))
end
--
-- VARIABLES
--
local place_file
local place_ok, place_err = pcall(function()
    local resolved_path = resolve_place_path()
    place_file = fs.readFile(resolved_path)
end)

local game: any
if place_ok then
    game = roblox.deserializePlace(place_file)
else
    warn(("Could not load place file: %s. Running with mock defaults."):format(tostring(place_err)))
    game = {}
end

--
-- RunService shim
--
-- roblox.deserializePlace returns Instances without runtime methods
-- like IsServer / IsClient / IsStudio.  This shim wraps RunService
-- so that modules calling these methods at load-time do not crash in
-- the headless test environment.
--
local run_service_shim = setmetatable({}, {
    __index = function(_, key)
        if (key == "IsServer")  then return function() return true  end end
        if (key == "IsClient")  then return function() return false end end
        if (key == "IsStudio")  then return function() return false end end

        return (game:GetService("RunService") :: any)[key]
    end,
    __newindex = function(_, key, value)
        (game:GetService("RunService") :: any)[key] = value
    end,
})

--
-- Players shim
--
-- Returns an empty player list so that modules iterating over players
-- at load-time do not error.  Individual player lookups return nil
-- since there are no connected clients in the test environment.
--
local players_shim = setmetatable({}, {
    __index = function(_, key)
        if (key == "GetPlayers")       then return function() return {} end end
        if (key == "GetPlayerByUserId") then return function() return nil end end

        return (game:GetService("Players") :: any)[key]
    end,
})

--
-- MemoryStore state tables
--
-- These tables are shared across every GetQueue / GetHashMap call that
-- uses the same name, which mirrors the real Roblox behaviour where
-- two calls with the same identifier return the same stored data.
--
local memory_store_hashes: {[string]: {[string]: any}} = {}
local memory_store_queues: {[string]: {
    items:   {{value: any, visible: boolean, batch_id: string?}},
    next_id: number,
}} = {}
local memory_store_sorted_maps: {[string]: {
    entries: {[string]: {value: any, sortKey: number}},
    next_id: number,
}} = {}
--
-- LOCAL FUNCTIONS (MemoryStore helpers)
--

--
-- make_hashmap_stub
--
-- Returns a table with SetAsync / GetAsync / RemoveAsync that reads
-- and writes a shared in-memory dictionary.  Every call for the same
-- hashmap name shares the same backing storage table, which means a
-- value written by one module is visible to another — same as the
-- real MemoryStoreService.GetHashMap.
--
local function make_hashmap_stub(hashmap_name: string): {SetAsync: any, GetAsync: any, RemoveAsync: any}
    if (memory_store_hashes[hashmap_name] == nil) then
        memory_store_hashes[hashmap_name] = {}
    end

    local storage = memory_store_hashes[hashmap_name]

    --
    -- SetAsync(key, value, expiration)
    --
    -- Writes a value into the shared storage.  The expiration parameter
    -- is accepted but ignored (the mock does not implement TTL).
    --
    local function set_async(_self: any, key: string, value: any, _expiration: number): ()
        storage[key] = value
    end

    --
    -- GetAsync(key)
    --
    -- Returns the value stored under the given key, or nil when the
    -- key does not exist (same behaviour as the real API).
    --
    local function get_async(_self: any, key: string): any
        return storage[key]
    end

    --
    -- RemoveAsync(key)
    --
    -- Deletes the entry for the given key from the shared storage.
    --
    local function remove_async(_self: any, key: string): ()
        storage[key] = nil
    end

    return {
        SetAsync    = set_async,
        GetAsync    = get_async,
        RemoveAsync = remove_async,
    }
end

--
-- make_queue_stub
--
-- Returns a table that mimics the MemoryStoreQueue API methods used
-- by this project: AddAsync, ReadAsync, RemoveAsync, and GetSizeAsync.
-- Items are stored in a list with visibility tracking so that
-- ReadAsync / RemoveAsync behave like the real FIFO queue with batch
-- removal.
--
-- Every call for the same queue name shares the same backing list,
-- matching the real Roblox behaviour.
--
local function make_queue_stub(queue_name: string): {
    AddAsync:    any,
    ReadAsync:   any,
    RemoveAsync: any,
    GetSizeAsync: any,
    _get_items:  any,
    _clear:      any,
}
    if (memory_store_queues[queue_name] == nil) then
        memory_store_queues[queue_name] = { items = {}, next_id = 0 }
    end

    local queue = memory_store_queues[queue_name]

    --
    -- add_async(value, expiration, timestamp)
    --
    -- Appends an item to the end of the queue in a visible state.
    -- The expiration and timestamp parameters are accepted but ignored
    -- (the mock does not implement TTL-based expiry).
    --
    local function add_async(_self: any, value: any, _expiration: number, _timestamp: number): string
        local new_item = {
            value    = value,
            visible  = true,
            batch_id = nil,
        }

        table.insert(queue.items, new_item)

        queue.next_id += 1
        local id = tostring(queue.next_id)

        return id
    end

    --
    -- read_async(count)
    --
    -- Reads up to `count` visible items from the front of the queue,
    -- marks them as invisible, and returns them together with a batch
    -- ID that must be passed to remove_async to delete the batch.
    --
    -- This mirrors the real MemoryStoreQueue:ReadAsync behaviour
    -- where read items become invisible for a configured timeout.
    --
    local function read_async(_self: any, count: number): ({any}, string)
        queue.next_id += 1
        local batch_id = tostring(queue.next_id)

        local results: {any} = {}
        local read_count = 0

        for _, item in ipairs(queue.items) do
            if (read_count >= count) then
                break
            end

            if (item.visible and item.batch_id == nil) then
                item.visible  = false
                item.batch_id = batch_id

                table.insert(results, item.value)
                read_count += 1
            end
        end

        return results, batch_id
    end

    --
    -- remove_async(batch_id)
    --
    -- Permanently removes all items that were previously read with
    -- the given batch ID.  Items from other batches are kept.
    --
    local function remove_async(_self: any, batch_id: string): ()
        local remaining: {{value: any, visible: boolean, batch_id: string?}} = {}

        for _, item in ipairs(queue.items) do
            if (item.batch_id ~= batch_id) then
                table.insert(remaining, item)
            end
        end

        queue.items = remaining
    end

    --
    -- get_size_async()
    --
    -- Returns the number of visible items currently in the queue.
    -- Items that have been read but not yet removed are excluded,
    -- which matches the real MemoryStoreQueue:GetSizeAsync behaviour.
    --
    local function get_size_async(): number
        local count = 0

        for _, item in ipairs(queue.items) do
            if (item.visible and item.batch_id == nil) then
                count += 1
            end
        end

        return count
    end

    --
    -- Test helpers (prefixed with underscore so they stand out)
    --

    -- Return every item (visible or not) for test assertions.
    local function _get_items(): {{value: any, visible: boolean, batch_id: string?}}
        return queue.items
    end

    -- Reset the queue to a completely empty state.
    local function _clear(): ()
        queue.items   = {}
        queue.next_id = 0
    end

    return {
        AddAsync     = add_async,
        ReadAsync    = read_async,
        RemoveAsync  = remove_async,
        GetSizeAsync = get_size_async,
        _get_items   = _get_items,
        _clear       = _clear,
    }
end

--
-- make_sorted_map_stub
--
-- Returns a table that mimics the MemoryStoreSortedMap API methods:
-- SetAsync, GetAsync, RemoveAsync, and GetRangeAsync.
-- Entries are stored with sort keys for ordered retrieval.
--
local function make_sorted_map_stub(map_name: string): {
    SetAsync:     any,
    GetAsync:     any,
    RemoveAsync:  any,
    GetRangeAsync: any,
    _clear:       any,
}
    if (memory_store_sorted_maps[map_name] == nil) then
        memory_store_sorted_maps[map_name] = { entries = {}, next_id = 0 }
    end

    local smap = memory_store_sorted_maps[map_name]

    --
    -- set_async(key, value, expiration, sortKey)
    --
    local function set_async(_self: any, key: string, value: any, _expiration: number, sortKey: number): ()
        smap.entries[key] = { value = value, sortKey = sortKey }
    end

    --
    -- get_async(key)
    --
    local function get_async(_self: any, key: string): any
        local entry = smap.entries[key]
        if (entry ~= nil) then
            return entry.value
        end
        return nil
    end

    --
    -- remove_async(key)
    --
    local function remove_async(_self: any, key: string): ()
        smap.entries[key] = nil
    end

    --
    -- get_range_async(direction, count, startKey?)
    --
    -- Returns up to `count` entries sorted by sortKey as a dictionary
    -- keyed by the original key strings.
    --
    local function get_range_async(_self: any, direction: any, count: number, startKey: string?): {{key: string, value: any, sortKey: any}}
        local sorted: {{key: string, value: any, sortKey: number}} = {}

        for key, entry in pairs(smap.entries) do
            table.insert(sorted, { key = key, value = entry.value, sortKey = entry.sortKey })
        end

        local ascending = (direction == Enum.SortDirection.Ascending)
        table.sort(sorted, function(a, b)
            if (ascending) then
                if (a.sortKey == b.sortKey) then return a.key < b.key end
                return a.sortKey < b.sortKey
            else
                if (a.sortKey == b.sortKey) then return a.key < b.key end
                return a.sortKey > b.sortKey
            end
        end)

        local startIdx = 1
        if (startKey ~= nil) then
            for i, item in ipairs(sorted) do
                if (item.key == startKey) then
                    startIdx = i + 1
                    break
                end
            end
        end

        local result: {{key: string, value: any, sortKey: any}} = {}
        for i = startIdx, math.min(startIdx + count - 1, #sorted) do
            table.insert(result, sorted[i])
        end

        return result
    end

    local function _clear(): ()
        smap.entries = {}
        smap.next_id = 0
    end

    return {
        SetAsync      = set_async,
        GetAsync      = get_async,
        RemoveAsync   = remove_async,
        GetRangeAsync = get_range_async,
        _clear        = _clear,
    }
end

--
-- MemoryStoreService shim
--
-- Intercepts GetHashMap and GetQueue calls and returns the in-memory
-- stubs defined above.  All other MemoryStoreService methods fall
-- through to the real deserialised game object.
--
local memory_store_shim = setmetatable({}, {
    __index = function(_, key)
        if (key == "GetHashMap") then
            return function(_self: any, hashmap_name: string): any
                return make_hashmap_stub(hashmap_name)
            end
        end

        if (key == "GetQueue") then
            return function(_self: any, queue_name: string, _invisibility_timeout: number?): any
                return make_queue_stub(queue_name)
            end
        end

        if (key == "GetSortedMap") then
            return function(_self: any, map_name: string): any
                return make_sorted_map_stub(map_name)
            end
        end

        return (game:GetService("MemoryStoreService") :: any)[key]
    end,
})
--
-- MODULE DEFINITION
--

--
-- game_proxy
--
-- Top-level proxy that intercepts GetService for the services we need
-- to stub (RunService, Players, MemoryStoreService) and passes all
-- other accesses through to the deserialised place object.
--
local game_proxy = setmetatable({}, {
    __index = function(_, key)
        if (key == "GetService") then
            return function(_self: any, service_name: string): any
                if (service_name == "RunService") then
                    return run_service_shim
                end

                if (service_name == "Players") then
                    return players_shim
                end

                if (service_name == "MemoryStoreService") then
                    return memory_store_shim
                end

                return game:GetService(service_name)
            end
        end

        if (key == "Players") then
            return players_shim
        end

        return (game :: any)[key]
    end,
})
--
-- RETURN VALUE
--
return game_proxy
