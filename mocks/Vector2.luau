--!strict
--
-- REQUIRES
--
-- (none - pure mock, no dependencies)
--
-- LOCAL TYPES
--
export type Vector2 = {
    -- type
    __type:     "Vector2",
    -- statics
    Up:          Vector2,
    Down:        Vector2,
    Left:        Vector2,
    Right:       Vector2,
    One:         Vector2,
    Zero:        Vector2,
    -- properties
    Magnitude:   number,
    Unit:        Vector2?,
    X:           number,
    Y:           number,

    -- Methods
    new:              (x: number?, y: number?)                                            -> Vector2,
    Floor:            (self: Vector2)                                                     -> Vector2,
    Ceil:             (self: Vector2)                                                     -> Vector2,
    Round:            (self: Vector2)                                                     -> Vector2,
    Lerp:             (self: Vector2, b: Vector2, percent: number)                        -> Vector2,
    Dot:              (self: Vector2, b: Vector2)                                         -> number,
    Cross:            (self: Vector2, b: Vector2)                                         -> number,
    FuzzyEq:          (self: Vector2, v1: Vector2, epsilon: number)                       -> boolean,
    IsClose:          (self: Vector2, v1: Vector2, epsilon: number)                       -> boolean,
    Angle:            (self: Vector2, b: Vector2)                                         -> number,
    Distance:         (self: Vector2, b: Vector2)                                         -> number,
    Normalize:        (self: Vector2)                                                     -> Vector2,
    Reflect:          (self: Vector2, normal: Vector2)                                    -> Vector2,
    Rotate:           (self: Vector2, angle: number)                                      -> Vector2,
    ClampMagnitude:   (self: Vector2, maxLength: number)                                  -> Vector2,
    MoveTowards:      (self: Vector2, target: Vector2, maxDistanceDelta: number)          -> Vector2,
}

type Vector2Metatable = {
    __index:    Vector2,
    __mul:      (a: number | Vector2, b: number | Vector2) -> Vector2,
    __div:      (a: number | Vector2, b: number | Vector2) -> Vector2,
    __add:      (a: number | Vector2, b: number | Vector2) -> Vector2,
    __sub:      (a: number | Vector2, b: number | Vector2) -> Vector2,
    __unm:      (self: Vector2)                             -> Vector2,
    __eq:       (a: Vector2, b: Vector2)                    -> boolean,
    __tostring: (self: Vector2)                             -> string,
}
--
-- CONSTANTS
--
local INF     = (math.huge)
local EPSILON = (0.000001)
local DEG2RAD = (math.pi / 180)
local RAD2DEG = (1 / DEG2RAD)
--
-- LOCAL FORWARD DECLARATIONS
--
-- (createRawVector2 and updateMagnitudeAndUnit are defined after the module
--  table so they can capture the metatable upvalue correctly.)
--
-- MODULE DEFINITION
--
local Vector2: Vector2 = {} :: Vector2
Vector2.__type = "Vector2"

local mt: Vector2Metatable = {
    __index = Vector2,
} :: Vector2Metatable

local function createRawVector2(x: number, y: number): Vector2
    local self: any = {
        X         = x,
        Y         = y,
        Magnitude = 0,
        Unit      = nil :: Vector2?,
    }
    setmetatable(self, mt)
    return self :: Vector2
end

local function updateMagnitudeAndUnit(self: Vector2)
    local xValue = self.X
    local yValue = self.Y

    local magnitude = math.sqrt((xValue * xValue) + (yValue * yValue))

    self.Magnitude = magnitude

    if (magnitude > EPSILON) then
        -- Create unit vector without calling Vector2.new to avoid recursion
        if (self.Unit == nil) then
            local unit = createRawVector2(xValue / magnitude, yValue / magnitude)

            unit.Magnitude = 1
            unit.Unit      = unit
            self.Unit      = unit
        else
            -- Update existing unit vector
            self.Unit.X = xValue / magnitude
            self.Unit.Y = yValue / magnitude
        end
    else
        if (self.Unit == nil) then
            local zeroUnit = createRawVector2(0, 0)

            zeroUnit.Magnitude = 0
            zeroUnit.Unit      = zeroUnit
            self.Unit          = zeroUnit
        else
            self.Unit.X = 0
            self.Unit.Y = 0
        end
    end
end

local function fuzzyEq(a: number, b: number, epsilon: number): boolean
    return ((a == b) or (math.abs(a - b) <= ((math.abs(a) + 1) * epsilon)))
end

local function isScalarVectorPair(a: any, b: any): (boolean, boolean)
    local aIsNumber = (type(a) == "number")
    local bIsNumber = (type(b) == "number")
    local aIsVector = (typeof(a) == "table") and ((a :: any).__type == "Vector2")
    local bIsVector = (typeof(b) == "table") and ((b :: any).__type == "Vector2")

    return (aIsNumber and bIsVector), (bIsNumber and aIsVector)
end

local function isVectorVectorPair(a: any, b: any): boolean
    local aIsVector = (typeof(a) == "table") and ((a :: any).__type == "Vector2")
    local bIsVector = (typeof(b) == "table") and ((b :: any).__type == "Vector2")

    return (aIsVector and bIsVector)
end

function Vector2.new(x: number?, y: number?): Vector2
    local xNum = x
    local yNum = y

    if (xNum == nil) then xNum = 0 end
    if (yNum == nil) then yNum = 0 end

    local self: any = createRawVector2(xNum, yNum)

    updateMagnitudeAndUnit(self)

    return self :: Vector2
end

function mt.__mul(a: number | Vector2, b: number | Vector2): Vector2
    local scalarVector, vectorScalar = isScalarVectorPair(a, b)
    local bothVector                 = isVectorVectorPair(a, b)

    if (scalarVector) then
        -- a is a scalar, b is a vector
        local scalar: number = a
        local vector: Vector2 = b :: Vector2

        return Vector2.new(scalar * vector.X, scalar * vector.Y)
    end

    if (vectorScalar) then
        -- a is a vector, b is a scalar
        local vector: Vector2 = a :: Vector2
        local scalar: number  = b

        return Vector2.new(vector.X * scalar, vector.Y * scalar)
    end

    if (bothVector) then
        -- Both a and b are vectors (component-wise multiplication)
        local vectorA: Vector2 = a :: Vector2
        local vectorB: Vector2 = b :: Vector2

        return Vector2.new(vectorA.X * vectorB.X, vectorA.Y * vectorB.Y)
    end

    error("Invalid operation for __mul")
end

function mt.__div(a: number | Vector2, b: number | Vector2): Vector2
    local scalarVector, vectorScalar = isScalarVectorPair(a, b)
    local bothVector                 = isVectorVectorPair(a, b)

    if (scalarVector) then
        -- a is a scalar, b is a vector
        local scalar: number = a
        local vector: Vector2 = b :: Vector2

        if ((math.abs(vector.X) < EPSILON) or (math.abs(vector.Y) < EPSILON)) then
            error("Division by zero or near-zero vector component")
        end

        return Vector2.new(scalar / vector.X, scalar / vector.Y)
    end

    if (vectorScalar) then
        -- a is a vector, b is a scalar
        local vector: Vector2 = a :: Vector2
        local scalar: number  = b

        if (math.abs(scalar) < EPSILON) then
            error("Division by zero or near-zero scalar")
        end

        return Vector2.new(vector.X / scalar, vector.Y / scalar)
    end

    if (bothVector) then
        -- Both a and b are vectors (component-wise division)
        local vectorA: Vector2 = a :: Vector2
        local vectorB: Vector2 = b :: Vector2

        if ((math.abs(vectorB.X) < EPSILON) or (math.abs(vectorB.Y) < EPSILON)) then
            error("Division by zero or near-zero vector component")
        end

        return Vector2.new(vectorA.X / vectorB.X, vectorA.Y / vectorB.Y)
    end

    error("Invalid operation for __div")
end

function mt.__add(a: number | Vector2, b: number | Vector2): Vector2
    local scalarVector, vectorScalar = isScalarVectorPair(a, b)
    local bothVector                 = isVectorVectorPair(a, b)

    if (scalarVector) then
        -- a is a scalar, b is a vector
        local scalar: number = a
        local vector: Vector2 = b :: Vector2

        return Vector2.new(scalar + vector.X, scalar + vector.Y)
    end

    if (vectorScalar) then
        -- a is a vector, b is a scalar
        local vector: Vector2 = a :: Vector2
        local scalar: number  = b

        return Vector2.new(vector.X + scalar, vector.Y + scalar)
    end

    if (bothVector) then
        -- Both a and b are vectors
        local vectorA: Vector2 = a :: Vector2
        local vectorB: Vector2 = b :: Vector2

        return Vector2.new(vectorA.X + vectorB.X, vectorA.Y + vectorB.Y)
    end

    error("Invalid operation for __add")
end

function mt.__sub(a: number | Vector2, b: number | Vector2): Vector2
    local scalarVector, vectorScalar = isScalarVectorPair(a, b)
    local bothVector                 = isVectorVectorPair(a, b)

    if (scalarVector) then
        -- a is a scalar, b is a vector
        local scalar: number = a
        local vector: Vector2 = b :: Vector2

        return Vector2.new(scalar - vector.X, scalar - vector.Y)
    end

    if (vectorScalar) then
        -- a is a vector, b is a scalar
        local vector: Vector2 = a :: Vector2
        local scalar: number  = b

        return Vector2.new(vector.X - scalar, vector.Y - scalar)
    end

    if (bothVector) then
        -- Both a and b are vectors
        local vectorA: Vector2 = a :: Vector2
        local vectorB: Vector2 = b :: Vector2

        return Vector2.new(vectorA.X - vectorB.X, vectorA.Y - vectorB.Y)
    end

    error("Invalid operation for __sub")
end

function mt.__unm(self: Vector2): Vector2
    return Vector2.new(-self.X, -self.Y)
end

function mt.__eq(a: Vector2, b: Vector2): boolean
    local xDiff = math.abs(a.X - b.X)
    local yDiff = math.abs(a.Y - b.Y)

    return ((xDiff < EPSILON) and (yDiff < EPSILON))
end

function mt.__tostring(self: Vector2): string
    return string.format("(%.4f, %.4f)", self.X, self.Y)
end

function Vector2:Floor(): Vector2
    return Vector2.new(math.floor(self.X), math.floor(self.Y))
end

function Vector2:Ceil(): Vector2
    return Vector2.new(math.ceil(self.X), math.ceil(self.Y))
end

function Vector2:Round(): Vector2
    local roundedX = math.floor(self.X + 0.5)
    local roundedY = math.floor(self.Y + 0.5)

    return Vector2.new(roundedX, roundedY)
end

function Vector2:Lerp(b: Vector2, percent: number): Vector2
    local clampedPercent = math.max(0, math.min(1, percent))

    return Vector2.new(
        self.X + ((b.X - self.X) * clampedPercent),
        self.Y + ((b.Y - self.Y) * clampedPercent)
    )
end

function Vector2:Dot(b: Vector2): number
    return ((self.X * b.X) + (self.Y * b.Y))
end

function Vector2:Cross(b: Vector2): number
    -- Returns scalar (z-component of 3D cross product)
    return ((self.X * b.Y) - (self.Y * b.X))
end

function Vector2:FuzzyEq(v1: Vector2, epsilon: number): boolean
    if (not fuzzyEq(v1.X, self.X, epsilon)) then
        return false
    end

    if (not fuzzyEq(v1.Y, self.Y, epsilon)) then
        return false
    end

    return true
end

function Vector2:IsClose(v1: Vector2, epsilon: number): boolean
    local difference = self - v1

    return (difference.Magnitude <= epsilon)
end

function Vector2:Angle(b: Vector2): number
    local dotValue       = self:Dot(b)
    local magProduct     = self.Magnitude * b.Magnitude

    if (magProduct < EPSILON) then
        return 0
    end

    local clampedCosine = math.max(-1, math.min(1, dotValue / magProduct))

    return (math.acos(clampedCosine) * RAD2DEG)
end

function Vector2:Distance(b: Vector2): number
    local dx = self.X - b.X
    local dy = self.Y - b.Y

    return math.sqrt((dx * dx) + (dy * dy))
end

function Vector2:Normalize(): Vector2
    local mag = self.Magnitude

    if (mag > EPSILON) then
        return Vector2.new(self.X / mag, self.Y / mag)
    end

    return Vector2.new(0, 0)
end

function Vector2:Reflect(normal: Vector2): Vector2
    local normalizedNormal = normal:Normalize()
    local dotValue         = self:Dot(normalizedNormal)

    return self - (normalizedNormal * (2 * dotValue))
end

function Vector2:Rotate(angle: number): Vector2
    local rad      = angle * DEG2RAD
    local cosTheta = math.cos(rad)
    local sinTheta = math.sin(rad)

    return Vector2.new(
        (self.X * cosTheta) - (self.Y * sinTheta),
        (self.X * sinTheta) + (self.Y * cosTheta)
    )
end

function Vector2:ClampMagnitude(maxLength: number): Vector2
    if (maxLength < 0) then
        error("maxLength cannot be negative")
    end

    local sqrMagnitude = (self.X * self.X) + (self.Y * self.Y)

    if (sqrMagnitude > (maxLength * maxLength)) then
        local mag = math.sqrt(sqrMagnitude)

        return Vector2.new(
            (self.X / mag) * maxLength,
            (self.Y / mag) * maxLength
        )
    end

    return Vector2.new(self.X, self.Y)
end

function Vector2:MoveTowards(target: Vector2, maxDistanceDelta: number): Vector2
    local toVector = target - self
    local dist     = toVector.Magnitude

    if ((dist <= maxDistanceDelta) or (dist < EPSILON)) then
        return target
    end

    return self + ((toVector / dist) * maxDistanceDelta)
end
--
-- STATIC PROPERTIES
--
Vector2.Zero  = Vector2.new(0,  0)
Vector2.One   = Vector2.new(1,  1)
Vector2.Up    = Vector2.new(0,  1)
Vector2.Down  = Vector2.new(0, -1)
Vector2.Left  = Vector2.new(-1, 0)
Vector2.Right = Vector2.new(1,  0)
--
-- RETURN VALUE
--
return Vector2
