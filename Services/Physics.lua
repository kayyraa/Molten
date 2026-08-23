local Vector3 = require("Services.Vector3")

local Physics = {}

Physics.Gravity = 196.2
Physics.Enabled = true
Physics.FixedDt = 1 / 60
Physics.MaxSubSteps = 4
Physics.MaxSpeed = 250

local Groups = {
    Default = { id = 0, name = "Default" },
}
local GroupMatrix = {}
local GroupList = { "Default" }
local Touching = {}
local Accumulator = 0

local function Arr3(v)
    if not v then return 0, 0, 0 end
    if type(v) == "table" and v.ToArray then
        local a = v:ToArray()
        return a[1] or 0, a[2] or 0, a[3] or 0
    end
    if type(v) == "table" then
        return tonumber(v[1]) or 0, tonumber(v[2]) or 0, tonumber(v[3]) or 0
    end
    return 0, 0, 0
end

local function SetArr3(part, key, x, y, z)
    part[key] = Vector3.new(x, y, z)
end

function Physics:RegisterCollisionGroup(name)
    if Groups[name] then return Groups[name] end
    local id = #GroupList
    Groups[name] = { id = id, name = name }
    GroupList[#GroupList + 1] = name
    return Groups[name]
end

function Physics:CollisionGroupSetCollidable(a, b, collidable)
    local key = tostring(a) .. ":" .. tostring(b)
    local key2 = tostring(b) .. ":" .. tostring(a)
    GroupMatrix[key] = collidable and true or false
    GroupMatrix[key2] = collidable and true or false
end

function Physics:CollisionGroupsAreCollidable(a, b)
    if not a then a = "Default" end
    if not b then b = "Default" end
    if a == b then return true end
    local key = tostring(a) .. ":" .. tostring(b)
    if GroupMatrix[key] ~= nil then return GroupMatrix[key] end
    return true
end

function Physics:GetRegisteredCollisionGroups()
    local t = {}
    for i = 1, #GroupList do
        t[i] = { name = GroupList[i], id = Groups[GroupList[i]].id }
    end
    return t
end

local function GetGroup(part)
    if part.CollisionGroup then
        return part.CollisionGroup
    end
    if type(part.GetAttribute) == "function" then
        local g = part:GetAttribute("CollisionGroup")
        if g then return g end
    end
    return "Default"
end

local function CanCollideWith(a, b)
    if a.CanCollide == false or b.CanCollide == false then return false end
    return Physics:CollisionGroupsAreCollidable(GetGroup(a), GetGroup(b))
end

local function CanTouchWith(a, b)
    if a.CanTouch == false or b.CanTouch == false then return false end
    return true
end

local function GetShape(part)
    return string.lower(tostring(part.Shape or "Block"))
end

local function GetExtents(part)
    local px, py, pz = Arr3(part.Position)
    local sx, sy, sz = Arr3(part.Size)
    local fid = tostring(part.CollisionFidelity or "Default")
    if GetShape(part) == "ball" or GetShape(part) == "sphere" then
        local r = math.min(sx, sy, sz) * 0.5
        return px, py, pz, r, r, r, "sphere"
    end
    if fid == "Box" then
        return px, py, pz, sx * 0.5, sy * 0.5, sz * 0.5, "box"
    end
    return px, py, pz, sx * 0.5, sy * 0.5, sz * 0.5, "box"
end

local function AabbOverlap(ax, ay, az, ahx, ahy, ahz, bx, by, bz, bhx, bhy, bhz)
    return math.abs(ax - bx) <= (ahx + bhx)
        and math.abs(ay - by) <= (ahy + bhy)
        and math.abs(az - bz) <= (ahz + bhz)
end

local function ResolveAabb(ax, ay, az, ahx, ahy, ahz, bx, by, bz, bhx, bhy, bhz)
    local dx = ax - bx
    local dy = ay - by
    local dz = az - bz
    local ox = (ahx + bhx) - math.abs(dx)
    local oy = (ahy + bhy) - math.abs(dy)
    local oz = (ahz + bhz) - math.abs(dz)
    if ox < oy and ox < oz then
        local s = dx >= 0 and 1 or -1
        return s * ox, 0, 0, s, 0, 0
    elseif oy < oz then
        local s = dy >= 0 and 1 or -1
        return 0, s * oy, 0, 0, s, 0
    else
        local s = dz >= 0 and 1 or -1
        return 0, 0, s * oz, 0, 0, s
    end
end

local function EnsureSignals(part)
    if not part.Touched then
        local handlers = {}
        part.Touched = {
            Connect = function(_, fn)
                handlers[#handlers + 1] = fn
                return { Disconnect = function()
                    for i = #handlers, 1, -1 do
                        if handlers[i] == fn then table.remove(handlers, i) break end
                    end
                end }
            end,
            Fire = function(_, other)
                for i = 1, #handlers do pcall(handlers[i], other) end
            end,
        }
    end
    if not part.TouchEnded then
        local handlers = {}
        part.TouchEnded = {
            Connect = function(_, fn)
                handlers[#handlers + 1] = fn
                return { Disconnect = function()
                    for i = #handlers, 1, -1 do
                        if handlers[i] == fn then table.remove(handlers, i) break end
                    end
                end }
            end,
            Fire = function(_, other)
                for i = 1, #handlers do pcall(handlers[i], other) end
            end,
        }
    end
end

local function CollectParts(node, list)
    if not node then return end
    if node.IsA and node:IsA("BasePart") then
        list[#list + 1] = node
    end
    local kids = rawget(node, "Children")
    if kids then
        for i = 1, #kids do
            CollectParts(kids[i], list)
        end
    end
end

local function GetVelocity(part)
    local v = part.AssemblyLinearVelocity or part.Velocity
    if type(v) == "table" and v.ToArray then
        local a = v:ToArray()
        return a[1] or 0, a[2] or 0, a[3] or 0
    end
    if type(v) == "table" then
        return tonumber(v[1]) or 0, tonumber(v[2]) or 0, tonumber(v[3]) or 0
    end
    return 0, 0, 0
end

local function SetVelocity(part, x, y, z)
    local max = Physics.MaxSpeed
    local sp = math.sqrt(x * x + y * y + z * z)
    if sp > max then
        local s = max / sp
        x, y, z = x * s, y * s, z * s
    end
    part.AssemblyLinearVelocity = Vector3.new(x, y, z)
    part.Velocity = part.AssemblyLinearVelocity
end

local function IsCharacterPart(part, charModel)
    if not charModel or not part then return false end
    local cur = part
    for _ = 1, 24 do
        if not cur then return false end
        if cur == charModel then return true end
        cur = rawget(cur, "_Parent") or cur.Parent
    end
    return false
end

local function SubStep(dt, gravity, parts, charModel)
    local nextTouch = {}

    for i = 1, #parts do
        local p = parts[i]
        if IsCharacterPart(p, charModel) then
            -- character controlled separately
        else
            EnsureSignals(p)
            if p.Anchored ~= true then
                local vx, vy, vz = GetVelocity(p)
                vy = vy - gravity * dt
                if vy < -120 then vy = -120 end
                local px, py, pz = Arr3(p.Position)
                local stepY = vy * dt
                if stepY < -2 then stepY = -2 end
                px = px + vx * dt
                py = py + stepY
                pz = pz + vz * dt
                if px ~= px or py ~= py or pz ~= pz then
                    px, py, pz = 0, 10, 0
                    vx, vy, vz = 0, 0, 0
                end
                if py < -500 then
                    py = 10
                    vx, vy, vz = 0, 0, 0
                end
                SetArr3(p, "Position", px, py, pz)
                SetVelocity(p, vx, vy, vz)
            end
        end
    end

    for i = 1, #parts do
        local a = parts[i]
        if not IsCharacterPart(a, charModel) then
        local ax, ay, az, ahx, ahy, ahz = GetExtents(a)
        for j = i + 1, #parts do
            local b = parts[j]
            if not IsCharacterPart(b, charModel) then
            local bx, by, bz, bhx, bhy, bhz = GetExtents(b)
            if AabbOverlap(ax, ay, az, ahx, ahy, ahz, bx, by, bz, bhx, bhy, bhz) then
                local pair = tostring(a) .. ":" .. tostring(b)
                nextTouch[pair] = { a, b }
                if CanTouchWith(a, b) then
                    if not Touching[pair] then
                        if a.Touched and a.Touched.Fire then a.Touched:Fire(b) end
                        if b.Touched and b.Touched.Fire then b.Touched:Fire(a) end
                    end
                end
                if CanCollideWith(a, b) then
                    local ox, oy, oz, nx, ny, nz = ResolveAabb(ax, ay, az, ahx, ahy, ahz, bx, by, bz, bhx, bhy, bhz)
                    local aAnch = a.Anchored == true
                    local bAnch = b.Anchored == true
                    local bounce = 0.15
                    if aAnch and not bAnch then
                        local px, py, pz = Arr3(b.Position)
                        SetArr3(b, "Position", px - ox, py - oy, pz - oz)
                        local vx, vy, vz = GetVelocity(b)
                        local vn = vx * nx + vy * ny + vz * nz
                        if vn < 0 then
                            SetVelocity(b, vx - vn * nx * (1 + bounce), vy - vn * ny * (1 + bounce), vz - vn * nz * (1 + bounce))
                        end
                        if ny > 0.5 then
                            local vx2, vy2, vz2 = GetVelocity(b)
                            SetVelocity(b, vx2 * 0.85, math.min(vy2, 0), vz2 * 0.85)
                        end
                    elseif bAnch and not aAnch then
                        local px, py, pz = Arr3(a.Position)
                        SetArr3(a, "Position", px + ox, py + oy, pz + oz)
                        local vx, vy, vz = GetVelocity(a)
                        local vn = vx * (-nx) + vy * (-ny) + vz * (-nz)
                        if vn < 0 then
                            SetVelocity(a, vx - vn * (-nx) * (1 + bounce), vy - vn * (-ny) * (1 + bounce), vz - vn * (-nz) * (1 + bounce))
                        end
                        if (-ny) > 0.5 or ny < -0.5 then
                            local vx2, vy2, vz2 = GetVelocity(a)
                            if oy > 0 then
                                SetVelocity(a, vx2 * 0.85, math.max(vy2, 0), vz2 * 0.85)
                            else
                                SetVelocity(a, vx2 * 0.85, math.min(vy2, 0), vz2 * 0.85)
                            end
                        end
                    elseif not aAnch and not bAnch then
                        local px, py, pz = Arr3(a.Position)
                        SetArr3(a, "Position", px + ox * 0.5, py + oy * 0.5, pz + oz * 0.5)
                        local qx, qy, qz = Arr3(b.Position)
                        SetArr3(b, "Position", qx - ox * 0.5, qy - oy * 0.5, qz - oz * 0.5)
                        local avx, avy, avz = GetVelocity(a)
                        local bvx, bvy, bvz = GetVelocity(b)
                        local rvx, rvy, rvz = avx - bvx, avy - bvy, avz - bvz
                        local vn = rvx * nx + rvy * ny + rvz * nz
                        if vn < 0 then
                            local j = vn * 0.5
                            SetVelocity(a, avx - j * nx, avy - j * ny, avz - j * nz)
                            SetVelocity(b, bvx + j * nx, bvy + j * ny, bvz + j * nz)
                        end
                    end
                    ax, ay, az = Arr3(a.Position)
                    bx, by, bz = Arr3(b.Position)
                end
            end
            end
        end
        end
    end

    for pair, ab in pairs(Touching) do
        if not nextTouch[pair] then
            local a, b = ab[1], ab[2]
            if a and a.TouchEnded and a.TouchEnded.Fire then a.TouchEnded:Fire(b) end
            if b and b.TouchEnded and b.TouchEnded.Fire then b.TouchEnded:Fire(a) end
        end
    end
    Touching = nextTouch
end

function Physics:Step(dt)
    if not self.Enabled then return end
    dt = math.min(math.max(dt or 0.016, 0), 0.05)
    Accumulator = Accumulator + dt
    local fixed = self.FixedDt
    local steps = 0
    local Ws = rawget(_G, "Workspace")
    if not Ws then
        Accumulator = 0
        return
    end
    local gravity = self.Gravity
    if Ws.Gravity ~= nil then gravity = tonumber(Ws.Gravity) or gravity end
    local parts = {}
    CollectParts(Ws, parts)
    local charModel = nil
    local R = rawget(_G, "Runtime")
    if R then charModel = R.Character end

    while Accumulator >= fixed and steps < self.MaxSubSteps do
        SubStep(fixed, gravity, parts, charModel)
        Accumulator = Accumulator - fixed
        steps = steps + 1
    end
    if steps >= self.MaxSubSteps then
        Accumulator = 0
    end
end

function Physics:Reset()
    Accumulator = 0
    Touching = {}
    local Ws = rawget(_G, "Workspace")
    if not Ws then return end
    local parts = {}
    CollectParts(Ws, parts)
    for i = 1, #parts do
        local p = parts[i]
        SetVelocity(p, 0, 0, 0)
        p.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
    end
end

function Physics:Init()
    self:RegisterCollisionGroup("Default")
    _G.PhysicsService = self
end

Physics:Init()
_G.Physics = Physics
return Physics