local Visuals = {}

local Cache = {
    attachments = {},
    handles = {},
    dirty = true,
}

local function ToPos3(v)
    if not v then return 0, 0, 0 end
    if type(v) == "table" and v.ToArray then v = v:ToArray() end
    if type(v) == "table" then
        return tonumber(v[1]) or 0, tonumber(v[2]) or 0, tonumber(v[3]) or 0
    end
    return 0, 0, 0
end

local function WorldPosOf(Node)
    if not Node then return 0, 0, 0 end
    local lx, ly, lz = ToPos3(Node.Position or (Node.GetAttribute and Node:GetAttribute("Position")))
    local Parent = rawget(Node, "_Parent") or Node.Parent
    if not Parent then return lx, ly, lz end
    local PC = rawget(Parent, "ClassName")
    if Parent.IsA and Parent:IsA("BasePart") then
        local px, py, pz = ToPos3(Parent.Position)
        return px + lx, py + ly, pz + lz
    end
    if PC == "Attachment" or PC == "Folder" or PC == "Model" then
        local px, py, pz = WorldPosOf(Parent)
        return px + lx, py + ly, pz + lz
    end
    if PC == "Workspace" or PC == "Game" or PC == "DataModel" then
        return lx, ly, lz
    end
    local px, py, pz = WorldPosOf(Parent)
    return px + lx, py + ly, pz + lz
end

function Visuals.Invalidate()
    Cache.dirty = true
end

local function Rebuild()
    Cache.attachments = {}
    Cache.handles = {}
    local function walk(Node)
        if not Node then return end
        local cn = rawget(Node, "ClassName")
        if cn == "Attachment" and Node.Visible ~= false then
            local x, y, z = WorldPosOf(Node)
            Cache.attachments[#Cache.attachments + 1] = {
                x = x, y = y, z = z, name = Node.Name
            }
        elseif cn == "HandleAdornment" and Node.Visible ~= false then
            local PosX, PosY, PosZ = 0, 2, 0
            local Adornee = Node.Adornee
            if Adornee and Adornee.IsA and Adornee:IsA("BasePart") then
                PosX, PosY, PosZ = ToPos3(Adornee.Position)
            elseif Adornee and rawget(Adornee, "ClassName") == "Attachment" then
                PosX, PosY, PosZ = WorldPosOf(Adornee)
            else
                local Parent = rawget(Node, "_Parent") or Node.Parent
                if Parent and Parent.IsA and Parent:IsA("BasePart") then
                    PosX, PosY, PosZ = ToPos3(Parent.Position)
                else
                    PosX, PosY, PosZ = WorldPosOf(Node)
                end
            end
local ox, oy, oz = ToPos3(Node.CFrameOffset)
local OriArr = nil
if Adornee and Adornee.IsA and Adornee:IsA("BasePart") and Adornee.Orientation then
    local OA = Adornee.Orientation
    OriArr = OA.ToArray and OA:ToArray() or OA
end
local CFrame = require("Services.CFrame")
local RotOff = CFrame.RotateByOrientation({ox, oy, oz}, OriArr)
PosX, PosY, PosZ = PosX + RotOff[1], PosY + RotOff[2], PosZ + RotOff[3]
            local sx, sy, sz = ToPos3(Node.Size)
            if sx == 0 and sy == 0 and sz == 0 then sx, sy, sz = 1, 1, 1 end
            local col = Node.Color
            local r, g, b = 0, 0.67, 1
            if type(col) == "table" then
                if col.R then r, g, b = col.R or 0, col.G or 0.67, col.B or 1
                else r, g, b = col[1] or 0, col[2] or 0.67, col[3] or 1 end
                if r > 1 or g > 1 or b > 1 then r, g, b = r / 255, g / 255, b / 255 end
            end
            Cache.handles[#Cache.handles + 1] = {
                x = PosX, y = PosY, z = PosZ,
                sx = sx, sy = sy, sz = sz,
                r = r, g = g, b = b,
                shape = tostring(Node.Shape or "Sphere"),
                tr = type(Node.Transparency) == "number" and Node.Transparency or 0.3,
                aot = Node.AlwaysOnTop ~= false,
            }
        end
        local ch = rawget(Node, "Children")
        if ch then
            for i = 1, #ch do walk(ch[i]) end
        end
    end
    if Workspace then walk(Workspace) end
    Cache.dirty = false
end

local function Project(Camera, wx, wy, wz)
    if not Camera then return nil end
    local CamPos = Camera:GetAttribute("Position") or {0, 4, 0}
    local CamRot = Camera:GetAttribute("Rotation") or {0, 0, 0}
    local deg = rawget(Camera, "FieldOfView") or (Camera.GetAttribute and Camera:GetAttribute("FieldOfView")) or 70
    if type(deg) == "number" and deg < 10 then deg = deg * (180 / math.pi) end
    deg = math.max(45, math.min(135, tonumber(deg) or 70))
    local Fov = deg * (math.pi / 180)
    local W, H = love.graphics.getDimensions()
    local Pitch, Yaw = CamRot[1] or 0, CamRot[2] or 0
    local Forward = {
        math.cos(Pitch) * math.sin(Yaw),
        math.sin(Pitch),
        -math.cos(Pitch) * math.cos(Yaw)
    }
    local Right = { math.cos(Yaw), 0, math.sin(Yaw) }
    local Up = {
        Right[2] * Forward[3] - Right[3] * Forward[2],
        Right[3] * Forward[1] - Right[1] * Forward[3],
        Right[1] * Forward[2] - Right[2] * Forward[1]
    }
    local dx, dy, dz = wx - CamPos[1], wy - CamPos[2], wz - CamPos[3]
    local z = dx * Forward[1] + dy * Forward[2] + dz * Forward[3]
    if z < 0.15 then return nil end
    local x = dx * Right[1] + dy * Right[2] + dz * Right[3]
    local y = dx * Up[1] + dy * Up[2] + dz * Up[3]
    local tanF = math.tan(Fov * 0.5)
    local sx = (x / (z * tanF)) * (H * 0.5) + W * 0.5
    local sy = (-y / (z * tanF)) * (H * 0.5) + H * 0.5
    return sx, sy, z
end

local function DrawProjectedBox(Camera, hx, hy, hz, sx, sy, sz, r, g, b, a)
    local hx2, hy2, hz2 = sx * 0.5, sy * 0.5, sz * 0.5
    local corners = {
        {hx - hx2, hy - hy2, hz - hz2}, {hx + hx2, hy - hy2, hz - hz2},
        {hx + hx2, hy + hy2, hz - hz2}, {hx - hx2, hy + hy2, hz - hz2},
        {hx - hx2, hy - hy2, hz + hz2}, {hx + hx2, hy - hy2, hz + hz2},
        {hx + hx2, hy + hy2, hz + hz2}, {hx - hx2, hy + hy2, hz + hz2},
    }
    local pts = {}
    for i = 1, 8 do
        local px, py = Project(Camera, corners[i][1], corners[i][2], corners[i][3])
        if not px then return end
        pts[i] = {px, py}
    end
    local edges = {
        {1,2},{2,3},{3,4},{4,1},
        {5,6},{6,7},{7,8},{8,5},
        {1,5},{2,6},{3,7},{4,8},
    }
    love.graphics.setColor(r, g, b, a or 0.9)
    love.graphics.setLineWidth(2)
    for _, e in ipairs(edges) do
        local a, b = pts[e[1]], pts[e[2]]
        love.graphics.line(a[1], a[2], b[1], b[2])
    end
    love.graphics.setLineWidth(1)
end

function Visuals.Render(Camera)
    if not Camera then return end
    if Cache.dirty then
        Rebuild()
    end

    for i = 1, #Cache.attachments do
        local a = Cache.attachments[i]
        local sx, sy = Project(Camera, a.x, a.y, a.z)
        if sx then
            love.graphics.setColor(1, 0.85, 0.15, 1)
            love.graphics.circle("fill", sx, sy, 5)
            love.graphics.setColor(1, 0.2, 0.2, 1)
            love.graphics.line(sx, sy - 10, sx, sy + 10)
            love.graphics.setColor(0.2, 1, 0.2, 1)
            love.graphics.line(sx - 10, sy, sx + 10, sy)
            love.graphics.setColor(1, 1, 1, 0.85)
            pcall(love.graphics.print, a.name or "Attachment", sx + 8, sy - 6)
        end
    end

    for i = 1, #Cache.handles do
        local h = Cache.handles[i]
        local sx, sy = Project(Camera, h.x, h.y, h.z)
        if sx then
            local alpha = 1 - (h.tr or 0.3)
            love.graphics.setColor(h.r, h.g, h.b, alpha)
            local rad = 10
            local sh = h.shape
            if sh == "Cube" or sh == "Block" then
                love.graphics.rectangle("fill", sx - rad, sy - rad, rad * 2, rad * 2)
            elseif sh == "Plane" then
                love.graphics.rectangle("fill", sx - rad * 1.6, sy - 3, rad * 3.2, 6)
            elseif sh == "Cylinder" then
                love.graphics.ellipse("fill", sx, sy, rad, rad * 0.55)
            else
                love.graphics.circle("fill", sx, sy, rad)
            end
            love.graphics.setColor(1, 1, 1, 0.45)
            love.graphics.circle("line", sx, sy, rad + 2)
            if h.aot then
                DrawProjectedBox(Camera, h.x, h.y, h.z, h.sx, h.sy, h.sz, h.r, h.g, h.b, 0.55)
            end
        end
    end

    -- Selection / hover wire boxes (AlwaysOnTop overlay)
    local function drawSel(part, rr, gg, bb)
        if not part then return end
        local function DrawPart(P)
            if not P or not P.IsA or not P:IsA("BasePart") then return end
            local px, py, pz = ToPos3(P.Position)
            local sx, sy, sz = ToPos3(P.Size)
            DrawProjectedBox(Camera, px, py, pz, sx, sy, sz, rr, gg, bb, 0.95)
        end
        if part.IsA and part:IsA("UnionOperation") and type(rawget(part, "SolidPieces")) == "table" then
            local Ux, Uy, Uz = ToPos3(part.Position)
            for I = 1, #part.SolidPieces do
                local Sp = part.SolidPieces[I]
                if Sp then
                    local lx, ly, lz = ToPos3(Sp.Position)
                    local sx, sy, sz = ToPos3(Sp.Size)
                    DrawProjectedBox(Camera, Ux + lx, Uy + ly, Uz + lz, sx, sy, sz, rr, gg, bb, 0.95)
                end
            end
            return
        end
        if part.IsA and part:IsA("BasePart") then
            DrawPart(part)
            return
        end
        if part.IsA and part:IsA("Model") then
            local function Walk(N)
                if N.IsA and N:IsA("BasePart") then DrawPart(N) end
                local Kids = rawget(N, "Children")
                if Kids then
                    for I = 1, #Kids do Walk(Kids[I]) end
                end
            end
            Walk(part)
        end
    end

    local sel = _G.Selection and _G.Selection.GetSelectedInstances and _G.Selection.GetSelectedInstances()
    if sel then
        for i = 1, #sel do
            drawSel(sel[i], 0.31, 0.55, 1.0)
        end
    elseif _G.SelectionHighlight and _G.SelectionHighlight.Adornee then
        drawSel(_G.SelectionHighlight.Adornee, 0.31, 0.55, 1.0)
    end
    if _G.HoverPart then
        drawSel(_G.HoverPart, 1.0, 0.85, 0.2)
    end
end

-- Invalidate on common instance changes
local hooked = false
function Visuals.HookInstanceSystem()
    if hooked then return end
    hooked = true
end

return Visuals