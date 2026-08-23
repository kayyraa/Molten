local Vector3 = require("Services.Vector3")
local Color = require("Services.Color")
local UDim = require("Services.UDim")

local Instance = {}

local GuidCounter = 0
local GuidIndex = {}

local function NextGuid()
    GuidCounter = GuidCounter + 1

    local t = 0
    pcall(function()
        if love and love.timer then
            t = math.floor(love.timer.getTime() * 1000) % 65535
        end
    end)

    return string.format("%08x-%04x-%04x", GuidCounter, t, math.random(0, 65535))
end

function Instance.GetByGuid(guid)
    return GuidIndex[guid]
end

local Inheritance = {
    Part = {"Part", "BasePart", "PVInstance", "Instance"},
    WedgePart = {"WedgePart", "Part", "BasePart", "PVInstance", "Instance"},
    CornerWedgePart = {"CornerWedgePart", "Part", "BasePart", "PVInstance", "Instance"},
    MeshPart = {"MeshPart", "BasePart", "PVInstance", "Instance"},
    SpawnLocation = {"SpawnLocation", "Part", "BasePart", "PVInstance", "Instance"},
    UnionOperation = {"UnionOperation", "BasePart", "PVInstance", "Instance"},
    Decal = {"Decal", "FaceInstance", "Instance"},
    Texture = {"Texture", "Decal", "FaceInstance", "Instance"},
    PointLight = {"PointLight", "Light", "Instance"},
    SpotLight = {"SpotLight", "Light", "Instance"},
    SurfaceLight = {"SurfaceLight", "Light", "Instance"},
    Attachment = {"Attachment", "Instance"},
    HandleAdornment = {"HandleAdornment", "PVInstance", "Instance"},
    Camera = {"Camera", "Instance"},
    Folder = {"Folder", "Instance"},
    Model = {"Model", "PVInstance", "Instance"},
    ScreenGui = {"ScreenGui", "LayerCollector", "GuiBase2D", "Instance"},
    Frame = {"Frame", "GuiObject", "GuiBase2D", "Instance"},
    TextLabel = {"TextLabel", "GuiObject", "GuiBase2D", "Instance"},
    ImageLabel = {"ImageLabel", "GuiObject", "GuiBase2D", "Instance"},
    UiPadding = {"UiPadding", "Instance"},
    Highlight = {"Highlight", "Instance"},
    SurfaceAppearance = {"SurfaceAppearance", "Instance"},
    Lighting = {"Lighting", "Instance"},
    Workspace = {"Workspace", "Instance"},
    ReplicatedStorage = {"ReplicatedStorage", "Instance"},
    ServerScriptService = {"ServerScriptService", "Instance"},
    ServerStorage = {"ServerStorage", "Instance"},
    StarterGui = {"StarterGui", "Instance"},
    StarterPlayer = {"StarterPlayer", "Instance"},
    StarterPlayerScripts = {"StarterPlayerScripts", "Instance"},
    StarterCharacterScripts = {"StarterCharacterScripts", "Instance"},
    Script = {"Script", "Instance"},
    LocalScript = {"LocalScript", "Instance"},
    ModuleScript = {"ModuleScript", "Instance"},
    RemoteEvent = {"RemoteEvent", "Instance"},
    RemoteFunction = {"RemoteFunction", "Instance"},
    BindableEvent = {"BindableEvent", "Instance"},
    BindableFunction = {"BindableFunction", "Instance"},
    Motor6D = {"Motor6D", "Instance"},
    Players = {"Players", "Instance"},
    Player = {"Player", "Instance"},
    Terrain = {"Terrain", "Instance"},
    BloomEffect = {"BloomEffect", "PostEffect", "Instance"},
    BlurEffect = {"BlurEffect", "PostEffect", "Instance"},
    DepthOfFieldEffect = {"DepthOfFieldEffect", "PostEffect", "Instance"},
    ColorCorrectionEffect = {"ColorCorrectionEffect", "PostEffect", "Instance"},
    SunRaysEffect = {"SunRaysEffect", "PostEffect", "Instance"},
    Atmosphere = {"Atmosphere", "Instance"},
    Clouds = {"Clouds", "Instance"},
    PostEffect = {"PostEffect", "Instance"},
}

local function CreateSignal()
    local Signal = {}
    local Handlers = {}

    function Signal:Connect(Fn)
        Handlers[#Handlers + 1] = Fn

        return {
            Disconnect = function()
                for Index = 1, #Handlers do
                    if Handlers[Index] == Fn then
                        table.remove(Handlers, Index)
                        break
                    end
                end
            end
        }
    end

    function Signal:Fire(...)
        for Index = 1, #Handlers do
            Handlers[Index](...)
        end
    end

    function Signal:HasConnections()
        return #Handlers > 0
    end

    return Signal
end

local function CloneValue(Value)
    if type(Value) ~= "table" then
        return Value
    end

    if Value.ToArray then
        local Arr = Value:ToArray()
        return Vector3.new(Arr[1], Arr[2], Arr[3])
    end

    local Copy = {}
    for Key, Val in pairs(Value) do
        Copy[Key] = CloneValue(Val)
    end

    return Copy
end

local Defaults = {
    BasePart = {
        Size = Vector3.new(4, 4, 4),
        Position = Vector3.new(0, 0, 0),
        Orientation = Vector3.new(0, 0, 0),
        Color = Color.FromRGBA(255, 255, 255),
        Material = {
            Reflectivity = 0,
            Roughness = 0.5,
            Metalness = 0,
            Refractivity = 0
        },
        Anchored = false,
        CanCollide = true,
        CanTouch = true,
        CanQuery = true,
        CollisionGroup = "Default",
        CollisionFidelity = "Default",
        AssemblyLinearVelocity = Vector3.new(0, 0, 0),
        AssemblyAngularVelocity = Vector3.new(0, 0, 0),
        Velocity = Vector3.new(0, 0, 0),
        Transparency = 0,
        Locked = false
    },

    Part = {
        Shape = "Block"
    },

    SpawnLocation = {
        Shape = "Block",
        Duration = 0,
        Enabled = true,
        Neutral = true,
        AllowTeamChangeOnTouch = false,
        TeamColor = {0.4, 0.7, 1, 1},
    },

    WedgePart = {
        Shape = "Wedge"
    },

    CornerWedgePart = {
        Shape = "CornerWedge"
    },

    MeshPart = {
        Shape = "Mesh"
    },

    SurfaceAppearance = {
        ColorMap = "",
        MetalnessMap = "",
        RoughnessMap = "",
        NormalMap = "",
        Color = Color.FromRGBA(255, 255, 255),
        Roughness = 0.5,
        Metalness = 0,
        AlphaMode = "Overlay",
    },

    Decal = {
        Face = "Front",
        Texture = "",
        UvStuds = {1, 1},
        UvOffset = {0, 0},
        Color = Color.FromRGBA(255, 255, 255),
        Transparency = 0
    },

    Texture = {
        Face = "Front",
        Texture = "",
        UvStuds = {1, 1},
        UvOffset = {0, 0},
        Color = Color.FromRGBA(255, 255, 255),
        Transparency = 0,
        StudsPerTileU = 1,
        StudsPerTileV = 1
    },

    PointLight = {
        Brightness = 1,
        Range = 16,
        Color = Color.FromRGBA(255, 255, 255),
        Shadows = false,
        Enabled = true
    },

    Attachment = {
        Position = Vector3.new(0, 0, 0),
        Visible = true,
        AxisVisible = true
    },

    HandleAdornment = {
        Adornee = nil,
        Shape = "Sphere",
        Size = Vector3.new(1, 1, 1),
        Color = Color.FromRGBA(0, 170, 255),
        Transparency = 0.3,
        Visible = true,
        AlwaysOnTop = true,
        Shadows = true,
        CFrameOffset = Vector3.new(0, 0, 0)
    },

    Highlight = {
        Adornee = nil,
        Enabled = true,
        DepthMode = "AlwaysOnTop",
        FillColor = Color.FromRGBA(255, 80, 40),
        FillTransparency = 0.7,
        OutlineColor = Color.FromRGBA(255, 200, 60),
        OutlineTransparency = 0
    },

    Frame = {
        BackgroundColor = Color.FromRGBA(40, 40, 40),
        Position = UDim.New(0, 0, 0, 0),
        Size = UDim.New(0, 100, 0, 100),
        Visible = true,
        ZIndex = 1,
        ClipsDescendants = true,
        ClipDescendants = true
    },

    
    Lighting = {
        ClockTime = 14,
        Brightness = 2,
        Ambient = Color.FromRGBA(70, 70, 80),
        OutdoorAmbient = Color.FromRGBA(128, 128, 140),
        ColorShift_Top = Color.FromRGBA(0, 0, 0),
        ColorShift_Bottom = Color.FromRGBA(0, 0, 0),
        FogColor = Color.FromRGBA(192, 192, 192),
        FogStart = 0,
        FogEnd = 100000,
        GlobalShadows = true,
        EnvironmentDiffuseScale = 1,
        EnvironmentSpecularScale = 1,
        Rendering = "Rasterized",
    },

    Workspace = {
        Gravity = 196.2,
        FallenPartsDestroyHeight = -500,
        StreamingEnabled = false,
    },

    Camera = {
        FieldOfView = 70,
    },

    Script = {
        Enabled = true,
        Source = "",
    },

    LocalScript = {
        Enabled = true,
        Source = "",
    },
    ModuleScript = {
        Source = "",
    },
    RemoteEvent = {},
    RemoteFunction = {},
    BindableEvent = {},
    BindableFunction = {},
    Motor6D = {
        Part0 = nil,
        Part1 = nil,
        C0 = {0, 0, 0},
        C1 = {0, 0, 0},
        Enabled = true,
    },
    Players = {},
    Player = {},

    Folder = {},
    ReplicatedStorage = {},
    ServerScriptService = {},
    ServerStorage = {},
    StarterGui = {},

    StarterPlayer = {
        CameraMaxZoomDistance = 128,
        CameraMinZoomDistance = 0.5,
        CameraMode = "Classic",
        DevCameraOcclusionMode = "Zoom",
        DevComputerCameraMovementMode = "UserChoice",
        DevComputerMovementMode = "UserChoice",
        DevTouchCameraMovementMode = "UserChoice",
        DevTouchMovementMode = "UserChoice",
        EnableMouseLockOption = true,
        AutoJumpEnabled = true,
        CharacterJumpHeight = 7.2,
        CharacterJumpPower = 50,
        CharacterUseJumpPower = false,
        CharacterMaxSlopeAngle = 89,
        CharacterWalkSpeed = 16,
        HealthDisplayDistance = 100,
        NameDisplayDistance = 100,
        LoadCharacterAppearance = true,
        UserEmotesEnabled = true,
    },
    StarterPlayerScripts = {},
    StarterCharacterScripts = {},

    Terrain = {
        WaterColor = {12/255, 84/255, 91/255, 1},
        WaterReflectance = 1,
        WaterTransparency = 0.3,
        WaterWaveSize = 0.15,
        WaterWaveSpeed = 10,
    },

    BloomEffect = {
        Enabled = true,
        Intensity = 0.4,
        Size = 24,
        Threshold = 0.95,
    },
    BlurEffect = {
        Enabled = true,
        Size = 24,
    },
    DepthOfFieldEffect = {
        Enabled = false,
        FarIntensity = 0.75,
        FocusDistance = 50,
        InFocusRadius = 30,
        NearIntensity = 0.75,
    },
    ColorCorrectionEffect = {
        Enabled = true,
        Brightness = 0,
        Contrast = 0,
        Saturation = 0,
        TintColor = {1, 1, 1, 1},
    },
    SunRaysEffect = {
        Enabled = true,
        Intensity = 0.25,
        Spread = 1,
    },
    Atmosphere = {
        Density = 0.3,
        Offset = 0.25,
        Color = {199/255, 199/255, 199/255, 1},
        Decay = {106/255, 112/255, 125/255, 1},
        Glare = 0,
        Haze = 0,
    },
    Clouds = {
        Cover = 0.5,
        Density = 0.7,
        Color = {1, 1, 1, 1},
    },
}

function Instance.new(ClassName, Parent)
    local Obj = {
        ClassName = ClassName,
        Name = ClassName,
        Children = {},
        Attributes = {},
        ZIndex = 1,
        DisplayOrder = 0,
        Guid = NextGuid(),
        OnEnter = CreateSignal(),
        OnLeave = CreateSignal(),
        OnClick = CreateSignal()
    }
    GuidIndex[Obj.Guid] = Obj

    local Chain = Inheritance[ClassName]
    if Chain then
        for Index = #Chain, 1, -1 do
            local Base = Chain[Index]
            local Def = Defaults[Base]
            if Def then
                for Key, Value in pairs(Def) do
                    Obj[Key] = CloneValue(Value)
                end
            end
        end
    else
        local Def = Defaults[ClassName]
        if Def then
            for Key, Value in pairs(Def) do
                Obj[Key] = CloneValue(Value)
            end
        end
    end

    Obj.Name = ClassName
    pcall(function()
        local R = package.loaded["Services.Runtime"] or rawget(_G, "Runtime")
        if R and R.HookInstance then R.HookInstance(Obj) end
    end)

    local isGui = (ClassName == "Frame" or ClassName == "TextLabel" or ClassName == "ImageLabel"
        or ClassName == "ScreenGui" or ClassName == "GuiObject")
    if isGui and Obj.Visible == nil then
        Obj.Visible = true
    end

    function Obj:GetChildren()
        return self.Children
    end

    function Obj:IsA(TargetClass)
        if self.ClassName == TargetClass then
            return true
        end

        local List = Inheritance[self.ClassName]
        if List then
            for Index = 1, #List do
                if List[Index] == TargetClass then
                    return true
                end
            end
        end

        return TargetClass == "Instance"
    end

    function Obj:GetChildrenOfClass(TargetClass)
        local Matched = {}
        for Index = 1, #self.Children do
            if self.Children[Index]:IsA(TargetClass) then
                Matched[#Matched + 1] = self.Children[Index]
            end
        end
        return Matched
    end

    function Obj:SetAttribute(Name, Value)
        local old = self.Attributes[Name]
        self.Attributes[Name] = Value

        if old ~= Value then
            local ch = rawget(self, "Changed")
            if ch and ch.Fire then
                pcall(function()
                    ch:Fire("Attribute." .. tostring(Name))
                end)
            end
        end
    end

    function Obj:GetAttribute(Name)
        return self.Attributes[Name]
    end

    function Obj:FindFirstChild(Name)
        for Index = 1, #self.Children do
            if self.Children[Index].Name == Name then
                return self.Children[Index]
            end
        end
        return nil
    end

    function Obj:Destroy()
        if self.Guid and GuidIndex[self.Guid] == self then
            GuidIndex[self.Guid] = nil
        end

        if self.Parent then
            for Index = 1, #self.Parent.Children do
                if self.Parent.Children[Index] == self then
                    table.remove(self.Parent.Children, Index)
                    break
                end
            end
        end

        
        local kids = rawget(self, "Children")
        if kids then
            for i = #kids, 1, -1 do
                local c = kids[i]
                if c then
                    rawset(c, "_Parent", nil)
                    if c.Guid and GuidIndex[c.Guid] == c then
                        GuidIndex[c.Guid] = nil
                    end
                end
                kids[i] = nil
            end
        end
    end

    function Obj:Clone()
        local copy = Instance.new(self.ClassName)

        
        local skip = {
            Children = true, Guid = true, _Parent = true, Parent = true,
            OnEnter = true, OnLeave = true, OnClick = true, Changed = true,
            ClassName = true,
        }

        for k, v in pairs(self) do
            if not skip[k] and type(v) ~= "function" then
                if k == "Attributes" then
                    copy.Attributes = CloneValue(v) or {}
                else
                    local ok, cloned = pcall(CloneValue, v)
                    if ok then
                        rawset(copy, k, cloned)
                    end
                end
            end
        end

        copy.Name = self.Name

        
        local kids = rawget(self, "Children")
        if kids then
            for i = 1, #kids do
                local childCopy = kids[i]:Clone()
                childCopy.Parent = copy
            end
        end

        return copy
    end

    local Metatable = {
        __index = function(Tbl, Key)
            if Key == "Parent" then
                return rawget(Tbl, "_Parent")
            end
            return rawget(Tbl, Key)
        end,

        __newindex = function(Tbl, Key, Value)
            if Key == "Parent" then
                local OldParent = rawget(Tbl, "_Parent")
                if OldParent then
                    for Index = 1, #OldParent.Children do
                        if OldParent.Children[Index] == Tbl then
                            table.remove(OldParent.Children, Index)
                            break
                        end
                    end
                end

                rawset(Tbl, "_Parent", Value)
                if Value and Value.Children then
                    table.insert(Value.Children, Tbl)
                end
                local Ex = package.loaded["Services.Explorer"] or rawget(_G, "Explorer")
                if Ex and Ex.MarkDirty then
                    pcall(function() Ex:MarkDirty() end)
                end
            else
                local old = rawget(Tbl, Key)
                rawset(Tbl, Key, Value)

                if old ~= Value then
                    local ch = rawget(Tbl, "Changed")
                    if ch and ch.Fire then
                        pcall(function()
                            ch:Fire(Key)
                        end)
                    end
                    if Key == "Name" then
                        local Ex = package.loaded["Services.Explorer"] or rawget(_G, "Explorer")
                        if Ex and Ex.MarkDirty then
                            pcall(function() Ex:MarkDirty() end)
                        end
                    end
                end
            end
        end
    }

    Obj.Changed = CreateSignal()
    setmetatable(Obj, Metatable)

    if Parent then
        Obj.Parent = Parent
    end

    return Obj
end

local ServiceDefinitions = {
    {Name = "Workspace", ClassName = "Workspace"},
    {Name = "ReplicatedStorage", ClassName = "ReplicatedStorage"},
    {Name = "Lighting", ClassName = "Lighting"},
    {Name = "ServerScriptService", ClassName = "ServerScriptService"},
    {Name = "ServerStorage", ClassName = "ServerStorage"},
    {Name = "StarterGui", ClassName = "StarterGui"},
    {Name = "StarterPlayer", ClassName = "StarterPlayer"},
    {Name = "Players", ClassName = "Players"},
}

if not _G.Game then
    _G.Game = Instance.new("Folder")
    _G.Game.Name = "Game"

    for Index = 1, #ServiceDefinitions do
        local Def = ServiceDefinitions[Index]
        local Service = Instance.new(Def.ClassName, _G.Game)
        Service.Name = Def.Name
        _G[Def.Name] = Service
    end
end

if _G.StarterPlayer then
    if not _G.StarterPlayer:FindFirstChild("StarterPlayerScripts") then
        local Sps = Instance.new("StarterPlayerScripts", _G.StarterPlayer)
        Sps.Name = "StarterPlayerScripts"
    end
    if not _G.StarterPlayer:FindFirstChild("StarterCharacterScripts") then
        local Scs = Instance.new("StarterCharacterScripts", _G.StarterPlayer)
        Scs.Name = "StarterCharacterScripts"
    end
    _G.StarterPlayerScripts = _G.StarterPlayer:FindFirstChild("StarterPlayerScripts")
    _G.StarterCharacterScripts = _G.StarterPlayer:FindFirstChild("StarterCharacterScripts")
end

if not _G.CoreGui then
    _G.CoreGui = Instance.new("Folder")
    _G.CoreGui.Name = "CoreGui"
end

if _G.Workspace and rawget(_G.Workspace, "CurrentCamera") == nil then
    rawset(_G.Workspace, "CurrentCamera", nil)
end

if _G.Workspace then
    local existing = nil
    for _, ch in ipairs(_G.Workspace:GetChildren()) do
        if ch.ClassName == "Terrain" or ch.Name == "Terrain" then
            existing = ch
            break
        end
    end
    if not existing then
        local terrain = Instance.new("Terrain", _G.Workspace)
        terrain.Name = "Terrain"
        
        terrain._Voxels = {}
        terrain._CellSize = 4

        function terrain:FillBlock(cframe, size, material)
            
            local pos
            if type(cframe) == "table" and cframe.Position then
                pos = cframe.Position
            elseif type(cframe) == "table" and (cframe[1] or cframe.Px) then
                pos = cframe
            else
                pos = {0, 0, 0}
            end
            local px = pos[1] or pos.Px or 0
            local py = pos[2] or pos.Py or 0
            local pz = pos[3] or pos.Pz or 0
            local sx, sy, sz = 4, 4, 4
            if type(size) == "table" then
                if size.ToArray then
                    local a = size:ToArray()
                    sx, sy, sz = a[1] or 4, a[2] or 4, a[3] or 4
                else
                    sx = size[1] or size.X or size.Px or 4
                    sy = size[2] or size.Y or size.Py or 4
                    sz = size[3] or size.Z or size.Pz or 4
                end
            end
            local mat = material
            if type(mat) == "table" then mat = tostring(mat) end
            mat = tostring(mat or "Grass")
            local cell = self._CellSize or 4
            local x0 = math.floor((px - sx * 0.5) / cell)
            local x1 = math.floor((px + sx * 0.5) / cell)
            local y0 = math.floor((py - sy * 0.5) / cell)
            local y1 = math.floor((py + sy * 0.5) / cell)
            local z0 = math.floor((pz - sz * 0.5) / cell)
            local z1 = math.floor((pz + sz * 0.5) / cell)
            self._Voxels = self._Voxels or {}
            local n = 0
            for x = x0, x1 do
                for y = y0, y1 do
                    for z = z0, z1 do
                        local key = x .. "," .. y .. "," .. z
                        self._Voxels[key] = mat
                        n = n + 1
                    end
                end
            end
            return n
        end

        function terrain:FillBall(position, radius, material)
            local px, py, pz = 0, 0, 0
            if type(position) == "table" then
                if position.ToArray then
                    local a = position:ToArray()
                    px, py, pz = a[1], a[2], a[3]
                else
                    px = position[1] or position.Px or 0
                    py = position[2] or position.Py or 0
                    pz = position[3] or position.Pz or 0
                end
            end
            radius = radius or 4
            local size = {radius * 2, radius * 2, radius * 2}
            return self:FillBlock({px, py, pz}, size, material)
        end

        function terrain:Fill(size, cframe, vertexShape, material)
            
            vertexShape = tostring(vertexShape or "Block")
            if vertexShape == "Ball" or vertexShape == "Sphere" then
                local pos = cframe
                if type(cframe) == "table" and cframe.Position then pos = cframe.Position end
                local r = 4
                if type(size) == "table" then
                    r = (size[1] or size.X or 8) * 0.5
                end
                return self:FillBall(pos, r, material)
            end
            return self:FillBlock(cframe, size, material)
        end

        function terrain:Clear()
            self._Voxels = {}
        end

        _G.Terrain = terrain
        rawset(_G.Workspace, "Terrain", terrain)
    else
        _G.Terrain = existing
        rawset(_G.Workspace, "Terrain", existing)
    end
end

return Instance