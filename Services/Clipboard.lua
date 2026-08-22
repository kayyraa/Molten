local Instance = require("Services.Instance")
local Vector3 = require("Services.Vector3")

local Clipboard = {}

local NonCloneableClasses = {
    Camera = true,
    Workspace = true,
    ReplicatedStorage = true,
    Lighting = true,
    ServerScriptService = true,
    ServerStorage = true,
    StarterGui = true,
    CoreGui = true,
    Game = true,
    Folder = false
}

local BlockedNames = {
    Baseplate = true,
    SelectionHighlight = true
}

local ClipboardData = nil

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

local SkipKeys = {
    Children = true,
    Attributes = true,
    OnEnter = true,
    OnLeave = true,
    OnClick = true,
    Changed = true,
    _Parent = true,
    _IsHovered = true,
    ClassName = true,
    Guid = true,
    GUID = true,
}

local function SnapshotNode(Node)
    local Snap = {
        ClassName = Node.ClassName,
        Properties = {},
        Attributes = {},
        Children = {}
    }

    for Key, Val in pairs(Node) do
        if type(Key) == "string" and not SkipKeys[Key] and type(Val) ~= "function" then
            Snap.Properties[Key] = CloneValue(Val)
        end
    end

    local AttrRoot = rawget(Node, "Attributes")
    if AttrRoot then
        for Key, Val in pairs(AttrRoot) do
            Snap.Attributes[Key] = CloneValue(Val)
        end
    end

    local Kids = rawget(Node, "Children")
    if Kids then
        for _, Child in ipairs(Kids) do
            if not BlockedNames[Child.Name] then
                Snap.Children[#Snap.Children + 1] = SnapshotNode(Child)
            end
        end
    end

    return Snap
end

local function InstantiateSnapshot(Snap, Parent)
    local Obj = Instance.new(Snap.ClassName, Parent)

    for Key, Val in pairs(Snap.Properties) do
        Obj[Key] = CloneValue(Val)
    end

    for Key, Val in pairs(Snap.Attributes) do
        Obj:SetAttribute(Key, CloneValue(Val))
    end

    for _, ChildSnap in ipairs(Snap.Children) do
        InstantiateSnapshot(ChildSnap, Obj)
    end

    return Obj
end

--- @param Nodes table -- list of instances to copy
function Clipboard:Copy(Nodes)
    if not Nodes or #Nodes == 0 then
        return false
    end

    local Snaps = {}
    for _, Node in ipairs(Nodes) do
        if Node and not BlockedNames[Node.Name] and NonCloneableClasses[Node.ClassName] ~= true then
            Snaps[#Snaps + 1] = SnapshotNode(Node)
        end
    end

    if #Snaps == 0 then
        return false
    end

    ClipboardData = Snaps
    return true
end

function Clipboard:HasData()
    return ClipboardData ~= nil and #ClipboardData > 0
end

--- @param Parent Instance -- where the pasted copies should be parented
--- @return table -- list of newly created instances
function Clipboard:Paste(Parent)
    if not ClipboardData or not Parent then
        return {}
    end

    local Created = {}
    for _, Snap in ipairs(ClipboardData) do
        Created[#Created + 1] = InstantiateSnapshot(Snap, Parent)
    end

    return Created
end

return Clipboard