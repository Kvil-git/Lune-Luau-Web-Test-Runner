--!strict
--
-- Zstd_Codec
--
-- A pure Luau implementation of the Zstandard (RFC 8878) compression format.
-- No external dependencies; only the standard `buffer` library is used.
--
-- The module provides a decoder that handles the complete frame format
-- (raw / RLE / compressed blocks, Huffman literals, FSE sequences, repeat
-- offsets, treeless literal blocks, skippable frames and frame concatenation)
-- and an encoder that produces valid Zstandard frames.
--
-- REQUIRES
--
-- (none - pure mock, no dependencies)
--
-- LOCAL TYPES
--
type Forward_Stream = {
    buf:        buffer,
    base:       number,
    size:       number,
    byte_index: number,
    bit_offset: number,
}

type Backward_Stream = {
    buf:    buffer,
    base:   number,
    offset: number,
}

type FSE_Table = {
    symbols:        {[number]: number},
    num_bits:       {[number]: number},
    new_state_base: {[number]: number},
    accuracy_log:   number,
    size:           number,
}

type HUF_Table = {
    symbols:  {[number]: number},
    num_bits: {[number]: number},
    max_bits: number,
}

type Output_Buffer = {
    buf: buffer,
    len: number,
    cap: number,
}

type Literals = {
    buf:  buffer,
    size: number,
}

type Sequence = {
    literal_length: number,
    match_length:   number,
    offset:         number,
}

type Frame_Header = {
    window_size:           number,
    frame_content_size:    number,
    dictionary_id:         number,
    content_checksum_flag: boolean,
    single_segment_flag:   boolean,
}

type Frame_Context = {
    header:           Frame_Header,
    literals_table:   HUF_Table?,
    ll_table:         FSE_Table?,
    of_table:         FSE_Table?,
    ml_table:         FSE_Table?,
    previous_offsets: {[number]: number},
    frame_base:       number,
}

--
-- CONSTANTS
--
local ZSTD_MAGIC_NUMBER     = 0xFD2FB528
local ZSTD_SKIPPABLE_MIN    = 0x184D2A50
local ZSTD_SKIPPABLE_MAX    = 0x184D2A5F
local MAX_BLOCK_SIZE        = (128 * 1024)
local MAX_LITERALS_SIZE     = MAX_BLOCK_SIZE
local HUF_MAX_BITS          = (16)
local HUF_MAX_SYMBS         = (256)
local FSE_MAX_SYMBS         = (256)

local SEQ_LL_MAX_CODE       = (35)
local SEQ_ML_MAX_CODE       = (52)

--
-- Predefined FSE distributions used by the Predefined_Mode for
-- sequences (RFC 8878, Appendix A).
--
local SEQ_LL_DEFAULT_DIST = {
    [0] = 4, 3, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 2, 2,
    2, 2, 2, 2, 2, 2, 2, 3, 2, 1, 1, 1, 1, 1, -1, -1, -1, -1,
}
local SEQ_OF_DEFAULT_DIST = {
    [0] = 1, 1, 1, 1, 1, 1, 2, 2, 2, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, -1, -1, -1, -1, -1,
}
local SEQ_ML_DEFAULT_DIST = {
    [0] = 1, 4, 3, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    1, 1, 1, 1, 1, 1, 1, 1, -1, -1, -1, -1, -1, -1, -1,
}

local SEQ_LL_DEFAULT_LENGTH = (36)
local SEQ_OF_DEFAULT_LENGTH = (29)
local SEQ_ML_DEFAULT_LENGTH = (53)

local SEQ_LL_DEFAULT_ACCURACY = (6)
local SEQ_OF_DEFAULT_ACCURACY = (5)
local SEQ_ML_DEFAULT_ACCURACY = (6)

local SEQ_LL_MAX_ACCURACY = (9)
local SEQ_OF_MAX_ACCURACY = (8)
local SEQ_ML_MAX_ACCURACY = (9)

local HUF_WEIGHTS_MAX_ACCURACY = (7)

--
-- Literal length decoding: baseline value and number of extra bits per code.
--
local SEQ_LL_BASELINES = {
    [0] = 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16,
    18, 20, 22, 24, 28, 32, 40, 48, 64, 128, 256, 512, 1024, 2048,
    4096, 8192, 16384, 32768, 65536,
}
local SEQ_LL_EXTRA_BITS = {
    [0] = 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1,
    1, 1, 1, 2, 2, 3, 3, 4, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16,
}

--
-- Match length decoding: baseline value and number of extra bits per code.
--
local SEQ_ML_BASELINES = {
    [0] = 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18,
    19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34,
    35, 37, 39, 41, 43, 47, 51, 59, 67, 83, 99, 131, 259, 515, 1027,
    2051, 4099, 8195, 16387, 32771, 65539,
}
local SEQ_ML_EXTRA_BITS = {
    [0] = 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
    0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 3, 3,
    4, 4, 5, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16,
}
--
-- ALIASES
--
-- Luau (unlike Lua 5.3+) has no bitwise operators, so the bit32 library is
-- used throughout for field extraction and packing.
--
local band   = bit32.band
local bor    = bit32.bor
local bxor   = bit32.bxor
local lshift = bit32.lshift
local rshift = bit32.rshift
--
-- LOCAL FUNCTIONS
--
--
-- Returns the index of the highest set bit of `value`, or -1 when `value`
-- is zero. Works exactly for integers up to 2^53.
--
local function Highest_Set_Bit(value: number): number
    if (value <= 0) then
        return -1
    end

    local result = 0
    while (value >= 2) do
        value = value // 2
        result += 1
    end
    return result
end

--
-- Reads `num_bits` (0..32) little-endian bits starting at `absolute_index`
-- bytes into `buf`, at `bit_offset` bits into that byte. This mirrors the
-- reference `read_bits_LE` used throughout the Zstandard specification.
--
local function Read_Bits_LE(buf: buffer, absolute_index: number, bit_offset: number, num_bits: number): number
    local result = 0
    local shift = 0
    local left = num_bits
    local index = absolute_index
    local offset = bit_offset

    while (left > 0) do
        local mask
        if (left >= 8) then
            mask = 0xFF
        else
            mask = lshift(1, left) - 1
        end

        local byte = buffer.readu8(buf, index)
        index  += 1

        result += lshift(band(rshift(byte, offset), mask), shift)
        shift  += 8 - offset
        left   -= 8 - offset
        offset  = 0
    end

    return result
end

--
-- Creates a forward (little-endian, MSB-later) bit reader over `buf`.
--
local function Forward_New(buf: buffer, base: number, size: number): Forward_Stream
    return {
        buf        = buf,
        base       = base,
        size       = size,
        byte_index = 0,
        bit_offset = 0,
    }
end

--
-- Reads `num_bits` (1..32) from a forward stream.
--
local function Forward_Read(stream: Forward_Stream, num_bits: number): number
    if ((num_bits <= 0) or (num_bits > 32)) then
        error("Zstd_Codec: invalid forward bit read")
    end

    local total = num_bits + stream.bit_offset
    local bytes = (total + 7) // 8
    local end_index = stream.byte_index + bytes
    if (end_index > stream.size) then
        error("Zstd_Codec: input buffer smaller than expected")
    end

    local value = Read_Bits_LE(stream.buf, stream.base + stream.byte_index, stream.bit_offset, num_bits)

    stream.byte_index += total // 8
    stream.bit_offset = total % 8
    return value
end

--
-- Reads up to 64 bits (used for wide, byte-aligned frame header fields).
-- Values above 2^53 lose precision but such sizes are not realistic.
--
local function Forward_Read_Wide(stream: Forward_Stream, num_bits: number): number
    if (num_bits <= 32) then
        return Forward_Read(stream, num_bits)
    end

    local low = Forward_Read(stream, 32)
    local high = Forward_Read(stream, num_bits - 32)
    return low + high * 4294967296
end

--
-- Backs the forward stream up by `num_bits` bits.
--
local function Forward_Rewind(stream: Forward_Stream, num_bits: number): ()
    local new_offset = stream.bit_offset - num_bits
    local bytes = (7 - new_offset) // 8
    stream.byte_index -= bytes
    stream.bit_offset = ((new_offset % 8) + 8) % 8
end

--
-- Aligns the forward stream to the next byte boundary.
--
local function Forward_Align(stream: Forward_Stream): ()
    if (stream.bit_offset ~= 0) then
        stream.byte_index += 1
        stream.bit_offset = 0
    end
end

--
-- Creates a backward bit reader. `last_byte` is the final byte of the
-- stream, whose highest set bit marks the end of the bitstream.
--
local function Backward_New(buf: buffer, base: number, size: number, last_byte: number): Backward_Stream
    local padding = 8 - Highest_Set_Bit(last_byte)
    return {
        buf    = buf,
        base   = base,
        offset = size * 8 - padding,
    }
end

--
-- Reads `bits` bits from the end of a backward stream. When the requested
-- read overflows past the start of the stream, the missing low bits are
-- filled in with zeros (RFC 8878).
--
local function Backward_Read(stream: Backward_Stream, bits: number): number
    stream.offset -= bits

    local offset = stream.offset
    local actual_offset = offset
    local actual_bits = bits

    if (offset < 0) then
        actual_bits = bits + offset
        actual_offset = 0
    end

    local result = 0
    if (actual_bits > 0) then
        result = Read_Bits_LE(stream.buf, stream.base + actual_offset // 8, actual_offset % 8, actual_bits)
    end

    if (offset < 0) then
        local overflow = -offset
        if (overflow >= 64) then
            result = 0
        else
            result = result * (2 ^ overflow)
        end
    end

    return result
end

--
-- Output buffer helpers.
--
local function Output_New(): Output_Buffer
    local capacity = 1024
    return {
        buf = buffer.create(capacity),
        len = 0,
        cap = capacity,
    }
end

local function Output_Ensure(output: Output_Buffer, extra: number): ()
    local needed = output.len + extra
    if (needed <= output.cap) then
        return
    end

    local new_cap = output.cap
    while (new_cap < needed) do
        new_cap *= 2
    end

    local new_buf = buffer.create(new_cap)
    buffer.copy(new_buf, 0, output.buf, 0, output.len)
    output.buf = new_buf
    output.cap = new_cap
end

local function Output_Write_Byte(output: Output_Buffer, byte: number): ()
    Output_Ensure(output, 1)
    buffer.writeu8(output.buf, output.len, byte)
    output.len += 1
end

local function Output_Write_Bytes(output: Output_Buffer, source: buffer, source_offset: number, count: number): ()
    Output_Ensure(output, count)
    buffer.copy(output.buf, output.len, source, source_offset, count)
    output.len += count
end

local function Output_Write_Repeat(output: Output_Buffer, byte: number, count: number): ()
    Output_Ensure(output, count)
    buffer.fill(output.buf, output.len, byte, count)
    output.len += count
end

local function Output_Finalize(output: Output_Buffer): buffer
    local result = buffer.create(output.len)
    if (output.len > 0) then
        buffer.copy(result, 0, output.buf, 0, output.len)
    end
    return result
end

--
-- Builds an FSE decoding table from a normalized probability distribution.
-- Symbols are addressed with zero-based indices to match RFC 8878.
--
local function FSE_Build_Table(norm_freqs: {[number]: number}, num_symbs: number, accuracy_log: number): FSE_Table
    if (accuracy_log > 15) then
        error("Zstd_Codec: FSE accuracy too large")
    end
    if (num_symbs > FSE_MAX_SYMBS) then
        error("Zstd_Codec: too many FSE symbols")
    end

    local size = lshift(1, accuracy_log)
    local symbols: {[number]: number} = {}
    local num_bits: {[number]: number} = {}
    local new_state_base: {[number]: number} = {}
    local state_desc: {[number]: number} = {}

    --
    -- Symbols with probability -1 ("less than one") are placed at the top
    -- of the table, each taking a single cell.
    --
    local high_threshold = size
    for symb = 0, num_symbs - 1 do
        if (norm_freqs[symb] == -1) then
            high_threshold -= 1
            symbols[high_threshold] = symb
            state_desc[symb] = 1
        end
    end

    --
    -- Remaining symbols are spread across the table using a step that is
    -- coprime with the table size, skipping the already-occupied cells.
    --
    local step = rshift(size, 1) + rshift(size, 3) + 3
    local mask = size - 1
    local position = 0
    for symb = 0, num_symbs - 1 do
        local probability = norm_freqs[symb]
        if (probability > 0) then
            state_desc[symb] = probability
            for _ = 1, probability do
                symbols[position] = symb
                repeat
                    position = band(position + step, mask)
                until position < high_threshold
            end
        end
    end

    if (position ~= 0) then
        error("Zstd_Codec: corrupted FSE distribution")
    end

    for state = 0, size - 1 do
        local symbol = symbols[state]
        local state_description = state_desc[symbol]
        state_desc[symbol] = state_description + 1

        local bits = accuracy_log - Highest_Set_Bit(state_description)
        num_bits[state] = bits
        new_state_base[state] = lshift(state_description, bits) - size
    end

    return {
        symbols        = symbols,
        num_bits       = num_bits,
        new_state_base = new_state_base,
        accuracy_log   = accuracy_log,
        size           = size,
    }
end

--
-- Builds an FSE decoding table that always returns a single symbol and
-- consumes no bits (RLE_Mode for sequence tables).
--
local function FSE_Build_RLE_Table(symbol: number): FSE_Table
    return {
        symbols        = { [0] = symbol },
        num_bits       = { [0] = 0 },
        new_state_base = { [0] = 0 },
        accuracy_log   = 0,
        size           = 1,
    }
end

--
-- Decodes an FSE distribution header (NCount) and builds a decoding table.
-- The header is a forward, little-endian bitstream.
--
local function FSE_Decode_Header(stream: Forward_Stream, max_accuracy_log: number): FSE_Table
    local accuracy_log = 5 + Forward_Read(stream, 4)
    if (accuracy_log > max_accuracy_log) then
        error("Zstd_Codec: FSE accuracy too large")
    end

    local remaining = lshift(1, accuracy_log)
    local frequencies: {[number]: number} = {}

    local symb = 0
    while ((remaining > 0) and (symb < FSE_MAX_SYMBS)) do
        local bits = Highest_Set_Bit(remaining + 1) + 1
        local value = Forward_Read(stream, bits)

        local lower_mask = lshift(1, bits - 1) - 1
        local threshold = lshift(1, bits) - 1 - (remaining + 1)

        if (band(value, lower_mask) < threshold) then
            Forward_Rewind(stream, 1)
            value = band(value, lower_mask)
        elseif (value > lower_mask) then
            value = value - threshold
        end

        local probability = value - 1
        if (probability < 0) then
            remaining -= -probability
        else
            remaining -= probability
        end

        frequencies[symb] = probability
        symb += 1

        if (probability == 0) then
            local repeat_count = Forward_Read(stream, 2)
            while (true) do
                for _ = 1, repeat_count do
                    if (symb < FSE_MAX_SYMBS) then
                        frequencies[symb] = 0
                        symb += 1
                    end
                end

                if (repeat_count == 3) then
                    repeat_count = Forward_Read(stream, 2)
                else
                    break
                end
            end
        end
    end

    Forward_Align(stream)

    if ((remaining ~= 0) or (symb >= FSE_MAX_SYMBS)) then
        error("Zstd_Codec: corrupted FSE distribution")
    end

    return FSE_Build_Table(frequencies, symb, accuracy_log)
end

local function FSE_Initialize_State(stream: Backward_Stream, table: FSE_Table): number
    return Backward_Read(stream, table.accuracy_log)
end

local function FSE_Peek_Symbol(table: FSE_Table, state: number): number
    return table.symbols[state]
end

local function FSE_Update_State(stream: Backward_Stream, table: FSE_Table, state: number): number
    local bits = table.num_bits[state]
    local rest = Backward_Read(stream, bits)
    return table.new_state_base[state] + rest
end

--
-- Decodes two interleaved FSE states (used for FSE-compressed Huffman
-- weights). Returns the decoded symbols and their count.
--
local function FSE_Decompress_Interleaved2(table: FSE_Table, stream: Backward_Stream): ({number}, number)
    local state_1 = FSE_Initialize_State(stream, table)
    local state_2 = FSE_Initialize_State(stream, table)

    local output: {number} = {}
    local count = 0

    while (true) do
        output[count] = FSE_Peek_Symbol(table, state_1)
        count += 1
        state_1 = FSE_Update_State(stream, table, state_1)
        if (stream.offset < 0) then
            output[count] = FSE_Peek_Symbol(table, state_2)
            count += 1
            break
        end

        output[count] = FSE_Peek_Symbol(table, state_2)
        count += 1
        state_2 = FSE_Update_State(stream, table, state_2)
        if (stream.offset < 0) then
            output[count] = FSE_Peek_Symbol(table, state_1)
            count += 1
            break
        end

        if (count > HUF_MAX_SYMBS + 8) then
            error("Zstd_Codec: Huffman weight stream too long")
        end
    end

    return output, count
end

--
-- Builds a canonical Huffman decoding table from per-symbol code lengths
-- (zero meaning "symbol not present").
--
local function HUF_Build_Table(bits: {[number]: number}, num_symbs: number): HUF_Table
    if (num_symbs > HUF_MAX_SYMBS) then
        error("Zstd_Codec: too many Huffman symbols")
    end

    local max_bits = 0
    local rank_count: {[number]: number} = {}
    for index = 0, num_symbs - 1 do
        local length = bits[index]
        if (length > HUF_MAX_BITS) then
            error("Zstd_Codec: Huffman table depth too large")
        end
        if (length > max_bits) then
            max_bits = length
        end
        rank_count[length] = (rank_count[length] or 0) + 1
    end

    if (max_bits == 0) then
        error("Zstd_Codec: empty Huffman table")
    end

    local table_size = lshift(1, max_bits)
    local symbols: {[number]: number} = {}
    local num_bits: {[number]: number} = {}

    local rank_index: {[number]: number} = {}
    rank_index[max_bits] = 0
    for length = max_bits, 1, -1 do
        local count = rank_count[length] or 0
        rank_index[length - 1] = rank_index[length] + count * lshift(1, max_bits - length)
        for index = rank_index[length], rank_index[length - 1] - 1 do
            num_bits[index] = length
        end
    end

    if (rank_index[0] ~= table_size) then
        error("Zstd_Codec: corrupted Huffman table")
    end

    for index = 0, num_symbs - 1 do
        local length = bits[index]
        if (length ~= 0) then
            local code = rank_index[length]
            local span = lshift(1, max_bits - length)
            for offset = code, code + span - 1 do
                symbols[offset] = index
            end
            rank_index[length] += span
        end
    end

    return {
        symbols  = symbols,
        num_bits = num_bits,
        max_bits = max_bits,
    }
end

--
-- Builds a Huffman decoding table from the transmitted weight list. The
-- final weight is deduced from the leftover of the power-of-two total.
--
local function HUF_Build_From_Weights(weights: {[number]: number}, num_symbs: number): HUF_Table
    if (num_symbs + 1 > HUF_MAX_SYMBS) then
        error("Zstd_Codec: too many Huffman symbols")
    end

    local weight_sum = 0
    for index = 0, num_symbs - 1 do
        local weight = weights[index]
        if (weight > HUF_MAX_BITS) then
            error("Zstd_Codec: corrupted Huffman weights")
        end
        if (weight > 0) then
            weight_sum += lshift(1, weight - 1)
        end
    end

    if (weight_sum == 0) then
        error("Zstd_Codec: corrupted Huffman weights")
    end

    local max_bits = Highest_Set_Bit(weight_sum) + 1
    if (max_bits > HUF_MAX_BITS) then
        error("Zstd_Codec: Huffman table depth too large")
    end

    local left_over = lshift(1, max_bits) - weight_sum
    if (band(left_over, left_over - 1) ~= 0) then
        error("Zstd_Codec: corrupted Huffman weights")
    end

    local last_weight = Highest_Set_Bit(left_over) + 1

    local bits: {[number]: number} = {}
    for index = 0, num_symbs - 1 do
        local weight = weights[index]
        if (weight > 0) then
            bits[index] = max_bits + 1 - weight
        else
            bits[index] = 0
        end
    end
    bits[num_symbs] = max_bits + 1 - last_weight

    return HUF_Build_Table(bits, num_symbs + 1)
end

--
-- Decodes a Huffman table description from a forward stream.
--
local function HUF_Decode_Table(stream: Forward_Stream): HUF_Table
    local header = Forward_Read(stream, 8)
    local weights: {[number]: number} = {}
    local num_symbs

    if (header >= 128) then
        num_symbs = header - 127
        local bytes = (num_symbs + 1) // 2
        if (stream.byte_index + bytes > stream.size) then
            error("Zstd_Codec: input buffer smaller than expected")
        end

        for index = 0, num_symbs - 1 do
            local byte = buffer.readu8(stream.buf, stream.base + stream.byte_index + index // 2)
            if (index % 2 == 0) then
                weights[index] = rshift(byte, 4)
            else
                weights[index] = band(byte, 0xF)
            end
        end
        stream.byte_index += bytes
    else
        --
        -- The FSE-compressed weights occupy `header` bytes; the NCount table
        -- is read forward, then the weight bitstream is read backward within
        -- the same region.
        --
        local fse_size = header
        if (stream.byte_index + fse_size > stream.size) then
            error("Zstd_Codec: input buffer smaller than expected")
        end

        local sub_stream = Forward_New(stream.buf, stream.base + stream.byte_index, fse_size)
        stream.byte_index += fse_size

        local table = FSE_Decode_Header(sub_stream, HUF_WEIGHTS_MAX_ACCURACY)

        local remaining = sub_stream.size - sub_stream.byte_index
        if (remaining <= 0) then
            error("Zstd_Codec: corrupted Huffman weights")
        end
        local back_base = sub_stream.base + sub_stream.byte_index
        local last_byte = buffer.readu8(sub_stream.buf, back_base + remaining - 1)
        local backward = Backward_New(sub_stream.buf, back_base, remaining, last_byte)

        local decoded_weights, count = FSE_Decompress_Interleaved2(table, backward)
        weights = decoded_weights
        num_symbs = count
    end

    return HUF_Build_From_Weights(weights, num_symbs)
end

--
-- Decodes a single backward Huffman stream into the literals buffer.
--
local function HUF_Decode_1_Stream(table: HUF_Table, literals: buffer, literals_position: number, stream: Backward_Stream): number
    local state = Backward_Read(stream, table.max_bits)
    local mask = lshift(1, table.max_bits) - 1
    local written = 0

    while (stream.offset > -table.max_bits) do
        local symbol = table.symbols[state]
        local bits = table.num_bits[state]

        buffer.writeu8(literals, literals_position + written, symbol)
        written += 1

        local rest = Backward_Read(stream, bits)
        state = band(lshift(state, bits) + rest, mask)
    end

    if (stream.offset ~= -table.max_bits) then
        error("Zstd_Codec: corrupted Huffman stream")
    end

    return written
end

--
-- Decodes a compressed literals body (1 or 4 streams).
--
local function HUF_Decode_Streams(ctx: Frame_Context, stream: Forward_Stream, block_type: number, num_streams: number, literals: buffer): number
    if (block_type == 2) then
        ctx.literals_table = HUF_Decode_Table(stream)
    elseif (ctx.literals_table == nil) then
        error("Zstd_Codec: treeless literals block without a table")
    end

    local table = ctx.literals_table :: HUF_Table
    local written = 0

    if (num_streams == 1) then
        local size = stream.size - stream.byte_index
        if (size <= 0) then
            error("Zstd_Codec: corrupted Huffman stream")
        end
        local base = stream.base + stream.byte_index
        local last_byte = buffer.readu8(stream.buf, base + size - 1)
        local backward = Backward_New(stream.buf, base, size, last_byte)
        written += HUF_Decode_1_Stream(table, literals, written, backward)
        stream.byte_index += size
        return written
    end

    local size_1 = Forward_Read(stream, 16)
    local size_2 = Forward_Read(stream, 16)
    local size_3 = Forward_Read(stream, 16)

    local base = stream.base + stream.byte_index
    local total = stream.size - stream.byte_index
    if (size_1 + size_2 + size_3 > total) then
        error("Zstd_Codec: corrupted Huffman jump table")
    end

    local size_4 = total - size_1 - size_2 - size_3

    local function decode_segment(segment_base: number, segment_size: number): number
        if (segment_size <= 0) then
            return 0
        end
        local last_byte = buffer.readu8(stream.buf, segment_base + segment_size - 1)
        local backward = Backward_New(stream.buf, segment_base, segment_size, last_byte)
        return HUF_Decode_1_Stream(table, literals, written, backward)
    end

    written += decode_segment(base, size_1)
    written += decode_segment(base + size_1, size_2)
    written += decode_segment(base + size_1 + size_2, size_3)
    written += decode_segment(base + size_1 + size_2 + size_3, size_4)

    stream.byte_index += total
    return written
end

--
-- Decodes a raw or RLE literals block.
--
local function Decode_Literals_Simple(stream: Forward_Stream, block_type: number, size_format: number): Literals
    local size
    if ((size_format == 0) or (size_format == 2)) then
        Forward_Rewind(stream, 1)
        size = Forward_Read(stream, 5)
    elseif (size_format == 1) then
        size = Forward_Read(stream, 12)
    else
        size = Forward_Read(stream, 20)
    end

    if (size > MAX_LITERALS_SIZE) then
        error("Zstd_Codec: literals block too large")
    end

    local alloc = size > 0 and size or 1
    local literals = buffer.create(alloc)

    if (block_type == 0) then
        if (stream.byte_index + size > stream.size) then
            error("Zstd_Codec: input buffer smaller than expected")
        end
        buffer.copy(literals, 0, stream.buf, stream.base + stream.byte_index, size)
        stream.byte_index += size
    else
        if (stream.byte_index + 1 > stream.size) then
            error("Zstd_Codec: input buffer smaller than expected")
        end
        local byte = buffer.readu8(stream.buf, stream.base + stream.byte_index)
        stream.byte_index += 1
        buffer.fill(literals, 0, byte, size)
    end

    return {
        buf  = literals,
        size = size,
    }
end

--
-- Decodes a Huffman-compressed literals block.
--
local function Decode_Literals_Compressed(ctx: Frame_Context, stream: Forward_Stream, block_type: number, size_format: number): Literals
    local num_streams = 4
    local regenerated_size
    local compressed_size

    if (size_format == 0) then
        num_streams = 1
        regenerated_size = Forward_Read(stream, 10)
        compressed_size = Forward_Read(stream, 10)
    elseif (size_format == 1) then
        regenerated_size = Forward_Read(stream, 10)
        compressed_size = Forward_Read(stream, 10)
    elseif (size_format == 2) then
        regenerated_size = Forward_Read(stream, 14)
        compressed_size = Forward_Read(stream, 14)
    else
        regenerated_size = Forward_Read(stream, 18)
        compressed_size = Forward_Read(stream, 18)
    end

    if (regenerated_size > MAX_LITERALS_SIZE) then
        error("Zstd_Codec: literals block too large")
    end

    if (stream.byte_index + compressed_size > stream.size) then
        error("Zstd_Codec: input buffer smaller than expected")
    end

    local body = Forward_New(stream.buf, stream.base + stream.byte_index, compressed_size)
    stream.byte_index += compressed_size

    local alloc = regenerated_size > 0 and regenerated_size or 1
    local literals = buffer.create(alloc)

    local written = HUF_Decode_Streams(ctx, body, block_type, num_streams, literals)
    if (written ~= regenerated_size) then
        error("Zstd_Codec: literal count mismatch")
    end

    return {
        buf  = literals,
        size = regenerated_size,
    }
end

--
-- Decodes the literals section of a block.
--
local function Decode_Literals(ctx: Frame_Context, stream: Forward_Stream): Literals
    local block_type = Forward_Read(stream, 2)
    local size_format = Forward_Read(stream, 2)

    if (block_type <= 1) then
        return Decode_Literals_Simple(stream, block_type, size_format)
    end
    return Decode_Literals_Compressed(ctx, stream, block_type, size_format)
end

--
-- Decodes a single sequence table (literal lengths, offsets or match
-- lengths) according to its compression mode.
--
local function Decode_Sequence_Table(previous: FSE_Table?, stream: Forward_Stream, table_type: number, mode: number): FSE_Table
    if (mode == 0) then
        if (table_type == 0) then
            return FSE_Build_Table(SEQ_LL_DEFAULT_DIST, SEQ_LL_DEFAULT_LENGTH, SEQ_LL_DEFAULT_ACCURACY)
        elseif (table_type == 1) then
            return FSE_Build_Table(SEQ_OF_DEFAULT_DIST, SEQ_OF_DEFAULT_LENGTH, SEQ_OF_DEFAULT_ACCURACY)
        else
            return FSE_Build_Table(SEQ_ML_DEFAULT_DIST, SEQ_ML_DEFAULT_LENGTH, SEQ_ML_DEFAULT_ACCURACY)
        end
    elseif (mode == 1) then
        if (stream.byte_index + 1 > stream.size) then
            error("Zstd_Codec: input buffer smaller than expected")
        end
        local symbol = buffer.readu8(stream.buf, stream.base + stream.byte_index)
        stream.byte_index += 1
        return FSE_Build_RLE_Table(symbol)
    elseif (mode == 2) then
        if (table_type == 0) then
            return FSE_Decode_Header(stream, SEQ_LL_MAX_ACCURACY)
        elseif (table_type == 1) then
            return FSE_Decode_Header(stream, SEQ_OF_MAX_ACCURACY)
        else
            return FSE_Decode_Header(stream, SEQ_ML_MAX_ACCURACY)
        end
    end

    if (previous == nil) then
        error("Zstd_Codec: repeat sequence table without a previous table")
    end
    return previous
end

--
-- Decodes the sequences section of a block.
--
local function Decode_Sequences(ctx: Frame_Context, stream: Forward_Stream): {Sequence}
    local header = Forward_Read(stream, 8)
    local num_sequences
    if (header < 128) then
        num_sequences = header
    elseif (header < 255) then
        num_sequences = lshift(header - 128, 8) + Forward_Read(stream, 8)
    else
        num_sequences = Forward_Read(stream, 16) + 0x7F00
    end

    if (num_sequences == 0) then
        return {}
    end

    local modes = Forward_Read(stream, 8)
    if (band(modes, 3) ~= 0) then
        error("Zstd_Codec: reserved sequence bits set")
    end

    local ll_table = Decode_Sequence_Table(ctx.ll_table, stream, 0, band(rshift(modes, 6), 3))
    local of_table = Decode_Sequence_Table(ctx.of_table, stream, 1, band(rshift(modes, 4), 3))
    local ml_table = Decode_Sequence_Table(ctx.ml_table, stream, 2, band(rshift(modes, 2), 3))

    ctx.ll_table = ll_table
    ctx.of_table = of_table
    ctx.ml_table = ml_table

    local base = stream.base + stream.byte_index
    local size = stream.size - stream.byte_index
    if (size <= 0) then
        error("Zstd_Codec: corrupted sequence section")
    end
    local last_byte = buffer.readu8(stream.buf, base + size - 1)
    local backward = Backward_New(stream.buf, base, size, last_byte)
    stream.byte_index += size

    local ll_state = FSE_Initialize_State(backward, ll_table)
    local of_state = FSE_Initialize_State(backward, of_table)
    local ml_state = FSE_Initialize_State(backward, ml_table)

    local sequences: {Sequence} = {}
    for index = 1, num_sequences do
        local of_code = FSE_Peek_Symbol(of_table, of_state)
        local ll_code = FSE_Peek_Symbol(ll_table, ll_state)
        local ml_code = FSE_Peek_Symbol(ml_table, ml_state)

        if ((ll_code > SEQ_LL_MAX_CODE) or (ml_code > SEQ_ML_MAX_CODE)) then
            error("Zstd_Codec: corrupted sequence code")
        end

        local offset = lshift(1, of_code) + Backward_Read(backward, of_code)
        local match_length = SEQ_ML_BASELINES[ml_code] + Backward_Read(backward, SEQ_ML_EXTRA_BITS[ml_code])
        local literal_length = SEQ_LL_BASELINES[ll_code] + Backward_Read(backward, SEQ_LL_EXTRA_BITS[ll_code])

        if (index < num_sequences) then
            ll_state = FSE_Update_State(backward, ll_table, ll_state)
            ml_state = FSE_Update_State(backward, ml_table, ml_state)
            of_state = FSE_Update_State(backward, of_table, of_state)
        end

        sequences[index] = {
            literal_length = literal_length,
            match_length   = match_length,
            offset         = offset,
        }
    end

    if (backward.offset ~= 0) then
        error("Zstd_Codec: sequence bitstream not fully consumed")
    end

    return sequences
end

--
-- Given a sequence's offset code, resolves the real offset and updates the
-- repeat offset history.
--
local function Compute_Offset(sequence: Sequence, history: {[number]: number}): number
    local offset

    if (sequence.offset <= 3) then
        local idx = sequence.offset - 1
        if (sequence.literal_length == 0) then
            idx += 1
        end

        if (idx == 0) then
            offset = history[1]
        else
            if (idx < 3) then
                offset = history[idx + 1]
            else
                offset = history[1] - 1
            end

            if (idx > 1) then
                history[3] = history[2]
            end
            history[2] = history[1]
            history[1] = offset
        end
    else
        offset = sequence.offset - 3
        history[3] = history[2]
        history[2] = history[1]
        history[1] = offset
    end

    return offset
end

--
-- Executes the sequences on top of the decoded literals, writing to the
-- frame output buffer.
--
local function Execute_Sequences(ctx: Frame_Context, output: Output_Buffer, literals: Literals, sequences: {Sequence}): ()
    local literal_position = 0
    local history = ctx.previous_offsets

    for index = 1, #sequences do
        local sequence = sequences[index]

        local literal_length = sequence.literal_length
        if (literal_position + literal_length > literals.size) then
            error("Zstd_Codec: sequence reads past literals")
        end
        Output_Write_Bytes(output, literals.buf, literal_position, literal_length)
        literal_position += literal_length

        local offset = Compute_Offset(sequence, history)
        if (offset <= 0) then
            error("Zstd_Codec: invalid offset")
        end

        local total_output = output.len - ctx.frame_base
        if (offset > total_output) then
            error("Zstd_Codec: offset beyond frame content")
        end

        for _ = 1, sequence.match_length do
            local byte = buffer.readu8(output.buf, output.len - offset)
            Output_Write_Byte(output, byte)
        end
    end

    local remaining = literals.size - literal_position
    Output_Write_Bytes(output, literals.buf, literal_position, remaining)
end

--
-- Decompresses a single compressed block (literal + sequences sections).
--
local function Decompress_Block(ctx: Frame_Context, output: Output_Buffer, stream: Forward_Stream): ()
    local literals = Decode_Literals(ctx, stream)
    local sequences = Decode_Sequences(ctx, stream)
    Execute_Sequences(ctx, output, literals, sequences)
end

--
-- Parses a frame header (RFC 8878, section 3.1.1.1).
--
local function Parse_Frame_Header(stream: Forward_Stream): Frame_Header
    local descriptor = Forward_Read(stream, 8)
    local frame_content_size_flag = rshift(descriptor, 6)
    local single_segment_flag = band(rshift(descriptor, 5), 1)
    local reserved_bit = band(rshift(descriptor, 3), 1)
    local content_checksum_flag = band(rshift(descriptor, 2), 1)
    local dictionary_id_flag = band(descriptor, 3)

    if (reserved_bit ~= 0) then
        error("Zstd_Codec: reserved frame header bit set")
    end

    local header: Frame_Header = {
        window_size           = 0,
        frame_content_size    = 0,
        dictionary_id         = 0,
        content_checksum_flag = content_checksum_flag == 1,
        single_segment_flag   = single_segment_flag == 1,
    }

    if (single_segment_flag == 0) then
        local window_descriptor = Forward_Read(stream, 8)
        local exponent = rshift(window_descriptor, 3)
        local mantissa = band(window_descriptor, 7)
        local window_base = 2 ^ (10 + exponent)
        local window_add = (window_base // 8) * mantissa
        header.window_size = window_base + window_add
    end

    if (dictionary_id_flag ~= 0) then
        local dictionary_bytes = ({ [1] = 1, [2] = 2, [3] = 4 })[dictionary_id_flag]
        header.dictionary_id = Forward_Read_Wide(stream, dictionary_bytes * 8)
    end

    if ((single_segment_flag == 1) or (frame_content_size_flag ~= 0)) then
        local size_bytes = ({ [1] = 1, [2] = 2, [3] = 4, [4] = 8 })[frame_content_size_flag + 1]
        header.frame_content_size = Forward_Read_Wide(stream, size_bytes * 8)
        if (size_bytes == 2) then
            header.frame_content_size += 256
        end
    end

    if (single_segment_flag == 1) then
        header.window_size = header.frame_content_size
    end

    return header
end

--
-- Decompresses a single data frame.
--
local function Decode_Data_Frame(stream: Forward_Stream, output: Output_Buffer): ()
    local header = Parse_Frame_Header(stream)
    if (header.dictionary_id ~= 0) then
        error("Zstd_Codec: dictionaries are not supported")
    end

    local ctx = {
        header           = header,
        literals_table   = nil,
        ll_table         = nil,
        of_table         = nil,
        ml_table         = nil,
        previous_offsets = { 1, 4, 8 },
        frame_base       = output.len,
    }

    local last_block = false
    repeat
        local last_flag = Forward_Read(stream, 1)
        local block_type = Forward_Read(stream, 2)
        local block_size = Forward_Read(stream, 21)

        if (block_type == 0) then
            if (stream.byte_index + block_size > stream.size) then
                error("Zstd_Codec: input buffer smaller than expected")
            end
            Output_Write_Bytes(output, stream.buf, stream.base + stream.byte_index, block_size)
            stream.byte_index += block_size
        elseif (block_type == 1) then
            if (stream.byte_index + 1 > stream.size) then
                error("Zstd_Codec: input buffer smaller than expected")
            end
            local byte = buffer.readu8(stream.buf, stream.base + stream.byte_index)
            stream.byte_index += 1
            Output_Write_Repeat(output, byte, block_size)
        elseif (block_type == 2) then
            if (stream.byte_index + block_size > stream.size) then
                error("Zstd_Codec: input buffer smaller than expected")
            end
            local block_stream = Forward_New(stream.buf, stream.base + stream.byte_index, block_size)
            stream.byte_index += block_size
            Decompress_Block(ctx, output, block_stream)
        else
            error("Zstd_Codec: reserved block type")
        end

        last_block = last_flag == 1
    until last_block

    if (header.content_checksum_flag) then
        stream.byte_index += 4
    end
end

--
-- ENCODER
--
--
-- Appends a single byte to a plain byte table.
--
local function Bytes_Write_U8(bytes: {number}, value: number): ()
    table.insert(bytes, band(value, 0xFF))
end

local function Bytes_Write_U16LE(bytes: {number}, value: number): ()
    table.insert(bytes, band(value, 0xFF))
    table.insert(bytes, band(rshift(value, 8), 0xFF))
end

local function Bytes_Write_U24LE(bytes: {number}, value: number): ()
    table.insert(bytes, band(value, 0xFF))
    table.insert(bytes, band(rshift(value, 8), 0xFF))
    table.insert(bytes, band(rshift(value, 16), 0xFF))
end

local function Bytes_Write_U32LE(bytes: {number}, value: number): ()
    table.insert(bytes, band(value, 0xFF))
    table.insert(bytes, band(rshift(value, 8), 0xFF))
    table.insert(bytes, band(rshift(value, 16), 0xFF))
    table.insert(bytes, band(rshift(value, 24), 0xFF))
end

--
-- Converts a plain byte table into a buffer.
--
local function Bytes_To_Buffer(bytes: {number}): buffer
    local count = #bytes
    local alloc = count > 0 and count or 1
    local result = buffer.create(alloc)
    for index = 1, count do
        buffer.writeu8(result, index - 1, bytes[index])
    end
    return result
end

--
-- LSB-first bit writer used to build backward-read FSE bitstreams. Bits are
-- appended at increasing positions; `Bit_Writer_Finish` adds the mandatory
-- end-of-stream marker bit and flushes the final partial byte.
--
type Bit_Writer = {
    bytes:     {number},
    container: number,
    bit_count: number,
}

type Encode_Sequence = {
    literal_length: number,
    match_length:   number,
    offset:         number,
}

local function Bit_Writer_New(): Bit_Writer
    return {
        bytes     = {},
        container = 0,
        bit_count = 0,
    }
end

local function Bit_Writer_Write(writer: Bit_Writer, value: number, num_bits: number): ()
    if (num_bits <= 0) then
        return
    end

    writer.container += value * (2 ^ writer.bit_count)
    writer.bit_count += num_bits

    while (writer.bit_count >= 8) do
        table.insert(writer.bytes, band(writer.container, 0xFF))
        writer.container = writer.container // 256
        writer.bit_count -= 8
    end
end

local function Bit_Writer_Finish(writer: Bit_Writer): {number}
    writer.container += 2 ^ writer.bit_count
    writer.bit_count += 1

    while (writer.bit_count > 0) do
        table.insert(writer.bytes, band(writer.container, 0xFF))
        writer.container = writer.container // 256
        writer.bit_count -= 8
    end

    return writer.bytes
end

--
-- Flushes a forward (little-endian) bit field, zero-padding the final byte.
-- Unlike `Bit_Writer_Finish` this adds no end-of-stream marker, as required
-- by the literals section header.
--
local function Bit_Writer_Finish_Forward(writer: Bit_Writer): {number}
    if (writer.bit_count > 0) then
        table.insert(writer.bytes, band(writer.container, 0xFF))
        writer.container = 0
        writer.bit_count = 0
    end

    return writer.bytes
end

--
-- Precomputes, for every (symbol, successor state) pair, the unique
-- predecessor state that emits the symbol and spans the successor. This is
-- the inverse of the decoding-table transition and drives the FSE back-chain.
--
local function FSE_Encode_Prepare(table: FSE_Table): ({[number]: {[number]: number}}, {[number]: number})
    local previous: {[number]: {[number]: number}} = {}
    local first_state: {[number]: number} = {}

    for state = 0, table.size - 1 do
        local symbol = table.symbols[state]
        local base = table.new_state_base[state]
        local span = lshift(1, table.num_bits[state])

        local row = previous[symbol]
        if (row == nil) then
            row = {}
            previous[symbol] = row
        end
        for successor = base, base + span - 1 do
            row[successor] = state
        end

        if (first_state[symbol] == nil) then
            first_state[symbol] = state
        end
    end

    return previous, first_state
end

--
-- Builds the state sequence for `codes` (1..count). The final state is
-- chosen freely among the states emitting the last code; earlier states are
-- derived by walking the FSE back-chain.
--
local function FSE_Encode_States(previous: {[number]: {[number]: number}}, first_state: {[number]: number}, codes: {number}, count: number): {number}
    local states: {number} = {}
    states[count] = first_state[codes[count]]

    for index = count - 1, 1, -1 do
        states[index] = previous[codes[index]][states[index + 1]]
    end

    return states
end

--
-- Maps a literal length to its code (RFC 8878, Table 16).
--
local function Choose_LL_Code(length: number): number
    if (length < 16) then
        return length
    end
    for code = SEQ_LL_MAX_CODE, 16, -1 do
        if (SEQ_LL_BASELINES[code] <= length) then
            return code
        end
    end
    return 15
end

--
-- Maps a match length to its code (RFC 8878, Table 17).
--
local function Choose_ML_Code(length: number): number
    if (length < 35) then
        return length - 3
    end
    for code = SEQ_ML_MAX_CODE, 32, -1 do
        if (SEQ_ML_BASELINES[code] <= length) then
            return code
        end
    end
    return 31
end

--
-- The predefined sequence tables (Predefined_Mode) and their encoding
-- transition tables, built once and reused for every block.
--
local SEQ_LL_TABLE = FSE_Build_Table(SEQ_LL_DEFAULT_DIST, SEQ_LL_DEFAULT_LENGTH, SEQ_LL_DEFAULT_ACCURACY)
local SEQ_OF_TABLE = FSE_Build_Table(SEQ_OF_DEFAULT_DIST, SEQ_OF_DEFAULT_LENGTH, SEQ_OF_DEFAULT_ACCURACY)
local SEQ_ML_TABLE = FSE_Build_Table(SEQ_ML_DEFAULT_DIST, SEQ_ML_DEFAULT_LENGTH, SEQ_ML_DEFAULT_ACCURACY)

local SEQ_LL_PREVIOUS, SEQ_LL_FIRST = FSE_Encode_Prepare(SEQ_LL_TABLE)
local SEQ_OF_PREVIOUS, SEQ_OF_FIRST = FSE_Encode_Prepare(SEQ_OF_TABLE)
local SEQ_ML_PREVIOUS, SEQ_ML_FIRST = FSE_Encode_Prepare(SEQ_ML_TABLE)

--
-- Builds Huffman code lengths from symbol frequencies using the classic
-- two-smallest merge. Returns nil when fewer than two symbols are present or
-- when the resulting depth exceeds the Zstandard limit of 11 bits.
--
local function Build_Huffman_Lengths(frequencies: {[number]: number}): ({[number]: number}?, number)
    local symbols: {number} = {}
    for symbol = 0, 255 do
        local frequency = frequencies[symbol]
        if ((frequency ~= nil) and (frequency > 0)) then
            table.insert(symbols, symbol)
        end
    end

    local count = #symbols
    if (count < 2) then
        return nil, 0
    end

    local weight: {number} = {}
    local parent: {number} = {}
    for index = 1, count do
        weight[index] = frequencies[symbols[index]]
        parent[index] = 0
    end

    local active: {number} = {}
    for index = 1, count do
        active[index] = index
    end

    local nodes = count
    while (#active > 1) do
        local first = 1
        local second = 2
        if (weight[active[second]] < weight[active[first]]) then
            first, second = second, first
        end
        for index = 3, #active do
            local current = weight[active[index]]
            if (current < weight[active[first]]) then
                second = first
                first = index
            elseif (current < weight[active[second]]) then
                second = index
            end
        end

        local left = active[first]
        local right = active[second]
        nodes += 1
        weight[nodes] = weight[left] + weight[right]
        parent[left] = nodes
        parent[right] = nodes

        local high = math.max(first, second)
        local low = math.min(first, second)
        table.remove(active, high)
        table.remove(active, low)
        table.insert(active, nodes)
    end

    local root = active[1]
    local lengths: {[number]: number} = {}
    local max_bits = 0
    for index = 1, count do
        local depth = 0
        local node = index
        while (node ~= root) do
            node = parent[node]
            depth += 1
        end
        lengths[symbols[index]] = depth
        if (depth > max_bits) then
            max_bits = depth
        end
    end

    if (max_bits > 11) then
        return nil, 0
    end
    return lengths, max_bits
end

--
-- Assigns canonical Huffman code values, mirroring the decoding table
-- construction exactly so encoder and decoder agree bit for bit.
--
local function Build_Huffman_Codes(lengths: {[number]: number}, max_bits: number): {[number]: number}
    local rank_count: {[number]: number} = {}
    for length = 0, max_bits do
        rank_count[length] = 0
    end
    for symbol = 0, 255 do
        local length = lengths[symbol]
        if (length ~= nil) then
            rank_count[length] += 1
        end
    end

    local rank_start: {[number]: number} = {}
    rank_start[max_bits] = 0
    for length = max_bits, 1, -1 do
        rank_start[length - 1] = rank_start[length] + rank_count[length] * lshift(1, max_bits - length)
    end

    local next_index: {[number]: number} = {}
    for length = 0, max_bits do
        next_index[length] = rank_start[length]
    end

    local codes: {[number]: number} = {}
    for symbol = 0, 255 do
        local length = lengths[symbol]
        if (length ~= nil) then
            local span = lshift(1, max_bits - length)
            local table_index = next_index[length]
            codes[symbol] = table_index // span
            next_index[length] = table_index + span
        end
    end

    return codes
end

--
-- Huffman-codes `count` literals starting at `start` into a backward-read
-- bitstream. Codes are written last-literal-first so the decoder, reading
-- backwards, recovers them in forward order.
--
local function Encode_Huffman_Stream(literals: {number}, start: number, count: number, codes: {[number]: number}, lengths: {[number]: number}): {number}
    local writer = Bit_Writer_New()
    for offset = count - 1, 0, -1 do
        local symbol = literals[start + offset]
        Bit_Writer_Write(writer, codes[symbol], lengths[symbol])
    end
    return Bit_Writer_Finish(writer)
end

--
-- Writes a Compressed_Literals_Block header (regenerated and compressed
-- sizes) for the given Size_Format.
--
local function Encode_Literals_Compressed_Header(size_format: number, regenerated_size: number, compressed_size: number): {number}
    local writer = Bit_Writer_New()
    Bit_Writer_Write(writer, 2, 2)
    Bit_Writer_Write(writer, size_format, 2)
    if ((size_format == 0) or (size_format == 1)) then
        Bit_Writer_Write(writer, regenerated_size, 10)
        Bit_Writer_Write(writer, compressed_size, 10)
    elseif (size_format == 2) then
        Bit_Writer_Write(writer, regenerated_size, 14)
        Bit_Writer_Write(writer, compressed_size, 14)
    else
        Bit_Writer_Write(writer, regenerated_size, 18)
        Bit_Writer_Write(writer, compressed_size, 18)
    end
    return Bit_Writer_Finish_Forward(writer)
end

--
-- Attempts a Huffman-compressed literals section. Returns nil when the tree
-- cannot be represented in direct mode (highest literal above 128), when the
-- code depth exceeds 11 bits, or when the sizes do not fit a supported
-- Size_Format.
--
local function Encode_Literals_Huffman(literals: {number}): {number}?
    local total = #literals
    if (total < 2) then
        return nil
    end

    local frequencies: {[number]: number} = {}
    local highest = -1
    for index = 1, total do
        local symbol = literals[index]
        frequencies[symbol] = (frequencies[symbol] or 0) + 1
        if (symbol > highest) then
            highest = symbol
        end
    end

    if (highest > 128) then
        return nil
    end

    local lengths, max_bits = Build_Huffman_Lengths(frequencies)
    if (lengths == nil) then
        return nil
    end

    local codes = Build_Huffman_Codes(lengths, max_bits)

    --
    -- Direct-mode tree description: header byte, then one 4-bit weight per
    -- symbol below the last present one (whose weight is deduced).
    --
    local tree: {number} = {}
    table.insert(tree, highest + 127)
    local nibble_pairs = (highest + 1) // 2
    for pair = 0, nibble_pairs - 1 do
        local high = 0
        local low = 0
        local index_high = pair * 2
        local index_low = index_high + 1
        if (index_high < highest) then
            local length = lengths[index_high]
            if (length ~= nil) then
                high = max_bits + 1 - length
            end
        end
        if (index_low < highest) then
            local length = lengths[index_low]
            if (length ~= nil) then
                low = max_bits + 1 - length
            end
        end
        table.insert(tree, bor(lshift(high, 4), low))
    end

    --
    -- Single-stream variant (Size_Format 0).
    --
    if (total <= 1023) then
        local stream = Encode_Huffman_Stream(literals, 1, total, codes, lengths)
        local compressed_size = #tree + #stream
        if (compressed_size <= 1023) then
            local bytes = Encode_Literals_Compressed_Header(0, total, compressed_size)
            for index = 1, #tree do
                table.insert(bytes, tree[index])
            end
            for index = 1, #stream do
                table.insert(bytes, stream[index])
            end
            return bytes
        end
    end

    --
    -- Four-stream variant (Size_Format 1/2/3) with a 6-byte jump table.
    --
    local segment_size = (total + 3) // 4
    if (3 * segment_size <= total) then
        local sizes = { segment_size, segment_size, segment_size, total - 3 * segment_size }
        local streams: {{number}} = {}
        local start = 1
        local too_large = false
        for index = 1, 4 do
            streams[index] = Encode_Huffman_Stream(literals, start, sizes[index], codes, lengths)
            if ((index <= 3) and (#streams[index] > 0xFFFF)) then
                too_large = true
            end
            start += sizes[index]
        end

        if (not too_large) then
            local compressed_size = #tree + 6
            for index = 1, 4 do
                compressed_size += #streams[index]
            end

            local size_format
            if ((total <= 1023) and (compressed_size <= 1023)) then
                size_format = 1
            elseif ((total <= 16383) and (compressed_size <= 16383)) then
                size_format = 2
            elseif ((total <= 262143) and (compressed_size <= 262143)) then
                size_format = 3
            end

            if (size_format ~= nil) then
                local bytes = Encode_Literals_Compressed_Header(size_format, total, compressed_size)
                for index = 1, #tree do
                    table.insert(bytes, tree[index])
                end
                Bytes_Write_U16LE(bytes, #streams[1])
                Bytes_Write_U16LE(bytes, #streams[2])
                Bytes_Write_U16LE(bytes, #streams[3])
                for index = 1, 4 do
                    for byte_index = 1, #streams[index] do
                        table.insert(bytes, streams[index][byte_index])
                    end
                end
                return bytes
            end
        end
    end

    return nil
end

--
-- Writes the literals section size field for a Raw or RLE block.
--
local function Write_Literals_Size(bytes: {number}, block_type: number, size: number): ()
    if (size < 32) then
        table.insert(bytes, bor(block_type, lshift(size, 3)))
    elseif (size < 4096) then
        table.insert(bytes, bor(block_type, 4, lshift(band(size, 0xF), 4)))
        table.insert(bytes, band(rshift(size, 4), 0xFF))
    else
        table.insert(bytes, bor(block_type, 12, lshift(band(size, 0xF), 4)))
        table.insert(bytes, band(rshift(size, 4), 0xFF))
        table.insert(bytes, band(rshift(size, 12), 0xFF))
    end
end

--
-- Encodes the literals section, preferring RLE when every literal is equal.
--
local function Encode_Literals_Section(literals: {number}): {number}
    local size = #literals
    if (size == 0) then
        return { 0 }
    end

    local raw: {number} = {}
    if (size >= 2) then
        local first = literals[1]
        local rle = true
        for index = 2, size do
            if (literals[index] ~= first) then
                rle = false
                break
            end
        end
        if (rle) then
            Write_Literals_Size(raw, 1, size)
            Bytes_Write_U8(raw, first)
            return raw
        end
    end

    Write_Literals_Size(raw, 0, size)
    for index = 1, size do
        table.insert(raw, literals[index])
    end

    local huffman = Encode_Literals_Huffman(literals)
    if (huffman ~= nil) then
        if (#huffman < #raw) then
            return huffman
        end
    end
    return raw
end

--
-- Encodes the sequences section: header, symbol modes (all Predefined_Mode)
-- and the interleaved FSE bitstream.
--
local function Encode_Sequences_Section(sequences: {Encode_Sequence}): {number}
    local count = #sequences
    local bytes: {number} = {}

    if (count < 128) then
        Bytes_Write_U8(bytes, count)
    elseif (count < 0x7F00) then
        Bytes_Write_U8(bytes, 128 + rshift(count, 8))
        Bytes_Write_U8(bytes, band(count, 0xFF))
    else
        Bytes_Write_U8(bytes, 255)
        Bytes_Write_U16LE(bytes, count - 0x7F00)
    end

    if (count == 0) then
        return bytes
    end

    Bytes_Write_U8(bytes, 0)

    local ll_codes: {number} = {}
    local ml_codes: {number} = {}
    local of_codes: {number} = {}
    local ll_extra_value: {number} = {}
    local ll_extra_bits: {number} = {}
    local ml_extra_value: {number} = {}
    local ml_extra_bits: {number} = {}
    local of_extra_value: {number} = {}
    local of_extra_bits: {number} = {}

    for index = 1, count do
        local sequence = sequences[index]

        local ll_code = Choose_LL_Code(sequence.literal_length)
        ll_codes[index] = ll_code
        ll_extra_bits[index] = SEQ_LL_EXTRA_BITS[ll_code]
        ll_extra_value[index] = sequence.literal_length - SEQ_LL_BASELINES[ll_code]

        local ml_code = Choose_ML_Code(sequence.match_length)
        ml_codes[index] = ml_code
        ml_extra_bits[index] = SEQ_ML_EXTRA_BITS[ml_code]
        ml_extra_value[index] = sequence.match_length - SEQ_ML_BASELINES[ml_code]

        local offset_value = sequence.offset + 3
        local of_code = Highest_Set_Bit(offset_value)
        of_codes[index] = of_code
        of_extra_bits[index] = of_code
        of_extra_value[index] = offset_value - lshift(1, of_code)
    end

    local ll_states = FSE_Encode_States(SEQ_LL_PREVIOUS, SEQ_LL_FIRST, ll_codes, count)
    local ml_states = FSE_Encode_States(SEQ_ML_PREVIOUS, SEQ_ML_FIRST, ml_codes, count)
    local of_states = FSE_Encode_States(SEQ_OF_PREVIOUS, SEQ_OF_FIRST, of_codes, count)

    --
    -- Assemble the reads in the exact order the decoder consumes them, then
    -- write them in reverse (the decoder reads the bitstream backwards).
    --
    local values: {number} = {}
    local widths: {number} = {}

    local function emit(value: number, width: number): ()
        table.insert(values, value)
        table.insert(widths, width)
    end

    emit(ll_states[1], SEQ_LL_TABLE.accuracy_log)
    emit(of_states[1], SEQ_OF_TABLE.accuracy_log)
    emit(ml_states[1], SEQ_ML_TABLE.accuracy_log)

    for index = 1, count do
        emit(of_extra_value[index], of_extra_bits[index])
        emit(ml_extra_value[index], ml_extra_bits[index])
        emit(ll_extra_value[index], ll_extra_bits[index])

        if (index < count) then
            emit(ll_states[index + 1] - SEQ_LL_TABLE.new_state_base[ll_states[index]], SEQ_LL_TABLE.num_bits[ll_states[index]])
            emit(ml_states[index + 1] - SEQ_ML_TABLE.new_state_base[ml_states[index]], SEQ_ML_TABLE.num_bits[ml_states[index]])
            emit(of_states[index + 1] - SEQ_OF_TABLE.new_state_base[of_states[index]], SEQ_OF_TABLE.num_bits[of_states[index]])
        end
    end

    local writer = Bit_Writer_New()
    for index = #values, 1, -1 do
        Bit_Writer_Write(writer, values[index], widths[index])
    end

    local bit_bytes = Bit_Writer_Finish(writer)
    for index = 1, #bit_bytes do
        table.insert(bytes, bit_bytes[index])
    end

    return bytes
end

--
-- Greedy hash-table match finder parameters.
--
local HASH_LOG   = (16)
local HASH_MASK  = lshift(1, HASH_LOG) - 1
local MIN_MATCH  = (4)

--
-- Hashes the four bytes starting at `position` into the hash table domain.
--
local function Hash_Sequence(input: buffer, position: number): number
    local b0 = buffer.readu8(input, position)
    local b1 = buffer.readu8(input, position + 1)
    local b2 = buffer.readu8(input, position + 2)
    local b3 = buffer.readu8(input, position + 3)
    local value = bor(b0, lshift(b1, 8), lshift(b2, 16), lshift(b3, 24))
    value = bxor(value, rshift(value, 15))
    return band(value, HASH_MASK)
end

--
-- Produces the literals and sequences for one block. `hash_table` persists
-- across blocks so matches may reference earlier content within the frame.
--
local function Find_Block_Sequences(input: buffer, block_start: number, block_end: number, hash_table: {[number]: number}): ({number}, {Encode_Sequence})
    local literals: {number} = {}
    local sequences: {Encode_Sequence} = {}
    local last_hash_position = block_end - MIN_MATCH

    local anchor = block_start
    local position = block_start

    while (position <= last_hash_position) do
        local hash = Hash_Sequence(input, position)
        local candidate = hash_table[hash]
        hash_table[hash] = position

        local matched = false
        if ((candidate ~= nil) and (candidate < position)) then
            local length = 0
            while (position + length < block_end) and
                  (buffer.readu8(input, candidate + length) == buffer.readu8(input, position + length)) do
                length += 1
            end

            if (length >= MIN_MATCH) then
                for index = anchor, position - 1 do
                    table.insert(literals, buffer.readu8(input, index))
                end

                table.insert(sequences, {
                    literal_length = position - anchor,
                    match_length   = length,
                    offset         = position - candidate,
                })

                local stop = math.min(position + length, last_hash_position)
                for index = position + 1, stop do
                    hash_table[Hash_Sequence(input, index)] = index
                end

                position += length
                anchor = position
                matched = true
            end
        end

        if (not matched) then
            position += 1
        end
    end

    for index = anchor, block_end - 1 do
        table.insert(literals, buffer.readu8(input, index))
    end

    return literals, sequences
end

--
-- Encodes a block as compressed literals + sequences sections.
--
local function Encode_Compressed_Block(input: buffer, block_start: number, block_end: number, hash_table: {[number]: number}): {number}
    local literals, sequences = Find_Block_Sequences(input, block_start, block_end, hash_table)

    local bytes = Encode_Literals_Section(literals)
    local sequence_bytes = Encode_Sequences_Section(sequences)
    for index = 1, #sequence_bytes do
        table.insert(bytes, sequence_bytes[index])
    end

    return bytes
end

--
-- MODULE DEFINITION
--
local Zstd_Codec = {}

--
-- Compresses `input` and returns a Zstandard frame.
--
function Zstd_Codec.Compress(input: buffer): buffer
    local size = buffer.len(input)
    local bytes: {number} = {}

    Bytes_Write_U32LE(bytes, ZSTD_MAGIC_NUMBER)

    if (size <= 255) then
        Bytes_Write_U8(bytes, 0x20)
        Bytes_Write_U8(bytes, size)
    else
        Bytes_Write_U8(bytes, 0xA0)
        Bytes_Write_U32LE(bytes, size)
    end

    if (size == 0) then
        Bytes_Write_U24LE(bytes, 1)
        return Bytes_To_Buffer(bytes)
    end

    local hash_table: {[number]: number} = {}
    local position = 0

    while (position < size) do
        local chunk = math.min(MAX_BLOCK_SIZE, size - position)
        local block_start = position
        local block_end = position + chunk
        local is_last = block_end >= size
        local last_flag = is_last and 1 or 0

        local first = buffer.readu8(input, block_start)
        local rle = chunk > 1
        if (rle) then
            for index = block_start + 1, block_end - 1 do
                if (buffer.readu8(input, index) ~= first) then
                    rle = false
                    break
                end
            end
        end

        if (rle) then
            Bytes_Write_U24LE(bytes, bor(last_flag, 2, lshift(chunk, 3)))
            Bytes_Write_U8(bytes, first)
        else
            local body = Encode_Compressed_Block(input, block_start, block_end, hash_table)
            if (#body < chunk) then
                Bytes_Write_U24LE(bytes, bor(last_flag, 4, lshift(#body, 3)))
                for index = 1, #body do
                    table.insert(bytes, body[index])
                end
            else
                Bytes_Write_U24LE(bytes, bor(last_flag, lshift(chunk, 3)))
                for index = block_start, block_end - 1 do
                    table.insert(bytes, buffer.readu8(input, index))
                end
            end
        end

        position = block_end
    end

    return Bytes_To_Buffer(bytes)
end

--
-- Decompresses a Zstandard payload (one or more concatenated frames, plus
-- optionally skippable frames).
--
function Zstd_Codec.Decompress(input: buffer): buffer
    local size = buffer.len(input)
    if (size < 4) then
        error("Zstd_Codec: input too small to be a Zstandard frame")
    end

    local stream = Forward_New(input, 0, size)
    local output = Output_New()

    while (stream.byte_index < stream.size) do
        if (stream.byte_index + 4 > stream.size) then
            error("Zstd_Codec: truncated frame magic")
        end

        local magic = Forward_Read(stream, 32)
        if (magic == ZSTD_MAGIC_NUMBER) then
            Decode_Data_Frame(stream, output)
        elseif ((magic >= ZSTD_SKIPPABLE_MIN) and (magic <= ZSTD_SKIPPABLE_MAX)) then
            local skip_size = Forward_Read(stream, 32)
            if (stream.byte_index + skip_size > stream.size) then
                error("Zstd_Codec: truncated skippable frame")
            end
            stream.byte_index += skip_size
        else
            error("Zstd_Codec: invalid frame magic number")
        end
    end

    return Output_Finalize(output)
end

--
-- Returns the decompressed size recorded in the first frame header. Raises
-- an error when the size is not present in the header.
--
function Zstd_Codec.Get_Decompressed_Size(input: buffer): number
    local size = buffer.len(input)
    if (size < 4) then
        error("Zstd_Codec: input too small to be a Zstandard frame")
    end

    local stream = Forward_New(input, 0, size)
    local magic = Forward_Read(stream, 32)
    if (magic ~= ZSTD_MAGIC_NUMBER) then
        error("Zstd_Codec: invalid frame magic number")
    end

    local header = Parse_Frame_Header(stream)
    if ((header.frame_content_size == 0) and (not header.single_segment_flag)) then
        error("Zstd_Codec: decompressed size is not present in the frame header")
    end

    return header.frame_content_size
end

--
-- RETURN VALUE
--
Zstd_Codec._internal = {
    Highest_Set_Bit    = Highest_Set_Bit,
    Read_Bits_LE       = Read_Bits_LE,
    FSE_Build_Table    = FSE_Build_Table,
    FSE_Decode_Header  = FSE_Decode_Header,
    HUF_Build_Table    = HUF_Build_Table,
    HUF_Build_From_Weights = HUF_Build_From_Weights,
    Forward_New        = Forward_New,
    Forward_Read       = Forward_Read,
    Backward_New       = Backward_New,
    Backward_Read      = Backward_Read,
}

return Zstd_Codec
