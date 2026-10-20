--!strict
--
-- Zstd_Oracle
--
-- Property-based tests that verify the pure-Luau Zstd_Codec against the
-- system `zstd` command line tool, used here as a reference oracle.  For a
-- wide range of generated inputs the suite checks that:
--
--   * our encoder's frames decompress correctly with the system tool,
--   * the system tool's frames decompress correctly with our decoder,
--   * the system tool can round-trip its own frames as a sanity check,
--   * each frame reports the correct decompressed size.
--
-- The whole suite is skipped (not failed) when the `zstd` executable is not
-- available on the host machine.
--
--
-- REQUIRES
--
--
-- Requires
--
local process    = require("@lune/process")
local fs         = require("@lune/fs")
local Zstd_Codec = require("../mocks/Zstd_Codec")
--
-- LOCAL TYPES
--
type Strategy<T> = {
    generate: () -> T,
    shrink:   (value: T) -> {T},
}

type Boundary_Pattern = {
    name:  string,
    build: (length: number) -> string,
}
--
-- CONSTANTS
--
local ZSTD_BINARY         = "zstd"
local DEFAULT_TEMP_BASE   = "/tmp"
local TEMP_DIR_NAME       = "lune_zstd_oracle"
local HEX_PREVIEW_BYTES   = (32)
local MAX_RUN_LENGTH      = (64)
local MAX_PROPERTY_LENGTH = (8192)
local ORACLE_LEVEL        = (19)
local LOW_ENTROPY_BYTES: {number} = { 0, 1, 2, 255 }
local LEVELS: {number} = { 1, 3, 9, 19 }
local TEMP_ENV_KEYS: {string} = { "TMPDIR", "TEMP" }
local BOUNDARY_SIZES: {number} = {
    0, 1, 2, 3,
    255, 256, 257,
    1023, 1024,
    4095, 4096, 4097,
    65535, 65536, 65537,
    131071, 131072, 131073,
    262144,
}
--
-- VARIABLES
--
--
-- Pick the first non-empty temporary directory from the environment,
-- falling back to /tmp when none is configured.
--
local resolved_temp_base = DEFAULT_TEMP_BASE

for _, env_key in ipairs(TEMP_ENV_KEYS) do
    local candidate = process.env[env_key]

    if (candidate ~= nil) and (#candidate > 0) then
        resolved_temp_base = candidate
        break
    end
end

local TEMP_DIR    = resolved_temp_base .. "/" .. TEMP_DIR_NAME
local TEMP_INPUT  = TEMP_DIR .. "/input.bin"
local TEMP_OUTPUT = TEMP_DIR .. "/output.bin"

--
-- Probe the system tool once so every test below can decide whether to run
-- or skip.
--
local zstd_probe_ok, zstd_probe = pcall(process.exec, ZSTD_BINARY, { "--version" })
local ZSTD_AVAILABLE = false

if (zstd_probe_ok) and (zstd_probe.ok) then
    ZSTD_AVAILABLE = true
end

--
-- LOCAL FUNCTIONS
--

--
-- Returns a compact hexadecimal preview of a byte string, truncated after
-- (max_bytes) bytes so that failure output stays readable.
--
local function Hex_Preview(data: string, max_bytes: number): string
    local data_length   = #data
    local preview_count = math.min(data_length, max_bytes)
    local parts: {string} = {}

    for index = 1, preview_count do
        local byte_value = string.byte(data, index)
        table.insert(parts, string.format("%02X", byte_value))
    end

    local preview = table.concat(parts, " ")

    if (data_length > max_bytes) then
        preview = preview .. " ..."
    end

    return preview
end

--
-- Raises an error describing the first point where two byte strings differ,
-- including their lengths and a hexadecimal preview of each.
--
local function Assert_Equal(actual: string, expected: string, context: string): ()
    if (actual == expected) then
        return
    end

    local actual_length   = #actual
    local expected_length = #expected
    local actual_preview   = Hex_Preview(actual, HEX_PREVIEW_BYTES)
    local expected_preview = Hex_Preview(expected, HEX_PREVIEW_BYTES)

    local actual_line   = ("\n  actual   (%d bytes): %s"):format(actual_length, actual_preview)
    local expected_line = ("\n  expected (%d bytes): %s"):format(expected_length, expected_preview)

    local message = ("%s: byte string mismatch"):format(context)
    message = message .. actual_line
    message = message .. expected_line

    error(message, 2)
end

--
-- Raises an error when two numbers are not equal.
--
local function Assert_Equal_Number(actual: number, expected: number, context: string): ()
    if (actual == expected) then
        return
    end

    error(("%s: expected %d, got %d"):format(context, expected, actual), 2)
end

--
-- Builds a string of (length) uniformly random bytes.
--
local function Build_Uniform_String(length: number): string
    local parts: {string} = {}

    for _ = 1, length do
        table.insert(parts, string.char(math.random(0, 255)))
    end

    return table.concat(parts)
end

--
-- Builds a string of (length) bytes made of short runs of repeated bytes,
-- which exercises the match finder's run handling.
--
local function Build_Runs_String(length: number): string
    local parts: {string} = {}
    local remaining = length

    while (remaining > 0) do
        local run_length = math.random(1, math.min(remaining, MAX_RUN_LENGTH))
        local run_char   = string.char(math.random(0, 255))

        for _ = 1, run_length do
            table.insert(parts, run_char)
        end

        remaining -= run_length
    end

    return table.concat(parts)
end

--
-- Builds a string of (length) lowercase letters with occasional spaces, to
-- exercise skewed Huffman literal distributions.
--
local function Build_Text_String(length: number): string
    local parts: {string} = {}

    for _ = 1, length do
        local roll = math.random(1, 10)

        if (roll == 1) then
            table.insert(parts, " ")
        else
            table.insert(parts, string.char(math.random(97, 122)))
        end
    end

    return table.concat(parts)
end

--
-- Builds a string of (length) bytes drawn from a tiny alphabet, producing
-- highly compressible input.
--
local function Build_Low_Entropy_String(length: number): string
    local parts: {string} = {}

    for _ = 1, length do
        local pick_index = math.random(1, #LOW_ENTROPY_BYTES)
        table.insert(parts, string.char(LOW_ENTROPY_BYTES[pick_index]))
    end

    return table.concat(parts)
end

--
-- Creates a strategy that generates byte strings of length
-- [0, max_length], mixing uniform, run-heavy, textual and low-entropy
-- distributions.  Values shrink toward the empty string and shorter
-- prefixes.
--
local function Make_Byte_String_Strategy(max_length: number): Strategy<string>
    local strategy: Strategy<string> = {
        generate = function(): string
            local length = math.random(0, max_length)
            local mode   = math.random(1, 4)

            if     (mode == 1) then return Build_Uniform_String(length)
            elseif (mode == 2) then return Build_Runs_String(length)
            elseif (mode == 3) then return Build_Text_String(length)
            end

            return Build_Low_Entropy_String(length)
        end,

        shrink = function(value: string): {string}
            local candidates: {string} = {}
            local value_length = #value

            if (value_length == 0) then
                return candidates
            end

            table.insert(candidates, "")

            local half_length = math.floor(value_length / 2)

            if (half_length > 0) then
                table.insert(candidates, value:sub(1, half_length))
            end

            local quarter_length = math.floor(value_length / 4)

            if (quarter_length > 0) then
                table.insert(candidates, value:sub(1, quarter_length))
            end

            return candidates
        end,
    }

    return strategy
end

--
-- Runs the system tool with the given arguments, raising an error when the
-- process cannot be started or exits with a non-zero code.
--
local function Run_Zstd(args: {string}, context: string): ()
    local run_ok, result = pcall(process.exec, ZSTD_BINARY, args)

    if (not run_ok) then
        local detail = tostring(result)
        error(("%s: failed to run %s: %s"):format(context, ZSTD_BINARY, detail), 2)
    end

    if (not result.ok) then
        local code   = result.code
        local stderr = result.stderr
        local detail = ("%s exited with code %d: %s"):format(ZSTD_BINARY, code, stderr)
        error(("%s: %s"):format(context, detail), 2)
    end
end

--
-- Compresses (raw) with the system tool at the given level, returning the
-- resulting frame bytes.  The explicit checksum flag lets the property test
-- vary the frame contents.
--
local function Run_Zstd_Compress(
    raw          : string,
    level        : number,
    use_checksum : boolean
): string
    fs.writeFile(TEMP_INPUT, raw)

    local level_flag = "-" .. tostring(level)
    local check_flag = "--check"

    if (not use_checksum) then
        check_flag = "--no-check"
    end

    local args = { "-q", "-f", level_flag, check_flag, TEMP_INPUT, "-o", TEMP_OUTPUT }
    Run_Zstd(args, "compress")

    return fs.readFile(TEMP_OUTPUT)
end

--
-- Decompresses a frame with the system tool, returning the raw bytes.
--
local function Run_Zstd_Decompress(frame: string): string
    fs.writeFile(TEMP_INPUT, frame)

    local args = { "-d", "-q", "-f", TEMP_INPUT, "-o", TEMP_OUTPUT }
    Run_Zstd(args, "decompress")

    return fs.readFile(TEMP_OUTPUT)
end

--
-- Cross-checks a single (raw) input against the oracle in both directions:
-- our frames must decode with the system tool, the system tool's frames must
-- decode with us, and both frames must agree on the decompressed size.
--
local function Check_Against_Oracle(
    raw          : string,
    level        : number,
    use_checksum : boolean
): ()
    local raw_buffer      = buffer.fromstring(raw)
    local our_frame       = Zstd_Codec.Compress(raw_buffer)
    local our_frame_bytes = buffer.tostring(our_frame)

    local our_from_our = buffer.tostring(Zstd_Codec.Decompress(our_frame))
    Assert_Equal(our_from_our, raw, "our decompress(our compress)")

    local system_from_our = Run_Zstd_Decompress(our_frame_bytes)
    Assert_Equal(system_from_our, raw, "system decompress(our compress)")

    local oracle_frame_bytes = Run_Zstd_Compress(raw, level, use_checksum)
    local oracle_frame       = buffer.fromstring(oracle_frame_bytes)

    local system_from_oracle = Run_Zstd_Decompress(oracle_frame_bytes)
    Assert_Equal(system_from_oracle, raw, "system decompress(system compress)")

    local our_from_oracle = buffer.tostring(Zstd_Codec.Decompress(oracle_frame))
    Assert_Equal(our_from_oracle, raw, "our decompress(system compress)")

    local our_size = Zstd_Codec.Get_Decompressed_Size(our_frame)
    Assert_Equal_Number(our_size, #raw, "our frame declared size")

    local oracle_size = Zstd_Codec.Get_Decompressed_Size(oracle_frame)
    Assert_Equal_Number(oracle_size, #raw, "oracle frame declared size")
end

--
-- Registers an oracle test, substituting a skipped test when the system
-- `zstd` tool is unavailable so the suite stays green on machines without it.
--
local function Register_Oracle_Test(name: string, body: () -> ()): ()
    if (ZSTD_AVAILABLE) then
        it(name, body)
    else
        xit(name .. " [skipped - system zstd CLI not found]", body)
    end
end

--
-- TESTS
--
describe("Zstd_Codec vs system zstd oracle", function()
    beforeAll(function()
        if (not ZSTD_AVAILABLE) then
            return
        end

        if (not fs.isDir(TEMP_DIR)) then
            fs.writeDir(TEMP_DIR)
        end
    end)

    afterAll(function()
        if (fs.isDir(TEMP_DIR)) then
            fs.removeDir(TEMP_DIR)
        end
    end)

    Register_Oracle_Test("finds a usable zstd CLI", function()
        if (not ZSTD_AVAILABLE) then
            error("zstd CLI became unavailable after the initial probe")
        end

        local probe_ok, probe = pcall(process.exec, ZSTD_BINARY, { "--version" })

        if (not probe_ok) then
            error("failed to execute " .. ZSTD_BINARY .. ": " .. tostring(probe))
        end

        if (not probe.ok) then
            error(("%s --version exited with code %d"):format(ZSTD_BINARY, probe.code))
        end
    end)

    Register_Oracle_Test("round-trips random inputs against the oracle", function()
        given({
            data         = Make_Byte_String_Strategy(MAX_PROPERTY_LENGTH),
            level        = g.sampled(LEVELS),
            use_checksum = g.boolean(),
        }, function(args)
            local data         = args.data :: string
            local level        = args.level :: number
            local use_checksum = args.use_checksum :: boolean

            Check_Against_Oracle(data, level, use_checksum)
        end)
    end)

    Register_Oracle_Test("round-trips boundary sizes against the oracle", function()
        local patterns: {Boundary_Pattern} = {
            { name = "uniform",     build = Build_Uniform_String },
            { name = "runs",        build = Build_Runs_String },
            { name = "text",        build = Build_Text_String },
            { name = "low_entropy", build = Build_Low_Entropy_String },
        }

        for _, size in ipairs(BOUNDARY_SIZES) do
            for _, pattern in ipairs(patterns) do
                local data = pattern.build(size)
                Check_Against_Oracle(data, ORACLE_LEVEL, true)
            end
        end
    end)
end)
