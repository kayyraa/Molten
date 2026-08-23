local Vector3 = require("Services.Vector3")
local CFrame = require("Services.CFrame")
local Tools = require("Services.Tools")

local Gizmos = {}

Gizmos.SnapSize = 1
Gizmos.RotateSnapDeg = 15
Gizmos.HandleScreenLen = 80
Gizmos.HandleHitPad = 12
Gizmos.RingSegments = 64
Gizmos.RingWorldScale = 0.55
Gizmos.Space = "Local"

local AXIS = {
    X = {1, 0, 0, 1.00, 0.28, 0.28},
    Y = {0, 1, 0, 0.28, 1.00, 0.38},
    Z = {0, 0, 1, 0.32, 0.48, 1.00},
}
local AXIS_ORDER = { "Z", "Y", "X" }

local Active = nil
local Hover = nil

local Projector = {}
Projector.__index = Projector

function Projector.new(Camera)
    local Pos = Camera:GetAttribute("Position") or {0, 4, 0}
    local Rot = Camera:GetAttribute("Rotation") or {0, 0, 0}
    local FovDeg = Camera.FieldOfView or 105
    local Fov = math.rad(FovDeg)
    local Cf = CFrame.FromPositionRotation(Pos, Rot[1] or 0, Rot[2] or 0)
    local W, H = love.graphics.getDimensions()
    return setmetatable({
        Pos = Cf.Position,
        Forward = Cf.Forward,
        Right = Cf.Right,
        Up = Cf.Up,
        Fov = Fov,
        TanFov = math.tan(Fov * 0.5),
        W = W,
        H = H,
    }, Projector)
end

function Projector:Project(Wx, Wy, Wz)
    local Dx = Wx - self.Pos[1]
    local Dy = Wy - self.Pos[2]
    local Dz = Wz - self.Pos[3]
    local Z = Dx * self.Forward[1] + Dy * self.Forward[2] + Dz * self.Forward[3]
    if Z < 0.12 then
        return nil
    end
    local X = Dx * self.Right[1] + Dy * self.Right[2] + Dz * self.Right[3]
    local Y = Dx * self.Up[1] + Dy * self.Up[2] + Dz * self.Up[3]
    local Sx = self.W * 0.5 + (X / (Z * self.TanFov)) * self.H
    local Sy = self.H * 0.5 + (-Y / (Z * self.TanFov)) * self.H
    return Sx, Sy, Z
end

function Projector:ProjectV(V)
    return self:Project(V[1], V[2], V[3])
end

function Projector:Ray(ScreenX, ScreenY)
    local Uvx = (ScreenX - 0.5 * self.W) / self.H
    local Uvy = (ScreenY - 0.5 * self.H) / self.H
    local Rd = {
        self.Forward[1] + self.Right[1] * Uvx * self.TanFov - self.Up[1] * Uvy * self.TanFov,
        self.Forward[2] + self.Right[2] * Uvx * self.TanFov - self.Up[2] * Uvy * self.TanFov,
        self.Forward[3] + self.Right[3] * Uvx * self.TanFov - self.Up[3] * Uvy * self.TanFov,
    }
    local Len = math.sqrt(Rd[1] * Rd[1] + Rd[2] * Rd[2] + Rd[3] * Rd[3])
    if Len < 1e-8 then Len = 1 end
    return self.Pos, { Rd[1] / Len, Rd[2] / Len, Rd[3] / Len }
end

function Projector:WorldPerPixel(Depth)
    return (2 * Depth * self.TanFov) / self.H
end

Gizmos.Projector = Projector

local function ToArr3(V)
    if not V then return 0, 0, 0 end
    if type(V) == "table" and V.ToArray then
        local A = V:ToArray()
        return A[1] or 0, A[2] or 0, A[3] or 0
    end
    if type(V) == "table" then
        return tonumber(V[1] or V.Px or V.X) or 0,
               tonumber(V[2] or V.Py or V.Y) or 0,
               tonumber(V[3] or V.Pz or V.Z) or 0
    end
    return 0, 0, 0
end

local function GetSelection()
    local Part = nil
    if _G.SelectionHighlight and _G.SelectionHighlight.Adornee then
        Part = _G.SelectionHighlight.Adornee
    end
    if not Part and _G.SelectionSet then
        for N, _ in pairs(_G.SelectionSet) do
            if N and N.IsA and (N:IsA("BasePart") or N:IsA("Part")) then
                Part = N
                break
            end
        end
    end
    if Part and Part.IsA and (Part:IsA("BasePart") or Part:IsA("Part")) and Part.Locked ~= true then
        return Part
    end
    return nil
end

local function Snap(V, Size)
    Size = Size or Gizmos.SnapSize
    if not Size or Size <= 0 then return V end
    return math.floor(V / Size + 0.5) * Size
end

local function SnapDeg(Deg, Step)
    Step = Step or Gizmos.RotateSnapDeg
    if not Step or Step <= 0 then return Deg end
    return math.floor(Deg / Step + 0.5) * Step
end

local function Dist2(Ax, Ay, Bx, By)
    local Dx, Dy = Ax - Bx, Ay - By
    return Dx * Dx + Dy * Dy
end

local function DistPointSeg(Px, Py, X1, Y1, X2, Y2)
    local Dx, Dy = X2 - X1, Y2 - Y1
    local Len2 = Dx * Dx + Dy * Dy
    local T = 0
    if Len2 > 1e-8 then
        T = math.max(0, math.min(1, ((Px - X1) * Dx + (Py - Y1) * Dy) / Len2))
    end
    local Cx = X1 + T * Dx
    local Cy = Y1 + T * Dy
    return Dist2(Px, Py, Cx, Cy)
end

local function GetPartOrientation(Part)
    local Ox, Oy, Oz = ToArr3(Part.Orientation)
    return { Ox or 0, Oy or 0, Oz or 0 }
end

local function LocalAxisDir(Name, Orientation)
    local A = AXIS[Name]
    local Local = { A[1], A[2], A[3] }
    if Gizmos.Space == "Local" and Orientation then
        return CFrame.RotateByOrientation(Local, Orientation)
    end
    return Local
end

local function BuildHandles(Proj, Part, Tool)
    local Px, Py, Pz = ToArr3(Part.Position)
    local Ox, Oy, Depth = Proj:Project(Px, Py, Pz)
    if not Ox then return nil end

    local Ori = GetPartOrientation(Part)
    local AxisWorld = Proj:WorldPerPixel(Depth) * Gizmos.HandleScreenLen
    local Handles = {
        Origin = { Px, Py, Pz },
        OriginScreen = { Ox, Oy },
        Depth = Depth,
        AxisWorld = AxisWorld,
        Tool = Tool,
        Orientation = Ori,
        CamPos = { Proj.Pos[1], Proj.Pos[2], Proj.Pos[3] },
        Axes = {},
        Rings = {},
    }

    for _, Name in ipairs(AXIS_ORDER) do
        local A = AXIS[Name]
        local Dir = LocalAxisDir(Name, Ori)
        local Tip = {
            Px + Dir[1] * AxisWorld,
            Py + Dir[2] * AxisWorld,
            Pz + Dir[3] * AxisWorld,
        }
        local Tx, Ty = Proj:Project(Tip[1], Tip[2], Tip[3])
        if Tx then
            Handles.Axes[Name] = {
                Name = Name,
                Dir = Dir,
                Color = { A[4], A[5], A[6] },
                Tip = Tip,
                TipScreen = { Tx, Ty },
                BaseScreen = { Ox, Oy },
            }
        end
    end

    if Tool == "Rotate" then
        local Radius = AxisWorld * Gizmos.RingWorldScale
        for _, Name in ipairs(AXIS_ORDER) do
            local A = AXIS[Name]
            local AxisDir = LocalAxisDir(Name, Ori)
            local U, V
            if Name == "X" then
                U = LocalAxisDir("Y", Ori)
                V = LocalAxisDir("Z", Ori)
            elseif Name == "Y" then
                U = LocalAxisDir("X", Ori)
                V = LocalAxisDir("Z", Ori)
            else
                U = LocalAxisDir("X", Ori)
                V = LocalAxisDir("Y", Ori)
            end
            local Pts = {}
            local Segs = Gizmos.RingSegments
            for I = 0, Segs do
                local T = (I / Segs) * math.pi * 2
                local C, S = math.cos(T), math.sin(T)
                local Wx = Px + (U[1] * C + V[1] * S) * Radius
                local Wy = Py + (U[2] * C + V[2] * S) * Radius
                local Wz = Pz + (U[3] * C + V[3] * S) * Radius
                local Sx, Sy = Proj:Project(Wx, Wy, Wz)
                if Sx then
                    Pts[#Pts + 1] = { Sx, Sy }
                else
                    Pts[#Pts + 1] = nil
                end
            end
            Handles.Rings[Name] = {
                Name = Name,
                Color = { A[4], A[5], A[6] },
                Axis = AxisDir,
                Radius = Radius,
                Pts = Pts,
            }
        end
    end

    return Handles
end

local function HitTest(Handles, Mx, My, Tool)
    if not Handles then return nil end
    local Best, BestD = nil, (Gizmos.HandleHitPad + 2) ^ 2

    if Tool == "Move" or Tool == "Scale" then
        for _, Name in ipairs(AXIS_ORDER) do
            local Ax = Handles.Axes[Name]
            if Ax then
                local D = DistPointSeg(Mx, My, Ax.BaseScreen[1], Ax.BaseScreen[2], Ax.TipScreen[1], Ax.TipScreen[2])
                if D < BestD then
                    BestD = D
                    Best = { Mode = Tool, Axis = Name, Kind = "Axis" }
                end
                local DTip = Dist2(Mx, My, Ax.TipScreen[1], Ax.TipScreen[2])
                if DTip < BestD then
                    BestD = DTip
                    Best = { Mode = Tool, Axis = Name, Kind = "Axis" }
                end
            end
        end

        if Tool == "Move" then
            local Planes = {
                { "XY", "X", "Y" },
                { "XZ", "X", "Z" },
                { "YZ", "Y", "Z" },
            }
            local Ox, Oy = Handles.OriginScreen[1], Handles.OriginScreen[2]
            for _, Info in ipairs(Planes) do
                local A = Handles.Axes[Info[2]]
                local B = Handles.Axes[Info[3]]
                if A and B then
                    local Ax = Ox + (A.TipScreen[1] - Ox) * 0.32
                    local Ay = Oy + (A.TipScreen[2] - Oy) * 0.32
                    local Bx = Ox + (B.TipScreen[1] - Ox) * 0.32
                    local By = Oy + (B.TipScreen[2] - Oy) * 0.32
                    local Cx = Ax + (Bx - Ox)
                    local Cy = Ay + (By - Oy)
                    local Mxp = (Ox + Cx) * 0.5
                    local Myp = (Oy + Cy) * 0.5
                    local D = Dist2(Mx, My, Mxp, Myp)
                    if D < BestD and D < 16 * 16 then
                        BestD = D
                        Best = { Mode = "Move", Plane = Info[1], Kind = "Plane" }
                    end
                end
            end
        end
    elseif Tool == "Rotate" then
        for _, Name in ipairs(AXIS_ORDER) do
            local Ring = Handles.Rings[Name]
            if Ring then
                local Pts = Ring.Pts
                for I = 1, #Pts - 1 do
                    local P0, P1 = Pts[I], Pts[I + 1]
                    if P0 and P1 then
                        local D = DistPointSeg(Mx, My, P0[1], P0[2], P1[1], P1[2])
                        if D < BestD then
                            BestD = D
                            Best = { Mode = "Rotate", Axis = Name, Kind = "Ring" }
                        end
                    end
                end
            end
        end
    end
    return Best
end

local function ScreenAxisDelta(Proj, Handles, AxisName, Mx, My, StartMx, StartMy)
    local Ax = Handles.Axes[AxisName]
    if not Ax then return 0 end
    local Dx = Ax.TipScreen[1] - Ax.BaseScreen[1]
    local Dy = Ax.TipScreen[2] - Ax.BaseScreen[2]
    local Len = math.sqrt(Dx * Dx + Dy * Dy)
    if Len < 1e-4 then return 0 end
    Dx, Dy = Dx / Len, Dy / Len
    local Mdx = Mx - StartMx
    local Mdy = My - StartMy
    local PixelsAlong = Mdx * Dx + Mdy * Dy
    return PixelsAlong * Proj:WorldPerPixel(Handles.Depth)
end

local function PlaneHit(Proj, Mx, My, Origin, Plane, Orientation)
    local Ro, Rd = Proj:Ray(Mx, My)
    local N
    if Gizmos.Space == "Local" and Orientation then
        if Plane == "XY" then
            N = LocalAxisDir("Z", Orientation)
        elseif Plane == "XZ" then
            N = LocalAxisDir("Y", Orientation)
        else
            N = LocalAxisDir("X", Orientation)
        end
    else
        if Plane == "XY" then N = {0, 0, 1}
        elseif Plane == "XZ" then N = {0, 1, 0}
        else N = {1, 0, 0} end
    end
    local Denom = N[1] * Rd[1] + N[2] * Rd[2] + N[3] * Rd[3]
    if math.abs(Denom) < 1e-8 then return nil end
    local T = ((Origin[1] - Ro[1]) * N[1] + (Origin[2] - Ro[2]) * N[2] + (Origin[3] - Ro[3]) * N[3]) / Denom
    if T < 0.05 then return nil end
    return {
        Ro[1] + Rd[1] * T,
        Ro[2] + Rd[2] * T,
        Ro[3] + Rd[3] * T,
    }
end

local function PoseProxy(Pos, Size, Ori)
    return {
        Position = Vector3.new(Pos[1], Pos[2], Pos[3]),
        Size = Size,
        Orientation = Ori,
        IsA = function(_, C) return C == "BasePart" or C == "Part" end,
    }
end

function Gizmos.IsActive()
    return Active ~= nil
end

function Gizmos.GetHover()
    return Hover
end

function Gizmos.SetSpace(Space)
    if Space == "Local" or Space == "World" then
        Gizmos.Space = Space
    end
end

function Gizmos.MousePressed(Camera, Mx, My)
    local Tool = Tools:GetTool()
    if Tool ~= "Move" and Tool ~= "Scale" and Tool ~= "Rotate" then
        return false
    end
    local Part = GetSelection()
    if not Part then return false end

    local Proj = Projector.new(Camera)
    local Handles = BuildHandles(Proj, Part, Tool)
    local Hit = HitTest(Handles, Mx, My, Tool)
    if not Hit then return false end

    local Px, Py, Pz = ToArr3(Part.Position)
    local Sx, Sy, Sz = ToArr3(Part.Size)
    local Ox, Oy, Oz = ToArr3(Part.Orientation)
    local Ori = { Ox or 0, Oy or 0, Oz or 0 }

    if Part.ClassName == "UnionOperation" and type(rawget(Part, "SolidPieces")) == "table" then
        local Copy = {}
        for I = 1, #Part.SolidPieces do
            local Sp = Part.SolidPieces[I]
            Copy[I] = {
                Position = {(Sp.Position and Sp.Position[1]) or 0, (Sp.Position and Sp.Position[2]) or 0, (Sp.Position and Sp.Position[3]) or 0},
                Size = {(Sp.Size and Sp.Size[1]) or 1, (Sp.Size and Sp.Size[2]) or 1, (Sp.Size and Sp.Size[3]) or 1},
            }
        end
        rawset(Part, "_GizmoStartSolids", Copy)
    end

    Active = {
        Part = Part,
        Tool = Tool,
        Hit = Hit,
        StartPos = { Px, Py, Pz },
        StartSize = { Sx, Sy, Sz },
        StartOri = Ori,
        Origin = { Px, Py, Pz },
        Orientation = Ori,
        MouseStart = { Mx, My },
    }

    if Hit.Kind == "Plane" then
        Active.StartPlanePt = PlaneHit(Proj, Mx, My, Active.Origin, Hit.Plane, Ori)
    elseif Hit.Kind == "Ring" then
        local Oxs, Oys = Handles.OriginScreen[1], Handles.OriginScreen[2]
        Active.StartAngle = math.atan2(My - Oys, Mx - Oxs)
        Active.RingOriginScreen = { Oxs, Oys }
    elseif Hit.Kind == "Axis" then
        Active.StartAxisDelta = ScreenAxisDelta(Proj, Handles, Hit.Axis, Mx, My, Mx, My)
    end
    return true
end

function Gizmos.MouseMoved(Camera, Mx, My)
    local Tool = Tools:GetTool()
    if Tool ~= "Move" and Tool ~= "Scale" and Tool ~= "Rotate" then
        Hover = nil
        if not Active then return false end
    end

    local Proj = Projector.new(Camera)

    if not Active then
        local Part = GetSelection()
        if Part then
            local Handles = BuildHandles(Proj, Part, Tool)
            Hover = HitTest(Handles, Mx, My, Tool)
        else
            Hover = nil
        end
        return false
    end

    local Part = Active.Part
    if not Part then
        Active = nil
        return true
    end

    local StartHandles = BuildHandles(Proj, PoseProxy(Active.StartPos, Part.Size, Part.Orientation), Active.Tool)
    if not StartHandles then
        return true
    end

    if Active.Tool == "Move" then
        if Active.Hit.Kind == "Axis" then
            local Delta = ScreenAxisDelta(Proj, StartHandles, Active.Hit.Axis, Mx, My,
                Active.MouseStart[1], Active.MouseStart[2])
            local Dir = LocalAxisDir(Active.Hit.Axis, Active.Orientation)
            local Nx = Active.StartPos[1] + Dir[1] * Delta
            local Ny = Active.StartPos[2] + Dir[2] * Delta
            local Nz = Active.StartPos[3] + Dir[3] * Delta
            if math.abs(Dir[1]) > 0.5 then Nx = Snap(Nx) end
            if math.abs(Dir[2]) > 0.5 then Ny = Snap(Ny) end
            if math.abs(Dir[3]) > 0.5 then Nz = Snap(Nz) end
            Part.Position = Vector3.new(Nx, Ny, Nz)
        elseif Active.Hit.Kind == "Plane" and Active.StartPlanePt then
            local Pt = PlaneHit(Proj, Mx, My, Active.Origin, Active.Hit.Plane, Active.Orientation)
            if Pt then
                local Dx = Pt[1] - Active.StartPlanePt[1]
                local Dy = Pt[2] - Active.StartPlanePt[2]
                local Dz = Pt[3] - Active.StartPlanePt[3]
                local Nx = Active.StartPos[1] + Dx
                local Ny = Active.StartPos[2] + Dy
                local Nz = Active.StartPos[3] + Dz
                local Ax = LocalAxisDir("X", Active.Orientation)
                local Ay = LocalAxisDir("Y", Active.Orientation)
                local Az = LocalAxisDir("Z", Active.Orientation)
                local Plane = Active.Hit.Plane
                local Off = { Dx, Dy, Dz }
                local function Dot(A, B) return A[1]*B[1] + A[2]*B[2] + A[3]*B[3] end
                if Plane == "XY" then
                    local AlongZ = Dot(Off, Az)
                    Nx = Nx - Az[1] * AlongZ
                    Ny = Ny - Az[2] * AlongZ
                    Nz = Nz - Az[3] * AlongZ
                elseif Plane == "XZ" then
                    local AlongY = Dot(Off, Ay)
                    Nx = Nx - Ay[1] * AlongY
                    Ny = Ny - Ay[2] * AlongY
                    Nz = Nz - Ay[3] * AlongY
                else
                    local AlongX = Dot(Off, Ax)
                    Nx = Nx - Ax[1] * AlongX
                    Ny = Ny - Ax[2] * AlongX
                    Nz = Nz - Ax[3] * AlongX
                end
                Part.Position = Vector3.new(Snap(Nx), Snap(Ny), Snap(Nz))
            end
        end
    elseif Active.Tool == "Scale" and Active.Hit.Kind == "Axis" then
        local Delta = ScreenAxisDelta(Proj, StartHandles, Active.Hit.Axis, Mx, My,
            Active.MouseStart[1], Active.MouseStart[2])
        local Dir = LocalAxisDir(Active.Hit.Axis, Active.Orientation)
        local Nx, Ny, Nz = Active.StartSize[1], Active.StartSize[2], Active.StartSize[3]
        local Axis = Active.Hit.Axis
        if Axis == "X" then Nx = math.max(0.2, Snap(Active.StartSize[1] + Delta)) end
        if Axis == "Y" then Ny = math.max(0.2, Snap(Active.StartSize[2] + Delta)) end
        if Axis == "Z" then Nz = math.max(0.2, Snap(Active.StartSize[3] + Delta)) end
        Part.Size = Vector3.new(Nx, Ny, Nz)
        ScaleUnionSolids(Part, Active.StartSize, {Nx, Ny, Nz})
        local Ddx = (Nx - Active.StartSize[1]) * 0.5
        local Ddy = (Ny - Active.StartSize[2]) * 0.5
        local Ddz = (Nz - Active.StartSize[3]) * 0.5
        local LocalOff = { Ddx, Ddy, Ddz }
        local WorldOff = CFrame.RotateByOrientation(LocalOff, Active.Orientation)
        Part.Position = Vector3.new(
            Active.StartPos[1] + WorldOff[1],
            Active.StartPos[2] + WorldOff[2],
            Active.StartPos[3] + WorldOff[3]
        )
    elseif Active.Tool == "Rotate" and Active.Hit.Kind == "Ring" then
        local Oxs = Active.RingOriginScreen[1]
        local Oys = Active.RingOriginScreen[2]
        local Ang = math.atan2(My - Oys, Mx - Oxs)
        local Delta = Ang - Active.StartAngle
        local Deg = Delta * 180 / math.pi
        if Active.Hit.Axis == "Z" then
            Deg = -Deg
        end
        Deg = SnapDeg(Deg)
        local Ori = {
            Active.StartOri[1],
            Active.StartOri[2],
            Active.StartOri[3],
        }
        if Active.Hit.Axis == "X" then Ori[1] = Active.StartOri[1] + Deg
        elseif Active.Hit.Axis == "Y" then Ori[2] = Active.StartOri[2] - Deg
        else Ori[3] = Active.StartOri[3] + Deg end
        Part.Orientation = Vector3.new(Ori[1], Ori[2], Ori[3])
    end

    pcall(function()
        require("Services.Visuals").Invalidate()
    end)
    return true
end

function Gizmos.MouseReleased()
    local Was = Active ~= nil
    Active = nil
    return Was
end

local function DrawArrow(X1, Y1, X2, Y2, R, G, B, Thick, Alpha)
    love.graphics.setColor(R, G, B, Alpha or 1)
    love.graphics.setLineWidth(Thick or 2.5)
    love.graphics.line(X1, Y1, X2, Y2)
    local Dx, Dy = X2 - X1, Y2 - Y1
    local Len = math.sqrt(Dx * Dx + Dy * Dy)
    if Len < 1 then
        love.graphics.setLineWidth(1)
        return
    end
    Dx, Dy = Dx / Len, Dy / Len
    local Px, Py = -Dy, Dx
    local Hs = 10
    love.graphics.polygon("fill",
        X2, Y2,
        X2 - Dx * Hs + Px * Hs * 0.5,
        Y2 - Dy * Hs + Py * Hs * 0.5,
        X2 - Dx * Hs - Px * Hs * 0.5,
        Y2 - Dy * Hs - Py * Hs * 0.5
    )
    love.graphics.setLineWidth(1)
end

local function DrawAxisArrow(Ax, Highlighted)
    local Thick = Highlighted and 4.0 or 2.4
    local Alpha = Highlighted and 1.0 or 0.88
    DrawArrow(
        Ax.BaseScreen[1], Ax.BaseScreen[2],
        Ax.TipScreen[1], Ax.TipScreen[2],
        Ax.Color[1], Ax.Color[2], Ax.Color[3],
        Thick, Alpha
    )
end

local function DrawRing(Ring, Highlighted)
    local Pts = Ring.Pts
    local Thick = Highlighted and 3.6 or 2.0
    local Alpha = Highlighted and 1.0 or 0.8
    love.graphics.setColor(Ring.Color[1], Ring.Color[2], Ring.Color[3], Alpha)
    love.graphics.setLineWidth(Thick)
    for I = 1, #Pts - 1 do
        local P0, P1 = Pts[I], Pts[I + 1]
        if P0 and P1 then
            love.graphics.line(P0[1], P0[2], P1[1], P1[2])
        end
    end
    love.graphics.setLineWidth(1)
end

function Gizmos.Render(Camera)
    if not Camera then return end
    local Tool = Tools:GetTool()
    if Tool ~= "Move" and Tool ~= "Scale" and Tool ~= "Rotate" then
        return
    end
    local Part = GetSelection()
    if not Part then return end

    local Proj = Projector.new(Camera)
    local Handles = BuildHandles(Proj, Part, Tool)
    if not Handles then return end

    local TopAxis = nil
    local TopPlane = nil
    if Active and Active.Hit then
        TopAxis = Active.Hit.Axis
        TopPlane = Active.Hit.Plane
    elseif Hover then
        TopAxis = Hover.Axis
        TopPlane = Hover.Plane
    end

    if Tool == "Move" or Tool == "Scale" then
        if Tool == "Move" then
            local Planes = {
                XY = { "X", "Y", 1, 1, 0.25 },
                XZ = { "X", "Z", 1, 0.35, 1 },
                YZ = { "Y", "Z", 0.25, 1, 1 },
            }
            local Ox, Oy = Handles.OriginScreen[1], Handles.OriginScreen[2]
            for PlaneName, Info in pairs(Planes) do
                if PlaneName ~= TopPlane then
                    local A = Handles.Axes[Info[1]]
                    local B = Handles.Axes[Info[2]]
                    if A and B then
                        local Ax = Ox + (A.TipScreen[1] - Ox) * 0.32
                        local Ay = Oy + (A.TipScreen[2] - Oy) * 0.32
                        local Bx = Ox + (B.TipScreen[1] - Ox) * 0.32
                        local By = Oy + (B.TipScreen[2] - Oy) * 0.32
                        local Cx = Ax + (Bx - Ox)
                        local Cy = Ay + (By - Oy)
                        love.graphics.setColor(Info[3], Info[4], Info[5], 0.18)
                        love.graphics.polygon("fill", Ox, Oy, Ax, Ay, Cx, Cy, Bx, By)
                        love.graphics.setColor(Info[3], Info[4], Info[5], 0.55)
                        love.graphics.setLineWidth(1)
                        love.graphics.polygon("line", Ox, Oy, Ax, Ay, Cx, Cy, Bx, By)
                    end
                end
            end
        end

        for _, Name in ipairs(AXIS_ORDER) do
            local Ax = Handles.Axes[Name]
            if Ax and Name ~= TopAxis then
                DrawAxisArrow(Ax, false)
                if Tool == "Scale" then
                    love.graphics.setColor(Ax.Color[1], Ax.Color[2], Ax.Color[3], 0.9)
                    love.graphics.rectangle("fill",
                        Ax.TipScreen[1] - 5, Ax.TipScreen[2] - 5, 10, 10)
                end
            end
        end

        local Ox, Oy = Handles.OriginScreen[1], Handles.OriginScreen[2]
        love.graphics.setColor(0.95, 0.95, 0.25, 1)
        love.graphics.rectangle("fill", Ox - 4, Oy - 4, 8, 8)

        if Tool == "Move" and TopPlane then
            local Planes = {
                XY = { "X", "Y", 1, 1, 0.25 },
                XZ = { "X", "Z", 1, 0.35, 1 },
                YZ = { "Y", "Z", 0.25, 1, 1 },
            }
            local Info = Planes[TopPlane]
            local A = Handles.Axes[Info[1]]
            local B = Handles.Axes[Info[2]]
            if A and B then
                local Ax = Ox + (A.TipScreen[1] - Ox) * 0.32
                local Ay = Oy + (A.TipScreen[2] - Oy) * 0.32
                local Bx = Ox + (B.TipScreen[1] - Ox) * 0.32
                local By = Oy + (B.TipScreen[2] - Oy) * 0.32
                local Cx = Ax + (Bx - Ox)
                local Cy = Ay + (By - Oy)
                love.graphics.setColor(Info[3], Info[4], Info[5], 0.55)
                love.graphics.polygon("fill", Ox, Oy, Ax, Ay, Cx, Cy, Bx, By)
                love.graphics.setColor(Info[3], Info[4], Info[5], 1)
                love.graphics.setLineWidth(2)
                love.graphics.polygon("line", Ox, Oy, Ax, Ay, Cx, Cy, Bx, By)
                love.graphics.setLineWidth(1)
            end
        end

        if TopAxis and Handles.Axes[TopAxis] then
            local Ax = Handles.Axes[TopAxis]
            DrawAxisArrow(Ax, true)
            if Tool == "Scale" then
                love.graphics.setColor(Ax.Color[1], Ax.Color[2], Ax.Color[3], 1)
                love.graphics.rectangle("fill",
                    Ax.TipScreen[1] - 6, Ax.TipScreen[2] - 6, 12, 12)
            end
        end

    elseif Tool == "Rotate" then
        for _, Name in ipairs(AXIS_ORDER) do
            local Ring = Handles.Rings[Name]
            if Ring and Name ~= TopAxis then
                DrawRing(Ring, false)
            end
        end
        local Ox, Oy = Handles.OriginScreen[1], Handles.OriginScreen[2]
        love.graphics.setColor(0.95, 0.95, 0.25, 1)
        love.graphics.rectangle("fill", Ox - 4, Oy - 4, 8, 8)
        if TopAxis and Handles.Rings[TopAxis] then
            DrawRing(Handles.Rings[TopAxis], true)
        end
    end
end

_G.Gizmos = Gizmos
return Gizmos