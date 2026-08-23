local Instance = require("Services.Instance")
local Vector3 = require("Services.Vector3")
local Color = require("Services.Color")

local Replication = {}

Replication.EditSnapshot = nil
Replication.Active = false

local SkipNames = {
    Camera = true,
}

local SkipClasses = {
    Camera = true,
}

local function CloneValue(V)
    if type(V) ~= "table" then
        return V
    end
    if V.ToArray then
        local A = V:ToArray()
        return Vector3.new(A[1], A[2], A[3])
    end
    local Out = {}
    for K, Val in pairs(V) do
        Out[K] = CloneValue(Val)
    end
    return Out
end

local function SerializeInstance(Node, Depth)
    Depth = Depth or 0
    if Depth > 64 or not Node then return nil end
    local ClassName = Node.ClassName or "Folder"
    if SkipClasses[ClassName] then return nil end
    if SkipNames[Node.Name] and ClassName == "Camera" then return nil end

    local Data = {
        ClassName = ClassName,
        Name = Node.Name,
        Props = {},
        Attributes = {},
        Children = {},
    }

    local SkipProp = {
        Children = true, Parent = true, _Parent = true, ClassName = true,
        OnEnter = true, OnLeave = true, OnClick = true, Changed = true,
        Guid = true, GUID = true, Attributes = true,
    }

    for K, V in pairs(Node) do
        if not SkipProp[K] and type(V) ~= "function" then
            local Ok, Cloned = pcall(CloneValue, V)
            if Ok then
                Data.Props[K] = Cloned
            end
        end
    end

    local Attrs = rawget(Node, "Attributes")
    if type(Attrs) == "table" then
        for K, V in pairs(Attrs) do
            local Ok, Cloned = pcall(CloneValue, V)
            if Ok then Data.Attributes[K] = Cloned end
        end
    end

    local Kids = rawget(Node, "Children")
    if Kids then
        for I = 1, #Kids do
            local ChildData = SerializeInstance(Kids[I], Depth + 1)
            if ChildData then
                Data.Children[#Data.Children + 1] = ChildData
            end
        end
    end

    return Data
end

local function DeserializeInstance(Data, Parent)
    if not Data then return nil end
    local Obj = Instance.new(Data.ClassName or "Folder", Parent)
    Obj.Name = Data.Name or Data.ClassName or "Instance"

    if Data.Props then
        for K, V in pairs(Data.Props) do
            if K ~= "Name" and K ~= "ClassName" then
                pcall(function()
                    Obj[K] = CloneValue(V)
                end)
            end
        end
    end

    if Data.Attributes then
        for K, V in pairs(Data.Attributes) do
            pcall(function()
                Obj:SetAttribute(K, CloneValue(V))
            end)
        end
    end

    if Data.Children then
        for I = 1, #Data.Children do
            DeserializeInstance(Data.Children[I], Obj)
        end
    end

    return Obj
end

function Replication:CaptureWorkspace()
    local Ws = rawget(_G, "Workspace")
    if not Ws then return nil end
    local Snapshot = {
        Children = {},
        Gravity = Ws.Gravity,
        FallenPartsDestroyHeight = Ws.FallenPartsDestroyHeight,
    }
    local Kids = rawget(Ws, "Children") or {}
    for I = 1, #Kids do
        local Child = Kids[I]
        if Child and not SkipClasses[Child.ClassName] and Child.ClassName ~= "Camera" then
            local Data = SerializeInstance(Child, 0)
            if Data then
                Snapshot.Children[#Snapshot.Children + 1] = Data
            end
        end
    end
    return Snapshot
end

function Replication:RestoreWorkspace(Snapshot)
    local Ws = rawget(_G, "Workspace")
    if not Ws or not Snapshot then return end

    local Keep = {}
    local Kids = rawget(Ws, "Children") or {}
    for I = #Kids, 1, -1 do
        local Child = Kids[I]
        if Child and (Child.ClassName == "Camera" or Child.Name == "Camera") then
            Keep[#Keep + 1] = Child
        else
            if Child and Child.Destroy then
                Child:Destroy()
            else
                table.remove(Kids, I)
            end
        end
    end

    if Snapshot.Gravity ~= nil then Ws.Gravity = Snapshot.Gravity end
    if Snapshot.FallenPartsDestroyHeight ~= nil then
        Ws.FallenPartsDestroyHeight = Snapshot.FallenPartsDestroyHeight
    end

    for I = 1, #(Snapshot.Children or {}) do
        DeserializeInstance(Snapshot.Children[I], Ws)
    end

    local Visuals = package.loaded["Services.Visuals"] or rawget(_G, "Visuals")
    if Visuals and Visuals.Invalidate then Visuals.Invalidate() end
    local Explorer = package.loaded["Services.Explorer"] or rawget(_G, "Explorer")
    if Explorer and Explorer.MarkDirty then Explorer:MarkDirty() end
    if Explorer and Explorer.Refresh then Explorer:Refresh() end
end

function Replication:BeginSession()
    if self.Active then return end
    self.EditSnapshot = self:CaptureWorkspace()
    self.Active = true
end

function Replication:EndSession()
    if not self.Active then return end
    if self.EditSnapshot then
        self:RestoreWorkspace(self.EditSnapshot)
    end
    self.EditSnapshot = nil
    self.Active = false
end

_G.Replication = Replication
return Replication