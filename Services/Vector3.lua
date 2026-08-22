local Vector3 = {}
Vector3.__index = Vector3

function Vector3.new(Px, Py, Pz)
    local Self = setmetatable({}, Vector3)
    Self.Px = Px or 0
    Self.Py = Py or 0
    Self.Pz = Pz or 0
    return Self
end

function Vector3:ToArray()
    return { self.Px, self.Py, self.Pz }
end

function Vector3.FromArray(Arr)
    return Vector3.new(Arr[1], Arr[2], Arr[3])
end

function Vector3:Add(Other)
    return Vector3.new(self.Px + Other.Px, self.Py + Other.Py, self.Pz + Other.Pz)
end

function Vector3:Sub(Other)
    return Vector3.new(self.Px - Other.Px, self.Py - Other.Py, self.Pz - Other.Pz)
end

function Vector3:Scale(Scalar)
    return Vector3.new(self.Px * Scalar, self.Py * Scalar, self.Pz * Scalar)
end

return Vector3