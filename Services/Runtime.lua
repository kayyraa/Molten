local Instance = require("Services.Instance")
local Vector3 = require("Services.Vector3")
local Color = require("Services.Color")

local Runtime = {}

Runtime.Mode = "Edit"
Runtime.Paused = false
Runtime.ViewSide = "Client"
Runtime.Character = nil
Runtime.LocalPlayer = nil
Runtime.Connections = {}
Runtime.ModuleCache = {}

local ServerQueue = {}
local ClientQueue = {}

local function Signal()
    local Handlers = {}
    local Sig = {}
    function Sig:Connect(Fn)
        Handlers[#Handlers + 1] = Fn
        return {
            Disconnect = function()
                for I = #Handlers, 1, -1 do
                    if Handlers[I] == Fn then
                        table.remove(Handlers, I)
                        break
                    end
                end
            end
        }
    end
    function Sig:Fire(...)
        for I = 1, #Handlers do
            local Ok, Err = pcall(Handlers[I], ...)
            if not Ok then
                local Gui = rawget(_G, "Gui")
                if Gui and Gui.Console and Gui.Console.Print then
                    Gui.Console:Print("[Runtime] " .. tostring(Err))
                end
            end
        end
    end
    return Sig
end

local function EnsurePlayers()
    local Players = rawget(_G, "Players")
    if not Players then
        local Game = rawget(_G, "Game")
        if Game then
            Players = Instance.new("Folder", Game)
            Players.Name = "Players"
            rawset(Players, "ClassName", "Players")
            _G.Players = Players
        end
    end
    return Players
end

local function EnsureRunService()
    local Rs = rawget(_G, "RunService")
    if not Rs then
        Rs = {
            ClassName = "RunService",
            Name = "RunService",
            Heartbeat = Signal(),
            Stepped = Signal(),
            RenderStepped = Signal(),
        }
        function Rs:IsStudio() return true end
        function Rs:IsRunning() return Runtime.Mode ~= "Edit" end
        function Rs:IsClient() return Runtime.Mode == "Play" end
        function Rs:IsServer() return Runtime.Mode == "Run" or Runtime.Mode == "Play" end
        _G.RunService = Rs
    end
    if not Rs.Heartbeat then Rs.Heartbeat = Signal() end
    if not Rs.Stepped then Rs.Stepped = Signal() end
    if not Rs.RenderStepped then Rs.RenderStepped = Signal() end
    return Rs
end

local function AttachRemoteApi(Obj)
    if not Obj then return end
    if Obj.ClassName == "RemoteEvent" then
        Obj.OnServerEvent = Obj.OnServerEvent or Signal()
        Obj.OnClientEvent = Obj.OnClientEvent or Signal()
        function Obj:FireServer(...)
            if Runtime.Mode == "Edit" then return end
            ServerQueue[#ServerQueue + 1] = { Kind = "RemoteEvent", Target = self, Args = {...} }
        end
        function Obj:FireClient(Player, ...)
            if Runtime.Mode == "Edit" then return end
            ClientQueue[#ClientQueue + 1] = { Kind = "RemoteEvent", Target = self, Args = {...} }
        end
        function Obj:FireAllClients(...)
            if Runtime.Mode == "Edit" then return end
            ClientQueue[#ClientQueue + 1] = { Kind = "RemoteEvent", Target = self, Args = {...} }
        end
    elseif Obj.ClassName == "RemoteFunction" then
        function Obj:InvokeServer(...)
            if Runtime.Mode == "Edit" then return end
            if self.OnServerInvoke then
                local Ok, A, B, C, D = pcall(self.OnServerInvoke, Runtime.LocalPlayer, ...)
                if Ok then return A, B, C, D end
            end
        end
        function Obj:InvokeClient(Player, ...)
            if Runtime.Mode == "Edit" then return end
            if self.OnClientInvoke then
                local Ok, A, B, C, D = pcall(self.OnClientInvoke, ...)
                if Ok then return A, B, C, D end
            end
        end
    end
end

local function WalkAttachRemotes(Node)
    if not Node then return end
    if Node.ClassName == "RemoteEvent" or Node.ClassName == "RemoteFunction" then
        AttachRemoteApi(Node)
    end
    local Kids = rawget(Node, "Children")
    if Kids then
        for I = 1, #Kids do
            WalkAttachRemotes(Kids[I])
        end
    end
end

local function LoadModule(Mod)
    if not Mod then return nil end
    if Runtime.ModuleCache[Mod] ~= nil then
        return Runtime.ModuleCache[Mod]
    end
    local Source = Mod.Source or ""
    if Source == "" then return nil end
    local Env = BuildEnv(false, Mod)
    local Chunk, Err = load(Source, "=" .. (Mod.Name or "Module"), "t", Env)
    if not Chunk then
        local Gui = rawget(_G, "Gui")
        if Gui and Gui.Console then Gui.Console:Print("[Module Error] " .. tostring(Err)) end
        return nil
    end
    local Ok, Result = pcall(Chunk)
    if not Ok then
        local Gui = rawget(_G, "Gui")
        if Gui and Gui.Console then Gui.Console:Print("[Module Error] " .. tostring(Result)) end
        return nil
    end
    Runtime.ModuleCache[Mod] = Result
    return Result
end

function BuildEnv(IsClient, ScriptInst)
    local Env = {}
    for K, V in pairs(_G) do
        Env[K] = V
    end
    Env.script = ScriptInst
    Env.workspace = rawget(_G, "Workspace")
    Env.Workspace = Env.workspace
    Env.game = rawget(_G, "Game")
    Env.Game = Env.game
    Env.print = function(...)
        local Parts = {}
        for I = 1, select("#", ...) do
            Parts[I] = tostring(select(I, ...))
        end
        local Msg = table.concat(Parts, "\t")
        local Gui = rawget(_G, "Gui")
        if Gui and Gui.Console and Gui.Console.Print then
            Gui.Console:Print(Msg)
        else
            print(Msg)
        end
    end
    Env.warn = Env.print
    Env.Instance = Instance
    Env.Vector3 = Vector3
    Env.Color3 = Color
    Env.CFrame = require("Services.CFrame")
    Env.Enum = rawget(_G, "Enum")
    Env.RaycastParams = rawget(_G, "RaycastParams")
    Env.RunService = EnsureRunService()
    Env.Players = EnsurePlayers()
    Env.wait = function(T)
        T = tonumber(T) or 0.03
        local Elapsed = 0
        while Elapsed < T do
            Elapsed = Elapsed + (love.timer.getDelta() or 0.016)
            coroutine.yield()
        end
    end
    Env.task = {
        wait = Env.wait,
        spawn = function(Fn, ...)
            local Args = {...}
            local Co = coroutine.create(function()
                Fn(table.unpack(Args))
            end)
            Runtime.Connections[#Runtime.Connections + 1] = { Co = Co, Side = IsClient and "client" or "server" }
        end,
        defer = function(Fn, ...)
            return Env.task.spawn(Fn, ...)
        end,
    }
    Env.require = function(Target)
        if type(Target) == "table" and Target.ClassName == "ModuleScript" then
            return LoadModule(Target)
        end
        if type(Target) == "string" then
            local Ok, Mod = pcall(require, Target)
            if Ok then return Mod end
        end
        return nil
    end
    if IsClient then
        Env.LocalPlayer = Runtime.LocalPlayer
    end
    setmetatable(Env, { __index = _G })
    return Env
end

local function IsUnderPlayer(Node)
    local Cur = Node
    for _ = 1, 24 do
        if not Cur then return false end
        if Cur.ClassName == "Player" or Cur.Name == "LocalPlayer" then
            return true
        end
        if Cur == Runtime.Character then
            return true
        end
        local Parent = rawget(Cur, "_Parent") or Cur.Parent
        if Parent == Cur then return false end
        Cur = Parent
    end
    return false
end

local function CollectScripts(Root, ClassName, List, FilterFn)
    if not Root then return end
    local Kids = rawget(Root, "Children")
    if not Kids and Root.GetChildren then
        Kids = Root:GetChildren()
    end
    if not Kids then return end
    for I = 1, #Kids do
        local N = Kids[I]
        if N.ClassName == ClassName and N.Enabled ~= false then
            if not FilterFn or FilterFn(N) then
                List[#List + 1] = N
            end
        end
        if N.ClassName ~= "ModuleScript" then
            CollectScripts(N, ClassName, List, FilterFn)
        end
    end
end

local StartedScripts = {}

local function StartScript(ScriptInst, IsClient)
    if not ScriptInst then return end
    local Key = tostring(ScriptInst.Guid or ScriptInst) .. ":" .. (IsClient and "c" or "s")
    if StartedScripts[Key] then return end
    StartedScripts[Key] = true
    if ScriptInst.ClassName == "ModuleScript" then return end
    if ScriptInst.ClassName == "LocalScript" and not IsClient then return end
    if ScriptInst.ClassName == "LocalScript" and IsClient then
        if not IsUnderPlayer(ScriptInst) and ScriptInst.Parent ~= Runtime.Character then
            local Allowed = false
            local StarterPlayer = rawget(_G, "StarterPlayer")
            local StarterGui = rawget(_G, "StarterGui")
            local Cur = ScriptInst
            for _ = 1, 16 do
                if not Cur then break end
                if Cur == StarterPlayer or Cur == StarterGui or Cur == Runtime.LocalPlayer or Cur == Runtime.Character then
                    Allowed = true
                    break
                end
                if Cur.ClassName == "Player" then
                    Allowed = true
                    break
                end
                Cur = rawget(Cur, "_Parent") or Cur.Parent
            end
            if not Allowed then
                return
            end
        end
    end
    local Source = ScriptInst.Source or ""
    if Source == "" then return end
    local Env = BuildEnv(IsClient, ScriptInst)
    local Chunk, Err = load(Source, "=" .. (ScriptInst.Name or "Script"), "t", Env)
    if not Chunk then
        local Gui = rawget(_G, "Gui")
        if Gui and Gui.Console then Gui.Console:Print("[Script Error] " .. tostring(Err)) end
        return
    end
    local Co = coroutine.create(Chunk)
    Runtime.Connections[#Runtime.Connections + 1] = { Co = Co, Script = ScriptInst, Side = IsClient and "client" or "server" }
    local Ok, Res = coroutine.resume(Co)
    if not Ok then
        local Gui = rawget(_G, "Gui")
        if Gui and Gui.Console then Gui.Console:Print("[Script Error] " .. tostring(Res)) end
    end
end

local function FindSpawnLocation()
    local Ws = rawget(_G, "Workspace")
    if not Ws then return nil end
    local Best = nil
    local function Walk(Node)
        local Kids = rawget(Node, "Children")
        if not Kids then return end
        for I = 1, #Kids do
            local N = Kids[I]
            if N.ClassName == "SpawnLocation" and N.Enabled ~= false then
                Best = N
                return true
            end
            if Walk(N) then return true end
        end
    end
    Walk(Ws)
    return Best
end

local function MakePart(Parent, Name, Size, Pos, ColorArr)
    local P = Instance.new("Part", Parent)
    P.Name = Name
    P.Size = Vector3.new(Size[1], Size[2], Size[3])
    P.Position = Vector3.new(Pos[1], Pos[2], Pos[3])
    P.Color = Color.FromRGBA(ColorArr[1], ColorArr[2], ColorArr[3])
    P.Anchored = true
    P.CanCollide = false
    P.CanTouch = false
    P.Material = { Reflectivity = 0.05, Roughness = 0.7 }
    return P
end

local function MakeMotor6D(Parent, Name, Part0, Part1, C0, C1)
    local M = Instance.new("Motor6D", Parent)
    M.Name = Name
    M.Part0 = Part0
    M.Part1 = Part1
    M.C0 = C0 or {0, 0, 0}
    M.C1 = C1 or {0, 0, 0}
    return M
end

local function CreateLocalPlayer()
    local Players = EnsurePlayers()
    if not Players then return nil end
    if Runtime.LocalPlayer then
        return Runtime.LocalPlayer
    end
    local Player = Instance.new("Player", Players)
    Player.Name = "LocalPlayer"
    Player.DisplayName = "Player1"
    Player.UserId = 1
    Player.Character = nil
    rawset(Players, "LocalPlayer", Player)
    Runtime.LocalPlayer = Player
    return Player
end

local function SpawnCharacter(Position)
    local Ws = rawget(_G, "Workspace")
    if not Ws then return nil end
    if Runtime.Character then
        if Runtime.Character.Destroy then Runtime.Character:Destroy() end
        Runtime.Character = nil
    end

    local X, Y, Z = Position[1] or 0, Position[2] or 0, Position[3] or 0
    if Y < 5 then Y = 5 end

    local Model = Instance.new("Model", Ws)
    Model.Name = "Character"

    local Root = MakePart(Model, "HumanoidRootPart", {2, 2, 1}, {X, Y, Z}, {163, 162, 165})
    Root.Transparency = 1
    Root.CanCollide = false
    Root.Anchored = true

    local Torso = MakePart(Model, "Torso", {2, 2, 1}, {X, Y, Z}, {13, 105, 172})
    local Head = MakePart(Model, "Head", {1.4, 1.4, 1.4}, {X, Y + 1.7, Z}, {234, 184, 146})
    local La = MakePart(Model, "Left Arm", {1, 2, 1}, {X - 1.5, Y, Z}, {234, 184, 146})
    local Ra = MakePart(Model, "Right Arm", {1, 2, 1}, {X + 1.5, Y, Z}, {234, 184, 146})
    local Ll = MakePart(Model, "Left Leg", {1, 2, 1}, {X - 0.5, Y - 2, Z}, {75, 151, 75})
    local Rl = MakePart(Model, "Right Leg", {1, 2, 1}, {X + 0.5, Y - 2, Z}, {75, 151, 75})

    MakeMotor6D(Torso, "RootJoint", Root, Torso, {0, 0, 0}, {0, 0, 0})
    MakeMotor6D(Torso, "Neck", Torso, Head, {0, 1, 0}, {0, -0.5, 0})
    MakeMotor6D(Torso, "Left Shoulder", Torso, La, {-1, 0.5, 0}, {0.5, 0.5, 0})
    MakeMotor6D(Torso, "Right Shoulder", Torso, Ra, {1, 0.5, 0}, {-0.5, 0.5, 0})
    MakeMotor6D(Torso, "Left Hip", Torso, Ll, {-0.5, -1, 0}, {0, 1, 0})
    MakeMotor6D(Torso, "Right Hip", Torso, Rl, {0.5, -1, 0}, {0, 1, 0})

    Model.PrimaryPart = Root
    Runtime.Character = Model
    Runtime.CharacterRoot = Root
    Runtime.CharacterYaw = 0
    Runtime.WalkPhase = 0
    Runtime.CharVelY = 0
    Runtime.OnGround = false
    Runtime.CharPos = {X, Y, Z}
    Runtime.AnimLeg = 0
    Runtime.AnimArm = 0
    Runtime.CharacterParts = {
        HumanoidRootPart = Root,
        Torso = Torso,
        Head = Head,
        ["Left Arm"] = La,
        ["Right Arm"] = Ra,
        ["Left Leg"] = Ll,
        ["Right Leg"] = Rl,
    }
    local Visuals = package.loaded["Services.Visuals"]
    if Visuals and Visuals.Invalidate then Visuals.Invalidate() end
    return Model
end

local function IsDescendantOf(Node, Ancestor)
    local Cur = Node
    for _ = 1, 24 do
        if not Cur then return false end
        if Cur == Ancestor then return true end
        Cur = rawget(Cur, "_Parent") or Cur.Parent
    end
    return false
end

local MaxStepUp = 2.2
local MaxStepDown = 3.5
local CharRadius = 1.0
local CharHalfHeight = 2.5

local function PartBox(Part)
    local Px, Py, Pz = 0, 0, 0
    local Sx, Sy, Sz = 4, 4, 4
    local Pos = Part.Position
    local Size = Part.Size
    if type(Pos) == "table" then
        if Pos.ToArray then Pos = Pos:ToArray() end
        Px, Py, Pz = Pos[1] or 0, Pos[2] or 0, Pos[3] or 0
    end
    if type(Size) == "table" then
        if Size.ToArray then Size = Size:ToArray() end
        Sx, Sy, Sz = Size[1] or 4, Size[2] or 4, Size[3] or 4
    end
    return Px, Py, Pz, Sx * 0.5, Sy * 0.5, Sz * 0.5
end

local function ForEachSolidBox(Part, Fn)
    if Part and Part.ClassName == "UnionOperation" and type(rawget(Part, "SolidPieces")) == "table" and #Part.SolidPieces > 0 then
        local Ux, Uy, Uz = 0, 0, 0
        local Pos = Part.Position
        if type(Pos) == "table" then
            if Pos.ToArray then Pos = Pos:ToArray() end
            Ux, Uy, Uz = Pos[1] or 0, Pos[2] or 0, Pos[3] or 0
        end
        for I = 1, #Part.SolidPieces do
            local Sp = Part.SolidPieces[I]
            if Sp then
                local P = Sp.Position or {0, 0, 0}
                local S = Sp.Size or {1, 1, 1}
                if type(P) == "table" and P.ToArray then P = P:ToArray() end
                if type(S) == "table" and S.ToArray then S = S:ToArray() end
                local Px = Ux + (P[1] or 0)
                local Py = Uy + (P[2] or 0)
                local Pz = Uz + (P[3] or 0)
                local Hx = math.abs(S[1] or 1) * 0.5
                local Hy = math.abs(S[2] or 1) * 0.5
                local Hz = math.abs(S[3] or 1) * 0.5
                Fn(Px, Py, Pz, Hx, Hy, Hz)
            end
        end
        return
    end
    local Px, Py, Pz, Hx, Hy, Hz = PartBox(Part)
    Fn(Px, Py, Pz, Hx, Hy, Hz)
end

local function CollectParts(IgnoreModel)
    local List = {}
    local Ws = rawget(_G, "Workspace")
    if not Ws then return List end
    local function Walk(Node)
        if Node and Node.IsA and Node:IsA("BasePart") and Node.CanCollide ~= false then
            if not (IgnoreModel and IsDescendantOf(Node, IgnoreModel)) then
                List[#List + 1] = Node
            end
        end
        local Kids = rawget(Node, "Children")
        if Kids then
            for I = 1, #Kids do Walk(Kids[I]) end
        end
    end
    Walk(Ws)
    return List
end

local function GroundY(X, Z, FeetY, IgnoreModel)
    local Best = nil
    local BestDist = 1e9
    local Parts = CollectParts(IgnoreModel)
    for I = 1, #Parts do
        ForEachSolidBox(Parts[I], function(Px, Py, Pz, Hx, Hy, Hz)
            if X >= Px - Hx - 0.05 and X <= Px + Hx + 0.05 and Z >= Pz - Hz - 0.05 and Z <= Pz + Hz + 0.05 then
                local Top = Py + Hy
                local Dist = FeetY - Top
                if Dist >= -MaxStepUp and Dist <= MaxStepDown then
                    if Dist < BestDist or (math.abs(Dist - BestDist) < 0.001 and (not Best or Top > Best)) then
                        BestDist = Dist
                        Best = Top
                    end
                end
            end
        end)
    end
    return Best
end

local function ResolveWalls(X, Y, Z, IgnoreModel)
    local Parts = CollectParts(IgnoreModel)
    local BodyBottom = Y - CharHalfHeight
    local BodyTop = Y + CharHalfHeight * 0.35
    for Pass = 1, 3 do
        for I = 1, #Parts do
            ForEachSolidBox(Parts[I], function(Px, Py, Pz, Hx, Hy, Hz)
                local Top = Py + Hy
                local Bot = Py - Hy
                if BodyTop > Bot + 0.05 and BodyBottom < Top - MaxStepUp then
                    local Dx = X - Px
                    local Dz = Z - Pz
                    local Ox = Hx + CharRadius - math.abs(Dx)
                    local Oz = Hz + CharRadius - math.abs(Dz)
                    if Ox > 0 and Oz > 0 then
                        if Ox < Oz then
                            X = Px + (Dx >= 0 and 1 or -1) * (Hx + CharRadius)
                        else
                            Z = Pz + (Dz >= 0 and 1 or -1) * (Hz + CharRadius)
                        end
                    end
                end
            end)
        end
    end
    return X, Z
end

local function CeilingY(X, Z, HeadY, IgnoreModel)
    local Best = nil
    local Parts = CollectParts(IgnoreModel)
    for I = 1, #Parts do
        local Px, Py, Pz, Hx, Hy, Hz = PartBox(Parts[I])
        if X >= Px - Hx and X <= Px + Hx and Z >= Pz - Hz and Z <= Pz + Hz then
            local Bot = Py - Hy
            if Bot >= HeadY - 0.05 and (not Best or Bot < Best) then
                Best = Bot
            end
        end
    end
    return Best
end

function Runtime:MoveCharacter(Dt, MoveX, MoveZ, WantJump)
    local Parts = self.CharacterParts
    if not Parts then return end
    local Root = Parts.HumanoidRootPart
    if not Root then return end

    Dt = math.min(math.max(Dt or 0.016, 0), 0.05)

    if self.CharPos == nil then
        local Pos = Root.Position
        if type(Pos) == "table" and Pos.ToArray then Pos = Pos:ToArray() end
        self.CharPos = {Pos[1] or 0, Pos[2] or 5, Pos[3] or 0}
    end
    local X, Y, Z = self.CharPos[1], self.CharPos[2], self.CharPos[3]

    local Speed = 16
    local Sp = rawget(_G, "StarterPlayer")
    if Sp and tonumber(Sp.CharacterWalkSpeed) then
        Speed = tonumber(Sp.CharacterWalkSpeed) or 16
    end
    local Len = math.sqrt(MoveX * MoveX + MoveZ * MoveZ)
    local Walking = Len > 0.05
    if Walking then
        MoveX, MoveZ = MoveX / Len, MoveZ / Len
        local TargetYaw = math.atan2(-MoveX, -MoveZ)
        local Cur = self.CharacterYaw or 0
        local Diff = TargetYaw - Cur
        while Diff > math.pi do Diff = Diff - math.pi * 2 end
        while Diff < -math.pi do Diff = Diff + math.pi * 2 end
        self.CharacterYaw = Cur + Diff * math.min(1, Dt * 12)
        if self.OnGround then
            self.WalkPhase = (self.WalkPhase or 0) + Dt * 8.5
        end
    end

    local Gravity = 196.2
    local Ws = rawget(_G, "Workspace")
    if Ws and Ws.Gravity then Gravity = tonumber(Ws.Gravity) or Gravity end

    self.Coyote = self.Coyote or 0
    if self.OnGround then
        self.Coyote = 0.12
    else
        self.Coyote = math.max(0, self.Coyote - Dt)
    end

    self.JumpBuf = self.JumpBuf or 0
    if WantJump then
        self.JumpBuf = 0.12
    else
        self.JumpBuf = math.max(0, self.JumpBuf - Dt)
    end

    self.CharVelY = (self.CharVelY or 0) - Gravity * Dt

    local CanJump = (self.OnGround or self.Coyote > 0) and (self.CharVelY <= 5)
    if self.JumpBuf > 0 and CanJump then
        local JumpVel = 56
        local Spj = rawget(_G, "StarterPlayer")
        if Spj then
            if Spj.CharacterUseJumpPower and tonumber(Spj.CharacterJumpPower) then
                JumpVel = tonumber(Spj.CharacterJumpPower) or 50
            elseif tonumber(Spj.CharacterJumpHeight) then
                local H = tonumber(Spj.CharacterJumpHeight) or 7.2
                local G = 196.2
                local Ws = rawget(_G, "Workspace")
                if Ws and Ws.Gravity then G = tonumber(Ws.Gravity) or G end
                JumpVel = math.sqrt(math.max(0, 2 * G * H))
            end
        end
        self.CharVelY = JumpVel
        self.OnGround = false
        self.Coyote = 0
        self.JumpBuf = 0
    end

    local HullHip = 3
    local PrevX, PrevZ = X, Z
    if Walking then
        X = X + MoveX * Speed * Dt
        Z = Z + MoveZ * Speed * Dt
    end

    X, Z = ResolveWalls(X, Y, Z, self.Character)

    Y = Y + self.CharVelY * Dt

    local FeetY = Y - HullHip
    local Ground = GroundY(X, Z, FeetY, self.Character)
    if Ground then
        local TargetY = Ground + HullHip
        local Rise = TargetY - Y
        if self.CharVelY <= 0 and Rise >= -0.2 and Rise <= MaxStepUp then
            Y = TargetY
            self.CharVelY = 0
            self.OnGround = true
        elseif self.CharVelY <= 0 and Rise < -0.2 and Rise >= -MaxStepDown then
            local Slide = math.min(1, Dt * 8)
            Y = Y + (TargetY - Y) * Slide
            self.CharVelY = math.min(self.CharVelY, -2)
            self.OnGround = Rise > -0.35
        else
            self.OnGround = false
        end
    else
        self.OnGround = false
    end

    local Head = Y + 1.5
    local Ceil = CeilingY(X, Z, Head, self.Character)
    if Ceil and Y + 1.6 > Ceil then
        Y = Ceil - 1.6
        if self.CharVelY > 0 then
            self.CharVelY = 0
        end
    end

    X, Z = ResolveWalls(X, Y, Z, self.Character)

    self.CharPos[1], self.CharPos[2], self.CharPos[3] = X, Y, Z

    local InAir = not self.OnGround
    local Phase = self.WalkPhase or 0
    local TargetLeg = (Walking and not InAir) and math.sin(Phase) * 0.9 or 0
    local TargetArm = (Walking and not InAir) and math.sin(Phase) * 0.7 or 0
    if InAir and Walking then
        TargetArm = math.sin(Phase) * 0.2
        TargetLeg = 0.15
    end
    local AnimSpeed = InAir and 6 or 14
    self.AnimLeg = (self.AnimLeg or 0) + (TargetLeg - (self.AnimLeg or 0)) * math.min(1, Dt * AnimSpeed)
    self.AnimArm = (self.AnimArm or 0) + (TargetArm - (self.AnimArm or 0)) * math.min(1, Dt * AnimSpeed)
    local LegAng = self.AnimLeg or 0
    local ArmAng = self.AnimArm or 0
    local Bob = (Walking and not InAir) and math.abs(math.sin(Phase)) * 0.08 or 0

    local Yaw = self.CharacterYaw or 0
    local Cy, Sy = math.cos(Yaw), math.sin(Yaw)

    local function RotX(Px, Py, Pz, A)
        local C, S = math.cos(A), math.sin(A)
        return Px, Py * C - Pz * S, Py * S + Pz * C
    end

    local function World(Lx, Ly, Lz, ApplyBob)
        if ApplyBob then Ly = Ly + Bob end
        return X + Lx * Cy + Lz * Sy, Y + Ly, Z + (-Lx * Sy + Lz * Cy)
    end

    local function SetPart(Part, Lx, Ly, Lz, Pitch, ApplyBob)
        local Wx, Wy, Wz = World(Lx, Ly, Lz, ApplyBob)
        Part.Position = Vector3.new(Wx, Wy, Wz)
        Part.Orientation = Vector3.new(math.deg(Pitch or 0), math.deg(Yaw), 0)
    end

    local function FromJoint(Jx, Jy, Jz, Ox, Oy, Oz, Ang)
        local Rx, Ry, Rz = RotX(Ox, Oy, Oz, Ang)
        return Jx + Rx, Jy + Ry, Jz + Rz
    end

    SetPart(Root, 0, 0, 0, 0, false)
    SetPart(Parts.Torso, 0, 0, 0, 0, true)
    SetPart(Parts.Head, 0, 1.7, 0, 0, true)

    local Lx, Ly, Lz = FromJoint(-1, 0.5, 0, -0.5, -0.5, 0, ArmAng)
    SetPart(Parts["Left Arm"], Lx, Ly, Lz, ArmAng, true)

    Lx, Ly, Lz = FromJoint(1, 0.5, 0, 0.5, -0.5, 0, -ArmAng)
    SetPart(Parts["Right Arm"], Lx, Ly, Lz, -ArmAng, true)

    Lx, Ly, Lz = FromJoint(-0.5, -1, 0, 0, -1, 0, LegAng)
    SetPart(Parts["Left Leg"], Lx, Ly, Lz, LegAng, true)

    Lx, Ly, Lz = FromJoint(0.5, -1, 0, 0, -1, 0, -LegAng)
    SetPart(Parts["Right Leg"], Lx, Ly, Lz, -LegAng, true)
end

function Runtime:IsEdit()
    return self.Mode == "Edit"
end

function Runtime:IsPlay()
    return self.Mode == "Play"
end

function Runtime:IsRun()
    return self.Mode == "Run"
end

function Runtime:IsPaused()
    return self.Paused == true
end

function Runtime:Pause()
    if self.Mode == "Edit" then return end
    self.Paused = true
    local Gui = rawget(_G, "Gui")
    if Gui and Gui.Console then Gui.Console:Print("[Runtime] Paused") end
end

function Runtime:Resume()
    if self.Mode == "Edit" then return end
    self.Paused = false
    local Gui = rawget(_G, "Gui")
    if Gui and Gui.Console then Gui.Console:Print("[Runtime] Resumed") end
end

function Runtime:TogglePause()
    if self.Mode == "Edit" then return end
    if self.Paused then
        self:Resume()
    else
        self:Pause()
    end
end

function Runtime:Stop(DoRestore)
    if DoRestore == nil then DoRestore = true end
    local WasSession = self.Mode ~= "Edit"
    self.Mode = "Edit"
    self.Paused = false
    for I = 1, #self.Connections do
        self.Connections[I] = nil
    end
    self.Connections = {}
    StartedScripts = {}
    self.ModuleCache = {}
    ServerQueue = {}
    ClientQueue = {}
    self.CharVelY = 0
    self.WalkPhase = 0
    self.CharPos = nil
    local Phys = package.loaded["Services.Physics"] or rawget(_G, "Physics")
    if Phys and Phys.Reset then Phys:Reset() end
    if self.Character then
        if self.Character.Destroy then self.Character:Destroy() end
        self.Character = nil
        self.CharacterRoot = nil
        self.CharacterParts = nil
    end
    if self.LocalPlayer then
        local P = self.LocalPlayer
        local Parent = rawget(P, "_Parent") or P.Parent
        if Parent and Parent.Children then
            for I = #Parent.Children, 1, -1 do
                if Parent.Children[I] == P then
                    table.remove(Parent.Children, I)
                end
            end
        end
        self.LocalPlayer = nil
        local Players = rawget(_G, "Players")
        if Players then rawset(Players, "LocalPlayer", nil) end
    end
    if DoRestore and WasSession then
        local Rep = package.loaded["Services.Replication"] or rawget(_G, "Replication")
        if not Rep then
            pcall(function() Rep = require("Services.Replication") end)
        end
        if Rep and Rep.EndSession then
            Rep:EndSession()
        end
    elseif not DoRestore then
        -- keep session snapshot; only tear down play runtime
    end
    local Visuals = package.loaded["Services.Visuals"]
    if Visuals and Visuals.Invalidate then Visuals.Invalidate() end
    local Explorer = package.loaded["Services.Explorer"]
    if Explorer and Explorer.Refresh then Explorer:Refresh() end
end

function Runtime:StartRun()
    self:Stop(false)
    local Rep = package.loaded["Services.Replication"] or rawget(_G, "Replication")
    if not Rep then pcall(function() Rep = require("Services.Replication") end) end
    if Rep then
        if Rep.Active and Rep.EditSnapshot and Rep.RestoreWorkspace then
            Rep:RestoreWorkspace(Rep.EditSnapshot)
        elseif Rep.BeginSession then
            Rep:BeginSession()
        end
    end
    self.Mode = "Run"
    EnsureRunService()
    local Phys = package.loaded["Services.Physics"] or rawget(_G, "Physics")
    if Phys and Phys.Reset then Phys:Reset() end
    WalkAttachRemotes(rawget(_G, "Game"))
    local List = {}
    CollectScripts(rawget(_G, "ServerScriptService"), "Script", List)
    CollectScripts(rawget(_G, "Workspace"), "Script", List)
    CollectScripts(rawget(_G, "Game"), "Script", List)
    for I = 1, #List do
        StartScript(List[I], false)
    end
    local Gui = rawget(_G, "Gui")
    if Gui and Gui.Console then Gui.Console:Print("[Runtime] Run (server scripts only)") end
end

function Runtime:StartPlay(AtCamera)
    self:Stop(false)
    local Rep = package.loaded["Services.Replication"] or rawget(_G, "Replication")
    if not Rep then pcall(function() Rep = require("Services.Replication") end) end
    if Rep then
        if Rep.Active and Rep.EditSnapshot and Rep.RestoreWorkspace then
            Rep:RestoreWorkspace(Rep.EditSnapshot)
        elseif Rep.BeginSession then
            Rep:BeginSession()
        end
    end
    self.Mode = "Play"
    EnsureRunService()
    local Phys = package.loaded["Services.Physics"] or rawget(_G, "Physics")
    if Phys and Phys.Reset then Phys:Reset() end
    CreateLocalPlayer()
    WalkAttachRemotes(rawget(_G, "Game"))

    local Pos = {0, 5, 0}
    if AtCamera then
        local Cam = Workspace and Workspace.CurrentCamera
        local P = Cam and (Cam:GetAttribute("Position") or Cam.Position)
        if type(P) == "table" then
            Pos = {P[1] or 0, math.max(P[2] or 5, 5), P[3] or 0}
        end
    else
        local Spawn = FindSpawnLocation()
        if Spawn and Spawn.Position then
            local P = Spawn.Position
            if type(P) == "table" and P.ToArray then P = P:ToArray() end
            if type(P) == "table" then
                Pos = {P[1] or 0, math.max((P[2] or 0) + 3, 5), P[3] or 0}
            end
        end
    end

    local Char = SpawnCharacter(Pos)
    if self.LocalPlayer then
        self.LocalPlayer.Character = Char
    end

    local ServerList = {}
    CollectScripts(rawget(_G, "ServerScriptService"), "Script", ServerList)
    CollectScripts(rawget(_G, "Workspace"), "Script", ServerList)
    CollectScripts(rawget(_G, "Game"), "Script", ServerList)
    for I = 1, #ServerList do
        StartScript(ServerList[I], false)
    end

    local ClientList = {}
    CollectScripts(rawget(_G, "StarterPlayer"), "LocalScript", ClientList)
    CollectScripts(rawget(_G, "StarterGui"), "LocalScript", ClientList)
    if self.LocalPlayer then
        CollectScripts(self.LocalPlayer, "LocalScript", ClientList)
    end
    if Char then
        CollectScripts(Char, "LocalScript", ClientList)
    end
    for I = 1, #ClientList do
        StartScript(ClientList[I], true)
    end

    local Gui = rawget(_G, "Gui")
    if Gui and Gui.Console then
        Gui.Console:Print(AtCamera and "[Runtime] Play Here" or "[Runtime] Play")
    end
end

function Runtime:Tick(Dt)
    if self.Mode == "Edit" then return end
    if self.Paused then return end
    local Rs = EnsureRunService()
    if Rs.Heartbeat then Rs.Heartbeat:Fire(Dt) end
    if Rs.Stepped then Rs.Stepped:Fire(Dt, Dt) end

    for I = #ServerQueue, 1, -1 do
        local Msg = table.remove(ServerQueue, I)
        if Msg and Msg.Kind == "RemoteEvent" and Msg.Target and Msg.Target.OnServerEvent then
            Msg.Target.OnServerEvent:Fire(self.LocalPlayer, table.unpack(Msg.Args or {}))
        end
    end
    for I = #ClientQueue, 1, -1 do
        local Msg = table.remove(ClientQueue, I)
        if Msg and Msg.Kind == "RemoteEvent" and Msg.Target and Msg.Target.OnClientEvent then
            Msg.Target.OnClientEvent:Fire(table.unpack(Msg.Args or {}))
        end
    end

    for I = #self.Connections, 1, -1 do
        local E = self.Connections[I]
        if E and E.Co and coroutine.status(E.Co) == "suspended" then
            local Ok, Res = coroutine.resume(E.Co)
            if not Ok then
                local Gui = rawget(_G, "Gui")
                if Gui and Gui.Console then Gui.Console:Print("[Script Error] " .. tostring(Res)) end
                table.remove(self.Connections, I)
            end
        elseif E and E.Co and coroutine.status(E.Co) == "dead" then
            table.remove(self.Connections, I)
        end
    end

    if Rs.RenderStepped then Rs.RenderStepped:Fire(Dt) end
end

_G.Runtime = Runtime
return Runtime