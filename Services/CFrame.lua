local Mat4 = {}

function Mat4.Identity()
    return {
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1
    }
end

function Mat4.Multiply(A, B)
    local R = {}

    for Col = 0, 3 do
        for Row = 0, 3 do
            local Sum = 0
            for K = 0, 3 do
                Sum = Sum + A[K * 4 + Row + 1] * B[Col * 4 + K + 1]
            end
            R[Col * 4 + Row + 1] = Sum
        end
    end

    return R
end

function Mat4.RotateY(Angle)
    local C, S = math.cos(Angle), math.sin(Angle)
    return {
        C, 0, -S, 0,
        0, 1, 0, 0,
        S, 0, C, 0,
        0, 0, 0, 1
    }
end

function Mat4.RotateX(Angle)
    local C, S = math.cos(Angle), math.sin(Angle)
    return {
        1, 0, 0, 0,
        0, C, S, 0,
        0, -S, C, 0,
        0, 0, 0, 1
    }
end

function Mat4.Translate(X, Y, Z)
    return {
        1, 0, 0, 0,
        0, 1, 0, 0,
        0, 0, 1, 0,
        X, Y, Z, 1
    }
end

function Mat4.Perspective(Fov, Aspect, Near, Far)
    local F = 1 / math.tan(Fov / 2)
    local RangeInv = 1 / (Near - Far)

    return {
        F / Aspect, 0, 0, 0,
        0, F, 0, 0,
        0, 0, (Near + Far) * RangeInv, -1,
        0, 0, Near * Far * RangeInv * 2, 0
    }
end

function Mat4.Inverse(M)
    local function A(R, C)
        return M[C * 4 + R + 1]
    end

    local function Inv4()
        local m00, m01, m02, m03 = A(0, 0), A(0, 1), A(0, 2), A(0, 3)
        local m10, m11, m12, m13 = A(1, 0), A(1, 1), A(1, 2), A(1, 3)
        local m20, m21, m22, m23 = A(2, 0), A(2, 1), A(2, 2), A(2, 3)
        local m30, m31, m32, m33 = A(3, 0), A(3, 1), A(3, 2), A(3, 3)

        local c00 = m11 * (m22 * m33 - m23 * m32) - m12 * (m21 * m33 - m23 * m31) + m13 * (m21 * m32 - m22 * m31)
        local c01 = -m10 * (m22 * m33 - m23 * m32) + m12 * (m20 * m33 - m23 * m30) - m13 * (m20 * m32 - m22 * m30)
        local c02 = m10 * (m21 * m33 - m23 * m31) - m11 * (m20 * m33 - m23 * m30) + m13 * (m20 * m31 - m21 * m30)
        local c03 = -m10 * (m21 * m32 - m22 * m31) + m11 * (m20 * m32 - m22 * m30) - m12 * (m20 * m31 - m21 * m30)

        local Det = m00 * c00 + m01 * c01 + m02 * c02 + m03 * c03
        if math.abs(Det) < 1e-12 then
            return Mat4.Identity()
        end

        local InvDet = 1 / Det

        local Cof = {
            c00, c01, c02, c03,
            -(m01 * (m22 * m33 - m23 * m32) - m02 * (m21 * m33 - m23 * m31) + m03 * (m21 * m32 - m22 * m31)),
            (m00 * (m22 * m33 - m23 * m32) - m02 * (m20 * m33 - m23 * m30) + m03 * (m20 * m32 - m22 * m30)),
            -(m00 * (m21 * m33 - m23 * m31) - m01 * (m20 * m33 - m23 * m30) + m03 * (m20 * m31 - m21 * m30)),
            (m00 * (m21 * m32 - m22 * m31) - m01 * (m20 * m32 - m22 * m30) + m02 * (m20 * m31 - m21 * m30)),
            (m01 * (m12 * m33 - m13 * m32) - m02 * (m11 * m33 - m13 * m31) + m03 * (m11 * m32 - m12 * m31)),
            -(m00 * (m12 * m33 - m13 * m32) - m02 * (m10 * m33 - m13 * m30) + m03 * (m10 * m32 - m12 * m30)),
            (m00 * (m11 * m33 - m13 * m31) - m01 * (m10 * m33 - m13 * m30) + m03 * (m10 * m31 - m11 * m30)),
            -(m00 * (m11 * m32 - m12 * m31) - m01 * (m10 * m32 - m12 * m30) + m02 * (m10 * m31 - m11 * m30)),
            -(m01 * (m12 * m23 - m13 * m22) - m02 * (m11 * m23 - m13 * m21) + m03 * (m11 * m22 - m12 * m21)),
            (m00 * (m12 * m23 - m13 * m22) - m02 * (m10 * m23 - m13 * m20) + m03 * (m10 * m22 - m12 * m20)),
            -(m00 * (m11 * m23 - m13 * m21) - m01 * (m10 * m23 - m13 * m20) + m03 * (m10 * m21 - m11 * m20)),
            (m00 * (m11 * m22 - m12 * m21) - m01 * (m10 * m22 - m12 * m20) + m02 * (m10 * m21 - m11 * m20))
        }

        local R = {}
        for Col = 0, 3 do
            for Row = 0, 3 do
                R[Col * 4 + Row + 1] = Cof[Row * 4 + Col + 1] * InvDet
            end
        end

        return R
    end

    return Inv4()
end

function Mat4.LookAt(Eye, Target, Up)
    local function Sub(A, B)
        return {A[1] - B[1], A[2] - B[2], A[3] - B[3]}
    end

    local function Norm(V)
        local Len = math.sqrt(V[1] * V[1] + V[2] * V[2] + V[3] * V[3])
        if Len == 0 then
            Len = 1
        end
        return {V[1] / Len, V[2] / Len, V[3] / Len}
    end

    local function Cross(A, B)
        return {
            A[2] * B[3] - A[3] * B[2],
            A[3] * B[1] - A[1] * B[3],
            A[1] * B[2] - A[2] * B[1]
        }
    end

    local function Dot(A, B)
        return A[1] * B[1] + A[2] * B[2] + A[3] * B[3]
    end

    local ZAxis = Norm(Sub(Eye, Target))
    local XAxis = Norm(Cross(Up, ZAxis))
    local YAxis = Cross(ZAxis, XAxis)

    return {
        XAxis[1], XAxis[2], XAxis[3], 0,
        YAxis[1], YAxis[2], YAxis[3], 0,
        ZAxis[1], ZAxis[2], ZAxis[3], 0,
        -Dot(XAxis, Eye), -Dot(YAxis, Eye), -Dot(ZAxis, Eye), 1
    }
end

-- ---------------------------------------------------------------------------
-- CFrame
-- ---------------------------------------------------------------------------

local CFrame = {}

local CFrameMeta = {}
CFrameMeta.__index = CFrameMeta

function CFrameMeta.__mul(a, b)
    if type(b) == "table" and not b[4] then
        local x = b[1] or b.X or b.x or 0
        local y = b[2] or b.Y or b.y or 0
        local z = b[3] or b.Z or b.z or 0

        return {
            a[1] + a[4] * x + a[5] * y + a[6] * z,
            a[2] + a[7] * x + a[8] * y + a[9] * z,
            a[3] + a[10] * x + a[11] * y + a[12] * z
        }
    end

    local x1, y1, z1 = a[1], a[2], a[3]
    local m11, m12, m13 = a[4], a[5], a[6]
    local m21, m22, m23 = a[7], a[8], a[9]
    local m31, m32, m33 = a[10], a[11], a[12]

    local x2, y2, z2 = b[1], b[2], b[3]
    local n11, n12, n13 = b[4], b[5], b[6]
    local n21, n22, n23 = b[7], b[8], b[9]
    local n31, n32, n33 = b[10], b[11], b[12]

    local nx = x1 + m11 * x2 + m12 * y2 + m13 * z2
    local ny = y1 + m21 * x2 + m22 * y2 + m23 * z2
    local nz = z1 + m31 * x2 + m32 * y2 + m33 * z2

    local r11 = m11 * n11 + m12 * n21 + m13 * n31
    local r12 = m11 * n12 + m12 * n22 + m13 * n32
    local r13 = m11 * n13 + m12 * n23 + m13 * n33

    local r21 = m21 * n11 + m22 * n21 + m23 * n31
    local r22 = m21 * n12 + m22 * n22 + m23 * n32
    local r23 = m21 * n13 + m22 * n23 + m23 * n33

    local r31 = m31 * n11 + m32 * n21 + m33 * n31
    local r32 = m31 * n12 + m32 * n22 + m33 * n32
    local r33 = m31 * n13 + m32 * n23 + m33 * n33

    return CFrame.new_internal(nx, ny, nz, r11, r12, r13, r21, r22, r23, r31, r32, r33)
end

function CFrameMeta:ToOrientation()
    local m23 = self[9]
    local pitch = math.asin(-math.max(-1, math.min(1, m23)))
    local roll, yaw

    if math.abs(m23) < 0.99999 then
        roll = math.atan2(self[6], self[12])
        yaw = math.atan2(self[8], self[5])
    else
        roll = math.atan2(-self[11], self[10])
        yaw = 0
    end

    return pitch, yaw, roll
end

function CFrame.new_internal(x, y, z, m11, m12, m13, m21, m22, m23, m31, m32, m33)
    local t = {
        x, y, z,
        m11, m12, m13,
        m21, m22, m23,
        m31, m32, m33
    }

    t.Position = {x, y, z}
    t.Right = {m11, m21, m31}
    t.Up = {m12, m22, m32}
    t.Forward = {-m13, -m23, -m33}

    return setmetatable(t, CFrameMeta)
end

function CFrame.new(x, y, z)
    if type(x) == "table" then
        z = x[3] or x.Z or x.z or 0
        y = x[2] or x.Y or x.y or 0
        x = x[1] or x.X or x.x or 0
    end

    x = x or 0
    y = y or 0
    z = z or 0

    return CFrame.new_internal(x, y, z, 1, 0, 0, 0, 1, 0, 0, 0, 1)
end

function CFrame.Angles(rx, ry, rz)
    local cx, sx = math.cos(rx or 0), math.sin(rx or 0)
    local cy, sy = math.cos(ry or 0), math.sin(ry or 0)
    local cz, sz = math.cos(rz or 0), math.sin(rz or 0)

    local mx = CFrame.new_internal(0, 0, 0, 1, 0, 0, 0, cx, -sx, 0, sx, cx)
    local my = CFrame.new_internal(0, 0, 0, cy, 0, sy, 0, 1, 0, -sy, 0, cy)
    local mz = CFrame.new_internal(0, 0, 0, cz, -sz, 0, sz, cz, 0, 0, 0, 1)

    return mx * my * mz
end

function CFrame.FromPositionRotation(Position, Pitch, Yaw)
    local Cp = math.cos(Pitch)
    local Sp = math.sin(Pitch)
    local Cy = math.cos(Yaw)
    local Sy = math.sin(Yaw)

    local Forward = {
        Cp * Sy,
        Sp,
        -Cp * Cy
    }
    local Right = {
        Cy,
        0,
        Sy
    }
    local Up = {
        Right[2] * Forward[3] - Right[3] * Forward[2],
        Right[3] * Forward[1] - Right[1] * Forward[3],
        Right[1] * Forward[2] - Right[2] * Forward[1]
    }

    return {
        Position = {Position[1], Position[2], Position[3]},
        Forward = Forward,
        Right = Right,
        Up = Up,
        Pitch = Pitch,
        Yaw = Yaw
    }
end

function CFrame.ViewMatrix(Cf)
    local X, Y = Cf.Right, Cf.Up
    local Z = {
        -Cf.Forward[1],
        -Cf.Forward[2],
        -Cf.Forward[3]
    }
    local Eye = Cf.Position

    local function Dot(A, B)
        return A[1] * B[1] + A[2] * B[2] + A[3] * B[3]
    end

    return {
        X[1], X[2], X[3], 0,
        Y[1], Y[2], Y[3], 0,
        Z[1], Z[2], Z[3], 0,
        -Dot(X, Eye), -Dot(Y, Eye), -Dot(Z, Eye), 1
    }
end

function CFrame.LookAt(Eye, Target, Up)
    return Mat4.LookAt(Eye, Target, Up or {0, 1, 0})
end

function CFrame.RotationFromEulerDegrees(Rx, Ry, Rz)
    local function ToRad(D)
        return (D or 0) * math.pi / 180
    end

    local Rax, Ray, Raz = ToRad(Rx), ToRad(Ry), ToRad(Rz)

    local Cx, Sx = math.cos(Rax), math.sin(Rax)
    local Cy, Sy = math.cos(Ray), math.sin(Ray)
    local Cz, Sz = math.cos(Raz), math.sin(Raz)

    local R = {
        Cy * Cz + Sy * Sx * Sz, Cz * Sy * Sx - Cy * Sz, Cx * Sy,
        Cx * Sz, Cx * Cz, -Sx,
        Cy * Sx * Sz - Sy * Cz, Sy * Sz + Cy * Cz * Sx, Cy * Cx
    }

    return {
        Right = {R[1], R[4], R[7]},
        Up = {R[2], R[5], R[8]},
        Forward = {R[3], R[6], R[9]},
    }
end

function CFrame.RotateByOrientation(Dir, Orientation)
    if not Orientation then
        return {Dir[1], Dir[2], Dir[3]}
    end

    local Ox, Oy, Oz = Orientation[1] or 0, Orientation[2] or 0, Orientation[3] or 0
    if Ox == 0 and Oy == 0 and Oz == 0 then
        return {Dir[1], Dir[2], Dir[3]}
    end

    local Basis = CFrame.RotationFromEulerDegrees(Ox, Oy, Oz)
    local X, Y, Z = Basis.Right, Basis.Up, Basis.Forward

    return {
        X[1] * Dir[1] + Y[1] * Dir[2] + Z[1] * Dir[3],
        X[2] * Dir[1] + Y[2] * Dir[2] + Z[2] * Dir[3],
        X[3] * Dir[1] + Y[3] * Dir[2] + Z[3] * Dir[3],
    }
end

function CFrame.TransformPoint(LocalPoint, PartPosition, PartOrientation)
    local Rotated = CFrame.RotateByOrientation(LocalPoint, PartOrientation)

    return {
        Rotated[1] + (PartPosition[1] or 0),
        Rotated[2] + (PartPosition[2] or 0),
        Rotated[3] + (PartPosition[3] or 0),
    }
end

return CFrame
