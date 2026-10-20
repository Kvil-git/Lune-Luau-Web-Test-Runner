--!strict
--
-- EncodingService
--
-- A mock of Roblox's EncodingService built on the pure-Luau Zstd_Codec.
-- It exposes the same surface used by game code:
--
--   * EncodingService:CompressBuffer(input, algorithm, level?)
--   * EncodingService:DecompressBuffer(input, algorithm)
--   * EncodingService:GetDecompressedBufferSize(input, algorithm)
--
-- Only CompressionAlgorithm.Zstd is implemented, matching the real service
-- (Zstd is currently the only value of the enum).  The mock accepts either
-- the numeric enum value (0), the item name ("Zstd"), or an EnumItem-like
-- table whose Name is "Zstd", and rejects anything else.
--
-- The real Roblox API documents Zstd levels from -7 to 22 inclusive with a
-- default of 1; the level is validated here but the pure-Luau encoder only
-- implements a positive, fixed search strategy, so the level is accepted
-- and ignored (round-trips remain byte-exact regardless of level).
--
-- The module returns a ready-to-use singleton, so both
-- `game:GetService("EncodingService")` and a directly required mock expose
-- the same object.
--
-- REQUIRES
--
--
-- Requires
--
local Zstd_Codec = require("./Zstd_Codec")
--
-- EXPORT TYPES
--
export type Encoding_Service = {
    CompressBuffer:            (self: Encoding_Service, input: buffer, algorithm: any, level: number?) -> buffer,
    DecompressBuffer:          (self: Encoding_Service, input: buffer, algorithm: any) -> buffer,
    GetDecompressedBufferSize: (self: Encoding_Service, input: buffer, algorithm: any) -> number?,
}
--
-- CONSTANTS
--
local ZSTD_ALGORITHM_VALUE  = (0)
local ZSTD_ALGORITHM_NAME   = "Zstd"
local MIN_COMPRESSION_LEVEL = (-7)
local MAX_COMPRESSION_LEVEL = (22)
local DEFAULT_LEVEL         = (1)
local MAX_DECOMPRESSED_SIZE = (1024) * (1024) * (1024)
--
-- LOCAL FUNCTIONS
--

--
-- Verifies that the supplied algorithm refers to Zstd.  Accepts the numeric
-- enum value (0), the enum item name ("Zstd"), or an EnumItem-like table
-- whose Name field is "Zstd".  Any other algorithm raises an error, mirroring
-- the fact that the real enum currently only defines Zstd.
--
local function Assert_Is_Zstd(algorithm: any): ()
    if (algorithm == ZSTD_ALGORITHM_VALUE) then
        return
    end

    if (algorithm == ZSTD_ALGORITHM_NAME) then
        return
    end

    if (type(algorithm) == "table") and (algorithm.Name == ZSTD_ALGORITHM_NAME) then
        return
    end

    error(("EncodingService: unsupported compression algorithm %s"):format(tostring(algorithm)), 3)
end

--
-- Validates the optional compression level.  Nil selects the documented
-- default of 1; out-of-range levels are rejected like the real service.
--
local function Resolve_Level(level: number?): number
    if (level == nil) then
        return DEFAULT_LEVEL
    end

    if (level < MIN_COMPRESSION_LEVEL) or (level > MAX_COMPRESSION_LEVEL) then
        error(("EncodingService: compression level %d out of range [%d, %d]")
            :format(level, MIN_COMPRESSION_LEVEL, MAX_COMPRESSION_LEVEL), 3)
    end

    return level
end

--
-- MODULE DEFINITION
--

--
-- The service is a singleton: its methods live directly on the returned
-- table and __index points back at itself, so colon-calls such as
-- Encoding_Service:CompressBuffer(...) resolve correctly.
--
local Encoding_Service = ({} :: any) :: Encoding_Service
Encoding_Service["__index"] = Encoding_Service

--
-- METHODS
--

--
-- Compresses (input) using the Zstd algorithm, returning a Zstd frame.
--
function Encoding_Service.CompressBuffer(
    self      : Encoding_Service,
    input     : buffer,
    algorithm : any,
    level     : number?
): buffer
    Assert_Is_Zstd(algorithm)
    Resolve_Level(level)

    return Zstd_Codec.Compress(input)
end

--
-- Decompresses a Zstd frame.  Raises an error when the frame is invalid or
-- does not contain a usable decompressed size, mirroring the real service.
--
function Encoding_Service.DecompressBuffer(
    self      : Encoding_Service,
    input     : buffer,
    algorithm : any
): buffer
    Assert_Is_Zstd(algorithm)

    return Zstd_Codec.Decompress(input)
end

--
-- Returns the decompressed size recorded in a Zstd frame, or nil when the
-- size is absent, corrupted, or larger than 1GB (the real service's limit).
--
function Encoding_Service.GetDecompressedBufferSize(
    self      : Encoding_Service,
    input     : buffer,
    algorithm : any
): number?
    Assert_Is_Zstd(algorithm)

    local size_ok, size = pcall(Zstd_Codec.Get_Decompressed_Size, input)

    if (not size_ok) then
        return nil
    end

    if (size > MAX_DECOMPRESSED_SIZE) then
        return nil
    end

    return size
end

--
-- RETURN VALUE
--
return Encoding_Service
