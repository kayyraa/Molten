local TextBox = _G.TextBox or require("Services.TextBox")
local Color = require("Services.Color")
local UDim = require("Services.UDim")
local Instance = require("Services.Instance")
local Vector3 = require("Services.Vector3")

local Properties = {}

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------
local CurrentNode = nil
local SelectedSet = nil
local Editing = nil
local ColorPicker = nil
local AttrDialog = nil
local CheckboxCache = {}
local PropConn = nil
local ContainerFrame = nil
local ScrollY = 0
local ContentHeight = 0
local VisibleHeight = 200
local Expanded = {}
local LastRowCount = 0

-- Forward declarations (single set — never redeclare these as local later)
local GetOverlayParent
local CloseColorPicker
local OpenColorPicker
local ApplyColorPicker
local CloseAttrDialog
local OpenAttrDialog
local CloseEnumDropdown
local OpenListDropdown
local GetRoot
local SetValueAtPath

local RowHeight = 24
local LabelWidth = 130
local NamePad = 6
local ValuePad = 6
local SwatchSize = 14

-- ---------------------------------------------------------------------------
-- Schema
-- ---------------------------------------------------------------------------
local PropertySchema = {
    Transparency = { type = "number", min = 0, max = 1 },
    Reflectivity = { type = "number", min = 0, max = 1 },
    Roughness = { type = "number", min = 0, max = 1 },
    Metalness = { type = "number", min = 0, max = 1 },
    Refractivity = { type = "number", min = 0, max = 1 },
    FillTransparency = { type = "number", min = 0, max = 1 },
    OutlineTransparency = { type = "number", min = 0, max = 1 },
    Brightness = { type = "number", min = 0, max = 10 },
    Range = { type = "number", min = 0, max = 1000 },
    ClockTime = { type = "number", min = 0, max = 24 },
    FogStart = { type = "number", min = 0 },
    FogEnd = { type = "number", min = 0 },
    Gravity = { type = "number", min = 0 },
    FieldOfView = { type = "number", min = 1, max = 120 },
    EnvironmentDiffuseScale = { type = "number", min = 0, max = 5 },
    EnvironmentSpecularScale = { type = "number", min = 0, max = 5 },
    FallenPartsDestroyHeight = { type = "number" },
    Color = { type = "color" },
    Ambient = { type = "color" },
    OutdoorAmbient = { type = "color" },
    FogColor = { type = "color" },
    FillColor = { type = "color" },
    OutlineColor = { type = "color" },
    ColorShift_Top = { type = "color" },
    ColorShift_Bottom = { type = "color" },
    BackgroundColor = { type = "color" },
    WaterColor = { type = "color" },
    Rendering = { type = "enum" },
}

local AttrTypes = {
    { id = "string",  label = "string" },
    { id = "number",  label = "number" },
    { id = "boolean", label = "boolean" },
    { id = "Color3",  label = "Color3" },
    { id = "Vector3", label = "Vector3" },
}

-- Enum maps for dropdown properties (Studio-like)
local EnumMaps = {
    Rendering = { "RayTraced", "Rasterized" },
    Shape = { "Block", "Ball", "Cylinder", "Wedge", "CornerWedge", "Cone" },
    Face = { "Top", "Bottom", "Front", "Back", "Left", "Right" },
    DepthMode = { "AlwaysOnTop", "Occluded" },
    -- Material is PBR fields only (Reflectivity/Roughness/Metalness/Refractivity), not an enum
}

local function NormalizeEnumValue(Value)
    if type(Value) ~= "string" then return Value end
    local leaf = Value:match("([^%.]+)$") or Value
    return leaf
end

local function GetEnumOptions(Path, Value)
    local leaf = ""
    if Path then
        leaf = Path:match("([^%.]+)$") or Path
    end
    local opts = EnumMaps[leaf]
    if opts then return opts end

    if type(Value) == "string" then
        local norm = NormalizeEnumValue(Value)
        for _, list in pairs(EnumMaps) do
            for _, v in ipairs(list) do
                if v == Value or v == norm then return list end
            end
        end
    end

    -- Enum-style table: { RayTraced = "RayTraced", Rasterized = "Rasterized" }
    if type(Value) == "table" and Value.ToArray == nil and Value.ClassName == nil then
        local keys = {}
        local n = 0
        for k, v in pairs(Value) do
            if type(k) == "string" and type(v) == "string" then
                keys[#keys + 1] = v
                n = n + 1
            elseif type(k) == "number" and type(v) == "string" then
                keys[#keys + 1] = v
                n = n + 1
            end
        end
        if n >= 2 and #keys == n then
            table.sort(keys)
            return keys
        end
    end
    return nil
end

local EnumDropdown = nil

function CloseEnumDropdown()
    if EnumDropdown and EnumDropdown.frame then
        pcall(function() EnumDropdown.frame:Destroy() end)
    end
    EnumDropdown = nil
end

--- Generic floating list. doesNotCloseDialogs=true keeps attr/color dialogs open (for type pickers).
function OpenListDropdown(opts, current, screenX, screenY, onPick, optsExtra)
    optsExtra = optsExtra or {}
    CloseEnumDropdown()
    if not optsExtra.keepDialogs then
        CloseColorPicker()
        -- only close attr dialog when picking a property enum, not when picking attr type
        if not optsExtra.fromAttrDialog then
            CloseAttrDialog()
        end
    end
    if not opts or #opts == 0 then return end

    local parent = GetOverlayParent()
    if not parent then return end

    local W, H = love.graphics.getDimensions()
    local rowH = 22
    local pw = optsExtra.width or 160
    local maxRows = optsExtra.maxRows or 12
    local visible = math.min(maxRows, #opts)
    local ph = visible * rowH + 4
    local px = math.floor(screenX or 200)
    local py = math.floor(screenY or 200)
    if px + pw > W - 8 then px = W - pw - 8 end
    if py + ph > H - 8 then py = H - ph - 8 end
    if px < 8 then px = 8 end
    if py < 8 then py = 8 end

    local panel = Instance.new("Frame", parent)
    panel.Name = "EnumDropdownOverlay"
    panel.BackgroundColor = Color.FromRGBA(36, 36, 42)
    panel.ZIndex = 900
    panel.Position = UDim.New(0, px, 0, py)
    panel.Size = UDim.FromOffset(pw, ph)
    panel.ClipsDescendants = true

    local baseBg = Color.FromRGBA(36, 36, 42)
    local hoverBg = Color.FromRGBA(70, 90, 130)
    local selectedBg = Color.FromRGBA(53, 83, 143)

    for i, opt in ipairs(opts) do
        if i > maxRows then break end
        local row = Instance.new("Frame", panel)
        local selected = (current == opt)
        local normalBg = selected and selectedBg or baseBg
        row.BackgroundColor = {
            normalBg[1], normalBg[2], normalBg[3], normalBg[4] or 1
        }
        row.Position = UDim.New(0, 1, 0, (i - 1) * rowH + 2)
        row.Size = UDim.New(1, -2, 0, rowH)
        row.ZIndex = 901
        local lab = Instance.new("TextLabel", row)
        lab.Text = tostring(opt)
        lab.TextSize = 12
        lab.TextColor = Color.FromRGBA(235, 235, 240)
        lab.BackgroundColor = Color.FromRGBA(0, 0, 0, 0)
        lab.Position = UDim.New(0, 8, 0, 0)
        lab.Size = UDim.FromScale(1, 1)
        lab.TextAlignment = { "Left", "Center" }
        lab.ZIndex = 902
        local choice = opt
        local nb = normalBg
        row.OnEnter:Connect(function()
            row.BackgroundColor = { hoverBg[1], hoverBg[2], hoverBg[3], 1 }
        end)
        row.OnLeave:Connect(function()
            row.BackgroundColor = { nb[1], nb[2], nb[3], nb[4] or 1 }
        end)
        lab.OnEnter:Connect(function()
            row.BackgroundColor = { hoverBg[1], hoverBg[2], hoverBg[3], 1 }
        end)
        lab.OnLeave:Connect(function()
            row.BackgroundColor = { nb[1], nb[2], nb[3], nb[4] or 1 }
        end)
        local function pick()
            CloseEnumDropdown()
            if onPick then onPick(choice) end
        end
        row.OnClick:Connect(pick)
        lab.OnClick:Connect(pick)
    end

    EnumDropdown = { frame = panel, path = optsExtra.path }
end

local function OpenEnumDropdown(Entry, screenX, screenY)
    local opts = GetEnumOptions(Entry.FullPath, Entry.Raw)
    if not opts or #opts == 0 then return end
    OpenListDropdown(opts, Entry.Raw, screenX, screenY, function(choice)
        if not CurrentNode then return end
        local Root = GetRoot(CurrentNode, Entry.IsAttr)
        SetValueAtPath(Root, Entry.FullPath, choice)
        Properties:Refresh()
        pcall(function() require("Services.Visuals").Invalidate() end)
    end, { path = Entry.FullPath, fromAttrDialog = false })
end


local DefaultMaterial = {
    Reflectivity = 0,
    Roughness = 0.5,
    Metalness = 0,
    Refractivity = 0,
}

local HiddenKeys = {
    Children = true, Attributes = true, ZIndex = true, DisplayOrder = true,
    OnEnter = true, OnLeave = true, OnClick = true, Changed = true,
    _Parent = true, _IsHovered = true, ClassName = true, Guid = true, GUID = true, Parent = true,
}

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
local function LeafName(Path)
    if not Path then return "" end
    return Path:match("([^%.]+)$") or Path
end

local function GetSpec(Path)
    local leaf = LeafName(Path)
    local spec = PropertySchema[leaf]
    if spec then return spec end
    if Path and Path:lower():find("color") then
        return { type = "color" }
    end
    return nil
end

local function ClampNumber(Num, Spec)
    if not Spec then return Num end
    if Spec.min ~= nil then Num = math.max(Spec.min, Num) end
    if Spec.max ~= nil then Num = math.min(Spec.max, Num) end
    return Num
end

local function IsExpanded(Path)
    if Expanded[Path] == nil then
        -- default: expand top-level groups that are short; collapse deep by default for colors?
        return true
    end
    return Expanded[Path]
end

local function ToggleGroup(Path)
    Expanded[Path] = not IsExpanded(Path)
end

local function SplitPath(Path)
    local Result = {}
    for Part in Path:gmatch("[^%.]+") do
        Result[#Result + 1] = Part
    end
    return Result
end

local function IsVector3(Value)
    return type(Value) == "table" and type(Value.ToArray) == "function"
end

local function IsArray(Value)
    if type(Value) ~= "table" then return false end
    local Count = #Value
    if Count == 0 then return false end
    for Index = 1, Count do
        if Value[Index] == nil then return false end
    end
    return true
end

local function IsArrayNumbers(Value)
    if not IsArray(Value) then return false end
    for i = 1, #Value do
        if type(Value[i]) ~= "number" then return false end
    end
    return true
end

local function IsInstanceLike(Value)
    if type(Value) ~= "table" then return false end
    local cn = rawget(Value, "ClassName")
    return type(cn) == "string"
end

local function IsDict(Value)
    if type(Value) ~= "table" then return false end
    if IsVector3(Value) or IsInstanceLike(Value) or IsArray(Value) then return false end
    for Key, Val in pairs(Value) do
        if type(Key) == "string" and type(Val) ~= "function" then
            return true
        end
    end
    return false
end

local function IsNumberSequence(Value)
    if type(Value) ~= "table" or IsVector3(Value) or IsInstanceLike(Value) then return false end
    if #Value == 0 then return false end
    local first = Value[1]
    return type(first) == "table" and first.Time ~= nil and first.Value ~= nil
end

local function CountDict(Value)
    local Count = 0
    for _ in pairs(Value) do Count = Count + 1 end
    return Count
end

local function MergeMaterial(Value)
    local Merged = {}
    for Key, Val in pairs(DefaultMaterial) do Merged[Key] = Val end
    if Value then
        for Key, Val in pairs(Value) do Merged[Key] = Val end
    end
    return Merged
end

local function ShouldHide(Key, Node)
    if HiddenKeys[Key] then return true end
    if Key == "Visible" then
        if not Node then return true end
        if Node:IsA("BasePart") or Node:IsA("Part") or Node:IsA("Model") or Node:IsA("Folder")
            or Node:IsA("Camera") or Node:IsA("PointLight") or Node:IsA("Decal") or Node:IsA("Texture") then
            return true
        end
        return false
    end
    return false
end

function GetRoot(Node, IsAttr)
    if IsAttr then
        return rawget(Node, "Attributes")
    end
    return Node
end

function SetValueAtPath(Root, FullPath, NewVal)
    if not Root or not FullPath then return false end
    local parts = SplitPath(FullPath)
    if #parts == 0 then return false end
    local cur = Root
    for i = 1, #parts - 1 do
        local key = parts[i]
        local nextKey = tonumber(key) or key
        if type(cur) ~= "table" then return false end
        local child = cur[nextKey]
        if child == nil then return false end
        -- Vector3 component write
        if IsVector3(child) and i == #parts - 1 then
            -- handled below when leaf is X/Y/Z
        end
        cur = child
    end
    local leaf = parts[#parts]
    local leafKey = tonumber(leaf) or leaf

    -- Vector3.X / .Y / .Z
    if IsVector3(cur) and (leaf == "X" or leaf == "Y" or leaf == "Z") then
        local arr = cur:ToArray()
        local idx = (leaf == "X" and 1) or (leaf == "Y" and 2) or 3
        arr[idx] = NewVal
        -- mutate in place if possible
        if cur.Px ~= nil then
            if leaf == "X" then cur.Px = NewVal
            elseif leaf == "Y" then cur.Py = NewVal
            else cur.Pz = NewVal end
        else
            -- replace parent field
            return false
        end
        return true
    end

    if type(cur) ~= "table" then return false end
    cur[leafKey] = NewVal
    return true
end

local function FormatValue(Value, FullPath)
    FullPath = FullPath or ""
    if IsVector3(Value) then
        local Arr = Value:ToArray()
        return string.format("%.3g, %.3g, %.3g", Arr[1], Arr[2], Arr[3])
    end
    if IsArrayNumbers(Value) then
        if FullPath:lower():find("color") or (GetSpec(FullPath) and GetSpec(FullPath).type == "color") then
            return string.format("%d, %d, %d",
                math.floor((Value[1] or 0) * 255 + 0.5),
                math.floor((Value[2] or 0) * 255 + 0.5),
                math.floor((Value[3] or 0) * 255 + 0.5))
        end
        local Parts = {}
        for Index = 1, math.min(#Value, 4) do
            Parts[#Parts + 1] = string.format("%.3g", Value[Index])
        end
        return table.concat(Parts, ", ")
    end
    if IsNumberSequence(Value) then
        return string.format("NumberSequence (%d)", #Value)
    end
    if type(Value) == "number" then
        if FullPath:lower():find("color") and Value <= 1 then
            return tostring(math.floor(Value * 255 + 0.5))
        end
        return string.format("%.4g", Value)
    end
    if type(Value) == "boolean" then
        return Value and "true" or "false"
    end
    if type(Value) == "table" and IsDict(Value) then
        return ""
    end
    if type(Value) == "table" then
        if next(Value) == nil then return "" end
        local ok, s = pcall(tostring, Value)
        return ok and s or ""
    end
    if Value == nil then return "" end
    local ok, s = pcall(tostring, Value)
    return ok and s or ""
end

local function FormatForEdit(Value, FullPath)
    FullPath = FullPath or ""
    if IsArrayNumbers(Value) then
        if FullPath:lower():find("color") then
            return string.format("%d, %d, %d",
                math.floor((Value[1] or 0) * 255 + 0.5),
                math.floor((Value[2] or 0) * 255 + 0.5),
                math.floor((Value[3] or 0) * 255 + 0.5))
        end
        local Parts = {}
        for Index = 1, #Value do Parts[#Parts + 1] = tostring(Value[Index]) end
        return table.concat(Parts, ", ")
    end
    if type(Value) == "number" then
        if FullPath:lower():find("color") and Value <= 1 then
            return tostring(math.floor(Value * 255 + 0.5))
        end
        return tostring(Value)
    end
    local ok, s = pcall(tostring, Value)
    return ok and s or ""
end

local function ParseBuffer(Buffer, Original, FullPath)
    Buffer = Buffer:match("^%s*(.-)%s*$")
    if Buffer == "" then return nil end

    if type(Original) == "number" then
        local Num = tonumber(Buffer)
        if not Num then return nil end
        local Lower = FullPath:lower()
        local Spec = GetSpec(FullPath)
        if Lower:find("color") and (not Spec or Spec.type == "color") then
            if Num > 1 then Num = Num / 255 end
            Num = math.max(0, math.min(1, Num))
        else
            if Spec and Spec.type == "number" then
                Num = ClampNumber(Num, Spec)
            elseif Lower:find("reflectivity") or Lower:find("roughness") or Lower:find("refractivity")
                or Lower:find("transparency") or Lower:find("metalness") then
                Num = math.max(0, math.min(1, Num))
            end
        end
        return Num
    elseif type(Original) == "string" then
        return Buffer
    elseif type(Original) == "boolean" then
        if Buffer:lower() == "true" or Buffer == "1" then return true end
        if Buffer:lower() == "false" or Buffer == "0" then return false end
        return nil
    elseif IsArrayNumbers(Original) then
        local parts = {}
        for token in Buffer:gmatch("[^,]+") do
            local n = tonumber(token:match("^%s*(.-)%s*$"))
            if not n then return nil end
            parts[#parts + 1] = n
        end
        if #parts < 2 then return nil end
        if FullPath:lower():find("color") then
            for i = 1, math.min(3, #parts) do
                if parts[i] > 1 then parts[i] = parts[i] / 255 end
                parts[i] = math.max(0, math.min(1, parts[i]))
            end
            if #parts < 4 then parts[4] = Original[4] or 1 end
        end
        return parts
    end
    local Num = tonumber(Buffer)
    if Num ~= nil then return Num end
    return Buffer
end

-- ---------------------------------------------------------------------------
-- Entry collection
-- ---------------------------------------------------------------------------
local function AddEntries(Out, FullPath, Display, Value, Depth, IsAttr)
    if Depth > 6 then
        Out[#Out + 1] = {
            FullPath = FullPath, Display = Display, Depth = Depth,
            IsGroup = false, Type = "string", Raw = tostring(Value), IsAttr = IsAttr
        }
        return
    end

    local RealValue = Value
    if IsInstanceLike(RealValue) then
        Out[#Out + 1] = {
            FullPath = FullPath, Display = Display, Depth = Depth,
            IsGroup = false, Type = "Instance",
            Raw = tostring(rawget(RealValue, "Name") or rawget(RealValue, "ClassName") or "?"),
            IsAttr = IsAttr
        }
        return
    end

    -- Enum properties (Rendering, Shape, …) always become a single dropdown row
    do
        local enumOpts = GetEnumOptions(FullPath, RealValue)
        if enumOpts then
            local raw = RealValue
            if type(RealValue) == "table" then
                raw = enumOpts[1]
                -- Prefer currently selected string if stored on the node under a known form
            elseif type(RealValue) == "string" then
                raw = NormalizeEnumValue(RealValue)
            end
            Out[#Out + 1] = {
                FullPath = FullPath, Display = Display, Depth = Depth,
                IsGroup = false, Type = "Enum", Raw = raw, IsAttr = IsAttr,
                EnumOptions = enumOpts,
            }
            return
        end
    end

    if FullPath == "Material" then
        if type(Value) == "string" or Value == nil then
            RealValue = MergeMaterial(nil)
        elseif IsDict(Value) then
            RealValue = MergeMaterial(Value)
        end
    end

    if IsDict(RealValue) then
        Out[#Out + 1] = {
            FullPath = FullPath, Display = Display, Depth = Depth,
            IsGroup = true, Type = "dict", Raw = RealValue, IsAttr = IsAttr
        }
        if IsExpanded(FullPath) then
            local Keys = {}
            for Key, Val in pairs(RealValue) do
                if type(Key) == "string" and type(Val) ~= "function" and not IsInstanceLike(Val) then
                    Keys[#Keys + 1] = Key
                end
            end
            table.sort(Keys, function(A, B) return tostring(A):lower() < tostring(B):lower() end)
            for _, Key in ipairs(Keys) do
                AddEntries(Out, FullPath .. "." .. Key, Key, RealValue[Key], Depth + 1, IsAttr)
            end
        end
    elseif IsVector3(RealValue) then
        Out[#Out + 1] = {
            FullPath = FullPath, Display = Display, Depth = Depth,
            IsGroup = true, Type = "Vector3", Raw = RealValue, IsAttr = IsAttr
        }
        if IsExpanded(FullPath) then
            local Arr = RealValue:ToArray()
            AddEntries(Out, FullPath .. ".X", "X", Arr[1], Depth + 1, IsAttr)
            AddEntries(Out, FullPath .. ".Y", "Y", Arr[2], Depth + 1, IsAttr)
            AddEntries(Out, FullPath .. ".Z", "Z", Arr[3], Depth + 1, IsAttr)
        end
    elseif IsNumberSequence(RealValue) then
        Out[#Out + 1] = {
            FullPath = FullPath, Display = Display, Depth = Depth,
            IsGroup = true, Type = "NumberSequence", Raw = RealValue, IsAttr = IsAttr
        }
        if IsExpanded(FullPath) then
            for Index = 1, #RealValue do
                AddEntries(Out, FullPath .. "." .. Index, "Keypoint " .. Index, RealValue[Index], Depth + 1, IsAttr)
            end
        end
    elseif IsArrayNumbers(RealValue) and #RealValue >= 2 and #RealValue <= 4 then
        local Spec = GetSpec(FullPath)
        local isColor = (Spec and Spec.type == "color") or (FullPath:lower():find("color") ~= nil)
        Out[#Out + 1] = {
            FullPath = FullPath, Display = Display, Depth = Depth,
            IsGroup = true, Type = isColor and "Color" or "Array", Raw = RealValue, IsAttr = IsAttr
        }
        if IsExpanded(FullPath) then
            if isColor then
                -- Studio: R, G, B only — swatch lives on the parent row
                local labels = { "R", "G", "B" }
                for Index = 1, math.min(3, #RealValue) do
                    AddEntries(Out, FullPath .. "." .. Index, labels[Index], RealValue[Index], Depth + 1, IsAttr)
                end
            else
                for Index = 1, #RealValue do
                    AddEntries(Out, FullPath .. "." .. Index, "[" .. Index .. "]", RealValue[Index], Depth + 1, IsAttr)
                end
            end
        end
    else
        local enumOpts = GetEnumOptions(FullPath, RealValue)
        local raw = RealValue
        local typ = type(RealValue)
        if enumOpts then
            typ = "Enum"
            -- Coerce Enum.Xxx table → current string value (prefer first option / match)
            if type(RealValue) == "table" then
                raw = enumOpts[1]
            elseif type(RealValue) == "string" then
                raw = NormalizeEnumValue(RealValue)
            end
        end
        Out[#Out + 1] = {
            FullPath = FullPath, Display = Display, Depth = Depth,
            IsGroup = false, Type = typ, Raw = raw, IsAttr = IsAttr,
            EnumOptions = enumOpts,
        }
    end
end

local function EnsureServiceDefaults(Node)
    if not Node or not Node.ClassName then return end
    local ensure = nil
    if Node.ClassName == "Lighting" then
        ensure = {
            ClockTime = 14, Brightness = 2,
            Ambient = Color.FromRGBA(70, 70, 80),
            OutdoorAmbient = Color.FromRGBA(128, 128, 140),
            ColorShift_Top = Color.FromRGBA(0, 0, 0),
            ColorShift_Bottom = Color.FromRGBA(0, 0, 0),
            FogColor = Color.FromRGBA(192, 192, 192),
            FogStart = 0, FogEnd = 100000,
            GlobalShadows = true,
            EnvironmentDiffuseScale = 1, EnvironmentSpecularScale = 1,
            Rendering = "RayTraced",
        }
    elseif Node.ClassName == "Workspace" then
        ensure = { Gravity = 196.2, FallenPartsDestroyHeight = -500, StreamingEnabled = false }
    elseif Node.ClassName == "Terrain" then
        ensure = {
            WaterColor = Color.FromRGBA(12, 84, 91),
            WaterReflectance = 1, WaterTransparency = 0.3,
            WaterWaveSize = 0.15, WaterWaveSpeed = 10,
        }
    end
    if ensure then
        for k, v in pairs(ensure) do
            if rawget(Node, k) == nil then
                if type(v) == "table" and not v.ToArray then
                    local copy = {}
                    for ck, cv in pairs(v) do copy[ck] = cv end
                    rawset(Node, k, copy)
                else
                    rawset(Node, k, v)
                end
            end
        end
    end
    local nm = rawget(Node, "Name")
    if type(nm) ~= "string" then
        rawset(Node, "Name", tostring(Node.ClassName or "Instance"))
    end
end

local function CollectEntries(Node)
    EnsureServiceDefaults(Node)
    local Props = {}
    local TopKeys = {}
    for Key, Val in pairs(Node) do
        if type(Key) == "string" and not ShouldHide(Key, Node) and type(Val) ~= "function" then
            TopKeys[#TopKeys + 1] = Key
        end
    end
    table.sort(TopKeys, function(A, B)
        if A == "Name" then return true end
        if B == "Name" then return false end
        return A:lower() < B:lower()
    end)
    for _, Key in ipairs(TopKeys) do
        AddEntries(Props, Key, Key, Node[Key], 0, false)
    end
    if Node:IsA("BasePart") then
        local HasMaterial = false
        for _, Key in ipairs(TopKeys) do
            if Key == "Material" then HasMaterial = true break end
        end
        if not HasMaterial then
            AddEntries(Props, "Material", "Material", MergeMaterial(nil), 0, false)
        end
    end

    local Attrs = {}
    local AttrRoot = rawget(Node, "Attributes")
    if AttrRoot then
        local AttrKeys = {}
        for Key in pairs(AttrRoot) do AttrKeys[#AttrKeys + 1] = Key end
        table.sort(AttrKeys, function(A, B) return tostring(A):lower() < tostring(B):lower() end)
        for _, Key in ipairs(AttrKeys) do
            AddEntries(Attrs, Key, Key, AttrRoot[Key], 0, true)
        end
    end
    return Props, Attrs
end

-- ---------------------------------------------------------------------------
-- Checkboxes
-- ---------------------------------------------------------------------------
local function LoadCheckbox(path)
    if CheckboxCache[path] ~= nil then return CheckboxCache[path] end
    local img = false
    if love.filesystem and love.filesystem.getInfo and love.filesystem.getInfo(path) then
        local ok, r = pcall(love.graphics.newImage, path)
        img = ok and r or false
    end
    CheckboxCache[path] = img
    return img
end

local function ResolveBoolState(Entry)
    if not SelectedSet then
        if type(Entry.Raw) == "boolean" then
            return Entry.Raw and "true" or "false"
        end
        return "false"
    end
    local seenTrue, seenFalse = false, false
    for node in pairs(SelectedSet) do
        local root = Entry.IsAttr and (rawget(node, "Attributes") or {}) or node
        local cur = root
        for part in string.gmatch(Entry.FullPath, "[^%.]+") do
            if type(cur) ~= "table" then cur = nil break end
            cur = cur[tonumber(part) or part]
        end
        if cur == true then seenTrue = true
        elseif cur == false then seenFalse = true end
    end
    if seenTrue and seenFalse then return "mix" end
    if seenTrue then return "true" end
    return "false"
end

-- ---------------------------------------------------------------------------
-- Floating layer (CoreGui) for pickers / dialogs
-- ---------------------------------------------------------------------------
function GetOverlayParent()
    if _G.CoreGui then return _G.CoreGui end
    if ContainerFrame then
        local p = rawget(ContainerFrame, "_Parent") or ContainerFrame.Parent
        if p then return p end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Color picker (floating overlay)
-- ---------------------------------------------------------------------------
function CloseColorPicker()
    if ColorPicker and ColorPicker.frame then
        pcall(function() ColorPicker.frame:Destroy() end)
    end
    ColorPicker = nil
end

function ApplyColorPicker()
    if not ColorPicker or not CurrentNode then
        CloseColorPicker()
        return
    end
    local c = ColorPicker.color
    local root = GetRoot(CurrentNode, ColorPicker.isAttr)
    local arr = {
        math.max(0, math.min(1, c[1] or 0)),
        math.max(0, math.min(1, c[2] or 0)),
        math.max(0, math.min(1, c[3] or 0)),
        math.max(0, math.min(1, c[4] or 1)),
    }
    SetValueAtPath(root, ColorPicker.path, arr)
    CloseColorPicker()
    Properties:Refresh()
    pcall(function() require("Services.Visuals").Invalidate() end)
end

function OpenColorPicker(Entry, screenX, screenY)
    CloseColorPicker()
    CloseAttrDialog()
    local raw = Entry.Raw
    if type(raw) ~= "table" then return end
    local r = raw[1] or 0
    local g = raw[2] or 0
    local b = raw[3] or 0
    local a = raw[4] or 1

    local parent = GetOverlayParent()
    if not parent then return end

    local W, H = love.graphics.getDimensions()
    local pw, ph = 210, 168
    local px = math.floor((screenX or 200) + 8)
    local py = math.floor((screenY or 200) - 10)
    if px + pw > W - 8 then px = W - pw - 8 end
    if py + ph > H - 8 then py = H - ph - 8 end
    if px < 8 then px = 8 end
    if py < 8 then py = 8 end

    local panel = Instance.new("Frame", parent)
    panel.Name = "ColorPickerOverlay"
    panel.BackgroundColor = Color.FromRGBA(45, 45, 50)
    panel.ZIndex = 500
    panel.Position = UDim.New(0, px, 0, py)
    panel.Size = UDim.FromOffset(pw, ph)

    local title = Instance.new("TextLabel", panel)
    title.Text = "Color — " .. tostring(Entry.Display or "Color")
    title.TextSize = 12
    title.TextColor = Color.FromRGBA(230, 230, 240)
    title.BackgroundColor = Color.FromRGBA(58, 58, 66)
    title.Position = UDim.New(0, 0, 0, 0)
    title.Size = UDim.New(1, 0, 0, 24)
    title.TextAlignment = { "Center", "Center" }

    local swatch = Instance.new("Frame", panel)
    swatch.Name = "Swatch"
    swatch.BackgroundColor = { r, g, b, 1 }
    swatch.Position = UDim.New(0, 12, 0, 36)
    swatch.Size = UDim.FromOffset(44, 44)

    local channelLabels = {}
    local function makeChannel(label, value, y, channel)
        local lab = Instance.new("TextLabel", panel)
        lab.Text = label
        lab.TextSize = 12
        lab.TextColor = Color.FromRGBA(200, 200, 210)
        lab.BackgroundColor = Color.FromRGBA(0, 0, 0, 0)
        lab.Position = UDim.New(0, 68, 0, y)
        lab.Size = UDim.New(0, 20, 0, 20)
        lab.TextAlignment = { "Left", "Center" }

        local box = Instance.new("Frame", panel)
        box.BackgroundColor = Color.FromRGBA(32, 32, 36)
        box.Position = UDim.New(0, 92, 0, y)
        box.Size = UDim.FromOffset(56, 20)
        box.ZIndex = 501

        local txt = Instance.new("TextLabel", box)
        txt.Name = "Val"
        txt.Text = tostring(math.floor(value * 255 + 0.5))
        txt.TextSize = 12
        txt.TextColor = Color.FromRGBA(255, 255, 255)
        txt.BackgroundColor = Color.FromRGBA(0, 0, 0, 0)
        txt.Size = UDim.FromScale(1, 1)
        txt.TextAlignment = { "Center", "Center" }
        channelLabels[channel] = txt
        box.Name = "ChannelBox" .. tostring(channel)

        local function beginChannelEdit()
            if not ColorPicker then return end
            local meta = {
                FullPath = (Entry.FullPath or "") .. ".__ch" .. channel,
                Raw = math.floor((ColorPicker.color[channel] or 0) * 255 + 0.5),
                IsAttr = Entry.IsAttr,
                Buffer = tostring(math.floor((ColorPicker.color[channel] or 0) * 255 + 0.5)),
                Cursor = 1, SelectAll = true, channel = channel,
            }
            Editing = meta
            ColorPicker.activeChannel = channel
            ColorPicker.channelLabels = channelLabels
            box.BackgroundColor = Color.FromRGBA(50, 90, 140)
            TextBox.Begin({
                id = "properties",
                text = meta.Buffer,
                filter = "number",
                selectAll = true,
                tag = meta,
                onChange = function(s)
                    Editing = meta
                    Editing.Buffer = s.Buffer
                    Editing.Cursor = s.Cursor
                    Editing.SelectAll = s.SelectAll
                    if TextBox.FormatDisplay then
                        txt.Text = TextBox.FormatDisplay(Editing)
                    else
                        txt.Text = s.Buffer
                    end
                end,
                onCommit = function(text)
                    local n = tonumber(text)
                    if n and ColorPicker then
                        n = math.max(0, math.min(255, n)) / 255
                        ColorPicker.color[channel] = n
                        swatch.BackgroundColor = {
                            ColorPicker.color[1], ColorPicker.color[2], ColorPicker.color[3], 1
                        }
                        txt.Text = tostring(math.floor(n * 255 + 0.5))
                    end
                    box.BackgroundColor = Color.FromRGBA(32, 32, 36)
                    if ColorPicker then ColorPicker.activeChannel = nil end
                    Editing = nil
                end,
                onCancel = function()
                    box.BackgroundColor = Color.FromRGBA(32, 32, 36)
                    if ColorPicker then ColorPicker.activeChannel = nil end
                    Editing = nil
                    txt.Text = tostring(math.floor((ColorPicker and ColorPicker.color[channel] or 0) * 255 + 0.5))
                end,
            })
            if TextBox.FormatDisplay then
                txt.Text = TextBox.FormatDisplay(meta)
            end
        end
        box.OnClick:Connect(beginChannelEdit)
        txt.OnClick:Connect(beginChannelEdit)
    end

    makeChannel("R", r, 36, 1)
    makeChannel("G", g, 60, 2)
    makeChannel("B", b, 84, 3)

    local applyBtn = Instance.new("Frame", panel)
    applyBtn.BackgroundColor = Color.FromRGBA(53, 83, 143)
    applyBtn.Position = UDim.New(0, 12, 0, 130)
    applyBtn.Size = UDim.FromOffset(90, 24)
    local applyLab = Instance.new("TextLabel", applyBtn)
    applyLab.Text = "Apply"
    applyLab.TextSize = 12
    applyLab.TextColor = Color.FromRGBA(255, 255, 255)
    applyLab.BackgroundColor = Color.FromRGBA(0, 0, 0, 0)
    applyLab.Size = UDim.FromScale(1, 1)
    applyLab.TextAlignment = { "Center", "Center" }
    applyBtn.OnClick:Connect(function() ApplyColorPicker() end)

    local cancelBtn = Instance.new("Frame", panel)
    cancelBtn.BackgroundColor = Color.FromRGBA(60, 60, 66)
    cancelBtn.Position = UDim.New(0, 110, 0, 130)
    cancelBtn.Size = UDim.FromOffset(88, 24)
    local cancelLab = Instance.new("TextLabel", cancelBtn)
    cancelLab.Text = "Cancel"
    cancelLab.TextSize = 12
    cancelLab.TextColor = Color.FromRGBA(220, 220, 220)
    cancelLab.BackgroundColor = Color.FromRGBA(0, 0, 0, 0)
    cancelLab.Size = UDim.FromScale(1, 1)
    cancelLab.TextAlignment = { "Center", "Center" }
    cancelBtn.OnClick:Connect(function() CloseColorPicker() end)

    ColorPicker = {
        path = Entry.FullPath,
        isAttr = Entry.IsAttr,
        color = { r, g, b, a },
        frame = panel,
    }
end

-- ---------------------------------------------------------------------------
-- Attribute create / manage dialog
-- ---------------------------------------------------------------------------
function CloseAttrDialog()
    if AttrDialog and AttrDialog.frame then
        pcall(function() AttrDialog.frame:Destroy() end)
    end
    AttrDialog = nil
end

local function DefaultForAttrType(typeId)
    if typeId == "number" then return 0 end
    if typeId == "boolean" then return false end
    if typeId == "Color3" then return Color.FromRGBA(255, 255, 255) end
    if typeId == "Vector3" then return Vector3.new(0, 0, 0) end
    return ""
end

local function DetectAttrType(val)
    if type(val) == "boolean" then return "boolean" end
    if type(val) == "number" then return "number" end
    if type(val) == "string" then return "string" end
    if IsVector3(val) then return "Vector3" end
    if IsArrayNumbers(val) and #val >= 3 then return "Color3" end
    return "string"
end

function OpenAttrDialog(screenX, screenY, existingName)
    CloseAttrDialog()
    CloseColorPicker()
    CloseEnumDropdown()
    if not CurrentNode then return end

    local parent = GetOverlayParent()
    if not parent then return end

    local isEdit = existingName ~= nil
    local attrs = rawget(CurrentNode, "Attributes")
    if not attrs then
        attrs = {}
        rawset(CurrentNode, "Attributes", attrs)
    end
    local typeMap = rawget(CurrentNode, "_AttrTypes")
    if not typeMap then
        typeMap = {}
        rawset(CurrentNode, "_AttrTypes", typeMap)
    end

    local existingVal = isEdit and attrs[existingName] or nil
    local typeId = (isEdit and typeMap[existingName]) or (isEdit and DetectAttrType(existingVal)) or "string"
    local nameBuf = existingName or "NewAttribute"

    local W, H = love.graphics.getDimensions()
    local pw, ph = 280, isEdit and 200 or 168
    local px = math.floor(screenX or 200)
    local py = math.floor(screenY or 200)
    if px + pw > W - 8 then px = W - pw - 8 end
    if py + ph > H - 8 then py = H - ph - 8 end
    if px < 8 then px = 8 end
    if py < 8 then py = 8 end

    local panel = Instance.new("Frame", parent)
    panel.Name = "AttrDialogOverlay"
    panel.BackgroundColor = Color.FromRGBA(45, 45, 50)
    panel.ZIndex = 800
    panel.Position = UDim.New(0, px, 0, py)
    panel.Size = UDim.FromOffset(pw, ph)

    local title = Instance.new("TextLabel", panel)
    title.Text = isEdit and "Edit Attribute" or "Add Attribute"
    title.TextSize = 12
    title.TextColor = Color.FromRGBA(230, 230, 240)
    title.BackgroundColor = Color.FromRGBA(58, 58, 66)
    title.Size = UDim.New(1, 0, 0, 24)
    title.TextAlignment = { "Center", "Center" }
    title.ZIndex = 801

    -- Name field
    local nameLab = Instance.new("TextLabel", panel)
    nameLab.Text = "Name"
    nameLab.TextSize = 12
    nameLab.TextColor = Color.FromRGBA(180, 180, 190)
    nameLab.BackgroundColor = Color.FromRGBA(0, 0, 0, 0)
    nameLab.Position = UDim.New(0, 12, 0, 36)
    nameLab.Size = UDim.New(0, 48, 0, 24)
    nameLab.TextAlignment = { "Left", "Center" }
    nameLab.ZIndex = 801

    local nameBox = Instance.new("Frame", panel)
    nameBox.BackgroundColor = Color.FromRGBA(28, 28, 32)
    nameBox.Position = UDim.New(0, 64, 0, 36)
    nameBox.Size = UDim.FromOffset(200, 24)
    nameBox.ZIndex = 801
    local nameTxt = Instance.new("TextLabel", nameBox)
    nameTxt.Text = nameBuf
    nameTxt.TextSize = 12
    nameTxt.TextColor = Color.FromRGBA(255, 255, 255)
    nameTxt.BackgroundColor = Color.FromRGBA(0, 0, 0, 0)
    nameTxt.Size = UDim.FromScale(1, 1)
    nameTxt.Position = UDim.New(0, 6, 0, 0)
    nameTxt.TextAlignment = { "Left", "Center" }
    nameTxt.ZIndex = 802

    local function beginNameEdit()
        TextBox.Begin({
            id = "properties",
            text = nameBuf,
            filter = "text",
            selectAll = true,
            onChange = function(s)
                nameBuf = s.Buffer
                nameTxt.Text = s.Buffer
            end,
            onCommit = function(text)
                nameBuf = text
                nameTxt.Text = text
            end,
            onCancel = function() end,
        })
    end
    nameBox.OnClick:Connect(beginNameEdit)
    nameTxt.OnClick:Connect(beginNameEdit)

    -- Type field with real dropdown
    local typeLab = Instance.new("TextLabel", panel)
    typeLab.Text = "Type"
    typeLab.TextSize = 12
    typeLab.TextColor = Color.FromRGBA(180, 180, 190)
    typeLab.BackgroundColor = Color.FromRGBA(0, 0, 0, 0)
    typeLab.Position = UDim.New(0, 12, 0, 70)
    typeLab.Size = UDim.New(0, 48, 0, 24)
    typeLab.TextAlignment = { "Left", "Center" }
    typeLab.ZIndex = 801

    local typeIdx = 1
    for i, tdef in ipairs(AttrTypes) do
        if tdef.id == typeId then typeIdx = i break end
    end
    local typeBox = Instance.new("Frame", panel)
    typeBox.BackgroundColor = Color.FromRGBA(28, 28, 32)
    typeBox.Position = UDim.New(0, 64, 0, 70)
    typeBox.Size = UDim.FromOffset(200, 24)
    typeBox.ZIndex = 801
    local typeTxt = Instance.new("TextLabel", typeBox)
    typeTxt.Text = AttrTypes[typeIdx].label .. "  ▾"
    typeTxt.TextSize = 12
    typeTxt.TextColor = Color.FromRGBA(255, 255, 255)
    typeTxt.BackgroundColor = Color.FromRGBA(0, 0, 0, 0)
    typeTxt.Size = UDim.FromScale(1, 1)
    typeTxt.Position = UDim.New(0, 6, 0, 0)
    typeTxt.TextAlignment = { "Left", "Center" }
    typeTxt.ZIndex = 802

    local function openTypeMenu()
        local labels = {}
        for _, tdef in ipairs(AttrTypes) do labels[#labels + 1] = tdef.label end
        local mx, my = love.mouse.getPosition()
        OpenListDropdown(labels, AttrTypes[typeIdx].label, mx, my + 4, function(choice)
            for i, tdef in ipairs(AttrTypes) do
                if tdef.label == choice then
                    typeIdx = i
                    typeId = tdef.id
                    typeTxt.Text = tdef.label .. "  ▾"
                    break
                end
            end
        end, { fromAttrDialog = true, keepDialogs = true, width = 200, path = "__attr_type" })
    end
    typeBox.OnClick:Connect(openTypeMenu)
    typeTxt.OnClick:Connect(openTypeMenu)

    local function commitAttr()
        local name = (nameBuf or ""):match("^%s*(.-)%s*$")
        if name == "" or not name:match("^[%a_][%w_]*$") then
            return
        end
        -- rename: remove old key
        if isEdit and existingName and existingName ~= name then
            if attrs[name] ~= nil then return end -- collision
            attrs[name] = attrs[existingName]
            attrs[existingName] = nil
            typeMap[name] = typeMap[existingName]
            typeMap[existingName] = nil
        end
        local prevType = typeMap[name]
        local val = attrs[name]
        if val == nil or prevType ~= typeId then
            val = DefaultForAttrType(typeId)
        end
        attrs[name] = val
        typeMap[name] = typeId
        CloseEnumDropdown()
        CloseAttrDialog()
        Properties:Refresh()
    end

    local okBtn = Instance.new("Frame", panel)
    okBtn.BackgroundColor = Color.FromRGBA(53, 83, 143)
    okBtn.Position = UDim.New(0, 12, 0, isEdit and 160 or 128)
    okBtn.Size = UDim.FromOffset(120, 26)
    okBtn.ZIndex = 801
    local okLab = Instance.new("TextLabel", okBtn)
    okLab.Text = isEdit and "Save" or "Create"
    okLab.TextSize = 12
    okLab.TextColor = Color.FromRGBA(255, 255, 255)
    okLab.BackgroundColor = Color.FromRGBA(0, 0, 0, 0)
    okLab.Size = UDim.FromScale(1, 1)
    okLab.TextAlignment = { "Center", "Center" }
    okLab.ZIndex = 802
    okBtn.OnClick:Connect(commitAttr)
    okLab.OnClick:Connect(commitAttr)

    local cancelBtn = Instance.new("Frame", panel)
    cancelBtn.BackgroundColor = Color.FromRGBA(60, 60, 66)
    cancelBtn.Position = UDim.New(0, 144, 0, isEdit and 160 or 128)
    cancelBtn.Size = UDim.FromOffset(120, 26)
    cancelBtn.ZIndex = 801
    local cancelLab = Instance.new("TextLabel", cancelBtn)
    cancelLab.Text = "Cancel"
    cancelLab.TextSize = 12
    cancelLab.TextColor = Color.FromRGBA(220, 220, 220)
    cancelLab.BackgroundColor = Color.FromRGBA(0, 0, 0, 0)
    cancelLab.Size = UDim.FromScale(1, 1)
    cancelLab.TextAlignment = { "Center", "Center" }
    cancelLab.ZIndex = 802
    local function doCancel()
        CloseEnumDropdown()
        CloseAttrDialog()
    end
    cancelBtn.OnClick:Connect(doCancel)
    cancelLab.OnClick:Connect(doCancel)

    if isEdit then
        local delBtn = Instance.new("Frame", panel)
        delBtn.BackgroundColor = Color.FromRGBA(120, 50, 50)
        delBtn.Position = UDim.New(0, 12, 0, 110)
        delBtn.Size = UDim.FromOffset(252, 26)
        delBtn.ZIndex = 801
        local delLab = Instance.new("TextLabel", delBtn)
        delLab.Text = "Delete Attribute"
        delLab.TextSize = 12
        delLab.TextColor = Color.FromRGBA(255, 220, 220)
        delLab.BackgroundColor = Color.FromRGBA(0, 0, 0, 0)
        delLab.Size = UDim.FromScale(1, 1)
        delLab.TextAlignment = { "Center", "Center" }
        delLab.ZIndex = 802
        local function doDelete()
            attrs[existingName] = nil
            typeMap[existingName] = nil
            CloseEnumDropdown()
            CloseAttrDialog()
            Properties:Refresh()
        end
        delBtn.OnClick:Connect(doDelete)
        delLab.OnClick:Connect(doDelete)
    end

    AttrDialog = { frame = panel, nameBuf = function() return nameBuf end }
end


-- ---------------------------------------------------------------------------
-- Row builder
-- ---------------------------------------------------------------------------
local function BuildRow(Parent, Entry, RowIndex)
    local Indent = (Entry.Depth or 0) * 14
    local Frame = Instance.new("Frame", Parent)
    Frame.Name = "PropRow"
    Frame.Position = UDim.New(0, 0, 0, RowIndex * RowHeight - ScrollY)
    Frame.Size = UDim.New(1, 0, 0, RowHeight)
    Frame.ClipsDescendants = true

    local isHead = Entry.Type == "Head" or Entry.Type == "Attributes"
    local isGroup = Entry.IsGroup
    local bg
    if isHead then
        bg = Color.FromRGBA(48, 48, 54)
    elseif isGroup then
        bg = Color.FromRGBA(42, 42, 47)
    elseif RowIndex % 2 == 0 then
        bg = Color.FromRGBA(36, 36, 40)
    else
        bg = Color.FromRGBA(33, 33, 37)
    end
    Frame.BackgroundColor = bg

    -- Expand arrow for groups
    if isGroup and Entry.Type ~= "Head" then
        local arrow = Instance.new("TextLabel", Frame)
        arrow.Text = IsExpanded(Entry.FullPath) and "▼" or "▶"
        arrow.TextSize = 9
        arrow.TextColor = Color.FromRGBA(160, 160, 170)
        arrow.BackgroundColor = Color.FromRGBA(0, 0, 0, 0)
        arrow.Position = UDim.New(0, Indent + 4, 0, 0)
        arrow.Size = UDim.New(0, 14, 1, 0)
        arrow.TextAlignment = { "Center", "Center" }
        Frame.OnClick:Connect(function()
            ToggleGroup(Entry.FullPath)
            Properties:Refresh()
        end)
    end

    -- Name column (fixed width, clipped)
    local NameLabel = Instance.new("TextLabel", Frame)
    NameLabel.Text = tostring(Entry.Display or "")
    NameLabel.BackgroundColor = Color.FromRGBA(0, 0, 0, 0)
    NameLabel.TextColor = isGroup and Color.FromRGBA(220, 220, 230) or Color.FromRGBA(165, 165, 175)
    NameLabel.Position = UDim.New(0, Indent + (isGroup and 18 or 6), 0, 0)
    NameLabel.Size = UDim.New(0, math.max(40, LabelWidth - Indent - 4), 1, 0)
    NameLabel.TextAlignment = { "Left", "Center" }
    NameLabel.TextSize = 12
    NameLabel.ClipsDescendants = true

    -- Value column
    local ValueFrame = Instance.new("Frame", Frame)
    ValueFrame.BackgroundColor = Color.FromRGBA(0, 0, 0, 0)
    ValueFrame.Position = UDim.New(0, LabelWidth + 4, 0, 1)
    ValueFrame.Size = UDim.New(1, -(LabelWidth + 8), 1, -2)
    ValueFrame.ClipsDescendants = true

    local ValueLabel = Instance.new("TextLabel", ValueFrame)
    ValueLabel.BackgroundColor = Color.FromRGBA(0, 0, 0, 0)
    ValueLabel.Position = UDim.New(0, ValuePad, 0, 0)
    ValueLabel.Size = UDim.New(1, -ValuePad * 2, 1, 0)
    ValueLabel.TextAlignment = { "Left", "Center" }
    ValueLabel.TextSize = 12
    ValueLabel.ClipsDescendants = true

    local IsEditing = Editing and Editing.FullPath == Entry.FullPath and Editing.IsAttr == Entry.IsAttr

    if isHead then
        ValueLabel.Text = ""
    elseif isGroup then
        if Entry.Type == "Color" and type(Entry.Raw) == "table" then
            -- One swatch on the main color row + RGB text
            ValueLabel.Text = FormatValue(Entry.Raw, Entry.FullPath)
            ValueLabel.TextColor = Color.FromRGBA(210, 210, 220)
            ValueLabel.Position = UDim.New(0, ValuePad + SwatchSize + 8, 0, 0)
            ValueLabel.Size = UDim.New(1, -(ValuePad * 2 + SwatchSize + 8), 1, 0)

            local border = Instance.new("Frame", ValueFrame)
            border.BackgroundColor = Color.FromRGBA(20, 20, 24)
            border.Position = UDim.New(0, ValuePad - 1, 0.5, 0)
            border.Anchor = { 0, 0.5 }
            border.Size = UDim.FromOffset(SwatchSize + 2, SwatchSize + 2)
            border.ZIndex = 1

            local sw = Instance.new("Frame", ValueFrame)
            sw.Name = "ColorSquare"
            sw.BackgroundColor = {
                Entry.Raw[1] or 1,
                Entry.Raw[2] or 1,
                Entry.Raw[3] or 1,
                1,
            }
            sw.Position = UDim.New(0, ValuePad, 0.5, 0)
            sw.Anchor = { 0, 0.5 }
            sw.Size = UDim.FromOffset(SwatchSize, SwatchSize)
            sw.ZIndex = 2

            ValueFrame.OnClick:Connect(function()
                local mx, my = love.mouse.getPosition()
                OpenColorPicker(Entry, mx, my)
            end)
        elseif Entry.Type == "dict" or Entry.Type == "Vector3" or Entry.Type == "Array"
            or Entry.Type == "NumberSequence" or Entry.Type == "Attributes" then
            ValueLabel.Text = FormatValue(Entry.Raw, Entry.FullPath)
            ValueLabel.TextColor = Color.FromRGBA(140, 140, 150)
        else
            ValueLabel.Text = FormatValue(Entry.Raw, Entry.FullPath)
            ValueLabel.TextColor = Color.FromRGBA(180, 180, 190)
        end
    else
        if IsEditing then
            ValueFrame.BackgroundColor = Editing.Error and Color.FromRGBA(90, 30, 30) or Color.FromRGBA(50, 90, 140)
            ValueLabel.Text = TextBox.FormatDisplay and TextBox.FormatDisplay(Editing) or (Editing.Buffer or "")
            ValueLabel.TextColor = Color.FromRGBA(255, 255, 200)
        elseif type(Entry.Raw) == "boolean" then
            ValueLabel.Text = ""
            local state = ResolveBoolState(Entry)
            local path = state == "true" and "Assets/Decals/CheckboxChecked.png"
                or state == "mix" and "Assets/Decals/CheckboxMix.png"
                or "Assets/Decals/CheckboxOff.png"
            local img = LoadCheckbox(path)
            if img then
                local Icon = Instance.new("ImageLabel", ValueFrame)
                Icon.Image = path
                Icon.Position = UDim.New(0, 4, 0.5, 0)
                Icon.Anchor = { 0, 0.5 }
                Icon.Size = UDim.FromOffset(16, 16)
                Icon.ZIndex = 2
            else
                ValueLabel.Text = state
                ValueLabel.TextColor = Color.FromRGBA(200, 200, 210)
            end
            Frame.OnClick:Connect(function()
                local newVal = ResolveBoolState(Entry) ~= "true"
                local targets = {}
                if SelectedSet then
                    for n in pairs(SelectedSet) do targets[#targets + 1] = n end
                else
                    targets[1] = CurrentNode
                end
                for _, node in ipairs(targets) do
                    local Root = GetRoot(node, Entry.IsAttr)
                    SetValueAtPath(Root, Entry.FullPath, newVal)
                end
                Properties:Refresh()
            end)
        else
            local enumOpts = Entry.EnumOptions or GetEnumOptions(Entry.FullPath, Entry.Raw)
            if Entry.Type == "Enum" and not enumOpts then
                enumOpts = GetEnumOptions(Entry.FullPath, Entry.Raw)
            end
            ValueLabel.Text = FormatValue(Entry.Raw, Entry.FullPath)
            local isColorChannel = Entry.FullPath and Entry.FullPath:lower():find("color") and type(Entry.Raw) == "number"
            if isColorChannel then
                ValueLabel.TextColor = Color.FromRGBA(255, 255, 255)
            elseif type(Entry.Raw) == "number" then
                ValueLabel.TextColor = Color.FromRGBA(170, 210, 255)
            else
                ValueLabel.TextColor = Color.FromRGBA(230, 230, 235)
            end

            if enumOpts then
                -- Enum: show ▾ and open floating dropdown (high ZIndex overlay)
                ValueLabel.Text = FormatValue(Entry.Raw, Entry.FullPath) .. "  ▾"
                ValueFrame.OnClick:Connect(function()
                    if EnumDropdown and EnumDropdown.path == Entry.FullPath then
                        CloseEnumDropdown()
                        return
                    end
                    local mx, my = love.mouse.getPosition()
                    OpenEnumDropdown(Entry, mx, my + 4)
                end)
            else
            -- Start edit on click
            local function StartEdit()
                if Editing and Editing.FullPath ~= Entry.FullPath then
                    Properties:Commit()
                end
                local Buf = FormatForEdit(Entry.Raw, Entry.FullPath)
                local filter = (type(Entry.Raw) == "number") and "number" or "text"
                local meta = {
                    FullPath = Entry.FullPath,
                    IsAttr = Entry.IsAttr,
                    Raw = Entry.Raw,
                    Type = type(Entry.Raw),
                    Error = false,
                    Buffer = Buf,
                    Cursor = #Buf + 1,
                    SelectAll = true,
                }
                TextBox.Begin({
                    id = "properties",
                    text = Buf,
                    filter = filter,
                    selectAll = true,
                    tag = meta,
                    onChange = function(s)
                        meta.Buffer = s.Buffer
                        meta.Cursor = s.Cursor
                        meta.SelectAll = s.SelectAll
                        Editing = meta
                        pcall(function() Properties:Refresh() end)
                    end,
                    onCommit = function(text)
                        Editing = meta
                        Editing.Buffer = text
                        Properties:Commit()
                    end,
                    onCancel = function()
                        Editing = nil
                        Properties:Refresh()
                    end,
                })
                Editing = meta
                Properties:Refresh()
            end
            ValueFrame.OnClick:Connect(StartEdit)
            end -- enumOpts else
        end
    end

    -- Attribute edit button (name/type) for top-level attributes
    if Entry.IsAttr and Entry.Depth == 0 and Entry.FullPath ~= "_Empty" and Entry.FullPath ~= "__AddAttr"
        and Entry.FullPath ~= "__Attributes" then
        local gearHit = Instance.new("Frame", Frame)
        gearHit.BackgroundColor = Color.FromRGBA(50, 55, 70)
        gearHit.Position = UDim.New(1, -52, 0, 2)
        gearHit.Size = UDim.New(0, 48, 1, -4)
        gearHit.ZIndex = 5
        local gearLab = Instance.new("TextLabel", gearHit)
        gearLab.Text = "Edit"
        gearLab.TextSize = 11
        gearLab.TextColor = Color.FromRGBA(180, 200, 255)
        gearLab.BackgroundColor = Color.FromRGBA(0, 0, 0, 0)
        gearLab.Size = UDim.FromScale(1, 1)
        gearLab.TextAlignment = { "Center", "Center" }
        gearLab.ZIndex = 6
        local attrName = Entry.FullPath
        local function openEdit()
            local mx, my = love.mouse.getPosition()
            OpenAttrDialog(mx, my, attrName)
        end
        gearHit.OnClick:Connect(openEdit)
        gearLab.OnClick:Connect(openEdit)
    end

    return Frame
end

-- ---------------------------------------------------------------------------
-- Visible height from dock
-- ---------------------------------------------------------------------------
local function ComputeVisibleHeight()
    local ScreenH = love.graphics.getHeight()
    local headerH = 17 -- Properties frame title bar
    local ok, Dock = pcall(require, "Services.Dock")
    if ok and Dock and Dock.GetLayout then
        local L = Dock:GetLayout()
        if L and L.RightBottom and L.RightBottom.H then
            -- List area = pane height minus header
            return math.max(60, L.RightBottom.H - headerH)
        end
    end
    if ContainerFrame then
        -- Fallback: try absolute size if dock resolved UDim already
        local sz = ContainerFrame.Size
        if type(sz) == "table" and type(sz.Y) == "table" and type(sz.Y.Offset) == "number" and sz.Y.Offset > 0 then
            return math.max(60, sz.Y.Offset)
        end
    end
    return math.max(60, ScreenH * 0.30)
end

-- ---------------------------------------------------------------------------
-- Public API
-- ---------------------------------------------------------------------------
function Properties:Init(Container)
    ContainerFrame = Container
end

function Properties:Select(Node, SelSet)
    CloseColorPicker()
    CloseAttrDialog()
    CloseEnumDropdown()
    if Editing then
        pcall(function() Properties:Commit() end)
    end
    CurrentNode = Node
    SelectedSet = SelSet
    ScrollY = 0
    if PropConn then
        pcall(function() PropConn:Disconnect() end)
        PropConn = nil
    end
    if Node and Node.Changed and Node.Changed.Connect then
        PropConn = Node.Changed:Connect(function()
            if not Editing then
                Properties:Refresh()
            end
        end)
    end
    Properties:Refresh()
end

function Properties:Refresh()
    if not ContainerFrame then return end

    local Old = rawget(ContainerFrame, "Children")
    if Old then
        for Index = #Old, 1, -1 do
            pcall(function() Old[Index]:Destroy() end)
        end
    end

    if not CurrentNode then
        ContentHeight = 0
        return
    end

    VisibleHeight = ComputeVisibleHeight()
    local Props, Attrs = CollectEntries(CurrentNode)
    local RowIndex = 0

    -- Header
    BuildRow(ContainerFrame, {
        FullPath = "__Head",
        Display = string.format("%s  \"%s\"", CurrentNode.ClassName or "Instance", CurrentNode.Name or ""),
        Depth = 0, IsGroup = true, Type = "Head", Raw = {},
    }, RowIndex)
    RowIndex = RowIndex + 1

    for Index = 1, #Props do
        BuildRow(ContainerFrame, Props[Index], RowIndex)
        RowIndex = RowIndex + 1
    end

    -- Attributes section
    local AttrExpanded = IsExpanded("__Attributes")
    BuildRow(ContainerFrame, {
        FullPath = "__Attributes",
        Display = "Attributes",
        Depth = 0, IsGroup = true, Type = "Attributes", Raw = {},
    }, RowIndex)
    RowIndex = RowIndex + 1

    if AttrExpanded then
        if #Attrs == 0 then
            BuildRow(ContainerFrame, {
                FullPath = "_Empty",
                Display = "(No Attributes)",
                Depth = 1, IsGroup = false, Type = "string", Raw = "", IsAttr = true,
            }, RowIndex)
            RowIndex = RowIndex + 1
        else
            for Index = 1, #Attrs do
                BuildRow(ContainerFrame, Attrs[Index], RowIndex)
                RowIndex = RowIndex + 1
            end
        end

        -- Add Attribute row
        local addFrame = Instance.new("Frame", ContainerFrame)
        addFrame.Position = UDim.New(0, 0, 0, RowIndex * RowHeight - ScrollY)
        addFrame.Size = UDim.New(1, 0, 0, RowHeight)
        addFrame.BackgroundColor = Color.FromRGBA(40, 48, 58)
        addFrame.ClipsDescendants = true
        local addLab = Instance.new("TextLabel", addFrame)
        addLab.Text = "+  Add Attribute"
        addLab.TextSize = 12
        addLab.TextColor = Color.FromRGBA(140, 180, 255)
        addLab.BackgroundColor = Color.FromRGBA(0, 0, 0, 0)
        addLab.Position = UDim.New(0, 20, 0, 0)
        addLab.Size = UDim.FromScale(1, 1)
        addLab.TextAlignment = { "Left", "Center" }
        addFrame.OnClick:Connect(function()
            local mx, my = love.mouse.getPosition()
            OpenAttrDialog(mx, my, nil)
        end)
        RowIndex = RowIndex + 1
    end

    LastRowCount = RowIndex
    ContentHeight = RowIndex * RowHeight
    local Max = math.max(0, ContentHeight - VisibleHeight)
    ScrollY = math.max(0, math.min(Max, ScrollY))
end

function Properties:Commit()
    if not Editing or not CurrentNode then
        Editing = nil
        return false
    end
    local NewVal = ParseBuffer(Editing.Buffer or "", Editing.Raw, Editing.FullPath)
    if NewVal == nil then
        Editing.Error = true
        Properties:Refresh()
        return false
    end
    local Root = GetRoot(CurrentNode, Editing.IsAttr)
    if not SetValueAtPath(Root, Editing.FullPath, NewVal) then
        Editing.Error = true
        Properties:Refresh()
        return false
    end
    Editing = nil
    Properties:Refresh()
    pcall(function() require("Services.Visuals").Invalidate() end)
    return true
end

function Properties:Blur()
    if not Editing then return false end
    return Properties:Commit()
end

function Properties:Cancel()
    Editing = nil
    CloseColorPicker()
    CloseAttrDialog()
    CloseEnumDropdown()
    Properties:Refresh()
end

function Properties:HandleTextInput(Text)
    if not Editing then return false end
    if TextBox and TextBox.IsActive() then
        return TextBox.HandleTextInput(Text)
    end
    return false
end

function Properties:HandleKey(Key)
    if Key == "escape" then
        if ColorPicker then CloseColorPicker() return true end
        if AttrDialog then CloseAttrDialog() return true end
        if EnumDropdown then CloseEnumDropdown() return true end
    end
    if not Editing then return false end
    if TextBox and TextBox.IsActive() then
        return TextBox.HandleKey(Key)
    end
    return false
end

function Properties:ContainsPoint(mx, my)
    local ok, Dock = pcall(require, "Services.Dock")
    if ok and Dock and Dock.GetLayout then
        local L = Dock:GetLayout()
        if L and L.RightBottom then
            local r = L.RightBottom
            return mx >= r.X and mx < r.X + r.W and my >= r.Y and my < r.Y + r.H
        end
    end
    return false
end

function Properties:HandleWheel(DeltaY)
    -- ContentHeight is maintained by Refresh after expand/collapse.
    -- Recompute visible height from dock every wheel tick.
    VisibleHeight = ComputeVisibleHeight()
    if LastRowCount > 0 then
        ContentHeight = LastRowCount * RowHeight
    elseif CurrentNode then
        local Props, Attrs = CollectEntries(CurrentNode)
        local rows = #Props + 2
        if IsExpanded("__Attributes") then
            rows = rows + math.max(1, #Attrs) + 1
        end
        ContentHeight = rows * RowHeight
    end
    local Max = math.max(0, ContentHeight - VisibleHeight)
    -- Smooth-ish: one row per notch, allow faster with larger delta
    local step = RowHeight * math.max(1, math.abs(DeltaY))
    if DeltaY > 0 then
        ScrollY = math.max(0, ScrollY - step)
    else
        ScrollY = math.min(Max, ScrollY + step)
    end
    Properties:Refresh()
end

function Properties:IsEditing()
    if Editing then return true end
    if TextBox and TextBox.IsActive and TextBox.IsActive() then
        local a = TextBox.Get()
        if a and (a.id == "properties" or a.id == "attr" or a.id == "color") then
            return true
        end
    end
    -- Dialogs open still block camera/shortcuts
    if ColorPicker or AttrDialog then return true end
    return false
end


local _LastCaretBlink = -1
function Properties:Tick()
    -- Keep caret blinking without full rebuild when possible
    if not Editing then return end
    if TextBox and TextBox.IsActive and TextBox.IsActive() then
        local a = TextBox.Get()
        if a then
            Editing.Buffer = a.Buffer
            Editing.Cursor = a.Cursor
            Editing.SelectAll = a.SelectAll
        end
    end
    local phase = math.floor(love.timer.getTime() * 2)
    -- Color picker channel caret (no full panel rebuild)
    if ColorPicker and ColorPicker.activeChannel and ColorPicker.channelLabels then
        local lab = ColorPicker.channelLabels[ColorPicker.activeChannel]
        if lab and TextBox.FormatDisplay then
            lab.Text = TextBox.FormatDisplay(Editing)
        end
        return
    end
    -- Property row caret: refresh only when blink phase flips
    if Editing and Editing.FullPath and not (Editing.FullPath:find("__ch", 1, true)) then
        if phase ~= _LastCaretBlink then
            _LastCaretBlink = phase
            Properties:Refresh()
        end
    end
end

function Properties:ClosePopups()
    CloseColorPicker()
    CloseAttrDialog()
    CloseEnumDropdown()
end

return Properties