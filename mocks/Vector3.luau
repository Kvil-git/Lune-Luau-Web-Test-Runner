--!strict
--[[
Documentation:
https://developer.roblox.com/en-us/api-reference/datatype/Vector3

Extra Info:
Cannot use any other constructor functions other than Vector3.new() because of enums.
This version can also add and subtract numbers to vectors

Made by HiddenKaiser on 9/11/20 at 2:30 pm
Modified by Kvil on 18/12/2024 2:38 pm to be fully strictly typed
--]]
--
-- LOCAL TYPES
--
export type Vector3 = {
    __type:     "Vector3",
    x:           number,
    y:           number,
    z:           number,
    Magnitude:   number,
    Unit:        Vector3?,
    magnitude:   number,
    unit:        Vector3?,
    X:           number,
    Y:           number,
    Z:           number,
    
    -- Methods
    new:                 (x: number, y: number, z: number)              ->  Vector3,
    Floor:               (self: Vector3)                                ->  Vector3,
    GetMagnitude:        (self: Vector3)                                ->  number,
    Lerp:                (self: Vector3, b:  Vector3, percent: number)  ->  Vector3,
    Dot:                 (self: Vector3, b:  Vector3)                   ->  number,
    Cross:               (self: Vector3, b:  Vector3)                   ->  Vector3,
    FuzzyEq:             (self: Vector3, v1: Vector3, epsilon: number)  ->  boolean,
    IsClose:             (self: Vector3, v1: Vector3, epsilon: number)  ->  boolean,
}

type Vector3Metatable = {
    __index: Vector3,
    __mul: (a: number | Vector3, b: number | Vector3) -> Vector3,
    __div: (a: number | Vector3, b: number | Vector3) -> Vector3,
    __add: (a: number | Vector3, b: number | Vector3) -> Vector3,
    __sub: (a: number | Vector3, b: number | Vector3) -> Vector3,
    __tostring: (self: Vector3) -> string,
}

local Vector3: Vector3 = {} :: any
Vector3.__type = "Vector3"

local mt: Vector3Metatable = {
    __index = Vector3,
}
--
-- CLASS DEFINITION
--
function Vector3.new(x: number, y: number, z: number): Vector3
    local xNum: number = x or 0
    local yNum: number = y or 0
    local zNum: number = z or 0
    
    local self: any = {
        x = xNum,
        y = yNum,
        z = zNum,
        Magnitude = 0,
        Unit = nil :: Vector3?,
        X = xNum,
        Y = yNum,
        Z = zNum,
    }
    setmetatable(self, mt)
    return self :: Vector3
end

function mt.__mul(a: number | Vector3, b: number | Vector3): Vector3
    if type(a) == "number" and typeof(b) == "table" and (b :: any).__type == "Vector3" then
        -- a is a scalar, b is a vector
        local scalar: number = a
        local vector: Vector3 = b :: Vector3
        return Vector3.new(scalar * vector.x, scalar * vector.y, scalar * vector.z)
    elseif type(b) == "number" and typeof(a) == "table" and (a :: any).__type == "Vector3" then
        -- a is a vector, b is a scalar
        local vector: Vector3 = a :: Vector3
        local scalar: number = b
        return Vector3.new(vector.x * scalar, vector.y * scalar, vector.z * scalar)
    elseif typeof(a) == "table" and (a :: any).__type == "Vector3" and typeof(b) == "table" and (b :: any).__type == "Vector3" then
        -- both a and b are vectors
        local vectorA: Vector3 = a :: Vector3
        local vectorB: Vector3 = b :: Vector3
        return Vector3.new(vectorA.x * vectorB.x, vectorA.y * vectorB.y, vectorA.z * vectorB.z)
    end
    
    error("Invalid operation for __mul")
end

function mt.__div(a: number | Vector3, b: number | Vector3): Vector3
    if type(a) == "number" and typeof(b) == "table" and (b :: any).__type == "Vector3" then
        -- a is a scalar, b is a vector
        local scalar: number = a
        local vector: Vector3 = b :: Vector3
        return Vector3.new(scalar / vector.x, scalar / vector.y, scalar / vector.z)
    elseif type(b) == "number" and typeof(a) == "table" and (a :: any).__type == "Vector3" then
        -- a is a vector, b is a scalar
        local vector: Vector3 = a :: Vector3
        local scalar: number = b
        return Vector3.new(vector.x / scalar, vector.y / scalar, vector.z / scalar)
    elseif typeof(a) == "table" and (a :: any).__type == "Vector3" and typeof(b) == "table" and (b :: any).__type == "Vector3" then
        -- both a and b are vectors
        local vectorA: Vector3 = a :: Vector3
        local vectorB: Vector3 = b :: Vector3
        return Vector3.new(vectorA.x / vectorB.x, vectorA.y / vectorB.y, vectorA.z / vectorB.z)
    end
    
    error("Invalid operation for __div")
end

function mt.__add(a: number | Vector3, b: number | Vector3): Vector3
    if type(a) == "number" and typeof(b) == "table" and (b :: any).__type == "Vector3" then
        -- a is a scalar, b is a vector
        local scalar: number = a
        local vector: Vector3 = b :: Vector3
        return Vector3.new(scalar + vector.x, scalar + vector.y, scalar + vector.z)
    elseif type(b) == "number" and typeof(a) == "table" and (a :: any).__type == "Vector3" then
        -- a is a vector, b is a scalar
        local vector: Vector3 = a :: Vector3
        local scalar: number = b
        return Vector3.new(vector.x + scalar, vector.y + scalar, vector.z + scalar)
    elseif typeof(a) == "table" and (a :: any).__type == "Vector3" and typeof(b) == "table" and (b :: any).__type == "Vector3" then
        -- both a and b are vectors
        local vectorA: Vector3 = a :: Vector3
        local vectorB: Vector3 = b :: Vector3
        return Vector3.new(vectorA.x + vectorB.x, vectorA.y + vectorB.y, vectorA.z + vectorB.z)
    end
    
    error("Invalid operation for __add")
end

function mt.__sub(a: number | Vector3, b: number | Vector3): Vector3
    if type(a) == "number" and typeof(b) == "table" and (b :: any).__type == "Vector3" then
        -- a is a scalar, b is a vector
        local scalar: number = a
        local vector: Vector3 = b :: Vector3
        return Vector3.new(scalar - vector.x, scalar - vector.y, scalar - vector.z)
    elseif type(b) == "number" and typeof(a) == "table" and (a :: any).__type == "Vector3" then
        -- a is a vector, b is a scalar
        local vector: Vector3 = a :: Vector3
        local scalar: number = b
        return Vector3.new(vector.x - scalar, vector.y - scalar, vector.z - scalar)
    elseif typeof(a) == "table" and (a :: any).__type == "Vector3" and typeof(b) == "table" and (b :: any).__type == "Vector3" then
        -- both a and b are vectors
        local vectorA: Vector3 = a :: Vector3
        local vectorB: Vector3 = b :: Vector3
        return Vector3.new(vectorA.x - vectorB.x, vectorA.y - vectorB.y, vectorA.z - vectorB.z)
    end
    
    error("Invalid operation for __sub")
end

function mt.__tostring(self: Vector3): string
    return "(" .. tostring(self.x) .. ", " .. tostring(self.y) .. ", " .. tostring(self.z) .. ")"
end

function Vector3:Floor(): Vector3
    return Vector3.new(math.floor(self.x), math.floor(self.y), math.floor(self.z))
end

function Vector3:GetMagnitude(): number
    return math.sqrt((self.x)^2 + (self.y)^2 + (self.z)^2)
end

function Vector3:Lerp(b: Vector3, percent: number): Vector3
    local result: Vector3 = self + ((b - self) * percent)
    return result
end

function Vector3:Dot(b: Vector3): number
    return (self.x * b.x) + (self.y * b.y) + (self.z * b.z)
end

function Vector3:Cross(b: Vector3): Vector3
    return Vector3.new(
        (self.y * b.z) - (self.z * b.y),
        (self.z * b.x) - (self.x * b.z),
        (self.x * b.y) - (self.y * b.x)
    )
end

function Vector3:FuzzyEq(v1: Vector3, epsilon: number): boolean
    local function fuzzyEq(a: number, b: number, epsilon: number): boolean
        return a == b or math.abs(a - b) <= (math.abs(a) + 1) * epsilon
    end
    
    if not fuzzyEq(v1.x, self.x, epsilon) then return false end
    if not fuzzyEq(v1.y, self.y, epsilon) then return false end
    if not fuzzyEq(v1.z, self.z, epsilon) then return false end
    return true
end
--
-- RETURN VALUE
--
return Vector3
