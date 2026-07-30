--!strict
--
-- REQUIRES
--
local Color3 = require("./Color3")
--
-- LOCAL TYPES
--
export type Color3Like = {
    __type: "Color3",
    R: number,
    G: number,
    B: number,
}

export type BrickColor = {
    __type: "BrickColor",

    Name:   string,
    Number: number,
    Color:  Color3Like,

    new:    (value: number | string | Color3Like) -> BrickColor,
    Random: ()                                     -> BrickColor,
    Blue:   ()                                     -> BrickColor,
    Yellow: ()                                     -> BrickColor,
    Red:    ()                                     -> BrickColor,
    Green:  ()                                     -> BrickColor,
    Black:  ()                                     -> BrickColor,
    White:  ()                                     -> BrickColor,
    Gray:   ()                                     -> BrickColor,
    Orange: ()                                     -> BrickColor,
    Purple: ()                                     -> BrickColor,
    Pink:   ()                                     -> BrickColor,
}

type BrickColorMetatable = {
    __index:    BrickColor,
    __eq:       (a: BrickColor, b: BrickColor) -> boolean,
    __tostring: (self: BrickColor)             -> string,
}

type BrickColorEntry = {
    Name:   string,
    Number: number,
    Color:  Color3Like,
}
--
-- VARIABLES
--
local paletteByNumber: {[number]: BrickColorEntry} = {}
local paletteByKey: {[string]: BrickColorEntry} = {}
local customByNumber: {[number]: BrickColorEntry} = {}
--
-- LOCAL FUNCTIONS
--
local function keyFromName(name: string): string
    return name:lower():gsub("[^%w]", "")
end

local function colorDistanceSquared(a: Color3Like, b: Color3Like): number
    local dr = a.R - b.R
    local dg = a.G - b.G
    local db = a.B - b.B
    return ((dr * dr) + (dg * dg) + (db * db))
end

local function makeEntry(number: number, name: string, color: Color3Like): BrickColorEntry
    return {
        Name   = name,
        Number = number,
        Color  = color,
    }
end

local function registerPaletteEntry(number: number, name: string, r: number, g: number, b: number): BrickColorEntry
    local entry = makeEntry(number, name, Color3.fromRGB(r, g, b))

    paletteByNumber[number]             = entry
    paletteByKey[keyFromName(name)]     = entry

    return entry
end

local function normalizeNumber(value: number): number
    return math.floor(value + 0.5)
end

local function isColor3Like(value: any): boolean
    local isTable   = (typeof(value) == "table")
    local hasType   = (value.__type == "Color3")
    local hasR      = (type(value.R) == "number")
    local hasG      = (type(value.G) == "number")
    local hasB      = (type(value.B) == "number")

    return (isTable and hasType and hasR and hasG and hasB)
end

--
-- findClosestPaletteEntry
--
-- Finds the palette entry whose color most closely matches the
-- given Color3, using squared Euclidean distance.
--
local function findClosestPaletteEntry(color: Color3Like): BrickColorEntry
    local bestEntry: BrickColorEntry? = nil
    local bestDistance                 = math.huge

    for _, entry in pairs(paletteByNumber) do
        local distance = colorDistanceSquared(color, entry.Color)

        if (distance < bestDistance) then
            bestDistance = distance
            bestEntry    = entry
        end
    end

    if (bestEntry ~= nil) then
        return bestEntry
    end

    return paletteByNumber[1] or makeEntry(1, "BrickColor #1", Color3.fromRGB(255, 255, 255))
end

--
-- getOrCreateNumericEntry
--
-- Returns the palette entry for a given BrickColor number.
-- If the number is not in the standard palette, a synthetic
-- entry is created and cached so round-tripping preserves it.
--
local function getOrCreateNumericEntry(number: number): BrickColorEntry
    local normalized   = normalizeNumber(number)
    local paletteEntry = paletteByNumber[normalized]

    if (paletteEntry ~= nil) then
        return paletteEntry
    end

    local cached = customByNumber[normalized]
    if (cached ~= nil) then
        return cached
    end

    local red   = (normalized * 53)      % 256
    local green = ((normalized * 97) + 64) % 256
    local blue  = ((normalized * 193) + 128) % 256

    local entry = makeEntry(
        normalized,
        ("BrickColor #%d"):format(normalized),
        Color3.fromRGB(red, green, blue)
    )

    customByNumber[normalized] = entry

    return entry
end
    local valueType = typeof(value)

    if (valueType == "number") then
        return createBrickColor(getOrCreateNumericEntry(value :: number))
    end

    if (valueType == "string") then
        local name    = value :: string
        local numeric = tonumber(name)

        if (numeric ~= nil) then
            return createBrickColor(getOrCreateNumericEntry(numeric))
        end

        local entry = paletteByKey[keyFromName(name)]
        if (entry ~= nil) then
            return createBrickColor(entry)
        end

        error(("Unknown BrickColor name '%s'"):format(name))
    end

    if (isColor3Like(value)) then
        return createBrickColor(findClosestPaletteEntry(value :: Color3Like))
    end

    error("BrickColor.new expects a number, string, or Color3")
end
--
-- PALETTE
--
registerPaletteEntry(1,   "White",              242, 243, 243)
registerPaletteEntry(21,  "Bright red",         196, 40,  28)
registerPaletteEntry(23,  "Bright blue",        13,  105, 172)
registerPaletteEntry(24,  "Bright yellow",      245, 205, 48)
registerPaletteEntry(26,  "Black",              27,  42,   53)
registerPaletteEntry(28,  "Dark stone grey",    99,  95,   98)
registerPaletteEntry(29,  "Medium stone grey",  163, 162, 165)
registerPaletteEntry(45,  "Bright green",       75,  151,  75)
registerPaletteEntry(101, "Brick yellow",       215, 197, 154)
registerPaletteEntry(102, "Light orange",       218, 133, 65)
registerPaletteEntry(103, "Nougat",             204, 142, 105)
registerPaletteEntry(104, "Bright violet",      107, 50,   124)
registerPaletteEntry(105, "Brown",              124, 92,   70)
registerPaletteEntry(106, "Dusty Rose",         199, 172, 120)
registerPaletteEntry(107, "Lavender",           180, 128, 255)
registerPaletteEntry(108, "Sand red",           151, 105, 91)
registerPaletteEntry(109, "Pastel blue",        177, 193, 255)
registerPaletteEntry(110, "Pastel green",       194, 218, 184)
registerPaletteEntry(111, "Pastel yellow",      253, 234, 141)
registerPaletteEntry(112, "Pastel violet",      203, 132, 253)
registerPaletteEntry(113, "Pink",               255, 152, 220)
registerPaletteEntry(114, "Really red",         255, 0,   0)
registerPaletteEntry(115, "Really blue",        0,   0,   255)
registerPaletteEntry(116, "Really black",       17,  17,   17)
registerPaletteEntry(117, "Earth green",        98,  124,  62)
registerPaletteEntry(118, "Cool yellow",        255, 246, 123)
registerPaletteEntry(119, "Nougat",             204, 142, 105)
registerPaletteEntry(120, "Lilac",              232, 186, 200)
registerPaletteEntry(121, "Cocoa",              121, 80,   53)
registerPaletteEntry(122, "Rust",               150, 85,   85)
registerPaletteEntry(123, "Flame yellow",       249, 214, 46)
registerPaletteEntry(124, "Muted green",        116, 134, 89)
registerPaletteEntry(125, "Royal blue",         65,  105, 225)
registerPaletteEntry(126, "Bright orange",      218, 133, 65)
registerPaletteEntry(127, "Deep orange",        255, 171, 0)
registerPaletteEntry(128, "Deep blue",          0,   85,   191)
--
-- MODULE DEFINITION
--
local BrickColor: BrickColor = {} :: any
BrickColor.__type = "BrickColor"

local mt = {
    __index = BrickColor,
} :: any

local function createBrickColor(entry: BrickColorEntry): BrickColor
    local self: any = {
        Name   = entry.Name,
        Number = entry.Number,
        Color  = entry.Color,
    }
    setmetatable(self, mt)
    return (self :: any) :: BrickColor
end

--
-- fromValue
--
-- Converts a number, string, or Color3-like value into a BrickColor.
--
local function fromValue(value: number | string | Color3Like): BrickColor
    local valueType = typeof(value)

    if (valueType == "number") then
        return createBrickColor(getOrCreateNumericEntry(value :: number))
    end

    if (valueType == "string") then
        local name    = value :: string
        local numeric = tonumber(name)

        if (numeric ~= nil) then
            return createBrickColor(getOrCreateNumericEntry(numeric))
        end

        local entry = paletteByKey[keyFromName(name)]
        if (entry ~= nil) then
            return createBrickColor(entry)
        end

        error(("Unknown BrickColor name '%s'"):format(name))
    end

    if (isColor3Like(value)) then
        return createBrickColor(findClosestPaletteEntry(value :: Color3Like))
    end

    error("BrickColor.new expects a number, string, or Color3")
end

function BrickColor.new(value: number | string | Color3Like): BrickColor
    return fromValue(value)
end

function BrickColor.Random(): BrickColor
    local entries = {}

    for _, entry in pairs(paletteByNumber) do
        table.insert(entries, entry)
    end

    local entries_count = #entries

    if (entries_count == 0) then
        return BrickColor.new(1)
    end

    return createBrickColor(entries[math.random(1, entries_count)])
end

function BrickColor.Blue(): BrickColor
    return BrickColor.new("Bright blue")
end

function BrickColor.Yellow(): BrickColor
    return BrickColor.new("Bright yellow")
end

function BrickColor.Red(): BrickColor
    return BrickColor.new("Bright red")
end

function BrickColor.Green(): BrickColor
    return BrickColor.new("Bright green")
end

function BrickColor.Black(): BrickColor
    return BrickColor.new("Black")
end

function BrickColor.White(): BrickColor
    return BrickColor.new("White")
end

function BrickColor.Gray(): BrickColor
    return BrickColor.new("Medium stone grey")
end

function BrickColor.Orange(): BrickColor
    return BrickColor.new("Bright orange")
end

function BrickColor.Purple(): BrickColor
    return BrickColor.new("Bright violet")
end

function BrickColor.Pink(): BrickColor
    return BrickColor.new("Pink")
end

function mt.__eq(a: BrickColor, b: BrickColor): boolean
    return (a.Number == b.Number)
end

function mt.__tostring(self: BrickColor): string
    return self.Name
end
--
-- RETURN VALUE
--
return BrickColor
