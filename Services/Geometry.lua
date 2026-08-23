local Geometry = {}

local Cache = {}

local function Key(Shape, Size)
    local Sx = math.floor((Size[1] or 1) * 100 + 0.5)
    local Sy = math.floor((Size[2] or 1) * 100 + 0.5)
    local Sz = math.floor((Size[3] or 1) * 100 + 0.5)

    return string.lower(tostring(Shape or "Block")) .. ":" .. Sx .. ":" .. Sy .. ":" .. Sz
end

local function PushV(Verts, x, y, z)
    Verts[#Verts + 1] = {x, y, z}
    return #Verts
end

local function PushT(Tris, a, b, c)
    Tris[#Tris + 1] = {a, b, c}
end

-- ---------------------------------------------------------------------------
-- Shape generators
-- ---------------------------------------------------------------------------

local function GenBlock(Sx, Sy, Sz)
    local hx, hy, hz = Sx * 0.5, Sy * 0.5, Sz * 0.5
    local V, T = {}, {}

    -- 8 corners
    PushV(V, -hx, -hy, -hz) -- 1
    PushV(V, hx, -hy, -hz)  -- 2
    PushV(V, hx, hy, -hz)   -- 3
    PushV(V, -hx, hy, -hz)  -- 4
    PushV(V, -hx, -hy, hz)  -- 5
    PushV(V, hx, -hy, hz)   -- 6
    PushV(V, hx, hy, hz)    -- 7
    PushV(V, -hx, hy, hz)   -- 8

    -- faces
    PushT(T, 1, 2, 3); PushT(T, 1, 3, 4) -- -Z
    PushT(T, 5, 7, 6); PushT(T, 5, 8, 7) -- +Z
    PushT(T, 1, 5, 6); PushT(T, 1, 6, 2) -- -Y
    PushT(T, 4, 3, 7); PushT(T, 4, 7, 8) -- +Y
    PushT(T, 1, 4, 8); PushT(T, 1, 8, 5) -- -X
    PushT(T, 2, 6, 7); PushT(T, 2, 7, 3) -- +X

    return V, T
end

local function GenWedge(Sx, Sy, Sz)
    local hx, hy, hz = Sx * 0.5, Sy * 0.5, Sz * 0.5
    local V, T = {}, {}

    -- Wedge: full base, slopes toward -Z top
    PushV(V, -hx, -hy, -hz) -- 1
    PushV(V, hx, -hy, -hz)  -- 2
    PushV(V, hx, -hy, hz)   -- 3
    PushV(V, -hx, -hy, hz)  -- 4
    PushV(V, -hx, hy, hz)   -- 5 top back
    PushV(V, hx, hy, hz)    -- 6

    -- bottom
    PushT(T, 1, 2, 3)
    PushT(T, 1, 3, 4)
    -- back
    PushT(T, 4, 3, 6)
    PushT(T, 4, 6, 5)
    -- slope
    PushT(T, 1, 5, 6)
    PushT(T, 1, 6, 2)
    -- sides
    PushT(T, 1, 4, 5)
    PushT(T, 2, 6, 3)

    return V, T
end

-- Roblox-style CornerWedge: rectangular base, single peak at (-hx, +hy, +hz)
local function GenCornerWedge(Sx, Sy, Sz)
    local hx, hy, hz = Sx * 0.5, Sy * 0.5, Sz * 0.5
    local V, T = {}, {}

    PushV(V, -hx, -hy, -hz) -- 1 bottom front-left
    PushV(V,  hx, -hy, -hz) -- 2 bottom front-right
    PushV(V,  hx, -hy,  hz) -- 3 bottom back-right
    PushV(V, -hx, -hy,  hz) -- 4 bottom back-left
    PushV(V, -hx,  hy,  hz) -- 5 peak (top back-left)

    -- bottom
    PushT(T, 1, 2, 3)
    PushT(T, 1, 3, 4)
    -- vertical back (+Z)
    PushT(T, 4, 3, 5)
    -- vertical left (-X)
    PushT(T, 1, 4, 5)
    -- slope toward +X
    PushT(T, 2, 5, 3)
    -- slope toward -Z
    PushT(T, 1, 5, 2)

    return V, T
end

local function GenCylinder(Sx, Sy, Sz, Segs)
    Segs = Segs or 12

    local r = math.min(Sx, Sz) * 0.5
    local hy = Sy * 0.5
    local V, T = {}, {}

    local topC = PushV(V, 0, hy, 0)
    local botC = PushV(V, 0, -hy, 0)
    local topRing, botRing = {}, {}

    for i = 0, Segs - 1 do
        local a = (i / Segs) * math.pi * 2
        local x, z = math.cos(a) * r, math.sin(a) * r
        topRing[i + 1] = PushV(V, x, hy, z)
        botRing[i + 1] = PushV(V, x, -hy, z)
    end

    for i = 1, Segs do
        local j = (i % Segs) + 1
        PushT(T, topC, topRing[j], topRing[i])
        PushT(T, botC, botRing[i], botRing[j])
        PushT(T, botRing[i], topRing[i], topRing[j])
        PushT(T, botRing[i], topRing[j], botRing[j])
    end

    return V, T
end

local function GenCone(Sx, Sy, Sz, Segs)
    Segs = Segs or 12

    local r = math.min(Sx, Sz) * 0.5
    local hy = Sy * 0.5
    local V, T = {}, {}

    local tip = PushV(V, 0, hy, 0)
    local baseC = PushV(V, 0, -hy, 0)
    local ring = {}

    for i = 0, Segs - 1 do
        local a = (i / Segs) * math.pi * 2
        ring[i + 1] = PushV(V, math.cos(a) * r, -hy, math.sin(a) * r)
    end

    for i = 1, Segs do
        local j = (i % Segs) + 1
        PushT(T, tip, ring[j], ring[i])
        PushT(T, baseC, ring[i], ring[j])
    end

    return V, T
end

local function GenPlane(Sx, Sy, Sz)
    local hx, hz = Sx * 0.5, Sz * 0.5
    local V, T = {}, {}

    PushV(V, -hx, 0, -hz)
    PushV(V, hx, 0, -hz)
    PushV(V, hx, 0, hz)
    PushV(V, -hx, 0, hz)

    PushT(T, 1, 2, 3)
    PushT(T, 1, 3, 4)

    return V, T
end

local function GenSphere(Sx, Sy, Sz, Slices, Stacks)
    Slices = Slices or 10
    Stacks = Stacks or 8

    local rx, ry, rz = Sx * 0.5, Sy * 0.5, Sz * 0.5
    local V, T = {}, {}
    local grid = {}

    for y = 0, Stacks do
        grid[y] = {}
        local v = y / Stacks
        local phi = v * math.pi
        local sy, cy = math.sin(phi), math.cos(phi)

        for x = 0, Slices do
            local u = x / Slices
            local theta = u * math.pi * 2
            local sx, cx = math.sin(theta), math.cos(theta)
            grid[y][x] = PushV(V, rx * sx * sy, ry * cy, rz * cx * sy)
        end
    end

    for y = 0, Stacks - 1 do
        for x = 0, Slices - 1 do
            local a = grid[y][x]
            local b = grid[y][x + 1]
            local c = grid[y + 1][x]
            local d = grid[y + 1][x + 1]

            PushT(T, a, c, b)
            PushT(T, b, c, d)
        end
    end

    return V, T
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------

--- Returns { Vertices = {{x,y,z},...}, Triangles = {{i,j,k},...}, BoundsHalf = {hx,hy,hz} }
--- Vertices are local-space (centered at origin). Indices are 1-based.
function Geometry.GetMesh(Shape, Size)
    local S = type(Size) == "table" and Size or {4, 4, 4}
    if S.ToArray then
        S = S:ToArray()
    end

    local k = Key(Shape, S)
    if Cache[k] then
        return Cache[k]
    end

    local shape = string.lower(tostring(Shape or "Block"))
    local V, T

    if shape == "sphere" or shape == "ball" then
        V, T = GenSphere(S[1], S[2], S[3], 10, 8)
    elseif shape == "cylinder" then
        V, T = GenCylinder(S[1], S[2], S[3], 12)
    elseif shape == "wedge" then
        V, T = GenWedge(S[1], S[2], S[3])
    elseif shape == "cornerwedge" then
        V, T = GenCornerWedge(S[1], S[2], S[3])
    elseif shape == "cone" then
        V, T = GenCone(S[1], S[2], S[3], 12)
    elseif shape == "plane" then
        V, T = GenPlane(S[1], S[2], S[3])
    elseif shape == "cube" then
        V, T = GenBlock(S[1], S[2], S[3])
    else
        V, T = GenBlock(S[1], S[2], S[3])
    end

    local mesh = {
        Vertices = V,
        Triangles = T,
        BoundsHalf = {S[1] * 0.5, S[2] * 0.5, S[3] * 0.5},
        Shape = shape
    }

    Cache[k] = mesh
    return mesh
end

function Geometry.ClearCache()
    Cache = {}
end

local function ToArr3(V)
    if not V then
        return {0, 0, 0}
    end
    if type(V) == "table" and V.ToArray then
        return V:ToArray()
    end
    if type(V) == "table" and V.Px then
        return {V.Px, V.Py, V.Pz}
    end
    return {V[1] or 0, V[2] or 0, V[3] or 0}
end

local function IsDescendantOf(Node, Ancestor)
    local Cur = Node
    while Cur do
        if Cur == Ancestor then
            return true
        end
        Cur = rawget(Cur, "_Parent") or rawget(Cur, "Parent")
    end
    return false
end

function Geometry.IntersectAABB(Ro, Rd, Pos, Half)
    local Inv = {
        Rd[1] ~= 0 and 1 / Rd[1] or 1e12,
        Rd[2] ~= 0 and 1 / Rd[2] or 1e12,
        Rd[3] ~= 0 and 1 / Rd[3] or 1e12,
    }
    local T0 = {
        (Pos[1] - Half[1] - Ro[1]) * Inv[1],
        (Pos[2] - Half[2] - Ro[2]) * Inv[2],
        (Pos[3] - Half[3] - Ro[3]) * Inv[3],
    }
    local T1 = {
        (Pos[1] + Half[1] - Ro[1]) * Inv[1],
        (Pos[2] + Half[2] - Ro[2]) * Inv[2],
        (Pos[3] + Half[3] - Ro[3]) * Inv[3],
    }
    local Tmin = {math.min(T0[1], T1[1]), math.min(T0[2], T1[2]), math.min(T0[3], T1[3])}
    local Tmax = {math.max(T0[1], T1[1]), math.max(T0[2], T1[2]), math.max(T0[3], T1[3])}
    local TNear = math.max(Tmin[1], math.max(Tmin[2], Tmin[3]))
    local TFar = math.min(Tmax[1], math.min(Tmax[2], Tmax[3]))
    if TNear > TFar or TFar < 0 then
        return nil
    end
    local T = TNear > 0 and TNear or TFar
    if T < 0 then
        return nil
    end
    local N = {0, 0, 0}
    local Eps = 1e-4
    if TNear > 0 then
        if math.abs(TNear - Tmin[1]) < Eps then
            N[1] = Rd[1] > 0 and -1 or 1
        elseif math.abs(TNear - Tmin[2]) < Eps then
            N[2] = Rd[2] > 0 and -1 or 1
        else
            N[3] = Rd[3] > 0 and -1 or 1
        end
    else
        if math.abs(TFar - Tmax[1]) < Eps then
            N[1] = Rd[1] > 0 and 1 or -1
        elseif math.abs(TFar - Tmax[2]) < Eps then
            N[2] = Rd[2] > 0 and 1 or -1
        else
            N[3] = Rd[3] > 0 and 1 or -1
        end
    end
    return T, N
end

function Geometry.IntersectSphere(Ro, Rd, Pos, Size)
    local R = math.min(Size[1], math.min(Size[2], Size[3])) * 0.5
    local Oc = {Ro[1] - Pos[1], Ro[2] - Pos[2], Ro[3] - Pos[3]}
    local B = Oc[1] * Rd[1] + Oc[2] * Rd[2] + Oc[3] * Rd[3]
    local C = Oc[1] * Oc[1] + Oc[2] * Oc[2] + Oc[3] * Oc[3] - R * R
    local H = B * B - C
    if H < 0 then
        return nil
    end
    H = math.sqrt(H)
    local T = -B - H
    if T < 0 then
        T = -B + H
    end
    if T < 0 then
        return nil
    end
    local Hx = Ro[1] + Rd[1] * T
    local Hy = Ro[2] + Rd[2] * T
    local Hz = Ro[3] + Rd[3] * T
    local Nx, Ny, Nz = Hx - Pos[1], Hy - Pos[2], Hz - Pos[3]
    local Len = math.sqrt(Nx * Nx + Ny * Ny + Nz * Nz)
    if Len > 1e-8 then
        Nx, Ny, Nz = Nx / Len, Ny / Len, Nz / Len
    end
    return T, {Nx, Ny, Nz}
end

function Geometry.IntersectCylinder(Ro, Rd, Pos, Size)
    local Radius = math.min(Size[1], Size[3]) * 0.5
    local HalfH = Size[2] * 0.5
    local Ocx, Ocz = Ro[1] - Pos[1], Ro[3] - Pos[3]
    local A = Rd[1] * Rd[1] + Rd[3] * Rd[3]
    local B = Ocx * Rd[1] + Ocz * Rd[3]
    local C = Ocx * Ocx + Ocz * Ocz - Radius * Radius
    local TSide, NSide
    if A > 1e-8 then
        local H = B * B - A * C
        if H >= 0 then
            H = math.sqrt(H)
            local T0 = (-B - H) / A
            local T1 = (-B + H) / A
            if T0 > T1 then
                T0, T1 = T1, T0
            end
            local Y0 = Ro[2] + Rd[2] * T0
            if T0 > 0 and math.abs(Y0 - Pos[2]) <= HalfH then
                TSide = T0
                NSide = {
                    (Ro[1] + Rd[1] * T0 - Pos[1]) / Radius,
                    0,
                    (Ro[3] + Rd[3] * T0 - Pos[3]) / Radius,
                }
            else
                local Y1 = Ro[2] + Rd[2] * T1
                if T1 > 0 and math.abs(Y1 - Pos[2]) <= HalfH then
                    TSide = T1
                    NSide = {
                        (Ro[1] + Rd[1] * T1 - Pos[1]) / Radius,
                        0,
                        (Ro[3] + Rd[3] * T1 - Pos[3]) / Radius,
                    }
                end
            end
        end
    end
    local TCap, NCap
    if math.abs(Rd[2]) > 1e-8 then
        for _, Sign in ipairs({1, -1}) do
            local Yp = Pos[2] + Sign * HalfH
            local T = (Yp - Ro[2]) / Rd[2]
            if T > 0 and (not TCap or T < TCap) then
                local Hx = Ro[1] + Rd[1] * T - Pos[1]
                local Hz = Ro[3] + Rd[3] * T - Pos[3]
                if Hx * Hx + Hz * Hz <= Radius * Radius then
                    TCap = T
                    NCap = {0, Sign, 0}
                end
            end
        end
    end
    if not TSide and not TCap then
        return nil
    end
    if not TSide then
        return TCap, NCap
    end
    if not TCap then
        return TSide, NSide
    end
    return (TSide < TCap) and TSide or TCap, (TSide < TCap) and NSide or NCap
end

function Geometry.IntersectPlaneY(Ro, Rd, PlaneY)
    if math.abs(Rd[2]) < 1e-6 then
        return nil
    end
    local T = (PlaneY - Ro[2]) / Rd[2]
    if T < 0 then
        return nil
    end
    return {Ro[1] + Rd[1] * T, Ro[2] + Rd[2] * T, Ro[3] + Rd[3] * T}
end

local function CameraFovRadians(Camera)
    local deg = nil
    if Camera then
        deg = rawget(Camera, "FieldOfView")
        if deg == nil and Camera.GetAttribute then
            deg = Camera:GetAttribute("FieldOfView")
        end
        if deg == nil then
            local old = Camera.GetAttribute and Camera:GetAttribute("Fov")
            if type(old) == "number" and old > 0 and old < 10 then
                deg = old * (180 / math.pi)
            elseif type(old) == "number" and old >= 10 then
                deg = old
            end
        end
    end
    deg = tonumber(deg) or 70
    if deg < 45 then deg = 45 end
    if deg > 135 then deg = 135 end
    return deg * (math.pi / 180)
end

function Geometry.CameraRay(Camera, ScreenX, ScreenY)
    local Width, Height = love.graphics.getDimensions()
    local Fov = CameraFovRadians(Camera)
    local Position = Camera:GetAttribute("Position") or {0, 4, 0}
    local Rotation = Camera:GetAttribute("Rotation") or {0, 0, 0}
    local Pitch, Yaw = Rotation[1] or 0, Rotation[2] or 0
    local Forward = {
        math.cos(Pitch) * math.sin(Yaw),
        math.sin(Pitch),
        -math.cos(Pitch) * math.cos(Yaw),
    }
    local Right = {math.cos(Yaw), 0, math.sin(Yaw)}
    local Up = {
        Right[2] * Forward[3] - Right[3] * Forward[2],
        Right[3] * Forward[1] - Right[1] * Forward[3],
        Right[1] * Forward[2] - Right[2] * Forward[1],
    }
    local UvX = (ScreenX - 0.5 * Width) / Height
    local UvY = (ScreenY - 0.5 * Height) / Height
    local TanFov = math.tan(Fov * 0.5)
    local Rd = {
        Forward[1] + Right[1] * UvX * TanFov - Up[1] * UvY * TanFov,
        Forward[2] + Right[2] * UvX * TanFov - Up[2] * UvY * TanFov,
        Forward[3] + Right[3] * UvX * TanFov - Up[3] * UvY * TanFov,
    }
    local Len = math.sqrt(Rd[1] * Rd[1] + Rd[2] * Rd[2] + Rd[3] * Rd[3])
    if Len < 1e-8 then
        Len = 1
    end
    Rd[1], Rd[2], Rd[3] = Rd[1] / Len, Rd[2] / Len, Rd[3] / Len
    return {Position[1], Position[2], Position[3]}, Rd
end

function Geometry.WorkspaceRaycast(Origin, Direction, Params)
    local Vector3 = require("Services.Vector3")
    local Ro = ToArr3(Origin)
    local DirArr = ToArr3(Direction)
    local Len = math.sqrt(DirArr[1] ^ 2 + DirArr[2] ^ 2 + DirArr[3] ^ 2)
    if Len < 1e-6 then
        return nil
    end
    local Rd = {DirArr[1] / Len, DirArr[2] / Len, DirArr[3] / Len}
    local BestT = Len
    local BestPart, BestNormal
    local Filter = Params and Params.FilterDescendantsInstances or {}
    local FilterType = Params and Params.FilterType or Enum.RaycastFilterMode.Exclude

    local function ShouldConsider(Part)
        if FilterType == Enum.RaycastFilterMode.Exclude then
            for _, F in ipairs(Filter) do
                if F == Part or IsDescendantOf(Part, F) then
                    return false
                end
            end
            return true
        end
        if #Filter == 0 then
            return false
        end
        for _, F in ipairs(Filter) do
            if F == Part or IsDescendantOf(Part, F) then
                return true
            end
        end
        return false
    end

    local function CheckPart(Part)
        if not ShouldConsider(Part) then
            return
        end
        local respect = true
        if Params and Params.RespectCanCollide ~= nil then
            respect = Params.RespectCanCollide
        end
        if respect and Part.CanCollide == false then
            return
        end
        if Part.CanQuery == false then
            return
        end
        local Pos = ToArr3(Part.Position or Part:GetAttribute("Position"))
        local Size = ToArr3(Part.Size or Part:GetAttribute("Size") or {4, 4, 4})
        local Shape = string.lower(tostring(Part.Shape or Part:GetAttribute("Shape") or "Block"))
        local T, N
        if Shape == "sphere" or Shape == "ball" then
            T, N = Geometry.IntersectSphere(Ro, Rd, Pos, Size)
        elseif Shape == "cylinder" then
            T, N = Geometry.IntersectCylinder(Ro, Rd, Pos, Size)
        else
            T, N = Geometry.IntersectAABB(Ro, Rd, Pos, {Size[1] * 0.5, Size[2] * 0.5, Size[3] * 0.5})
        end
        if T and T >= 0 and T <= BestT then
            BestT = T
            BestPart = Part
            BestNormal = N
        end
    end

    local function Traverse(Node)
        if Node.IsA and Node:IsA("BasePart") then
            CheckPart(Node)
        end
        local Children = rawget(Node, "Children")
        if Children then
            for _, C in ipairs(Children) do
                Traverse(C)
            end
        end
    end

    Traverse(Workspace)
    if not BestPart then
        return nil
    end
    local HitPos = {
        Ro[1] + Rd[1] * BestT,
        Ro[2] + Rd[2] * BestT,
        Ro[3] + Rd[3] * BestT,
    }
    return RaycastResult.new({
        Instance = BestPart,
        Position = Vector3.new(HitPos[1], HitPos[2], HitPos[3]),
        Normal = Vector3.new(BestNormal[1], BestNormal[2], BestNormal[3]),
        Distance = BestT,
    })
end

Geometry.ToArr3 = ToArr3

return Geometry

