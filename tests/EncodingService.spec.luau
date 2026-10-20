--!strict
--
-- EncodingService
--
-- Tests the EncodingService mock, which wraps the pure-Luau Zstd_Codec with
-- the same interface as Roblox's real service.  Covered here:
--
--   * byte-exact round-trips across levels, sizes and data shapes,
--   * agreement with Zstd_Codec directly,
--   * GetDecompressedBufferSize reporting the recorded size,
--   * rejection of unsupported algorithms and out-of-range levels,
--   * access through the game:GetService shim.
--
--
-- REQUIRES
--
--
-- Requires
--
local Encoding_Service = require("../mocks/EncodingService")
local Zstd_Codec       = require("../mocks/Zstd_Codec")
local game             = require("../mocks/game")
--
-- CONSTANTS
--
local ZSTD_ALGORITHM       = Enum.CompressionAlgorithm.Zstd
local VALID_LEVELS: {number} = { -7, 1, 3, 19, 22 }
local SAMPLE_TEXT          = string.rep("The quick brown fox. ", 40)
local SAMPLE_BYTES         = "\000\001\002\255\000hello\000\255"
--
-- LOCAL FUNCTIONS
--

--
-- Builds a buffer whose bytes are the result of a simple deterministic
-- pattern, so tests do not depend on the random generator.
--
local function Make_Pattern_Buffer(length: number): buffer
    local byte_indices: {number} = {}

    for index = 1, length do
        table.insert(byte_indices, (index * 31) % 256)
    end

    return buffer.fromstring(string.char(table.unpack(byte_indices)))
end

--
-- Returns a compact hexadecimal preview of a byte string for failure output.
--
local function Hex_Preview(data: string, max_bytes: number): string
    local data_length   = #data
    local preview_count = math.min(data_length, max_bytes)
    local parts: {string} = {}

    for index = 1, preview_count do
        table.insert(parts, string.format("%02X", string.byte(data, index)))
    end

    local preview = table.concat(parts, " ")

    if (data_length > max_bytes) then
        preview = preview .. " ..."
    end

    return preview
end

--
-- Asserts two byte strings are identical, reporting a hex preview otherwise.
--
local function Assert_Bytes_Equal(actual: string, expected: string, context: string): ()
    if (actual == expected) then
        return
    end

    local actual_line   = ("\n  actual   (%d bytes): %s"):format(#actual, Hex_Preview(actual, (32)))
    local expected_line = ("\n  expected (%d bytes): %s"):format(#expected, Hex_Preview(expected, (32)))

    error(context .. ": byte mismatch" .. actual_line .. expected_line, 2)
end

--
-- Compresses and decompresses (raw) at (level), asserting the round-trip is
-- byte-exact and the reported size matches.
--
local function Assert_Round_Trip(raw: string, level: number): ()
    local input_buffer = buffer.fromstring(raw)

    local compressed = Encoding_Service:CompressBuffer(input_buffer, ZSTD_ALGORITHM, level)

    local declared_size = Encoding_Service:GetDecompressedBufferSize(compressed, ZSTD_ALGORITHM)
    if (declared_size ~= #raw) then
        error(("size mismatch at level %d: expected %d, got %s")
            :format(level, #raw, tostring(declared_size)), 2)
    end

    local restored = Encoding_Service:DecompressBuffer(compressed, ZSTD_ALGORITHM)
    Assert_Bytes_Equal(buffer.tostring(restored), raw, ("round-trip at level %d"):format(level))
end

--
-- TESTS
--
describe("EncodingService mock", function()
    describe("CompressBuffer and DecompressBuffer", function()
        it("round-trips text content", function()
            local input_buffer = buffer.fromstring(SAMPLE_TEXT)
            local compressed   = Encoding_Service:CompressBuffer(input_buffer, ZSTD_ALGORITHM)

            local restored = Encoding_Service:DecompressBuffer(compressed, ZSTD_ALGORITHM)

            Assert_Bytes_Equal(buffer.tostring(restored), SAMPLE_TEXT, "text round-trip")
        end)

        it("round-trips arbitrary bytes including NUL", function()
            local input_buffer = buffer.fromstring(SAMPLE_BYTES)
            local compressed   = Encoding_Service:CompressBuffer(input_buffer, ZSTD_ALGORITHM)

            local restored = Encoding_Service:DecompressBuffer(compressed, ZSTD_ALGORITHM)

            Assert_Bytes_Equal(buffer.tostring(restored), SAMPLE_BYTES, "bytes round-trip")
        end)

        it("round-trips an empty buffer", function()
            local input_buffer = buffer.fromstring("")
            local compressed   = Encoding_Service:CompressBuffer(input_buffer, ZSTD_ALGORITHM)

            local restored = Encoding_Service:DecompressBuffer(compressed, ZSTD_ALGORITHM)

            Assert_Bytes_Equal(buffer.tostring(restored), "", "empty round-trip")
        end)

        it("round-trips every supported level", function()
            for _, level in ipairs(VALID_LEVELS) do
                Assert_Round_Trip(SAMPLE_TEXT, level)
            end
        end)

        it("defaults the level when omitted", function()
            local input_buffer = buffer.fromstring(SAMPLE_TEXT)
            local compressed   = Encoding_Service:CompressBuffer(input_buffer, ZSTD_ALGORITHM)

            local restored = Encoding_Service:DecompressBuffer(compressed, ZSTD_ALGORITHM)

            Assert_Bytes_Equal(buffer.tostring(restored), SAMPLE_TEXT, "default level round-trip")
        end)
    end)

    describe("GetDecompressedBufferSize", function()
        it("matches the original size across a range of lengths", function()
            local sizes: {number} = { 0, 1, 2, 255, 256, 4096, 65535 }

            for _, size in ipairs(sizes) do
                local input_buffer  = Make_Pattern_Buffer(size)
                local compressed    = Encoding_Service:CompressBuffer(input_buffer, ZSTD_ALGORITHM)
                local declared_size = Encoding_Service:GetDecompressedBufferSize(compressed, ZSTD_ALGORITHM)

                if (declared_size ~= size) then
                    error(("expected size %d, got %s"):format(size, tostring(declared_size)), 2)
                end
            end
        end)
    end)

    describe("algorithm validation", function()
        it("accepts the numeric Zstd value", function()
            local input_buffer = buffer.fromstring(SAMPLE_TEXT)
            local compressed   = Encoding_Service:CompressBuffer(input_buffer, 0)

            local restored = Encoding_Service:DecompressBuffer(compressed, 0)

            Assert_Bytes_Equal(buffer.tostring(restored), SAMPLE_TEXT, "numeric algorithm round-trip")
        end)

        it("rejects an unknown algorithm", function()
            local input_buffer = buffer.fromstring(SAMPLE_TEXT)
            local ok = pcall(function()
                Encoding_Service:CompressBuffer(input_buffer, "Deflate")
            end)

            expect(ok).to.equal(false)
        end)

        it("rejects an out-of-range level", function()
            local input_buffer = buffer.fromstring(SAMPLE_TEXT)
            local ok = pcall(function()
                Encoding_Service:CompressBuffer(input_buffer, ZSTD_ALGORITHM, 100)
            end)

            expect(ok).to.equal(false)
        end)
    end)

    describe("agreement with Zstd_Codec", function()
        it("produces frames Zstd_Codec can decode", function()
            local input_buffer = buffer.fromstring(SAMPLE_TEXT)
            local compressed   = Encoding_Service:CompressBuffer(input_buffer, ZSTD_ALGORITHM)

            local restored = Zstd_Codec.Decompress(compressed)

            Assert_Bytes_Equal(buffer.tostring(restored), SAMPLE_TEXT, "codec decodes service frame")
        end)

        it("decodes frames Zstd_Codec produces", function()
            local input_buffer = buffer.fromstring(SAMPLE_TEXT)
            local compressed   = Zstd_Codec.Compress(input_buffer)

            local restored = Encoding_Service:DecompressBuffer(compressed, ZSTD_ALGORITHM)

            Assert_Bytes_Equal(buffer.tostring(restored), SAMPLE_TEXT, "service decodes codec frame")
        end)
    end)

    describe("game:GetService shim", function()
        it("returns a working EncodingService instance", function()
            local service      = game:GetService("EncodingService")
            local input_buffer = buffer.fromstring(SAMPLE_TEXT)
            local compressed   = service:CompressBuffer(input_buffer, ZSTD_ALGORITHM)
            local restored     = service:DecompressBuffer(compressed, ZSTD_ALGORITHM)

            Assert_Bytes_Equal(buffer.tostring(restored), SAMPLE_TEXT, "service via GetService")
        end)
    end)
end)
