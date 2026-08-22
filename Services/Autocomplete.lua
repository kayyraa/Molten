-- Services/Autocomplete.lua
-- Static knowledge of Molten's global API + Luau/Lua stdlib, used to power
-- the script editor's autocomplete popup. Kept data-only and separate from
-- ScriptEditor so it's easy to extend as the engine grows.

local Autocomplete = {}

-- Kind is used only for icon/coloring in the popup: "class", "function",
-- "property", "keyword", "enum", "local"
local function Members(List)
    local Map = {}
    for _, Entry in ipairs(List) do
        Map[#Map + 1] = Entry
    end
    return Map
end

-- ---------------------------------------------------------------------------
-- Top-level globals available in Molten scripts
-- ---------------------------------------------------------------------------

Autocomplete.Globals = {
    {Name = "game", Kind = "class", Detail = "DataModel"},
    {Name = "workspace", Kind = "class", Detail = "Workspace"},
    {Name = "Workspace", Kind = "class", Detail = "Workspace"},
    {Name = "script", Kind = "class", Detail = "Script"},
    {Name = "Vector3", Kind = "class", Detail = "Vector3 library"},
    {Name = "CFrame", Kind = "class", Detail = "CFrame library"},
    {Name = "Color3", Kind = "class", Detail = "Color library"},
    {Name = "Instance", Kind = "class", Detail = "Instance library"},
    {Name = "Enum", Kind = "class", Detail = "Enum library"},
    {Name = "RaycastParams", Kind = "class", Detail = "RaycastParams.new()"},
    {Name = "RaycastResult", Kind = "class", Detail = "RaycastResult"},
    {Name = "RunService", Kind = "class", Detail = "RunService"},
    {Name = "UserInputService", Kind = "class", Detail = "UserInputService"},
    {Name = "CollectionService", Kind = "class", Detail = "CollectionService"},
    {Name = "Lighting", Kind = "class", Detail = "Lighting service"},
    {Name = "ReplicatedStorage", Kind = "class", Detail = "ReplicatedStorage"},
    {Name = "ServerScriptService", Kind = "class", Detail = "ServerScriptService"},
    {Name = "ServerStorage", Kind = "class", Detail = "ServerStorage"},
    {Name = "StarterGui", Kind = "class", Detail = "StarterGui"},
    {Name = "CoreGui", Kind = "class", Detail = "CoreGui"},
    {Name = "print", Kind = "function", Detail = "print(...)"},
    {Name = "warn", Kind = "function", Detail = "warn(...)"},
    {Name = "error", Kind = "function", Detail = "error(message, level?)"},
    {Name = "assert", Kind = "function", Detail = "assert(value, message?)"},
    {Name = "type", Kind = "function", Detail = "type(value)"},
    {Name = "typeof", Kind = "function", Detail = "typeof(value)"},
    {Name = "pairs", Kind = "function", Detail = "pairs(t)"},
    {Name = "ipairs", Kind = "function", Detail = "ipairs(t)"},
    {Name = "next", Kind = "function", Detail = "next(t, key?)"},
    {Name = "pcall", Kind = "function", Detail = "pcall(f, ...)"},
    {Name = "xpcall", Kind = "function", Detail = "xpcall(f, handler, ...)"},
    {Name = "select", Kind = "function", Detail = "select(i, ...)"},
    {Name = "unpack", Kind = "function", Detail = "unpack(t)"},
    {Name = "require", Kind = "function", Detail = "require(path)"},
    {Name = "tonumber", Kind = "function", Detail = "tonumber(v, base?)"},
    {Name = "tostring", Kind = "function", Detail = "tostring(v)"},
    {Name = "setmetatable", Kind = "function", Detail = "setmetatable(t, mt)"},
    {Name = "getmetatable", Kind = "function", Detail = "getmetatable(t)"},
    {Name = "rawget", Kind = "function", Detail = "rawget(t, k)"},
    {Name = "rawset", Kind = "function", Detail = "rawset(t, k, v)"},
    {Name = "rawequal", Kind = "function", Detail = "rawequal(a, b)"},
    {Name = "rawlen", Kind = "function", Detail = "rawlen(t)"},
    {Name = "math", Kind = "class", Detail = "math library"},
    {Name = "string", Kind = "class", Detail = "string library"},
    {Name = "table", Kind = "class", Detail = "table library"},
    {Name = "coroutine", Kind = "class", Detail = "coroutine library"},
    {Name = "bit32", Kind = "class", Detail = "bit32 library"},
    {Name = "utf8", Kind = "class", Detail = "utf8 library"},
    {Name = "os", Kind = "class", Detail = "os library"},
    {Name = "debug", Kind = "class", Detail = "debug library"},
    {Name = "buffer", Kind = "class", Detail = "buffer library"},
    {Name = "vector", Kind = "class", Detail = "vector library"},
    {Name = "and", Kind = "keyword"},
    {Name = "break", Kind = "keyword"},
    {Name = "do", Kind = "keyword"},
    {Name = "else", Kind = "keyword"},
    {Name = "elseif", Kind = "keyword"},
    {Name = "end", Kind = "keyword"},
    {Name = "false", Kind = "keyword"},
    {Name = "for", Kind = "keyword"},
    {Name = "function", Kind = "keyword"},
    {Name = "if", Kind = "keyword"},
    {Name = "in", Kind = "keyword"},
    {Name = "local", Kind = "keyword"},
    {Name = "const", Kind = "keyword"},
    {Name = "nil", Kind = "keyword"},
    {Name = "not", Kind = "keyword"},
    {Name = "or", Kind = "keyword"},
    {Name = "repeat", Kind = "keyword"},
    {Name = "return", Kind = "keyword"},
    {Name = "then", Kind = "keyword"},
    {Name = "true", Kind = "keyword"},
    {Name = "until", Kind = "keyword"},
    {Name = "while", Kind = "keyword"},
    {Name = "continue", Kind = "keyword"},
}

-- ---------------------------------------------------------------------------
-- Members for "Global." completion, keyed by the exact global name above
-- ---------------------------------------------------------------------------

Autocomplete.Members = {
    Vector3 = Members({
        {Name = "new", Kind = "function", Detail = "Vector3.new(x, y, z)"},
        {Name = "zero", Kind = "property", Detail = "Vector3(0, 0, 0)"},
        {Name = "one", Kind = "property", Detail = "Vector3(1, 1, 1)"},
        {Name = "FromArray", Kind = "function", Detail = "Vector3.FromArray(arr)"},
    }),

    CFrame = Members({
        {Name = "new", Kind = "function", Detail = "CFrame.new(x, y, z)"},
        {Name = "Angles", Kind = "function", Detail = "CFrame.Angles(rx, ry, rz)"},
        {Name = "LookAt", Kind = "function", Detail = "CFrame.LookAt(eye, target, up?)"},
        {Name = "FromPositionRotation", Kind = "function", Detail = "CFrame.FromPositionRotation(pos, pitch, yaw)"},
    }),

    Color3 = Members({
        {Name = "FromRGBA", Kind = "function", Detail = "Color3.FromRGBA(r, g, b, a?)"},
        {Name = "Float", Kind = "function", Detail = "Color3.Float(r, g, b, a)"},
        {Name = "Mix", Kind = "function", Detail = "Color3.Mix(a, b, t)"},
        {Name = "Lerp", Kind = "function", Detail = "Color3.Lerp(a, b, t)"},
    }),

    Instance = Members({
        {Name = "new", Kind = "function", Detail = "Instance.new(className, parent?)"},
        {Name = "GetByGuid", Kind = "function", Detail = "Instance.GetByGuid(guid)"},
    }),

    Enum = Members({
        {Name = "RaycastFilterMode", Kind = "enum"},
        {Name = "Material", Kind = "enum"},
        {Name = "NormalId", Kind = "enum"},
        {Name = "PartType", Kind = "enum"},
        {Name = "Shape", Kind = "enum"},
        {Name = "HighlightDepthMode", Kind = "enum"},
        {Name = "HandleAdornmentShape", Kind = "enum"},
    }),

    ["Enum.RaycastFilterMode"] = Members({
        {Name = "Exclude", Kind = "property"},
        {Name = "Include", Kind = "property"},
    }),

    ["Enum.Material"] = Members({
        {Name = "Plastic", Kind = "property"},
        {Name = "SmoothPlastic", Kind = "property"},
        {Name = "Neon", Kind = "property"},
        {Name = "Wood", Kind = "property"},
        {Name = "Metal", Kind = "property"},
        {Name = "Concrete", Kind = "property"},
        {Name = "Glass", Kind = "property"},
        {Name = "Fabric", Kind = "property"},
        {Name = "Sand", Kind = "property"},
        {Name = "Grass", Kind = "property"},
        {Name = "Ice", Kind = "property"},
        {Name = "Brick", Kind = "property"},
        {Name = "Granite", Kind = "property"},
        {Name = "Marble", Kind = "property"},
        {Name = "ForceField", Kind = "property"},
    }),

    ["Enum.NormalId"] = Members({
        {Name = "Top", Kind = "property"},
        {Name = "Bottom", Kind = "property"},
        {Name = "Front", Kind = "property"},
        {Name = "Back", Kind = "property"},
        {Name = "Left", Kind = "property"},
        {Name = "Right", Kind = "property"},
    }),

    ["Enum.PartType"] = Members({
        {Name = "Ball", Kind = "property"},
        {Name = "Block", Kind = "property"},
        {Name = "Cylinder", Kind = "property"},
        {Name = "Wedge", Kind = "property"},
        {Name = "CornerWedge", Kind = "property"},
        {Name = "Cone", Kind = "property"},
    }),

    RaycastParams = Members({
        {Name = "new", Kind = "function", Detail = "RaycastParams.new()"},
    }),

    Workspace = Members({
        {Name = "Raycast", Kind = "function", Detail = "Workspace:Raycast(origin, direction, params?)"},
        {Name = "CurrentCamera", Kind = "property", Detail = "Camera"},
        {Name = "GetChildren", Kind = "function", Detail = "Workspace:GetChildren()"},
    }),

    math = Members({
        {Name = "abs", Kind = "function"}, {Name = "acos", Kind = "function"},
        {Name = "asin", Kind = "function"}, {Name = "atan", Kind = "function"},
        {Name = "atan2", Kind = "function"}, {Name = "ceil", Kind = "function"},
        {Name = "clamp", Kind = "function"}, {Name = "cos", Kind = "function"},
        {Name = "deg", Kind = "function"}, {Name = "exp", Kind = "function"},
        {Name = "floor", Kind = "function"}, {Name = "fmod", Kind = "function"},
        {Name = "huge", Kind = "property"}, {Name = "log", Kind = "function"},
        {Name = "max", Kind = "function"}, {Name = "min", Kind = "function"},
        {Name = "pi", Kind = "property"}, {Name = "random", Kind = "function"},
        {Name = "randomseed", Kind = "function"}, {Name = "rad", Kind = "function"},
        {Name = "round", Kind = "function"}, {Name = "sign", Kind = "function"},
        {Name = "sin", Kind = "function"}, {Name = "sqrt", Kind = "function"},
        {Name = "tan", Kind = "function"}, {Name = "noise", Kind = "function"},
    }),

    string = Members({
        {Name = "byte", Kind = "function"}, {Name = "char", Kind = "function"},
        {Name = "find", Kind = "function"}, {Name = "format", Kind = "function"},
        {Name = "gmatch", Kind = "function"}, {Name = "gsub", Kind = "function"},
        {Name = "len", Kind = "function"}, {Name = "lower", Kind = "function"},
        {Name = "match", Kind = "function"}, {Name = "rep", Kind = "function"},
        {Name = "reverse", Kind = "function"}, {Name = "split", Kind = "function"},
        {Name = "sub", Kind = "function"}, {Name = "upper", Kind = "function"},
        {Name = "pack", Kind = "function"}, {Name = "unpack", Kind = "function"},
    }),

    table = Members({
        {Name = "insert", Kind = "function"}, {Name = "remove", Kind = "function"},
        {Name = "concat", Kind = "function"}, {Name = "sort", Kind = "function"},
        {Name = "clear", Kind = "function"}, {Name = "clone", Kind = "function"},
        {Name = "find", Kind = "function"}, {Name = "freeze", Kind = "function"},
        {Name = "isfrozen", Kind = "function"}, {Name = "pack", Kind = "function"},
        {Name = "unpack", Kind = "function"}, {Name = "create", Kind = "function"},
    }),

    coroutine = Members({
        {Name = "create", Kind = "function"}, {Name = "resume", Kind = "function"},
        {Name = "yield", Kind = "function"}, {Name = "status", Kind = "function"},
        {Name = "wrap", Kind = "function"}, {Name = "isyieldable", Kind = "function"},
        {Name = "running", Kind = "function"}, {Name = "close", Kind = "function"},
    }),

    os = Members({
        {Name = "time", Kind = "function"}, {Name = "date", Kind = "function"},
        {Name = "clock", Kind = "function"}, {Name = "difftime", Kind = "function"},
    }),

    -- Members shared by any instance-like value (Part, Model, Folder, etc).
    -- Used as a fallback when the receiver's exact class isn't known but it
    -- looks like an Instance (came from Instance.new(...) etc).
    ["*Instance"] = Members({
        {Name = "Name", Kind = "property"},
        {Name = "ClassName", Kind = "property"},
        {Name = "Parent", Kind = "property"},
        {Name = "IsA", Kind = "function", Detail = ":IsA(className)"},
        {Name = "FindFirstChild", Kind = "function", Detail = ":FindFirstChild(name)"},
        {Name = "GetChildren", Kind = "function", Detail = ":GetChildren()"},
        {Name = "GetChildrenOfClass", Kind = "function", Detail = ":GetChildrenOfClass(className)"},
        {Name = "Clone", Kind = "function", Detail = ":Clone()"},
        {Name = "Destroy", Kind = "function", Detail = ":Destroy()"},
        {Name = "SetAttribute", Kind = "function", Detail = ":SetAttribute(name, value)"},
        {Name = "GetAttribute", Kind = "function", Detail = ":GetAttribute(name)"},
        {Name = "Changed", Kind = "property", Detail = "Signal"},
    }),

    ["*BasePart"] = Members({
        {Name = "Position", Kind = "property", Detail = "Vector3"},
        {Name = "Size", Kind = "property", Detail = "Vector3"},
        {Name = "Orientation", Kind = "property", Detail = "Vector3"},
        {Name = "Color", Kind = "property"},
        {Name = "Material", Kind = "property"},
        {Name = "Anchored", Kind = "property", Detail = "boolean"},
        {Name = "Transparency", Kind = "property", Detail = "number"},
        {Name = "Locked", Kind = "property", Detail = "boolean"},
        {Name = "Shape", Kind = "property"},
    }),
}

-- Known instance-producing class names (used to know when a `local X =
-- Instance.new("Part")` should get BasePart-flavored member completions).
Autocomplete.BasePartClasses = {
    Part = true, WedgePart = true, CornerWedgePart = true, MeshPart = true,
}

return Autocomplete