--!strict
--
-- EXPORT TYPES
--
export type Strategy<T> = {
    generate: () -> T,
    shrink: (value: T) -> {T},
}

--
-- ALIASES
--
local random = math.random

--
-- LOCAL FUNCTIONS
--

-- Asserts that a condition holds and returns an error message otherwise.
local function Assert_Or_Error(condition: boolean, message: string)
    if (not condition) then
        error(message)
    end
end

--
-- BASE STRATEGIES
--

--
-- Creates a strategy that generates integers uniformly in [min, max].
--
-- Shrinks toward 0, then toward ±1, then halves toward 0.
--
-- Parameters:
--     • min (number) - Minimum value (inclusive)
--     • max (number) - Maximum value (inclusive)
--
-- Returns:
--     Strategy<number>
--
local function Integer(min: number, max: number): Strategy<number>
    if (min > max) then
        local temp   = min
        min          = max
        max          = temp
    end

    local strategy: Strategy<number> = {
        generate = function(): number
            return random(min, max)
        end,
        shrink = function(value: number): {number}
            if (value == 0) then
                return {}
            end

            local candidates: {number} = {}

            table.insert(candidates, 0)

            local abs_value = math.abs(value)
            if (abs_value > 1) then
                local sign = if value > 0 then 1 else -1
                table.insert(candidates, sign)

                local current = abs_value
                while (current > 1) do
                    current = math.floor(current / 2)
                    if (current ~= 0) then
                        table.insert(candidates, sign * current)
                    end
                end
            end

            return candidates
        end,
    }

    return strategy
end

--
-- Creates a strategy that generates floats uniformly in [min, max].
--
-- Shrinks toward 0, then halves toward 0.
--
-- Parameters:
--     • min (number) - Minimum value (inclusive)
--     • max (number) - Maximum value (inclusive)
--
-- Returns:
--     Strategy<number>
--
local function Float(min: number, max: number): Strategy<number>
    if (min > max) then
        local temp = min
        min        = max
        max        = temp
    end

    local range = max - min

    local strategy: Strategy<number> = {
        generate = function(): number
            return min + random() * range
        end,
        shrink = function(value: number): {number}
            local candidates: {number} = {}

            table.insert(candidates, 0)

            local half = value / 2
            if (half ~= value) then
                table.insert(candidates, half)
            end

            if (value > 0) then
                table.insert(candidates, value - 1)
            elseif (value < 0) then
                table.insert(candidates, value + 1)
            end

            return candidates
        end,
    }

    return strategy
end

--
-- Creates a strategy that generates true or false.
--
-- Shrinks toward false.
--
-- Returns:
--     Strategy<boolean>
--
local function Boolean(): Strategy<boolean>
    local strategy: Strategy<boolean> = {
        generate = function(): boolean
            return random() > 0.5
        end,
        shrink = function(value: boolean): {boolean}
            if (value) then
                return { false }
            end
            return {}
        end,
    }

    return strategy
end

--
-- Creates a strategy that generates a single printable ASCII character.
--
-- Shrinks toward 'a'.
--
-- Returns:
--     Strategy<string>
--
local function Character(): Strategy<string>
    local strategy: Strategy<string> = {
        generate = function(): string
            local char_code = random(32, 126)
            return string.char(char_code)
        end,
        shrink = function(value: string): {string}
            if (value == "a") then
                return {}
            end

            local candidates: {string} = {}
            table.insert(candidates, "a")
            return candidates
        end,
    }

    return strategy
end

--
-- Creates a strategy that generates strings of length [min_len, max_len].
--
-- Shrinks toward empty string, then shorter strings.
--
-- Parameters:
--     • min_len (number) - Minimum string length (inclusive)
--     • max_len (number) - Maximum string length (inclusive)
--     • char_strategy (Strategy<string>?) - Strategy for individual characters (default: Character)
--
-- Returns:
--     Strategy<string>
--
local function String(min_len: number, max_len: number, char_strategy: Strategy<string>?): Strategy<string>
    if (min_len > max_len) then
        local temp = min_len
        min_len    = max_len
        max_len    = temp
    end

    local char_s = char_strategy or Character()

    local strategy: Strategy<string> = {
        generate = function(): string
            local length      = random(min_len, max_len)
            local characters: {string} = {}

            for _ = 1, length do
                table.insert(characters, char_s.generate())
            end

            return table.concat(characters)
        end,
        shrink = function(value: string): {string}
            local candidates: {string} = {}

            local length = #value
            if (length == 0) then
                return candidates
            end

            table.insert(candidates, "")
            if (length > 0) then
                -- Remove characters from the end
                for i = length, 1, -1 do
                    local shorter = value:sub(1, i - 1)
                    table.insert(candidates, shorter)
                end

                -- Remove characters from the start
                for i = length, 1, -1 do
                    if (i > 1) then
                        local shorter = value:sub(i)
                        table.insert(candidates, shorter)
                    end
                end
            end

            return candidates
        end,
    }

    return strategy
end

--
-- Creates a strategy that generates lists of values from the element strategy.
--
-- Shrinks toward empty list, then removes one element at a time.
--
-- Parameters:
--     • element_strategy (Strategy<T>) - Strategy for individual elements
--     • min_size (number) - Minimum list size (inclusive)
--     • max_size (number) - Maximum list size (inclusive)
--
-- Returns:
--     Strategy<{T}>
--
local function List<T>(element_strategy: Strategy<T>, min_size: number, max_size: number): Strategy<{T}>
    if (min_size > max_size) then
        local temp   = min_size
        min_size     = max_size
        max_size     = temp
    end

    local strategy: Strategy<{T}> = {
        generate = function(): {T}
            local size   = random(min_size, max_size)
            local result: {T} = {}

            for _ = 1, size do
                table.insert(result, element_strategy.generate())
            end

            return result
        end,
        shrink = function(value: {T}): {{T}}
            local candidates: {{T}} = {}

            local count = #value
            if (count == 0) then
                return candidates
            end

            table.insert(candidates, {})

            if (count > 0) then
                for i = 1, count do
                    local shorter: {T} = {}

                    for j = 1, count do
                        if (j ~= i) then
                            table.insert(shorter, value[j])
                        end
                    end

                    table.insert(candidates, shorter)
                end
            end

            return candidates
        end,
    }

    return strategy
end

--
-- Creates a strategy that picks uniformly from a fixed set of elements.
--
-- Shrinks toward earlier elements in the list.
--
-- Parameters:
--     • elements ({T}) - Fixed set of elements to pick from
--
-- Returns:
--     Strategy<T>
--
local function Sampled<T>(elements: {T}): Strategy<T>
    local strategy: Strategy<T> = {
        generate = function(): T
            local count = #elements
            Assert_Or_Error(count > 0, "Sampled strategy requires at least one element")

            local index = random(1, count)
            return elements[index]
        end,
        shrink = function(value: T): {T}
            local candidates: {T} = {}

            -- Find the index of the current value
            local found_index: number? = nil
            for i, element in ipairs(elements) do
                if (element == value) then
                    found_index = i
                    break
                end
            end

            if (found_index) then
                -- Try elements before the current one
                for i = 1, found_index - 1 do
                    table.insert(candidates, elements[i])
                end
            end

            return candidates
        end,
    }

    return strategy
end

--
-- Creates a strategy that generates fixed-size tuples.
--
-- Shrinks each element independently.
--
-- Parameters:
--     • strategies ({Strategy<any>}) - Array of strategies for each tuple position
--
-- Returns:
--     Strategy<{any}>
--
local function Tuple(strategies: {Strategy<any>}): Strategy<{any}>
    local strategy: Strategy<{any}> = {
        generate = function(): {any}
            local result: {any} = {}

            for _, s in ipairs(strategies) do
                table.insert(result, s.generate())
            end

            return result
        end,
        shrink = function(value: {any}): {{any}}
            local candidates: {{any}} = {}

            -- Shrink each position independently
            for i, s in ipairs(strategies) do
                local element     = value[i]
                local shrunk_list = s.shrink(element)

                for _, shrunk_element in ipairs(shrunk_list) do
                    local new_tuple: {any} = {}

                    for j, v in ipairs(value) do
                        if (j == i) then
                            table.insert(new_tuple, shrunk_element)
                        else
                            table.insert(new_tuple, v)
                        end
                    end

                    table.insert(candidates, new_tuple)
                end
            end

            return candidates
        end,
    }

    return strategy
end

--
-- Creates a strategy that generates tables with generated keys and values.
--
-- Shrinks by removing keys.
--
-- Parameters:
--     • key_strategy (Strategy<any>) - Strategy for keys
--     • value_strategy (Strategy<any>) - Strategy for values
--     • max_pairs (number?) - Maximum number of key-value pairs (default: 5)
--
-- Returns:
--     Strategy<{[any]: any}>
--
local function Dictionary(
    key_strategy  : Strategy<any>,
    value_strategy: Strategy<any>,
    max_pairs     : number?
): Strategy<{[any]: any}>
    local max = max_pairs or 5

    if (max < 1) then
        max = 1
    end

    local strategy: Strategy<{[any]: any}> = {
        generate = function(): {[any]: any}
            local count  = random(1, max)
            local result: {[any]: any} = {}

            for _ = 1, count do
                local key   = key_strategy.generate()
                local value = value_strategy.generate()
                result[key] = value
            end

            return result
        end,
        shrink = function(value: {[any]: any}): {{[any]: any}}
            local candidates: {{[any]: any}} = {}

            -- If already empty, nothing to shrink
            local first_key = next(value)
            if (first_key == nil) then
                return candidates
            end

            table.insert(candidates, {})

            -- Remove one key at a time
            local keys: {any} = {}
            for k, _ in pairs(value) do
                table.insert(keys, k)
            end

            for _, key_to_remove in ipairs(keys) do
                local smaller: {[any]: any} = {}

                for k, v in pairs(value) do
                    if (k ~= key_to_remove) then
                        smaller[k] = v
                    end
                end

                table.insert(candidates, smaller)
            end

            return candidates
        end,
    }

    return strategy
end

--
-- COMBINATORS
--

--
-- Transforms generated values using a mapping function.
--
-- Shrinking uses the source strategy's shrink, then transforms the result.
--
-- Parameters:
--     • strategy (Strategy<T>) - Source strategy
--     • transform (function) - Mapping function: (T) -> U
--
-- Returns:
--     Strategy<U>
--
local function Map<T, U>(strategy: Strategy<T>, transform: (value: T) -> U): Strategy<U>
    local memo: {[any]: T} = {}

    local mapped_strategy: Strategy<U> = {
        generate = function(): U
            local source_value = strategy.generate()
            local result       = transform(source_value)

            -- Store mapping so we can reverse it during shrinking
            memo[result] = source_value

            return result
        end,
        shrink = function(value: U): {U}
            local source_value = memo[value]

            if (source_value == nil) then
                return {}
            end

            local shrunk_sources = strategy.shrink(source_value)
            local candidates: {U} = {}

            for _, shrunk_source in ipairs(shrunk_sources) do
                local shrunk_mapped = transform(shrunk_source)
                memo[shrunk_mapped] = shrunk_source
                table.insert(candidates, shrunk_mapped)
            end

            return candidates
        end,
    }

    return mapped_strategy
end

--
-- Filters generated values using a predicate.
--
-- Regenerates values up to (max_attempts) times if the predicate fails.
-- Shrinks using the source strategy.
--
-- Parameters:
--     • strategy (Strategy<T>) - Source strategy
--     • predicate (function) - Filter function: (T) -> boolean
--     • max_attempts (number?) - Maximum regeneration attempts (default: 100)
--
-- Returns:
--     Strategy<T>
--
local function Filter<T>(strategy: Strategy<T>, predicate: (value: T) -> boolean, max_attempts: number?): Strategy<T>
    local max_tries = max_attempts or 100

    local filtered_strategy: Strategy<T> = {
        generate = function(): T
            for _ = 1, max_tries do
                local value = strategy.generate()

                if (predicate(value)) then
                    return value
                end
            end

            error(("Filter strategy: could not satisfy predicate after %d attempts"):format(max_tries))
        end,
        shrink = function(value: T): {T}
            local shrink_candidates = strategy.shrink(value)
            local candidates: {T} = {}

            for _, candidate in ipairs(shrink_candidates) do
                if (predicate(candidate)) then
                    table.insert(candidates, candidate)
                end
            end

            return candidates
        end,
    }

    return filtered_strategy
end

--
-- Picks uniformly from a list of strategies.
--
-- Shrinks by trying each alternative strategy's shrink.
--
-- Parameters:
--     • strategies ({Strategy<T>}) - Array of strategies to choose from
--
-- Returns:
--     Strategy<T>
--
local function One_Of<T>(strategies: {Strategy<T>}): Strategy<T>
    Assert_Or_Error(#strategies > 0, "One_Of requires at least one strategy")

    local strategy: Strategy<T> = {
        generate = function(): T
            local index = random(1, #strategies)
            return strategies[index].generate()
        end,
        shrink = function(value: T): {T}
            local candidates: {T} = {}

            -- Try shrinking with each strategy
            for _, s in ipairs(strategies) do
                local shrunk_list = s.shrink(value)

                for _, candidate in ipairs(shrunk_list) do
                    table.insert(candidates, candidate)
                end
            end

            return candidates
        end,
    }

    return strategy
end

--
-- Picks from strategies with weighted probabilities.
--
-- Shrinks by trying each strategy's shrink in order of weight (heaviest first).
--
-- Parameters:
--     • pairs ({{weight: number, strategy: Strategy<T>}}) - Array of weight-strategy pairs
--
-- Returns:
--     Strategy<T>
--
local function Frequency<T>(pairs: {{weight: number, strategy: Strategy<T>}}): Strategy<T>
    Assert_Or_Error(#pairs > 0, "Frequency requires at least one strategy pair")

    -- Build cumulative weight table for generation
    local cumulative: {number} = {}
    local total_weight: number = 0

    for _, pair in ipairs(pairs) do
        total_weight        += pair.weight
        table.insert(cumulative, total_weight)
    end

    Assert_Or_Error(total_weight > 0, "Frequency: total weight must be positive")

    local strategy: Strategy<T> = {
        generate = function(): T
            local roll      = random() * total_weight
            local chosen_index = 1

            for i, cum_weight in ipairs(cumulative) do
                if (roll <= cum_weight) then
                    chosen_index = i
                    break
                end
            end

            return pairs[chosen_index].strategy.generate()
        end,
        shrink = function(value: T): {T}
            local candidates: {T} = {}

            -- Try shrinking with each strategy, highest weight first
            for i = #pairs, 1, -1 do
                local s = pairs[i].strategy
                local shrunk_list = s.shrink(value)

                for _, candidate in ipairs(shrunk_list) do
                    table.insert(candidates, candidate)
                end
            end

            return candidates
        end,
    }

    return strategy
end

--
-- MODULE DEFINITION
--
local Generators = {
    integer    = Integer,
    float      = Float,
    boolean    = Boolean,
    character  = Character,
    string     = String,
    list       = List,
    sampled    = Sampled,
    tuple      = Tuple,
    dictionary = Dictionary,
    map        = Map,
    filter     = Filter,
    one_of     = One_Of,
    frequency  = Frequency,
}
--
-- RETURN VALUE
--
return Generators