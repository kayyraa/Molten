local Enum = {}

Enum.RaycastFilterMode = {
    Exclude = "Exclude",
    Include = "Include",
}

Enum.Material = {
    Plastic = "Plastic",
    SmoothPlastic = "SmoothPlastic",
    Neon = "Neon",
    Wood = "Wood",
    Metal = "Metal",
    Concrete = "Concrete",
    Glass = "Glass",
    Fabric = "Fabric",
    Sand = "Sand",
    Grass = "Grass",
    Ice = "Ice",
    Brick = "Brick",
    Granite = "Granite",
    Marble = "Marble",
    ForceField = "ForceField",
    Slate = "Slate",
    Cobblestone = "Cobblestone",
    WoodPlanks = "WoodPlanks",
    Foil = "Foil",
    DiamondPlate = "DiamondPlate",
    Air = "Air",
    Water = "Water",
    Rock = "Rock",
    Glacier = "Glacier",
    Snow = "Snow",
    Sandstone = "Sandstone",
    Mud = "Mud",
    Basalt = "Basalt",
    Ground = "Ground",
    Asphalt = "Asphalt",
    LeafyGrass = "LeafyGrass",
    Salt = "Salt",
    Limestone = "Limestone",
    Pavement = "Pavement",
}

Enum.NormalId = {
    Top = "Top",
    Bottom = "Bottom",
    Front = "Front",
    Back = "Back",
    Left = "Left",
    Right = "Right",
}

Enum.PartType = {
    Ball = "Ball",
    Block = "Block",
    Cylinder = "Cylinder",
    Wedge = "Wedge",
    CornerWedge = "CornerWedge",
    Cone = "Cone",
}

Enum.Shape = Enum.PartType

Enum.HighlightDepthMode = {
    AlwaysOnTop = "AlwaysOnTop",
    Occluded = "Occluded",
}

Enum.HandleAdornmentShape = {
    Cone = "Cone",
    Sphere = "Sphere",
    Cube = "Cube",
    Cylinder = "Cylinder",
    Wedge = "Wedge",
    Plane = "Plane",
}

-- ---------------------------------------------------------------------------
-- RaycastParams / RaycastResult
-- ---------------------------------------------------------------------------

local RaycastParams = {}
RaycastParams.__index = RaycastParams

function RaycastParams.new()
    return setmetatable({
        FilterDescendantsInstances = {},
        FilterType = Enum.RaycastFilterMode.Exclude,
        IgnoreWater = true,
        CollisionGroup = "Default",
        RespectCanCollide = true,
    }, RaycastParams)
end

local RaycastResult = {}
RaycastResult.__index = RaycastResult

function RaycastResult.new(fields)
    fields = fields or {}

    return setmetatable({
        Instance = fields.Instance,
        Position = fields.Position,
        Normal = fields.Normal,
        Distance = fields.Distance or 0,
        Material = fields.Material,
    }, RaycastResult)
end

-- ---------------------------------------------------------------------------
-- Fabric (small math utility namespace)
-- ---------------------------------------------------------------------------

local Fabric = {}

function Fabric.Lerp(a, b, t)
    return a + (b - a) * t
end

-- ---------------------------------------------------------------------------
-- Globals
-- ---------------------------------------------------------------------------

_G.Enum = Enum
_G.RaycastParams = RaycastParams
_G.RaycastResult = RaycastResult
_G.Fabric = Fabric

_G.Vector3 = require("Services.Vector3")
_G.Color = require("Services.Color")
_G.CFrame = require("Services.CFrame")
_G.UDim = require("Services.UDim")

if not _G.Instance then
    _G.Instance = require("Services.Instance")
end

return {
    Enum = Enum,
    RaycastParams = RaycastParams,
    RaycastResult = RaycastResult,
    Fabric = Fabric,
}