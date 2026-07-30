--!strict
--
-- REQUIRES
--
-- (none - pure mock, no dependencies)
--
-- LOCAL TYPES
--
export type Color3 = {
    __type: "Color3",

    R: number,
    G: number,
    B: number,

    new:      (r: number?, g: number?, b: number?)                 -> Color3,
    fromRGB:  (r: number,  g: number,  b: number)                  -> Color3,
    fromHSV:  (h: number,  s: number,  v: number)                  -> Color3,
    fromHex:  (hexCode: string)                                    -> Color3,
    ToHSV:    (self: Color3)                                       -> (number, number, number),
    toHSV:    (self: Color3)                                       -> (number, number, number),
    ToHex:    (self: Color3)                                       -> string,
}

type Color3Metatable = {
    __index:    Color3,
    __eq:       (a: Color3, b: Color3) -> boolean,
    __tostring: (self: Color3)         -> string,
}
--
-- MODULE DEFINITION
--
local Color3: Color3 = {} :: any
Color3.__type = "Color3"

local mt = {
    __index = Color3,
} :: any

--
-- LOCAL FUNCTIONS
--
local function clamp01(value: number): number
    return math.clamp(value, 0, 1)
end

local function hexPairToNumber(pair: string): number
    local value = tonumber(pair, 16)

    if (value == nil) then
        error(("Invalid hex pair '%s'"):format(pair))
    end

    return value
end

local function rgbToHsv(r: number, g: number, b: number): (number, number, number)
    local maxValue = math.max(r, g, b)
    local minValue = math.min(r, g, b)
    local delta    = maxValue - minValue

    local h = 0
    local s = 0
    local v = maxValue

    if (maxValue > 0) then
        s = delta / maxValue
    end

    if (delta > 0) then
        if (maxValue == r) then
            h = ((g - b) / delta) % 6
        elseif (maxValue == g) then
            h = ((b - r) / delta) + 2
        else
            h = ((r - g) / delta) + 4
        end

        h = h / 6

        if (h < 0) then
            h = h + 1
        end
    end

    return h, s, v
end

local function hsvToRgb(h: number, s: number, v: number): (number, number, number)
    local hue      = (h % 1) * 6
    local sector   = math.floor(hue)
    local fraction = hue - sector

    local p = v * (1 - s)
    local q = v * (1 - fraction * s)
    local t = v * (1 - (1 - fraction) * s)

    if     (sector == 0) then
        return v, t, p
    elseif (sector == 1) then
        return q, v, p
    elseif (sector == 2) then
        return p, v, t
    elseif (sector == 3) then
        return p, q, v
    elseif (sector == 4) then
        return t, p, v
    else
        return v, p, q
    end
end

local function createRawColor3(r: number, g: number, b: number): Color3
    local self: any = {
        R = r,
        G = g,
        B = b,
    }
    setmetatable(self, mt)
    return self :: Color3
end

function Color3.new(r: number?, g: number?, b: number?): Color3
    local red   = r
    local green = g
    local blue  = b

    if (red   == nil) then red   = 0 end
    if (green == nil) then green = 0 end
    if (blue  == nil) then blue  = 0 end

    return createRawColor3(clamp01(red), clamp01(green), clamp01(blue))
end

function Color3.fromRGB(r: number, g: number, b: number): Color3
    local red   = r
    local green = g
    local blue  = b

    if (red   == nil) then red   = 0 end
    if (green == nil) then green = 0 end
    if (blue  == nil) then blue  = 0 end

    return Color3.new(red / 255, green / 255, blue / 255)
end

function Color3.fromHSV(h: number, s: number, v: number): Color3
    local hue        = h
    local saturation = s
    local value      = v

    if (hue        == nil) then hue        = 0 end
    if (saturation == nil) then saturation = 0 end
    if (value      == nil) then value      = 0 end

    local red, green, blue = hsvToRgb(clamp01(hue), clamp01(saturation), clamp01(value))

    return Color3.new(red, green, blue)
end

function Color3.fromHex(hexCode: string): Color3
    local hex = hexCode:gsub("^#", "")

    if (#hex == 3) then
        hex = hex:sub(1, 1):rep(2) .. hex:sub(2, 2):rep(2) .. hex:sub(3, 3):rep(2)
    end

    if (#hex ~= 6) then
        error(("Invalid hex color '%s'"):format(hexCode))
    end

    return Color3.fromRGB(
        hexPairToNumber(hex:sub(1, 2)),
        hexPairToNumber(hex:sub(3, 4)),
        hexPairToNumber(hex:sub(5, 6))
    )
end

function Color3:ToHSV(): (number, number, number)
    return rgbToHsv(self.R, self.G, self.B)
end

function Color3:toHSV(): (number, number, number)
    return self:ToHSV()
end

function Color3:ToHex(): string
    local r = math.round(self.R * 255)
    local g = math.round(self.G * 255)
    local b = math.round(self.B * 255)
    return string.format("%02X%02X%02X", r, g, b)
end

function mt.__eq(a: Color3, b: Color3): boolean
    return ((a.R == b.R) and (a.G == b.G) and (a.B == b.B))
end

function mt.__tostring(self: Color3): string
    return ("Color3.new(%0.6f, %0.6f, %0.6f)"):format(self.R, self.G, self.B)
end
--
-- RETURN VALUE
--
return Color3
