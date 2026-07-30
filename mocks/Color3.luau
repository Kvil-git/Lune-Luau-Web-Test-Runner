--!strict
--[[
Documentation:
https://create.roblox.com/docs/reference/engine/datatypes/Color3

Extra Info:
This mock supports the standard Color3 constructors and basic color conversion helpers.
--]]

--
-- LOCAL TYPES
--
export type Color3 = {
    __type: "Color3",

    R: number,
    G: number,
    B: number,

    new: (r: number?, g: number?, b: number?) -> Color3,
    fromRGB: (r: number, g: number, b: number) -> Color3,
    fromHSV: (h: number, s: number, v: number) -> Color3,
    fromHex: (hexCode: string) -> Color3,
    ToHSV: (self: Color3) -> (number, number, number),
    toHSV: (self: Color3) -> (number, number, number),
    ToHex: (self: Color3) -> string,
}

type Color3Metatable = {
    __index: Color3,
    __eq: (a: Color3, b: Color3) -> boolean,
    __tostring: (self: Color3) -> string,
}

local Color3: Color3 = {} :: any
Color3.__type = "Color3"

local mt = {
    __index = Color3,
} :: any

local function clamp01(value: number): number
    return math.clamp(value, 0, 1)
end

local function hexPairToNumber(pair: string): number
    return tonumber(pair, 16) or 0
end

local function rgbToHsv(r: number, g: number, b: number): (number, number, number)
    local maxValue = math.max(r, g, b)
    local minValue = math.min(r, g, b)
    local delta = maxValue - minValue

    local h = 0
    local s = 0
    local v = maxValue

    if maxValue > 0 then
        s = delta / maxValue
    end

    if delta > 0 then
        if maxValue == r then
            h = ((g - b) / delta) % 6
        elseif maxValue == g then
            h = ((b - r) / delta) + 2
        else
            h = ((r - g) / delta) + 4
        end

        h /= 6
        if h < 0 then
            h += 1
        end
    end

    return h, s, v
end

local function hsvToRgb(h: number, s: number, v: number): (number, number, number)
    local hue = (h % 1) * 6
    local sector = math.floor(hue)
    local fraction = hue - sector

    local p = v * (1 - s)
    local q = v * (1 - fraction * s)
    local t = v * (1 - (1 - fraction) * s)

    if sector == 0 then
        return v, t, p
    elseif sector == 1 then
        return q, v, p
    elseif sector == 2 then
        return p, v, t
    elseif sector == 3 then
        return p, q, v
    elseif sector == 4 then
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
    return createRawColor3(clamp01(r or 0), clamp01(g or 0), clamp01(b or 0))
end

function Color3.fromRGB(r: number, g: number, b: number): Color3
    return Color3.new((r or 0) / 255, (g or 0) / 255, (b or 0) / 255)
end

function Color3.fromHSV(h: number, s: number, v: number): Color3
    local red, green, blue = hsvToRgb(clamp01(h or 0), clamp01(s or 0), clamp01(v or 0))
    return Color3.new(red, green, blue)
end

function Color3.fromHex(hexCode: string): Color3
    local hex = hexCode:gsub("^#", "")
    if #hex == 3 then
        hex = hex:sub(1, 1):rep(2) .. hex:sub(2, 2):rep(2) .. hex:sub(3, 3):rep(2)
    end

    if #hex ~= 6 then
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
    return string.format("%02X%02X%02X", math.round(self.R * 255), math.round(self.G * 255), math.round(self.B * 255))
end

function mt.__eq(a: Color3, b: Color3): boolean
    return a.R == b.R and a.G == b.G and a.B == b.B
end

function mt.__tostring(self: Color3): string
    return ("Color3.new(%0.6f, %0.6f, %0.6f)"):format(self.R, self.G, self.B)
end
--
-- RETURN VALUE
--
return Color3
