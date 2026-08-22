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

local AXIS = {
    X = {1, 0, 0, 1.00, 0.28, 0.28},
    Y = {0, 1, 0, 0.28, 1.00, 0.38},
    Z = {0, 0, 1, 0.32, 0.48, 1.00},
}
local AXIS_ORDER = { "X", "Y", "Z" }

local Active = nil
local Hover = nil

-- ===========================================================================
-- Projector (OOP world ↔ screen, same math as Pixel shader)
-- ===========================================================================

local Projector = {}
Projector.__index = Projector

function Projector.new(Camera)
    local Pos = Camera:GetAttribute("Position") or {0, 4, 0}
    local Rot = Camera:GetAttribute("Rotation") or {0, 0, 0}
    local Fov = Camera:GetAttribute("Fov") or (math.pi / 1.75)
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

-- World → screen. Inverse of:
--   Uv = (Screen - 0.5*Res) / Res.y
--   Ray = normalize(Fwd + Right*Uv.x*TanFov - Up*Uv.y*TanFov)
function Projector:Project(wx, wy, wz)
    local dx = wx - self.Pos[1]
    local dy = wy - self.Pos[2]
    local dz = wz - self.Pos[3]
    local z = dx * self.Forward[1] + dy * self.Forward[2] + dz * self.Forward[3]
    if z < 0.12 then
        return nil
    end
    local x = dx * self.Right[1] + dy * self.Right[2] + dz * self.Right[3]
    local y = dx * self.Up[1] + dy * self.Up[2] + dz * self.Up[3]
    local sx = self.W * 0.5 + (x / (z * self.TanFov)) * self.H
    local sy = self.H * 0.5 + (-y / (z * self.TanFov)) * self.H
    return sx, sy, z
end

function Projector:ProjectV(v)
    return self:Project(v[1], v[2], v[3])
end

function Projector:Ray(screenX, screenY)
    local uvx = (screenX - 0.5 * self.W) / self.H
    local uvy = (screenY - 0.5 * self.H) / self.H
    local rd = {
        self.Forward[1] + self.Right[1] * uvx * self.TanFov - self.Up[1] * uvy * self.TanFov,
        self.Forward[2] + self.Right[2] * uvx * self.TanFov - self.Up[2] * uvy * self.TanFov,
        self.Forward[3] + self.Right[3] * uvx * self.TanFov - self.Up[3] * uvy * self.TanFov,
    }
    local len = math.sqrt(rd[1] * rd[1] + rd[2] * rd[2] + rd[3] * rd[3])
    if len < 1e-8 then len = 1 end
    return self.Pos, { rd[1] / len, rd[2] / len, rd[3] / len }
end

function Projector:WorldPerPixel(depth)
    return (2 * depth * self.TanFov) / self.H
end

Gizmos.Projector = Projector

-- ===========================================================================
-- Helpers
-- ===========================================================================

local function ToArr3(v)
    if not v then return 0, 0, 0 end
    if type(v) == "table" and v.ToArray then
        local a = v:ToArray()
        return a[1] or 0, a[2] or 0, a[3] or 0
    end
    if type(v) == "table" then
        return tonumber(v[1] or v.Px or v.X) or 0,
               tonumber(v[2] or v.Py or v.Y) or 0,
               tonumber(v[3] or v.Pz or v.Z) or 0
    end
    return 0, 0, 0
end

local function GetSelection()
    local part = nil
    if _G.SelectionHighlight and _G.SelectionHighlight.Adornee then
        part = _G.SelectionHighlight.Adornee
    end
    if not part and _G.SelectionSet then
        for n, _ in pairs(_G.SelectionSet) do
            if n and n.IsA and (n:IsA("BasePart") or n:IsA("Part")) then
                part = n
                break
            end
        end
    end
    if part and part.IsA and (part:IsA("BasePart") or part:IsA("Part")) and part.Locked ~= true then
        return part
    end
    return nil
end

local function Snap(v, size)
    size = size or Gizmos.SnapSize
    if not size or size <= 0 then return v end
    return math.floor(v / size + 0.5) * size
end

local function SnapDeg(deg, step)
    step = step or Gizmos.RotateSnapDeg
    if not step or step <= 0 then return deg end
    return math.floor(deg / step + 0.5) * step
end

local function Dist2(ax, ay, bx, by)
    local dx, dy = ax - bx, ay - by
    return dx * dx + dy * dy
end

local function DistPointSeg(px, py, x1, y1, x2, y2)
    local dx, dy = x2 - x1, y2 - y1
    local len2 = dx * dx + dy * dy
    local t = 0
    if len2 > 1e-8 then
        t = math.max(0, math.min(1, ((px - x1) * dx + (py - y1) * dy) / len2))
    end
    local cx = x1 + t * dx
    local cy = y1 + t * dy
    return Dist2(px, py, cx, cy)
end

-- ===========================================================================
-- Handle geometry
-- ===========================================================================

local function BuildHandles(proj, part, tool)
    local px, py, pz = ToArr3(part.Position)
    local ox, oy, depth = proj:Project(px, py, pz)
    if not ox then return nil end

    local axisWorld = proj:WorldPerPixel(depth) * Gizmos.HandleScreenLen
    local handles = {
        origin = { px, py, pz },
        originScreen = { ox, oy },
        depth = depth,
        axisWorld = axisWorld,
        tool = tool,
        axes = {},
        rings = {},
    }

    for _, name in ipairs(AXIS_ORDER) do
        local a = AXIS[name]
        local tip = {
            px + a[1] * axisWorld,
            py + a[2] * axisWorld,
            pz + a[3] * axisWorld,
        }
        local tx, ty = proj:Project(tip[1], tip[2], tip[3])
        if tx then
            handles.axes[name] = {
                name = name,
                dir = { a[1], a[2], a[3] },
                color = { a[4], a[5], a[6] },
                tip = tip,
                tipScreen = { tx, ty },
                baseScreen = { ox, oy },
            }
        end
    end

    if tool == "Rotate" then
        local radius = axisWorld * Gizmos.RingWorldScale
        for _, name in ipairs(AXIS_ORDER) do
            local a = AXIS[name]
            local pts = {}
            local segs = Gizmos.RingSegments
            local ux, uy, uz, vx, vy, vz
            if name == "X" then
                ux, uy, uz = 0, 1, 0
                vx, vy, vz = 0, 0, 1
            elseif name == "Y" then
                ux, uy, uz = 1, 0, 0
                vx, vy, vz = 0, 0, 1
            else
                ux, uy, uz = 1, 0, 0
                vx, vy, vz = 0, 1, 0
            end
            for i = 0, segs do
                local t = (i / segs) * math.pi * 2
                local c, s = math.cos(t), math.sin(t)
                local wx = px + (ux * c + vx * s) * radius
                local wy = py + (uy * c + vy * s) * radius
                local wz = pz + (uz * c + vz * s) * radius
                local sx, sy = proj:Project(wx, wy, wz)
                if sx then
                    pts[#pts + 1] = { sx, sy }
                else
                    pts[#pts + 1] = nil
                end
            end
            handles.rings[name] = {
                name = name,
                color = { a[4], a[5], a[6] },
                axis = { a[1], a[2], a[3] },
                radius = radius,
                pts = pts,
            }
        end
    end

    return handles
end

local function HitTest(handles, mx, my, tool)
    if not handles then return nil end
    local best, bestD = nil, (Gizmos.HandleHitPad + 2) ^ 2

    if tool == "Move" or tool == "Scale" then
        for _, name in ipairs(AXIS_ORDER) do
            local ax = handles.axes[name]
            if ax then
                local d = DistPointSeg(mx, my, ax.baseScreen[1], ax.baseScreen[2], ax.tipScreen[1], ax.tipScreen[2])
                if d < bestD then
                    bestD = d
                    best = { mode = tool, axis = name, kind = "axis" }
                end
                local dTip = Dist2(mx, my, ax.tipScreen[1], ax.tipScreen[2])
                if dTip < bestD then
                    bestD = dTip
                    best = { mode = tool, axis = name, kind = "axis" }
                end
            end
        end

        if tool == "Move" then
            local planes = {
                { "XY", "X", "Y" },
                { "XZ", "X", "Z" },
                { "YZ", "Y", "Z" },
            }
            local ox, oy = handles.originScreen[1], handles.originScreen[2]
            for _, info in ipairs(planes) do
                local a = handles.axes[info[2]]
                local b = handles.axes[info[3]]
                if a and b then
                    local ax = ox + (a.tipScreen[1] - ox) * 0.32
                    local ay = oy + (a.tipScreen[2] - oy) * 0.32
                    local bx = ox + (b.tipScreen[1] - ox) * 0.32
                    local by = oy + (b.tipScreen[2] - oy) * 0.32
                    local cx = ax + (bx - ox)
                    local cy = ay + (by - oy)
                    local mxp = (ox + cx) * 0.5
                    local myp = (oy + cy) * 0.5
                    local d = Dist2(mx, my, mxp, myp)
                    if d < bestD and d < 16 * 16 then
                        bestD = d
                        best = { mode = "Move", plane = info[1], kind = "plane" }
                    end
                end
            end
        end
    elseif tool == "Rotate" then
        for _, name in ipairs(AXIS_ORDER) do
            local ring = handles.rings[name]
            if ring then
                local pts = ring.pts
                for i = 1, #pts - 1 do
                    local p0, p1 = pts[i], pts[i + 1]
                    if p0 and p1 then
                        local d = DistPointSeg(mx, my, p0[1], p0[2], p1[1], p1[2])
                        if d < bestD then
                            bestD = d
                            best = { mode = "Rotate", axis = name, kind = "ring" }
                        end
                    end
                end
            end
        end
    end
    return best
end

local function ScreenAxisDelta(proj, handles, axisName, mx, my, startMx, startMy)
    local ax = handles.axes[axisName]
    if not ax then return 0 end
    local dx = ax.tipScreen[1] - ax.baseScreen[1]
    local dy = ax.tipScreen[2] - ax.baseScreen[2]
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 1e-4 then return 0 end
    dx, dy = dx / len, dy / len
    local mdx = mx - startMx
    local mdy = my - startMy
    local pixelsAlong = mdx * dx + mdy * dy
    return pixelsAlong * proj:WorldPerPixel(handles.depth)
end

local function PlaneHit(proj, mx, my, origin, plane)
    local Ro, Rd = proj:Ray(mx, my)
    local n
    if plane == "XY" then n = {0, 0, 1}
    elseif plane == "XZ" then n = {0, 1, 0}
    else n = {1, 0, 0} end
    local denom = n[1] * Rd[1] + n[2] * Rd[2] + n[3] * Rd[3]
    if math.abs(denom) < 1e-8 then return nil end
    local t = ((origin[1] - Ro[1]) * n[1] + (origin[2] - Ro[2]) * n[2] + (origin[3] - Ro[3]) * n[3]) / denom
    if t < 0.05 then return nil end
    return {
        Ro[1] + Rd[1] * t,
        Ro[2] + Rd[2] * t,
        Ro[3] + Rd[3] * t,
    }
end

local function PoseProxy(pos, size, ori)
    return {
        Position = Vector3.new(pos[1], pos[2], pos[3]),
        Size = size,
        Orientation = ori,
        IsA = function(_, c) return c == "BasePart" or c == "Part" end,
    }
end

-- ===========================================================================
-- Input
-- ===========================================================================

function Gizmos.IsActive()
    return Active ~= nil
end

function Gizmos.GetHover()
    return Hover
end

function Gizmos.MousePressed(Camera, mx, my)
    local tool = Tools:GetTool()
    if tool ~= "Move" and tool ~= "Scale" and tool ~= "Rotate" then
        return false
    end
    local part = GetSelection()
    if not part then return false end

    local proj = Projector.new(Camera)
    local handles = BuildHandles(proj, part, tool)
    local hit = HitTest(handles, mx, my, tool)
    if not hit then return false end

    local px, py, pz = ToArr3(part.Position)
    local sx, sy, sz = ToArr3(part.Size)
    local ox, oy, oz = ToArr3(part.Orientation)

    Active = {
        part = part,
        tool = tool,
        hit = hit,
        startPos = { px, py, pz },
        startSize = { sx, sy, sz },
        startOri = { ox or 0, oy or 0, oz or 0 },
        origin = { px, py, pz },
        mouseStart = { mx, my },
    }

    if hit.kind == "plane" then
        Active.startPlanePt = PlaneHit(proj, mx, my, Active.origin, hit.plane)
    elseif hit.kind == "ring" then
        local oxs, oys = handles.originScreen[1], handles.originScreen[2]
        Active.startAngle = math.atan2(my - oys, mx - oxs)
        Active.ringOriginScreen = { oxs, oys }
    end
    return true
end

function Gizmos.MouseMoved(Camera, mx, my)
    local tool = Tools:GetTool()
    if tool ~= "Move" and tool ~= "Scale" and tool ~= "Rotate" then
        Hover = nil
        if not Active then return false end
    end

    local proj = Projector.new(Camera)

    if not Active then
        local part = GetSelection()
        if part then
            local handles = BuildHandles(proj, part, tool)
            Hover = HitTest(handles, mx, my, tool)
        else
            Hover = nil
        end
        return false
    end

    local part = Active.part
    if not part then
        Active = nil
        return true
    end

    local startHandles = BuildHandles(proj, PoseProxy(Active.startPos, part.Size, part.Orientation), Active.tool)
    if not startHandles then
        return true
    end

    if Active.tool == "Move" then
        if Active.hit.kind == "axis" then
            local delta = ScreenAxisDelta(proj, startHandles, Active.hit.axis, mx, my,
                Active.mouseStart[1], Active.mouseStart[2])
            local dir = AXIS[Active.hit.axis]
            local nx = Active.startPos[1] + dir[1] * delta
            local ny = Active.startPos[2] + dir[2] * delta
            local nz = Active.startPos[3] + dir[3] * delta
            if dir[1] ~= 0 then nx = Snap(nx) end
            if dir[2] ~= 0 then ny = Snap(ny) end
            if dir[3] ~= 0 then nz = Snap(nz) end
            part.Position = Vector3.new(nx, ny, nz)
        elseif Active.hit.kind == "plane" and Active.startPlanePt then
            local pt = PlaneHit(proj, mx, my, Active.origin, Active.hit.plane)
            if pt then
                local dx = pt[1] - Active.startPlanePt[1]
                local dy = pt[2] - Active.startPlanePt[2]
                local dz = pt[3] - Active.startPlanePt[3]
                local plane = Active.hit.plane
                local nx = Active.startPos[1] + dx
                local ny = Active.startPos[2] + dy
                local nz = Active.startPos[3] + dz
                if plane == "XY" then
                    nz = Active.startPos[3]
                    nx, ny = Snap(nx), Snap(ny)
                elseif plane == "XZ" then
                    ny = Active.startPos[2]
                    nx, nz = Snap(nx), Snap(nz)
                else
                    nx = Active.startPos[1]
                    ny, nz = Snap(ny), Snap(nz)
                end
                part.Position = Vector3.new(nx, ny, nz)
            end
        end
    elseif Active.tool == "Scale" and Active.hit.kind == "axis" then
        local delta = ScreenAxisDelta(proj, startHandles, Active.hit.axis, mx, my,
            Active.mouseStart[1], Active.mouseStart[2])
        local dir = AXIS[Active.hit.axis]
        local nx, ny, nz = Active.startSize[1], Active.startSize[2], Active.startSize[3]
        if dir[1] ~= 0 then nx = math.max(0.2, Snap(Active.startSize[1] + delta)) end
        if dir[2] ~= 0 then ny = math.max(0.2, Snap(Active.startSize[2] + delta)) end
        if dir[3] ~= 0 then nz = math.max(0.2, Snap(Active.startSize[3] + delta)) end
        part.Size = Vector3.new(nx, ny, nz)
        local ddx = (nx - Active.startSize[1]) * 0.5 * dir[1]
        local ddy = (ny - Active.startSize[2]) * 0.5 * dir[2]
        local ddz = (nz - Active.startSize[3]) * 0.5 * dir[3]
        part.Position = Vector3.new(
            Active.startPos[1] + ddx,
            Active.startPos[2] + ddy,
            Active.startPos[3] + ddz
        )
    elseif Active.tool == "Rotate" and Active.hit.kind == "ring" then
        local oxs = Active.ringOriginScreen[1]
        local oys = Active.ringOriginScreen[2]
        local ang = math.atan2(my - oys, mx - oxs)
        local delta = ang - Active.startAngle
        local deg = delta * 180 / math.pi
        if Active.hit.axis == "X" or Active.hit.axis == "Z" then
            deg = -deg
        end
        deg = SnapDeg(deg)
        local ori = {
            Active.startOri[1],
            Active.startOri[2],
            Active.startOri[3],
        }
        if Active.hit.axis == "X" then ori[1] = Active.startOri[1] + deg
        elseif Active.hit.axis == "Y" then ori[2] = Active.startOri[2] + deg
        else ori[3] = Active.startOri[3] + deg end
        part.Orientation = Vector3.new(ori[1], ori[2], ori[3])
    end

    pcall(function()
        require("Services.Visuals").Invalidate()
    end)
    return true
end

function Gizmos.MouseReleased()
    local was = Active ~= nil
    Active = nil
    return was
end

-- ===========================================================================
-- Drawing — non-hovered first, hovered / active last (highest z)
-- ===========================================================================

local function DrawArrow(x1, y1, x2, y2, r, g, b, thick, alpha)
    love.graphics.setColor(r, g, b, alpha or 1)
    love.graphics.setLineWidth(thick or 2.5)
    love.graphics.line(x1, y1, x2, y2)
    local dx, dy = x2 - x1, y2 - y1
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 1 then
        love.graphics.setLineWidth(1)
        return
    end
    dx, dy = dx / len, dy / len
    local px, py = -dy, dx
    local hs = 10
    love.graphics.polygon("fill",
        x2, y2,
        x2 - dx * hs + px * hs * 0.5,
        y2 - dy * hs + py * hs * 0.5,
        x2 - dx * hs - px * hs * 0.5,
        y2 - dy * hs - py * hs * 0.5
    )
    love.graphics.setLineWidth(1)
end

local function DrawAxisArrow(ax, highlighted)
    local thick = highlighted and 4.0 or 2.4
    local alpha = highlighted and 1.0 or 0.88
    DrawArrow(
        ax.baseScreen[1], ax.baseScreen[2],
        ax.tipScreen[1], ax.tipScreen[2],
        ax.color[1], ax.color[2], ax.color[3],
        thick, alpha
    )
end

local function DrawRing(ring, highlighted)
    local pts = ring.pts
    local thick = highlighted and 3.6 or 2.0
    local alpha = highlighted and 1.0 or 0.8
    love.graphics.setColor(ring.color[1], ring.color[2], ring.color[3], alpha)
    love.graphics.setLineWidth(thick)
    for i = 1, #pts - 1 do
        local p0, p1 = pts[i], pts[i + 1]
        if p0 and p1 then
            love.graphics.line(p0[1], p0[2], p1[1], p1[2])
        end
    end
    love.graphics.setLineWidth(1)
end

function Gizmos.Render(Camera)
    if not Camera then return end
    local tool = Tools:GetTool()
    if tool ~= "Move" and tool ~= "Scale" and tool ~= "Rotate" then
        return
    end
    local part = GetSelection()
    if not part then return end

    local proj = Projector.new(Camera)
    local handles = BuildHandles(proj, part, tool)
    if not handles then return end

    local hoverAxis = Hover and Hover.axis
    local hoverPlane = Hover and Hover.plane
    local activeAxis = Active and Active.hit and Active.hit.axis
    local activePlane = Active and Active.hit and Active.hit.plane
    local topAxis = activeAxis or hoverAxis
    local topPlane = activePlane or hoverPlane

    if tool == "Move" or tool == "Scale" then
        -- 1) non-top planes under everything
        if tool == "Move" then
            local ox, oy = handles.originScreen[1], handles.originScreen[2]
            local planes = {
                { "XY", "X", "Y", 1, 1, 0.25 },
                { "XZ", "X", "Z", 1, 0.35, 1 },
                { "YZ", "Y", "Z", 0.25, 1, 1 },
            }
            for _, info in ipairs(planes) do
                local a = handles.axes[info[2]]
                local b = handles.axes[info[3]]
                if a and b and info[1] ~= topPlane then
                    local ax = ox + (a.tipScreen[1] - ox) * 0.32
                    local ay = oy + (a.tipScreen[2] - oy) * 0.32
                    local bx = ox + (b.tipScreen[1] - ox) * 0.32
                    local by = oy + (b.tipScreen[2] - oy) * 0.32
                    local cx = ax + (bx - ox)
                    local cy = ay + (by - oy)
                    love.graphics.setColor(info[4], info[5], info[6], 0.18)
                    love.graphics.polygon("fill", ox, oy, ax, ay, cx, cy, bx, by)
                    love.graphics.setColor(info[4], info[5], info[6], 0.55)
                    love.graphics.setLineWidth(1.2)
                    love.graphics.polygon("line", ox, oy, ax, ay, cx, cy, bx, by)
                    love.graphics.setLineWidth(1)
                end
            end
        end

        -- 2) non-hovered axes
        for _, name in ipairs(AXIS_ORDER) do
            local ax = handles.axes[name]
            if ax and name ~= topAxis then
                DrawAxisArrow(ax, false)
                if tool == "Scale" then
                    love.graphics.setColor(ax.color[1], ax.color[2], ax.color[3], 0.9)
                    love.graphics.rectangle("fill",
                        ax.tipScreen[1] - 5, ax.tipScreen[2] - 5, 10, 10)
                end
            end
        end

        -- 3) center marker
        local ox, oy = handles.originScreen[1], handles.originScreen[2]
        love.graphics.setColor(0.95, 0.95, 0.25, 1)
        love.graphics.rectangle("fill", ox - 4, oy - 4, 8, 8)

        -- 4) hovered / active plane on top of other planes
        if tool == "Move" and topPlane then
            local planes = {
                XY = { "X", "Y", 1, 1, 0.25 },
                XZ = { "X", "Z", 1, 0.35, 1 },
                YZ = { "Y", "Z", 0.25, 1, 1 },
            }
            local info = planes[topPlane]
            local a = handles.axes[info[1]]
            local b = handles.axes[info[2]]
            if a and b then
                local ax = ox + (a.tipScreen[1] - ox) * 0.32
                local ay = oy + (a.tipScreen[2] - oy) * 0.32
                local bx = ox + (b.tipScreen[1] - ox) * 0.32
                local by = oy + (b.tipScreen[2] - oy) * 0.32
                local cx = ax + (bx - ox)
                local cy = ay + (by - oy)
                love.graphics.setColor(info[3], info[4], info[5], 0.55)
                love.graphics.polygon("fill", ox, oy, ax, ay, cx, cy, bx, by)
                love.graphics.setColor(info[3], info[4], info[5], 1)
                love.graphics.setLineWidth(2)
                love.graphics.polygon("line", ox, oy, ax, ay, cx, cy, bx, by)
                love.graphics.setLineWidth(1)
            end
        end

        -- 5) hovered / active axis LAST (highest z)
        if topAxis and handles.axes[topAxis] then
            local ax = handles.axes[topAxis]
            DrawAxisArrow(ax, true)
            if tool == "Scale" then
                love.graphics.setColor(ax.color[1], ax.color[2], ax.color[3], 1)
                love.graphics.rectangle("fill",
                    ax.tipScreen[1] - 6, ax.tipScreen[2] - 6, 12, 12)
            end
        end

    elseif tool == "Rotate" then
        -- non-hovered rings first
        for _, name in ipairs(AXIS_ORDER) do
            local ring = handles.rings[name]
            if ring and name ~= topAxis then
                DrawRing(ring, false)
            end
        end
        -- center
        local ox, oy = handles.originScreen[1], handles.originScreen[2]
        love.graphics.setColor(0.95, 0.95, 0.25, 1)
        love.graphics.circle("fill", ox, oy, 4)
        -- hovered / active ring on top
        if topAxis and handles.rings[topAxis] then
            DrawRing(handles.rings[topAxis], true)
        end
    end
end

_G.Gizmos = Gizmos
return Gizmos