local TextBox = _G.TextBox or require("Services.TextBox")
local Color = require("Services.Color")
local Theme = _G.Theme or require("Services.Theme")
local UDim = require("Services.UDim")
local Instance = require("Services.Instance")
local Vector3 = require("Services.Vector3")

local Properties = {}

local CurrentNode = nil
local SelectedSet = nil
local Editing = nil
local ColorPicker = nil
local AttrDialog = nil
local ObjectPick = nil
local CheckboxCache = {}
local PropConn = nil
local ContainerFrame = nil
local ScrollY = 0
local ContentHeight = 0
local VisibleHeight = 200
local Expanded = {}
local LastRowCount = 0

local GetOverlayParent
local CloseColorPicker
local OpenColorPicker
local ApplyColorPicker
local CloseAttrDialog
local OpenAttrDialog

local function AttachFocusRing(Parent)
    local Inset = 2
    local Thick = 2
    local Parts = {}
    local function Make(Name, Pos, Size)
        local F = Instance.new("Frame", Parent)
        F.Name = Name
        F.BackgroundColor = Theme.Get("FocusRing")
        F.Position = Pos
        F.Size = Size
        F.ZIndex = 20
        Parts[#Parts + 1] = F
    end
    Make("FocusRingT", UDim.New(0, Inset, 0, Inset), UDim.New(1, -(Inset * 2), 0, Thick))
    Make("FocusRingB", UDim.New(0, Inset, 1, -(Inset + Thick)), UDim.New(1, -(Inset * 2), 0, Thick))
    Make("FocusRingL", UDim.New(0, Inset, 0, Inset), UDim.New(0, Thick, 1, -(Inset * 2)))
    Make("FocusRingR", UDim.New(1, -(Inset + Thick), 0, Inset), UDim.New(0, Thick, 1, -(Inset * 2)))
    return Parts
end

local function PulseFocusRing(Parts, IsError)
    if not Parts then
        return
    end
    local Wave = 0.5 + 0.5 * math.sin(love.timer.getTime() * 3.2)
    local Alpha = 0.35 + 0.65 * Wave
    local Col
    if IsError then
        local E = Theme.Get("FocusRingError")
        Col = {E[1], E[2], E[3], Alpha}
    else
        local F = Theme.Get("FocusRing")
        Col = {F[1], F[2], F[3], Alpha}
    end
    for I = 1, #Parts do
        Parts[I].BackgroundColor = Col
    end
end

local CloseEnumDropdown
local OpenListDropdown
local GetRoot
local SetValueAtPath

local RowHeight = 24
local LabelWidth = 130
local NamePad = 6
local ValuePad = 6

local function GetPanelWidth()
    local W = 280
    local Ok, Dock = pcall(require, "Services.Dock")
    if Ok and Dock and Dock.GetLayout then
        local L = Dock:GetLayout()
        if L and L.RightBottom and L.RightBottom.W and L.RightBottom.W > 0 then
            W = L.RightBottom.W
        elseif L and L.Right and L.Right.W and L.Right.W > 0 then
            W = L.Right.W
        end
    end
    if ContainerFrame then
        local Sz = ContainerFrame.Size
        if type(Sz) == "table" and (Sz[2] or 0) > 40 then
            W = Sz[2]
        end
    end
    return W
end

local function GetLabelColumnWidth()
    local PanelW = GetPanelWidth()
    local Half = math.floor(PanelW * 0.5)
    return math.max(90, math.min(Half, PanelW - 90))
end


local function EnsureCaret(Parent, Meta)
    if not Parent or not Meta then
        return
    end
    local Caret = Meta.CaretFrame
    if not Caret or rawget(Caret, "_Parent") ~= Parent then
        Caret = Instance.new("Frame", Parent)
        Caret.Name = "TextCaret"
        Caret.BackgroundColor = Theme.Get("BrightText")
        Caret.Size = UDim.FromOffset(1, 14)
        Caret.ZIndex = 25
        Caret.MouseCursor = "ibeam"
        Meta.CaretFrame = Caret
    end
    return Caret
end

local function UpdateCaretOverlay(Meta, Label, Parent)
    if not Meta or not Label then
        return
    end
    local Show, Cur, Buf = false, 1, ""
    if TextBox.GetCaretInfo then
        Show, Cur, Buf = TextBox.GetCaretInfo(Meta)
    end
    local Caret = EnsureCaret(Parent or Label, Meta)
    if not Caret then
        return
    end
    if not Show then
        Caret.BackgroundColor = {0, 0, 0, 0}
        return
    end
    local Prefix = (Buf or ""):sub(1, math.max(0, Cur - 1))
    local Font = love.graphics.getFont()
    local PrefixW = 0
    if Font then
        PrefixW = Font:getWidth(Prefix)
    else
        PrefixW = #Prefix * 7
    end
    local Pad = ValuePad or 6
    Caret.BackgroundColor = Theme.Get("BrightText")
    Caret.Position = UDim.New(0, Pad + PrefixW, 0.5, 0)
    Caret.Anchor = {0, 0.5}
    Caret.Size = UDim.FromOffset(1, 14)
end

local function TruncateToWidth(Text, WidthPx)
    Text = tostring(Text or "")
    if Text == "" then
        return Text
    end
    local CharW = 7
    local MaxChars = math.max(1, math.floor(WidthPx / CharW))
    if #Text <= MaxChars then
        return Text
    end
    if MaxChars <= 1 then
        return "..."
    end
    return Text:sub(1, MaxChars - 1) .. "..."
end

local SwatchSize = 14

local PropertySchema = {
    CurrentCamera = { type = "object", class = "Camera", readOnly = true, onlyClasses = { Workspace = true } },
    Adornee = { type = "object", onlyClasses = { Highlight = true, HandleAdornment = true } },
    Parent = { type = "object" },
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
    FieldOfView = { type = "number", min = 45, max = 135 },
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

local EnumMaps = {
    Rendering = { "RayTraced", "Rasterized" },
    Shape = { "Block", "Ball", "Cylinder", "Wedge", "CornerWedge", "Cone" },
    Face = { "Top", "Bottom", "Front", "Back", "Left", "Right" },
    DepthMode = { "AlwaysOnTop", "Occluded" },
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

function Properties:DismissPopupsIfOutside(X, Y)
    local function PointInFrame(Frame, Px, Py)
        if not Frame then return false end
        local Pos = Frame.Position
        local Size = Frame.Size
        if not Pos or not Size then return false end
        local Ox = (Pos[2] or 0)
        local Oy = (Pos[4] or 0)
        local W = (Size[2] or 0)
        local H = (Size[4] or 0)
        if (Size[1] or 0) ~= 0 or (Size[3] or 0) ~= 0 then
            return true
        end
        return Px >= Ox and Px < Ox + W and Py >= Oy and Py < Oy + H
    end
    if EnumDropdown and EnumDropdown.frame then
        local F = EnumDropdown.frame
        local Pos = F.Position
        local Size = F.Size
        local Ox = Pos and (Pos[2] or 0) or 0
        local Oy = Pos and (Pos[4] or 0) or 0
        local W = Size and (Size[2] or 0) or 0
        local H = Size and (Size[4] or 0) or 0
        if not (X >= Ox and X < Ox + W and Y >= Oy and Y < Oy + H) then
            CloseEnumDropdown()
            return true
        end
    end
    return false
end


function OpenListDropdown(opts, current, screenX, screenY, onPick, optsExtra)
    optsExtra = optsExtra or {}
    CloseEnumDropdown()
    if not optsExtra.keepDialogs and not optsExtra.fromAttrDialog then
        CloseColorPicker()
        CloseAttrDialog()
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
    panel.BackgroundColor = Theme.Get("Dropdown")
    panel.ZIndex = 2500
    panel.Position = UDim.New(0, px, 0, py)
    panel.Size = UDim.FromOffset(pw, ph)
    panel.ClipsDescendants = true

    local baseBg = Theme.Get("Dropdown")
    local hoverBg = Theme.Get("ItemHover")
    local selectedBg = Theme.Get("ItemSelected")

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
        row.ZIndex = 2501
        local lab = Instance.new("TextLabel", row)
        lab.Text = tostring(opt)
        lab.TextSize = 12
        lab.TextColor = Theme.Get("ValueText")
        lab.BackgroundColor = Color.FromRGBA(0, 0, 0, 0)
        lab.Position = UDim.New(0, 8, 0, 0)
        lab.Size = UDim.FromScale(1, 1)
        lab.TextAlignment = { "Left", "Center" }
        lab.ZIndex = 2502
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
    Surface = true,
}

local CategoryOrder = {
    "Appearance",
    "Transform",
    "Data",
    "Behavior",
    "Lighting",
    "Effects",
    "Other",
}

local CategoryMap = {
    Intensity = "Effects",
    Threshold = "Effects",
    Density = "Effects",
    Cover = "Effects",
    Haze = "Effects",
    Glare = "Effects",
    Spread = "Effects",
    FocusDistance = "Effects",
    InFocusRadius = "Effects",
    FarIntensity = "Effects",
    NearIntensity = "Effects",
    Saturation = "Effects",
    Contrast = "Effects",
    Color = "Appearance",
    Material = "Appearance",
    Transparency = "Appearance",
    Reflectivity = "Appearance",
    Reflectance = "Appearance",
    Roughness = "Appearance",
    Metalness = "Appearance",
    Refractivity = "Appearance",
    Shape = "Appearance",
    CastShadow = "Appearance",
    CastShadows = "Appearance",
    Texture = "Appearance",
    Face = "Appearance",
    UvStuds = "Appearance",
    UvOffset = "Appearance",
    FillColor = "Appearance",
    FillTransparency = "Appearance",
    OutlineColor = "Appearance",
    OutlineTransparency = "Appearance",
    DepthMode = "Appearance",
    AlwaysOnTop = "Appearance",
    Position = "Transform",
    Size = "Transform",
    Orientation = "Transform",
    Rotation = "Transform",
    CFrame = "Transform",
    CFrameOffset = "Transform",
    Name = "Data",
    ClassName = "Data",
    Parent = "Data",
    Locked = "Data",
    Archivable = "Data",
    Anchored = "Behavior",
    CanCollide = "Behavior",
    CanTouch = "Behavior",
    CanQuery = "Behavior",
    Massless = "Behavior",
    Enabled = "Behavior",
    Brightness = "Lighting",
    Range = "Lighting",
    Shadows = "Lighting",
    Ambient = "Lighting",
    OutdoorAmbient = "Lighting",
    ClockTime = "Lighting",
    FogColor = "Lighting",
    FogStart = "Lighting",
    FogEnd = "Lighting",
    Adornee = "Appearance",
}

local FilterText = ""

local function CategoryFor(Key)
    return CategoryMap[Key] or "Other"
end

local function EnsureCategoryDefaults()
    for _, Cat in ipairs(CategoryOrder) do
        local Path = "__cat__" .. Cat
        if Expanded[Path] == nil then
            Expanded[Path] = true
        end
    end
end

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

local function ClassAllowsSchema(Key, Node)
    local Spec = PropertySchema[Key]
    if not Spec or not Spec.onlyClasses then
        return true
    end
    if not Node then
        return false
    end
    local Cn = rawget(Node, "ClassName")
    if Spec.onlyClasses[Cn] then
        return true
    end
    if Node.IsA then
        for ClassName in pairs(Spec.onlyClasses) do
            if Node:IsA(ClassName) then
                return true
            end
        end
    end
    return false
end

local function ShouldHide(Key, Node)
    if type(Key) ~= "string" then return true end
    if HiddenKeys[Key] then return true end
    if Key:sub(1, 1) == "_" then return true end
    if Key == "Surface" then return true end
    if Key == "Adornee" and not ClassAllowsSchema("Adornee", Node) then
        return true
    end
    if Key == "CurrentCamera" and not ClassAllowsSchema("CurrentCamera", Node) then
        return true
    end
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
        if IsVector3(child) and i == #parts - 1 then
        end
        cur = child
    end
    local leaf = parts[#parts]
    local leafKey = tonumber(leaf) or leaf

    if IsVector3(cur) and (leaf == "X" or leaf == "Y" or leaf == "Z") then
        local arr = cur:ToArray()
        local idx = (leaf == "X" and 1) or (leaf == "Y" and 2) or 3
        arr[idx] = NewVal
        if cur.Px ~= nil then
            if leaf == "X" then cur.Px = NewVal
            elseif leaf == "Y" then cur.Py = NewVal
            else cur.Pz = NewVal end
        else
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
    if IsInstanceLike(Value) then
        local Nm = rawget(Value, "Name") or rawget(Value, "ClassName") or "?"
        local Cn = rawget(Value, "ClassName") or "Instance"
        return string.format("%s (%s)", tostring(Nm), tostring(Cn))
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

local function AddEntries(Out, FullPath, Display, Value, Depth, IsAttr)
    if Depth > 6 then
        Out[#Out + 1] = {
            FullPath = FullPath, Display = Display, Depth = Depth,
            IsGroup = false, Type = "string", Raw = tostring(Value), IsAttr = IsAttr
        }
        return
    end

    local RealValue = Value
    local Spec = GetSpec(FullPath)
    if (Spec and Spec.type == "object") or IsInstanceLike(RealValue) then
        local Ref = IsInstanceLike(RealValue) and RealValue or nil
        local Label
        if Ref then
            local Nm = rawget(Ref, "Name") or rawget(Ref, "ClassName") or "?"
            local Cn = rawget(Ref, "ClassName") or "Instance"
            Label = string.format("%s (%s)", tostring(Nm), tostring(Cn))
        else
            Label = "None"
        end
        Out[#Out + 1] = {
            FullPath = FullPath,
            Display = Display,
            Depth = Depth,
            IsGroup = false,
            Type = "Instance",
            Raw = Label,
            InstanceRef = Ref,
            ClassFilter = Spec and Spec.class or nil,
            ReadOnly = Spec and Spec.readOnly or false,
            IsAttr = IsAttr,
        }
        return
    end

    do
        local enumOpts = GetEnumOptions(FullPath, RealValue)
        if enumOpts then
            local raw = RealValue
            if type(RealValue) == "table" then
                raw = enumOpts[1]
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
                if type(Key) == "string" and Key:sub(1, 1) ~= "_"
                    and type(Val) ~= "function" and not IsInstanceLike(Val) then
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
    elseif Node.ClassName == "BloomEffect" then
        ensure = { Enabled = true, Intensity = 0.4, Size = 24, Threshold = 0.95 }
    elseif Node.ClassName == "DepthOfFieldEffect" then
        ensure = { Enabled = false, FarIntensity = 0.75, FocusDistance = 50, InFocusRadius = 30, NearIntensity = 0.75 }
    elseif Node.ClassName == "ColorCorrectionEffect" then
        ensure = { Enabled = true, Brightness = 0, Contrast = 0, Saturation = 0 }
    elseif Node.ClassName == "SunRaysEffect" then
        ensure = { Enabled = true, Intensity = 0.25, Spread = 1 }
    elseif Node.ClassName == "Atmosphere" then
        ensure = { Density = 0.3, Offset = 0.25, Glare = 0, Haze = 0 }
    elseif Node.ClassName == "Clouds" then
        ensure = { Cover = 0.5, Density = 0.7 }
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


function Properties:IsObjectPicking()
    return ObjectPick ~= nil
end

function Properties:CancelObjectPick()
    ObjectPick = nil
end

function Properties:BeginObjectPick(Entry)
    if not Entry or not CurrentNode then
        return
    end
    if Entry.ReadOnly then
        return
    end
    ObjectPick = {
        path = Entry.FullPath,
        isAttr = Entry.IsAttr,
        class = Entry.ClassFilter,
    }
end

function Properties:TryAssignObject(Inst)
    if not ObjectPick or not CurrentNode then
        return false
    end
    if Inst == nil then
        return false
    end
    if not IsInstanceLike(Inst) then
        return false
    end
    if ObjectPick.class and Inst.IsA and not Inst:IsA(ObjectPick.class) then
        return false
    end
    local Root = GetRoot(CurrentNode, ObjectPick.isAttr)
    SetValueAtPath(Root, ObjectPick.path, Inst)
    if ObjectPick.path == "CurrentCamera" and CurrentNode then
        local Cn = rawget(CurrentNode, "ClassName")
        if Cn == "Workspace" then
            CurrentNode.CurrentCamera = Inst
            _G.CurrentCamera = Inst
        end
    end
    ObjectPick = nil
    Properties:Refresh()
    pcall(function() require("Services.Visuals").Invalidate() end)
    return true
end

function Properties:GetCursor(X, Y)
    if ObjectPick then
        return "hand"
    end
    if TextBox and TextBox.IsActive and TextBox.IsActive() then
        return "ibeam"
    end
    if Editing then
        return "ibeam"
    end
    return nil
end

local function CollectEntries(Node)
    EnsureServiceDefaults(Node)
    EnsureCategoryDefaults()
    local ByCat = {}
    for _, Cat in ipairs(CategoryOrder) do
        ByCat[Cat] = {}
    end
    local TopKeys = {}
    if rawget(Node, "Surface") ~= nil then
        rawset(Node, "Surface", nil)
    end
    if rawget(Node, "Adornee") ~= nil and not ClassAllowsSchema("Adornee", Node) then
        rawset(Node, "Adornee", nil)
    end
    for Key, Val in pairs(Node) do
        if type(Key) == "string" and Key ~= "Surface" and not ShouldHide(Key, Node) and type(Val) ~= "function" then
            TopKeys[#TopKeys + 1] = Key
        end
    end
    table.sort(TopKeys, function(A, B)
        if A == "Name" then return true end
        if B == "Name" then return false end
        return A:lower() < B:lower()
    end)
    local Filter = (FilterText or ""):lower()
    local function PassFilter(Name)
        if Filter == "" then return true end
        return tostring(Name):lower():find(Filter, 1, true) ~= nil
    end
    local Seen = {}
    for _, Key in ipairs(TopKeys) do
        if PassFilter(Key) then
            local Cat = CategoryFor(Key)
            AddEntries(ByCat[Cat], Key, Key, Node[Key], 0, false)
            Seen[Key] = true
        end
    end
    for Key, Spec in pairs(PropertySchema) do
        if type(Key) == "string" and Spec and Spec.type == "object" and not Seen[Key]
            and ClassAllowsSchema(Key, Node) and not ShouldHide(Key, Node) then
            if PassFilter(Key) then
                local Cat = CategoryFor(Key)
                local Val = Node[Key]
                if Val == nil then
                    Val = false
                end
                AddEntries(ByCat[Cat], Key, Key, Val, 0, false)
                Seen[Key] = true
            end
        end
    end
    if Node:IsA("BasePart") then
        local HasMaterial = false
        for _, Key in ipairs(TopKeys) do
            if Key == "Material" then
                HasMaterial = true
                break
            end
        end
        if not HasMaterial and PassFilter("Material") then
            AddEntries(ByCat.Appearance, "Material", "Material", MergeMaterial(nil), 0, false)
        end
    end
    local Props = {}
    for _, Cat in ipairs(CategoryOrder) do
        local List = ByCat[Cat]
        if #List > 0 then
            Props[#Props + 1] = {
                Kind = "Category",
                Name = Cat,
                FullPath = "__cat__" .. Cat,
                Count = #List,
                Depth = 0,
            }
            if IsExpanded("__cat__" .. Cat) then
                for _, Entry in ipairs(List) do
                    Props[#Props + 1] = Entry
                end
            end
        end
    end
    local Attrs = {}
    local AttrRoot = rawget(Node, "Attributes")
    if AttrRoot then
        local AttrKeys = {}
        for Key in pairs(AttrRoot) do
            if type(Key) == "string" and Key:sub(1, 1) ~= "_" then
                AttrKeys[#AttrKeys + 1] = Key
            end
        end
        table.sort(AttrKeys, function(A, B)
            return tostring(A):lower() < tostring(B):lower()
        end)
        for _, Key in ipairs(AttrKeys) do
            if PassFilter(Key) then
                AddEntries(Attrs, Key, Key, AttrRoot[Key], 0, true)
            end
        end
    end
    return Props, Attrs
end

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

function GetOverlayParent()
    local Core = _G.CoreGui
    if not Core then
        return ContainerFrame and (rawget(ContainerFrame, "_Parent") or ContainerFrame.Parent) or nil
    end
    local OverlayGui = nil
    local Children = rawget(Core, "Children") or {}
    for I = 1, #Children do
        local Ch = Children[I]
        if rawget(Ch, "Name") == "OverlayGui" and rawget(Ch, "ClassName") == "ScreenGui" then
            OverlayGui = Ch
            break
        end
    end
    if not OverlayGui then
        OverlayGui = Instance.new("ScreenGui", Core)
        OverlayGui.Name = "OverlayGui"
        OverlayGui.DisplayOrder = 100
        OverlayGui.Enabled = true
    else
        OverlayGui.DisplayOrder = 100
        OverlayGui.Enabled = true
    end
    return OverlayGui
end

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

function RgbToHsv(R, G, B)
    local MaxV = math.max(R, G, B)
    local MinV = math.min(R, G, B)
    local D = MaxV - MinV
    local H = 0
    if D > 1e-6 then
        if MaxV == R then
            H = ((G - B) / D) % 6
        elseif MaxV == G then
            H = (B - R) / D + 2
        else
            H = (R - G) / D + 4
        end
        H = H * 60
        if H < 0 then H = H + 360 end
    end
    local S = MaxV > 1e-6 and (D / MaxV) or 0
    return H, S, MaxV
end

function HsvToRgb(H, S, V)
    H = (H % 360 + 360) % 360
    local C = V * S
    local X = C * (1 - math.abs((H / 60) % 2 - 1))
    local M = V - C
    local Rp, Gp, Bp = 0, 0, 0
    if H < 60 then
        Rp, Gp, Bp = C, X, 0
    elseif H < 120 then
        Rp, Gp, Bp = X, C, 0
    elseif H < 180 then
        Rp, Gp, Bp = 0, C, X
    elseif H < 240 then
        Rp, Gp, Bp = 0, X, C
    elseif H < 300 then
        Rp, Gp, Bp = X, 0, C
    else
        Rp, Gp, Bp = C, 0, X
    end
    return Rp + M, Gp + M, Bp + M
end

local function EnsureColorCacheDir()
    if love.filesystem and love.filesystem.createDirectory then
        pcall(love.filesystem.createDirectory, "Cache")
    end
end

local function WriteSvPng(Hue, Size)
    EnsureColorCacheDir()
    local Path = string.format("Cache/Sv_%d_%d.png", math.floor(Hue + 0.5) % 360, Size)
    if love.filesystem.getInfo and love.filesystem.getInfo(Path) then
        return Path
    end
    local Data = love.image.newImageData(Size, Size)
    for Y = 0, Size - 1 do
        for X = 0, Size - 1 do
            local S = X / math.max(1, Size - 1)
            local V = 1 - Y / math.max(1, Size - 1)
            local R, G, B = HsvToRgb(Hue, S, V)
            Data:setPixel(X, Y, R, G, B, 1)
        end
    end
    Data:encode("png", Path)
    return Path
end

local function WriteHuePng(Width, Height)
    EnsureColorCacheDir()
    local Path = string.format("Cache/HueStrip_%d_%d.png", Width, Height)
    if love.filesystem.getInfo and love.filesystem.getInfo(Path) then
        return Path
    end
    local Data = love.image.newImageData(Width, Height)
    for Y = 0, Height - 1 do
        local H = (Y / math.max(1, Height - 1)) * 360
        local R, G, B = HsvToRgb(H, 1, 1)
        for X = 0, Width - 1 do
            Data:setPixel(X, Y, R, G, B, 1)
        end
    end
    Data:encode("png", Path)
    return Path
end

function OpenColorPicker(Entry, screenX, screenY)
    CloseColorPicker()
    CloseAttrDialog()
    local Raw = Entry.Raw
    if type(Raw) ~= "table" then
        return
    end
    local R = math.max(0, math.min(1, Raw[1] or 0))
    local G = math.max(0, math.min(1, Raw[2] or 0))
    local B = math.max(0, math.min(1, Raw[3] or 0))
    local A = math.max(0, math.min(1, Raw[4] or 1))
    local Hue, Sat, Val = RgbToHsv(R, G, B)

    local Parent = GetOverlayParent()
    if not Parent then
        return
    end

    local W, H = love.graphics.getDimensions()
    local Pw, Ph = 280, 260
    local Px = math.floor((screenX or 200) + 8)
    local Py = math.floor((screenY or 200) - 10)
    if Px + Pw > W - 8 then Px = W - Pw - 8 end
    if Py + Ph > H - 8 then Py = H - Ph - 8 end
    if Px < 8 then Px = 8 end
    if Py < 8 then Py = 8 end

    local Panel = Instance.new("Frame", Parent)
    Panel.Name = "ColorPickerOverlay"
    Panel.BackgroundColor = Theme.Get("ModalOverlay")
    Panel.ZIndex = 2000
    Panel.Position = UDim.New(0, Px, 0, Py)
    Panel.Size = UDim.FromOffset(Pw, Ph)

    local Title = Instance.new("TextLabel", Panel)
    Title.Text = "Color - " .. tostring(Entry.Display or "Color")
    Title.TextSize = 12
    Title.TextColor = Theme.Get("TitlebarText")
    Title.BackgroundColor = Color.FromRGBA(52, 52, 60)
    Title.Position = UDim.New(0, 0, 0, 0)
    Title.Size = UDim.New(1, 0, 0, 22)
    Title.TextAlignment = { "Center", "Center" }

    local SvSize = 140
    local SvPath = WriteSvPng(Hue, SvSize)
    local SvImg = Instance.new("ImageLabel", Panel)
    SvImg.Name = "SvSquare"
    SvImg.Image = SvPath
    SvImg.Position = UDim.New(0, 12, 0, 30)
    SvImg.Size = UDim.FromOffset(SvSize, SvSize)
    SvImg.ZIndex = 2001

    local Cursor = Instance.new("Frame", Panel)
    Cursor.Name = "SvCursor"
    Cursor.BackgroundColor = Color.FromRGBA(255, 255, 255)
    Cursor.Size = UDim.FromOffset(8, 8)
    Cursor.ZIndex = 2005
    local function PlaceCursor()
        local Cx = 12 + Sat * (SvSize - 1) - 4
        local Cy = 30 + (1 - Val) * (SvSize - 1) - 4
        Cursor.Position = UDim.New(0, math.floor(Cx + 0.5), 0, math.floor(Cy + 0.5))
    end
    PlaceCursor()

    local HueW, HueH = 18, SvSize
    local HuePath = WriteHuePng(HueW, HueH)
    local HueImg = Instance.new("ImageLabel", Panel)
    HueImg.Name = "HueStrip"
    HueImg.Image = HuePath
    HueImg.Position = UDim.New(0, 12 + SvSize + 10, 0, 30)
    HueImg.Size = UDim.FromOffset(HueW, HueH)
    HueImg.ZIndex = 2001

    local HueCursor = Instance.new("Frame", Panel)
    HueCursor.Name = "HueCursor"
    HueCursor.BackgroundColor = Color.FromRGBA(255, 255, 255)
    HueCursor.Size = UDim.FromOffset(HueW + 4, 4)
    HueCursor.ZIndex = 2005
    local function PlaceHueCursor()
        local Cy = 30 + (Hue / 360) * (HueH - 1) - 2
        HueCursor.Position = UDim.New(0, 12 + SvSize + 8, 0, math.floor(Cy + 0.5))
    end
    PlaceHueCursor()

    local Swatch = Instance.new("Frame", Panel)
    Swatch.Name = "Swatch"
    Swatch.BackgroundColor = { R, G, B, 1 }
    Swatch.Position = UDim.New(0, 12 + SvSize + 10 + HueW + 12, 0, 30)
    Swatch.Size = UDim.FromOffset(56, 40)
    Swatch.ZIndex = 501

    local ChannelLabels = {}
    local function MakeField(Label, Value, X, Y, Key, MaxV)
        local Lab = Instance.new("TextLabel", Panel)
        Lab.Text = Label
        Lab.TextSize = 11
        Lab.TextColor = Color.FromRGBA(190, 190, 200)
        Lab.BackgroundColor = Color.FromRGBA(0, 0, 0, 0)
        Lab.Position = UDim.New(0, X, 0, Y)
        Lab.Size = UDim.New(0, 18, 0, 18)
        Lab.TextAlignment = { "Left", "Center" }
        Lab.ZIndex = 501
        local Box = Instance.new("Frame", Panel)
        Box.BackgroundColor = Theme.Get("InputFieldBackground")
        Box.Position = UDim.New(0, X + 18, 0, Y)
        Box.Size = UDim.FromOffset(42, 18)
        Box.ZIndex = 2001
        local Txt = Instance.new("TextLabel", Box)
        Txt.Text = tostring(math.floor(Value + 0.5))
        Txt.TextSize = 11
        Txt.TextColor = Color.FromRGBA(255, 255, 255)
        Txt.BackgroundColor = Color.FromRGBA(0, 0, 0, 0)
        Txt.Size = UDim.FromScale(1, 1)
        Txt.TextAlignment = { "Center", "Center" }
        Txt.ZIndex = 2002
        ChannelLabels[Key] = Txt
        local function BeginEdit()
            if not ColorPicker then return end
            local Clean = Txt.Text:gsub("[^%d%.%-]", "")
            if Clean == "" then Clean = "0" end
            local Meta = {
                Buffer = Clean,
                Cursor = #Clean + 1,
                SelectAll = true,
                Label = Txt,
            }
            TextBox.Begin({
                id = "color",
                text = Clean,
                filter = "number",
                selectAll = true,
                tag = Meta,
                onChange = function(State)
                    Meta.Buffer = State.Buffer or ""
                    Meta.Cursor = State.Cursor or 1
                    Meta.SelectAll = State.SelectAll
                    Txt.Text = Meta.Buffer or ""
                end,
                onCommit = function(Text)
                    local N = tonumber((Text or ""):gsub("[^%d%.%-]", ""))
                    if not N then return end
                    N = math.max(0, math.min(MaxV, N))
                    if Key == "R" or Key == "G" or Key == "B" then
                        local Idx = (Key == "R" and 1) or (Key == "G" and 2) or 3
                        ColorPicker.color[Idx] = N / 255
                        local Hh, Ss, Vv = RgbToHsv(ColorPicker.color[1], ColorPicker.color[2], ColorPicker.color[3])
                        ColorPicker.hue, ColorPicker.sat, ColorPicker.val = Hh, Ss, Vv
                    elseif Key == "H" then
                        ColorPicker.hue = N
                        local Rr, Gg, Bb = HsvToRgb(ColorPicker.hue, ColorPicker.sat, ColorPicker.val)
                        ColorPicker.color[1], ColorPicker.color[2], ColorPicker.color[3] = Rr, Gg, Bb
                    elseif Key == "S" or Key == "V" then
                        if Key == "S" then ColorPicker.sat = N / 100 else ColorPicker.val = N / 100 end
                        local Rr, Gg, Bb = HsvToRgb(ColorPicker.hue, ColorPicker.sat, ColorPicker.val)
                        ColorPicker.color[1], ColorPicker.color[2], ColorPicker.color[3] = Rr, Gg, Bb
                    end
                    ColorPicker.RefreshUi()
                end,
                onCancel = function()
                    ColorPicker.RefreshUi()
                end,
            })
        end
        Box.OnClick:Connect(BeginEdit)
        Txt.OnClick:Connect(BeginEdit)
    end

    local FieldX = 12 + SvSize + 10 + HueW + 12
    MakeField("R", R * 255, FieldX, 78, "R", 255)
    MakeField("G", G * 255, FieldX, 98, "G", 255)
    MakeField("B", B * 255, FieldX, 118, "B", 255)
    MakeField("H", Hue, FieldX, 148, "H", 360)
    MakeField("S", Sat * 100, FieldX, 168, "S", 100)
    MakeField("V", Val * 100, FieldX, 188, "V", 100)

    local function RefreshUi()
        if not ColorPicker then return end
        local C = ColorPicker.color
        Swatch.BackgroundColor = { C[1], C[2], C[3], 1 }
        if ChannelLabels.R then ChannelLabels.R.Text = tostring(math.floor(C[1] * 255 + 0.5)) end
        if ChannelLabels.G then ChannelLabels.G.Text = tostring(math.floor(C[2] * 255 + 0.5)) end
        if ChannelLabels.B then ChannelLabels.B.Text = tostring(math.floor(C[3] * 255 + 0.5)) end
        if ChannelLabels.H then ChannelLabels.H.Text = tostring(math.floor(ColorPicker.hue + 0.5)) end
        if ChannelLabels.S then ChannelLabels.S.Text = tostring(math.floor(ColorPicker.sat * 100 + 0.5)) end
        if ChannelLabels.V then ChannelLabels.V.Text = tostring(math.floor(ColorPicker.val * 100 + 0.5)) end
        local NewPath = WriteSvPng(ColorPicker.hue, SvSize)
        SvImg.Image = NewPath
        PlaceCursor = function()
            local Cx = 12 + ColorPicker.sat * (SvSize - 1) - 4
            local Cy = 30 + (1 - ColorPicker.val) * (SvSize - 1) - 4
            Cursor.Position = UDim.New(0, math.floor(Cx + 0.5), 0, math.floor(Cy + 0.5))
        end
        PlaceCursor()
        PlaceHueCursor = function()
            local Cy = 30 + (ColorPicker.hue / 360) * (HueH - 1) - 2
            HueCursor.Position = UDim.New(0, 12 + SvSize + 8, 0, math.floor(Cy + 0.5))
        end
        PlaceHueCursor()
    end

    local function HitSv(Mx, My)
        Mx = Mx or love.mouse.getPosition()
        if My == nil then
            Mx, My = love.mouse.getPosition()
        end
        local Lx = Mx - Px - 12
        local Ly = My - Py - 30
        Lx = math.max(0, math.min(SvSize - 1, Lx))
        Ly = math.max(0, math.min(SvSize - 1, Ly))
        ColorPicker.sat = Lx / math.max(1, SvSize - 1)
        ColorPicker.val = 1 - Ly / math.max(1, SvSize - 1)
        local Rr, Gg, Bb = HsvToRgb(ColorPicker.hue, ColorPicker.sat, ColorPicker.val)
        ColorPicker.color[1], ColorPicker.color[2], ColorPicker.color[3] = Rr, Gg, Bb
        ColorPicker.RefreshUi()
    end

    local function HitHue(Mx, My)
        Mx = Mx or love.mouse.getPosition()
        if My == nil then
            Mx, My = love.mouse.getPosition()
        end
        local Ly = My - Py - 30
        Ly = math.max(0, math.min(HueH - 1, Ly))
        ColorPicker.hue = (Ly / math.max(1, HueH - 1)) * 360
        local Rr, Gg, Bb = HsvToRgb(ColorPicker.hue, ColorPicker.sat, ColorPicker.val)
        ColorPicker.color[1], ColorPicker.color[2], ColorPicker.color[3] = Rr, Gg, Bb
        ColorPicker.RefreshUi()
    end

    SvImg.OnClick:Connect(function()
        local Mx, My = love.mouse.getPosition()
        ColorPicker.dragging = "sv"
        HitSv(Mx, My)
    end)
    HueImg.OnClick:Connect(function()
        local Mx, My = love.mouse.getPosition()
        ColorPicker.dragging = "hue"
        HitHue(Mx, My)
    end)

    local ApplyBtn = Instance.new("Frame", Panel)
    ApplyBtn.BackgroundColor = Theme.Get("ItemSelected")
    ApplyBtn.Position = UDim.New(0, 12, 0, 226)
    ApplyBtn.Size = UDim.FromOffset(120, 24)
    ApplyBtn.ZIndex = 2010
    local ApplyLab = Instance.new("TextLabel", ApplyBtn)
    ApplyLab.Text = "Apply"
    ApplyLab.TextSize = 12
    ApplyLab.TextColor = Color.FromRGBA(255, 255, 255)
    ApplyLab.BackgroundColor = Color.FromRGBA(0, 0, 0, 0)
    ApplyLab.Size = UDim.FromScale(1, 1)
    ApplyLab.TextAlignment = { "Center", "Center" }
    ApplyLab.ZIndex = 2011
    do
        local Nc = Theme.Get("ItemSelected")
        local Hc = Theme.Get("MainButtonHover")
        local function Go() ApplyColorPicker() end
        ApplyBtn.OnClick:Connect(Go)
        ApplyLab.OnClick:Connect(Go)
        ApplyBtn.OnEnter:Connect(function() ApplyBtn.BackgroundColor = Hc end)
        ApplyBtn.OnLeave:Connect(function() ApplyBtn.BackgroundColor = Nc end)
        ApplyLab.OnEnter:Connect(function() ApplyBtn.BackgroundColor = Hc end)
        ApplyLab.OnLeave:Connect(function() ApplyBtn.BackgroundColor = Nc end)
    end

    local CancelBtn = Instance.new("Frame", Panel)
    CancelBtn.BackgroundColor = Theme.Get("Button")
    CancelBtn.Position = UDim.New(0, 144, 0, 226)
    CancelBtn.Size = UDim.FromOffset(120, 24)
    CancelBtn.ZIndex = 2010
    local CancelLab = Instance.new("TextLabel", CancelBtn)
    CancelLab.Text = "Cancel"
    CancelLab.TextSize = 12
    CancelLab.TextColor = Color.FromRGBA(220, 220, 220)
    CancelLab.BackgroundColor = Color.FromRGBA(0, 0, 0, 0)
    CancelLab.Size = UDim.FromScale(1, 1)
    CancelLab.TextAlignment = { "Center", "Center" }
    CancelLab.ZIndex = 502
    CancelBtn.OnClick:Connect(function() CloseColorPicker() end)
    CancelLab.OnClick:Connect(function() CloseColorPicker() end)

    ColorPicker = {
        path = Entry.FullPath,
        isAttr = Entry.IsAttr,
        color = { R, G, B, A },
        hue = Hue,
        sat = Sat,
        val = Val,
        frame = Panel,
        RefreshUi = RefreshUi,
        HitSv = HitSv,
        HitHue = HitHue,
        panelX = Px,
        panelY = Py,
        svSize = SvSize,
        hueW = HueW,
        dragging = nil,
    }
end

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
    if not CurrentNode then
        return
    end
    local Parent = GetOverlayParent()
    if not Parent then
        return
    end
    local IsEdit = existingName ~= nil
    local Attrs = rawget(CurrentNode, "Attributes")
    if not Attrs then
        Attrs = {}
        rawset(CurrentNode, "Attributes", Attrs)
    end
    local TypeMap = rawget(CurrentNode, "_AttrTypes")
    if not TypeMap then
        TypeMap = {}
        rawset(CurrentNode, "_AttrTypes", TypeMap)
    end
    local ExistingVal = IsEdit and Attrs[existingName] or nil
    local TypeId = (IsEdit and TypeMap[existingName]) or (IsEdit and DetectAttrType(ExistingVal)) or "string"
    local NameBuf = existingName or "NewAttribute"
    local ValueBuf = ""
    if ExistingVal ~= nil then
        if type(ExistingVal) == "boolean" then
            ValueBuf = ExistingVal and "true" or "false"
        elseif type(ExistingVal) == "number" then
            ValueBuf = tostring(ExistingVal)
        elseif type(ExistingVal) == "string" then
            ValueBuf = ExistingVal
        elseif IsVector3(ExistingVal) then
            local Arr = ExistingVal:ToArray()
            ValueBuf = string.format("%.3g, %.3g, %.3g", Arr[1], Arr[2], Arr[3])
        elseif type(ExistingVal) == "table" then
            ValueBuf = string.format("%d, %d, %d",
                math.floor((ExistingVal[1] or 0) * 255 + 0.5),
                math.floor((ExistingVal[2] or 0) * 255 + 0.5),
                math.floor((ExistingVal[3] or 0) * 255 + 0.5))
        else
            ValueBuf = tostring(ExistingVal)
        end
    end
    local TypeIdx = 1
    for I, T in ipairs(AttrTypes) do
        if T.id == TypeId then
            TypeIdx = I
            break
        end
    end
    local W, H = love.graphics.getDimensions()
    local Pw, Ph = 300, IsEdit and 230 or 200
    local Px = math.floor(screenX or 200)
    local Py = math.floor(screenY or 200)
    if Px + Pw > W - 8 then Px = W - Pw - 8 end
    if Py + Ph > H - 8 then Py = H - Ph - 8 end
    if Px < 8 then Px = 8 end
    if Py < 8 then Py = 8 end
    local Panel = Instance.new("Frame", Parent)
    Panel.Name = "AttrDialogOverlay"
    Panel.BackgroundColor = Theme.Get("CategoryHeader")
    Panel.ZIndex = 2000
    Panel.Position = UDim.New(0, Px, 0, Py)
    Panel.Size = UDim.FromOffset(Pw, Ph)
    local Title = Instance.new("TextLabel", Panel)
    Title.Text = IsEdit and "Edit Attribute" or "Add Attribute"
    Title.TextSize = 12
    Title.TextColor = Theme.Get("TitlebarText")
    Title.BackgroundColor = Color.FromRGBA(54, 54, 62)
    Title.Size = UDim.New(1, 0, 0, 24)
    Title.TextAlignment = { "Center", "Center" }
    Title.ZIndex = 801
    local function MakeLabel(Text, X, Y)
        local Lab = Instance.new("TextLabel", Panel)
        Lab.Text = Text
        Lab.TextSize = 12
        Lab.TextColor = Theme.Get("SubText")
        Lab.BackgroundColor = Color.FromRGBA(0, 0, 0, 0)
        Lab.Position = UDim.New(0, X, 0, Y)
        Lab.Size = UDim.New(0, 52, 0, 24)
        Lab.TextAlignment = { "Left", "Center" }
        Lab.ZIndex = 801
        return Lab
    end
    local function MakeBox(X, Y, Ww, Text)
        local Box = Instance.new("Frame", Panel)
        Box.BackgroundColor = Theme.Get("InputFieldBackground")
        Box.Position = UDim.New(0, X, 0, Y)
        Box.Size = UDim.FromOffset(Ww, 24)
        Box.ZIndex = 2001
        local Txt = Instance.new("TextLabel", Box)
        Txt.Text = Text
        Txt.TextSize = 12
        Txt.TextColor = Color.FromRGBA(255, 255, 255)
        Txt.BackgroundColor = Color.FromRGBA(0, 0, 0, 0)
        Txt.Position = UDim.New(0, 6, 0, 0)
        Txt.Size = UDim.New(1, -12, 1, 0)
        Txt.TextAlignment = { "Left", "Center" }
        Txt.ZIndex = 2002
        return Box, Txt
    end
    MakeLabel("Name", 12, 36)
    local NameBox, NameTxt = MakeBox(64, 36, 220, NameBuf)
    local function BeginName()
        local Meta = {
            Buffer = NameBuf or "",
            Cursor = #(NameBuf or "") + 1,
            SelectAll = true,
            Label = NameTxt,
        }
        TextBox.Begin({
            id = "attr",
            text = NameBuf or "",
            filter = "text",
            selectAll = true,
            tag = Meta,
            onChange = function(S)
                NameBuf = S.Buffer or ""
                Meta.Buffer = NameBuf
                Meta.Cursor = S.Cursor or (#NameBuf + 1)
                Meta.SelectAll = S.SelectAll
                if NameTxt then
                    NameTxt.Text = NameBuf
                end
                UpdateCaretOverlay(Meta, NameTxt, NameBox)
            end,
            onCommit = function(T)
                NameBuf = T or ""
                if NameTxt then NameTxt.Text = NameBuf end
            end,
            onCancel = function()
                if NameTxt then NameTxt.Text = NameBuf or "" end
            end,
        })
        if NameTxt then
            NameTxt.Text = NameBuf or ""
        end
    end
    NameBox.OnClick:Connect(BeginName)
    NameTxt.OnClick:Connect(BeginName)
    MakeLabel("Type", 12, 68)
    local TypeBox, TypeTxt = MakeBox(64, 68, 220, AttrTypes[TypeIdx].label .. "  v")
    local function OpenTypeDropdown()
        local Opts = {}
        for _, T in ipairs(AttrTypes) do
            Opts[#Opts + 1] = T.label
        end
        local Mx, My = love.mouse.getPosition()
        local Ty = My + 4
        OpenListDropdown(Opts, AttrTypes[TypeIdx].label, Mx, Ty, function(Choice)
            for I, T in ipairs(AttrTypes) do
                if T.label == Choice then
                    TypeIdx = I
                    TypeId = T.id
                    TypeTxt.Text = T.label .. "  v"
                    if not IsEdit or ExistingVal == nil then
                        local Def = DefaultForAttrType(TypeId)
                        if type(Def) == "boolean" then
                            ValueBuf = Def and "true" or "false"
                        elseif type(Def) == "number" then
                            ValueBuf = tostring(Def)
                        elseif IsVector3(Def) then
                            ValueBuf = "0, 0, 0"
                        elseif type(Def) == "table" then
                            ValueBuf = "255, 255, 255"
                        else
                            ValueBuf = tostring(Def)
                        end
                        if AttrDialog and AttrDialog.ValueTxt then
                            AttrDialog.ValueTxt.Text = ValueBuf
                        end
                    end
                    break
                end
            end
        end, { path = "__attr_type", maxRows = 8, width = 220, fromAttrDialog = true, keepDialogs = true })
    end
    TypeBox.OnClick:Connect(OpenTypeDropdown)
    TypeTxt.OnClick:Connect(OpenTypeDropdown)
    MakeLabel("Value", 12, 100)
    local ValueBox, ValueTxt = MakeBox(64, 100, 220, ValueBuf ~= "" and ValueBuf or "")
    local function BeginValue()
        local Meta = {
            Buffer = ValueBuf or "",
            Cursor = #(ValueBuf or "") + 1,
            SelectAll = true,
            Label = ValueTxt,
        }
        TextBox.Begin({
            id = "attr",
            text = ValueBuf or "",
            filter = "text",
            selectAll = true,
            tag = Meta,
            onChange = function(S)
                ValueBuf = S.Buffer or ""
                Meta.Buffer = ValueBuf
                Meta.Cursor = S.Cursor or (#ValueBuf + 1)
                Meta.SelectAll = S.SelectAll
                if ValueTxt then
                    ValueTxt.Text = ValueBuf or ""
                end
            end,
            onCommit = function(T)
                ValueBuf = T or ""
                ValueTxt.Text = ValueBuf
            end,
            onCancel = function() end,
        })
    end
    ValueBox.OnClick:Connect(BeginValue)
    ValueTxt.OnClick:Connect(BeginValue)
    local function ParseValue(Type, Text)
        Text = tostring(Text or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if Type == "boolean" then
            local L = Text:lower()
            return L == "true" or L == "1" or L == "yes"
        end
        if Type == "number" then
            return tonumber(Text) or 0
        end
        if Type == "Vector3" then
            local Parts = {}
            for P in Text:gmatch("[^,]+") do
                Parts[#Parts + 1] = tonumber(P) or 0
            end
            return Vector3.new(Parts[1] or 0, Parts[2] or 0, Parts[3] or 0)
        end
        if Type == "Color3" then
            local Parts = {}
            for P in Text:gmatch("[^,]+") do
                Parts[#Parts + 1] = tonumber(P) or 0
            end
            local R = (Parts[1] or 0)
            local G = (Parts[2] or 0)
            local B = (Parts[3] or 0)
            if R > 1 or G > 1 or B > 1 then
                return Color.FromRGBA(R, G, B)
            end
            return Color.Float(R, G, B, 1)
        end
        return Text
    end
    local function SyncAttrFieldsFromTextBox()
        if not (TextBox and TextBox.IsActive and TextBox.IsActive()) then
            return
        end
        local A = TextBox.Get()
        if not A or A.id ~= "attr" then
            return
        end
        local Tag = A.Tag
        if Tag and Tag.Label == NameTxt then
            NameBuf = A.Buffer or ""
        elseif Tag and Tag.Label == ValueTxt then
            ValueBuf = A.Buffer or ""
        else
            if NameTxt and A.Buffer then
                NameBuf = A.Buffer
            end
        end
        if TextBox.End then
            TextBox.End()
        end
    end
    local function CommitAttr()
        SyncAttrFieldsFromTextBox()
        local Name = tostring(NameBuf or ""):gsub("^%s+", ""):gsub("%s+$", "")
        if Name == "" or Name:sub(1, 1) == "_" then
            if NameBox then
                NameBox.BackgroundColor = Color.FromRGBA(90, 30, 30)
            end
            return
        end
        if not Attrs then
            return
        end
        if IsEdit and existingName and existingName ~= Name then
            Attrs[existingName] = nil
            TypeMap[existingName] = nil
        end
        Attrs[Name] = ParseValue(TypeId, ValueBuf)
        TypeMap[Name] = TypeId
        rawset(CurrentNode, "Attributes", Attrs)
        rawset(CurrentNode, "_AttrTypes", TypeMap)
        CloseEnumDropdown()
        CloseAttrDialog()
        Properties:Refresh()
        pcall(function() require("Services.Visuals").Invalidate() end)
    end
    local function WireButton(Btn, Lab, NormalCol, HoverCol, ClickFn)
        Btn.OnClick:Connect(ClickFn)
        Lab.OnClick:Connect(ClickFn)
        Btn.OnEnter:Connect(function()
            Btn.BackgroundColor = HoverCol
        end)
        Btn.OnLeave:Connect(function()
            Btn.BackgroundColor = NormalCol
        end)
        Lab.OnEnter:Connect(function()
            Btn.BackgroundColor = HoverCol
        end)
        Lab.OnLeave:Connect(function()
            Btn.BackgroundColor = NormalCol
        end)
    end
    local OkBtn = Instance.new("Frame", Panel)
    OkBtn.BackgroundColor = Theme.Get("ItemSelected")
    OkBtn.Position = UDim.New(0, 12, 0, IsEdit and 190 or 150)
    OkBtn.Size = UDim.FromOffset(130, 26)
    OkBtn.ZIndex = 2010
    local OkLab = Instance.new("TextLabel", OkBtn)
    OkLab.Text = IsEdit and "Save" or "Create"
    OkLab.TextSize = 12
    OkLab.TextColor = Color.FromRGBA(255, 255, 255)
    OkLab.BackgroundColor = Color.FromRGBA(0, 0, 0, 0)
    OkLab.Size = UDim.FromScale(1, 1)
    OkLab.TextAlignment = { "Center", "Center" }
    OkLab.ZIndex = 2011
    WireButton(OkBtn, OkLab, Theme.Get("ItemSelected"), Theme.Get("MainButtonHover"), CommitAttr)
    local CancelBtn = Instance.new("Frame", Panel)
    CancelBtn.BackgroundColor = Theme.Get("Button")
    CancelBtn.Position = UDim.New(0, 154, 0, IsEdit and 190 or 150)
    CancelBtn.Size = UDim.FromOffset(130, 26)
    CancelBtn.ZIndex = 2010
    local CancelLab = Instance.new("TextLabel", CancelBtn)
    CancelLab.Text = "Cancel"
    CancelLab.TextSize = 12
    CancelLab.TextColor = Color.FromRGBA(220, 220, 220)
    CancelLab.BackgroundColor = Color.FromRGBA(0, 0, 0, 0)
    CancelLab.Size = UDim.FromScale(1, 1)
    CancelLab.TextAlignment = { "Center", "Center" }
    CancelLab.ZIndex = 2011
    local function DoCancel()
        if TextBox and TextBox.IsActive and TextBox.IsActive() then
            if TextBox.End then TextBox.End() end
        end
        CloseEnumDropdown()
        CloseAttrDialog()
    end
    WireButton(CancelBtn, CancelLab, Theme.Get("Button"), Theme.Get("ButtonHover"), DoCancel)
    if IsEdit then
        local DelBtn = Instance.new("Frame", Panel)
        DelBtn.BackgroundColor = Color.FromRGBA(120, 50, 50)
        DelBtn.Position = UDim.New(0, 12, 0, 140)
        DelBtn.Size = UDim.FromOffset(272, 26)
        DelBtn.ZIndex = 2010
        local DelLab = Instance.new("TextLabel", DelBtn)
        DelLab.Text = "Delete Attribute"
        DelLab.TextSize = 12
        DelLab.TextColor = Color.FromRGBA(255, 220, 220)
        DelLab.BackgroundColor = Color.FromRGBA(0, 0, 0, 0)
        DelLab.Size = UDim.FromScale(1, 1)
        DelLab.TextAlignment = { "Center", "Center" }
        DelLab.ZIndex = 2011
        local function DoDelete()
            if existingName then
                Attrs[existingName] = nil
                TypeMap[existingName] = nil
            end
            CloseEnumDropdown()
            CloseAttrDialog()
            Properties:Refresh()
        end
        DelBtn.OnClick:Connect(DoDelete)
        DelLab.OnClick:Connect(DoDelete)
    end
    AttrDialog = {
        frame = Panel,
        ValueTxt = ValueTxt,
        nameBuf = function() return NameBuf end,
    }
end

local function BuildRow(Parent, Entry, RowIndex)
    local Indent = (Entry.Depth or 0) * 14
    local Frame = Instance.new("Frame", Parent)
    Frame.Name = "PropRow"
    Frame.Position = UDim.New(0, 0, 0, RowIndex * RowHeight - ScrollY)
    Frame.Size = UDim.New(1, 0, 0, RowHeight)

    if Entry.Kind == "Header" or Entry.Type == "Header" then
        Frame.BackgroundColor = Theme.Get("CategoryHeader")
        local Title = Instance.new("TextLabel", Frame)
        Title.BackgroundColor = Color.FromRGBA(0, 0, 0, 0)
        Title.Position = UDim.New(0, 8, 0, 0)
        Title.Size = UDim.New(1, -16, 1, 0)
        Title.Text = Entry.Display or ""
        Title.TextSize = 12
        Title.TextColor = Theme.Get("TitlebarText")
        Title.TextAlignment = { "Left", "Center" }
        Title.ZIndex = 3
        return Frame
    end
    if Entry.Kind == "Category" then
        Frame.BackgroundColor = Theme.Get("CategoryHeader")
        local Arrow = Instance.new("ImageLabel", Frame)
        Arrow.BackgroundColor = Color.FromRGBA(0, 0, 0, 0)
        Arrow.Image = IsExpanded(Entry.FullPath) and "Assets/Decals/ArrowDown.png" or "Assets/Decals/ArrowRight.png"
        Arrow.Anchor = {0, 0.5}
        Arrow.Position = UDim.New(0, 4, 0.5, 0)
        Arrow.Size = UDim.FromOffset(16, 16)
        Arrow.ZIndex = 3
        Arrow.MouseCursor = "hand"
        local Title = Instance.new("TextLabel", Frame)
        Title.BackgroundColor = Color.FromRGBA(0, 0, 0, 0)
        Title.Position = UDim.New(0, 22, 0, 0)
        Title.Size = UDim.New(1, -40, 1, 0)
        Title.Text = string.format("%s  (%d)", Entry.Name, Entry.Count or 0)
        Title.TextSize = 12
        Title.TextColor = Theme.Get("TitlebarText")
        Title.TextAlignment = { "Left", "Center" }
        Title.ZIndex = 3
        Frame.OnClick:Connect(function()
            ToggleGroup(Entry.FullPath)
            Properties:Refresh()
        end)
        return Frame
    end
    Frame.ClipsDescendants = true

    local isHead = Entry.Type == "Head" or Entry.Type == "Attributes"
    local isGroup = Entry.IsGroup
    local bg
    if isHead then
        bg = Theme.Get("CategoryHeader")
    elseif isGroup then
        bg = Theme.Get("CategoryHeader")
    elseif RowIndex % 2 == 0 then
        bg = Theme.Get("RowEven")
    else
        bg = Theme.Get("RowOdd")
    end
    Frame.BackgroundColor = bg

    if isGroup and Entry.Type ~= "Head" then
        local arrow = Instance.new("ImageLabel", Frame)
        arrow.BackgroundColor = Color.FromRGBA(0, 0, 0, 0)
        arrow.Image = IsExpanded(Entry.FullPath) and "Assets/Decals/ArrowDown.png" or "Assets/Decals/ArrowRight.png"
        arrow.Anchor = {0, 0.5}
        arrow.Position = UDim.New(0, Indent + 2, 0.5, 0)
        arrow.Size = UDim.FromOffset(14, 14)
        arrow.ZIndex = 3
        arrow.MouseCursor = "hand"
        Frame.OnClick:Connect(function()
            ToggleGroup(Entry.FullPath)
            Properties:Refresh()
        end)
    end

    local ColW = GetLabelColumnWidth()
    local NameX = Indent + (isGroup and 18 or 6)
    local NameW = math.max(40, ColW - NameX - 4)
    local NameLabel = Instance.new("TextLabel", Frame)
    NameLabel.Text = TruncateToWidth(Entry.Display or "", NameW)
    NameLabel.BackgroundColor = Color.FromRGBA(0, 0, 0, 0)
    NameLabel.TextColor = isGroup and Theme.Get("MainText") or Theme.Get("SubText")
    NameLabel.Position = UDim.New(0, NameX, 0, 0)
    NameLabel.Size = UDim.New(0, NameW, 1, 0)
    NameLabel.TextAlignment = { "Left", "Center" }
    NameLabel.TextSize = 12
    NameLabel.ClipsDescendants = true
    NameLabel.TextWrapped = false

    local ValueFrame = Instance.new("Frame", Frame)
    ValueFrame.BackgroundColor = Color.FromRGBA(0, 0, 0, 0)
    ValueFrame.Position = UDim.New(0, ColW + 4, 0, 1)
    ValueFrame.Size = UDim.New(1, -(ColW + 8), 1, -2)
    ValueFrame.ClipsDescendants = true

    local ValueLabel = Instance.new("TextLabel", ValueFrame)
    ValueLabel.BackgroundColor = Color.FromRGBA(0, 0, 0, 0)
    ValueLabel.Position = UDim.New(0, ValuePad, 0, 0)
    ValueLabel.Size = UDim.New(1, -ValuePad * 2, 1, 0)
    ValueLabel.TextAlignment = { "Left", "Center" }
    ValueLabel.TextSize = 12
    ValueLabel.ClipsDescendants = true
    ValueLabel.TextWrapped = false

    local IsEditing = Editing and Editing.FullPath == Entry.FullPath and Editing.IsAttr == Entry.IsAttr

    if isHead then
        ValueLabel.Text = ""
    elseif isGroup then
        if Entry.Type == "Color" and type(Entry.Raw) == "table" then
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
            ValueLabel.TextColor = Theme.Get("SubText")
        else
            ValueLabel.Text = FormatValue(Entry.Raw, Entry.FullPath)
            ValueLabel.TextColor = Theme.Get("SubText")
        end
    else
        if Entry.Type == "Instance" then
            ValueLabel.Text = Entry.Raw or "None"
            if Entry.ReadOnly then
                ValueLabel.TextColor = Theme.Get("DimmedText")
                ValueFrame.BackgroundColor = Color.FromRGBA(0, 0, 0, 0)
                ValueFrame.MouseCursor = "arrow"
            elseif ObjectPick and ObjectPick.path == Entry.FullPath then
                ValueLabel.Text = "Select object..."
                ValueLabel.TextColor = Color.FromRGBA(255, 220, 120)
                ValueFrame.BackgroundColor = Color.FromRGBA(50, 50, 30)
            else
                ValueLabel.TextColor = Theme.Get("ObjectText")
            end
            if not Entry.ReadOnly then
                ValueFrame.OnClick:Connect(function()
                    if ObjectPick and ObjectPick.path == Entry.FullPath then
                        ObjectPick = nil
                        Properties:Refresh()
                        return
                    end
                    Properties:BeginObjectPick(Entry)
                    Properties:Refresh()
                end)
                local ClearBtn = Instance.new("TextLabel", ValueFrame)
                ClearBtn.Text = "x"
                ClearBtn.TextSize = 12
                ClearBtn.TextColor = Color.FromRGBA(200, 120, 120)
                ClearBtn.BackgroundColor = Color.FromRGBA(0, 0, 0, 0)
                ClearBtn.Position = UDim.New(1, -18, 0, 0)
                ClearBtn.Size = UDim.New(0, 16, 1, 0)
                ClearBtn.TextAlignment = { "Center", "Center" }
                ClearBtn.ZIndex = 5
                ClearBtn.MouseCursor = "hand"
                ClearBtn.OnClick:Connect(function()
                    ObjectPick = nil
                    local Root = GetRoot(CurrentNode, Entry.IsAttr)
                    if not Root then
                        Root = CurrentNode
                    end
                    local Path = Entry.FullPath
                    if Path and Path:find(".", 1, true) == nil and type(Root) == "table" then
                        rawset(Root, Path, false)
                    else
                        SetValueAtPath(Root, Path, false)
                    end
                    Properties:Refresh()
                end)
            end
        elseif IsEditing then
            ValueFrame.BackgroundColor = Color.FromRGBA(0, 0, 0, 0)
            ValueLabel.Text = Editing.Buffer or ""
            ValueLabel.TextColor = Theme.Get("ValueText")
            local Ring = AttachFocusRing(ValueFrame)
            Editing.FocusRing = Ring
            Editing.Label = ValueLabel
            Editing.ValueFrame = ValueFrame
            PulseFocusRing(Ring, Editing.Error)
            UpdateCaretOverlay(Editing, ValueLabel, ValueFrame)
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
                ValueLabel.TextColor = Theme.Get("NumberText")
            else
                ValueLabel.TextColor = Theme.Get("ValueText")
            end

            if enumOpts then
                ValueLabel.Text = FormatValue(Entry.Raw, Entry.FullPath) .. "  v"
                ValueFrame.OnClick:Connect(function()
                    if EnumDropdown and EnumDropdown.path == Entry.FullPath then
                        CloseEnumDropdown()
                        return
                    end
                    local mx, my = love.mouse.getPosition()
                    OpenEnumDropdown(Entry, mx, my + 4)
                end)
            else
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
                        if meta.Label then
                            meta.Label.Text = s.Buffer or ""
                            meta.Label.TextColor = Theme.Get("ValueText")
                        end
                        UpdateCaretOverlay(meta, meta.Label, meta.ValueFrame)
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
                meta.Label = ValueLabel
                meta.ValueFrame = ValueFrame
                ValueLabel.Text = Buf
                ValueLabel.TextColor = Theme.Get("ValueText")
                ValueFrame.BackgroundColor = Color.FromRGBA(0, 0, 0, 0)
                meta.FocusRing = AttachFocusRing(ValueFrame)
                Editing.FocusRing = meta.FocusRing
                PulseFocusRing(meta.FocusRing, false)
                UpdateCaretOverlay(meta, ValueLabel, ValueFrame)
            end
            ValueFrame.OnClick:Connect(StartEdit)
            end
        end
    end

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

local function ComputeVisibleHeight()
    local ScreenH = love.graphics.getHeight()
    local headerH = 17
    local ok, Dock = pcall(require, "Services.Dock")
    if ok and Dock and Dock.GetLayout then
        local L = Dock:GetLayout()
        if L and L.RightBottom and L.RightBottom.H then
            return math.max(60, L.RightBottom.H - headerH)
        end
    end
    if ContainerFrame then
        local sz = ContainerFrame.Size
        if type(sz) == "table" and type(sz.Y) == "table" and type(sz.Y.Offset) == "number" and sz.Y.Offset > 0 then
            return math.max(60, sz.Y.Offset)
        end
    end
    return math.max(60, ScreenH * 0.30)
end

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
    if not ContainerFrame then
        return
    end
    EnsureCategoryDefaults()
    local Kids = rawget(ContainerFrame, "Children")
    if Kids then
        for Index = #Kids, 1, -1 do
            local Child = Kids[Index]
            if Child and Child.Destroy then
                Child:Destroy()
            end
        end
    end
    if not CurrentNode then
        LastRowCount = 0
        ContentHeight = 0
        return
    end
    local Props, Attrs = CollectEntries(CurrentNode)
    local RowIndex = 0
    do
        local FilterFrame = Instance.new("Frame", ContainerFrame)
        FilterFrame.Name = "FilterBar"
        FilterFrame.Position = UDim.New(0, 0, 0, RowIndex * RowHeight - ScrollY)
        FilterFrame.Size = UDim.New(1, 0, 0, RowHeight)
        FilterFrame.BackgroundColor = Theme.Get("RowEven")
        FilterFrame.ZIndex = 2
        local FilterLabel = Instance.new("TextLabel", FilterFrame)
        FilterLabel.Text = "Filter"
        FilterLabel.TextSize = 11
        FilterLabel.TextColor = Theme.Get("SubText")
        FilterLabel.BackgroundColor = Color.FromRGBA(0, 0, 0, 0)
        FilterLabel.Position = UDim.New(0, 6, 0, 0)
        FilterLabel.Size = UDim.New(0, 40, 1, 0)
        FilterLabel.TextAlignment = { "Left", "Center" }
        local Box = Instance.new("Frame", FilterFrame)
        Box.BackgroundColor = Theme.Get("InputFieldBackground")
        Box.Position = UDim.New(0, 48, 0, 3)
        Box.Size = UDim.New(1, -56, 0, RowHeight - 6)
        Box.ZIndex = 3
        local Txt = Instance.new("TextLabel", Box)
        Txt.Text = FilterText ~= "" and FilterText or "Filter Properties..."
        Txt.TextSize = 12
        Txt.TextColor = FilterText ~= "" and Theme.Get("TitlebarText") or Color.FromRGBA(110, 110, 120)
        Txt.BackgroundColor = Color.FromRGBA(0, 0, 0, 0)
        Txt.Position = UDim.New(0, 6, 0, 0)
        Txt.Size = UDim.FromScale(1, 1)
        Txt.TextAlignment = { "Left", "Center" }
        Txt.ZIndex = 4
        local function BeginFilter()
            TextBox.Begin({
                id = "PropFilter",
                text = FilterText,
                filter = "text",
                selectAll = true,
                onChange = function(State)
                    FilterText = State.Buffer or ""
                    Txt.Text = FilterText ~= "" and FilterText or "Filter Properties..."
                    Txt.TextColor = FilterText ~= "" and Theme.Get("TitlebarText") or Color.FromRGBA(110, 110, 120)
                end,
                onCommit = function(Text)
                    FilterText = Text or ""
                    Properties:Refresh()
                end,
                onCancel = function()
                    Properties:Refresh()
                end,
            })
        end
        Box.OnClick:Connect(BeginFilter)
        Txt.OnClick:Connect(BeginFilter)
        RowIndex = RowIndex + 1
    end
    BuildRow(ContainerFrame, {
        Kind = "Header",
        Display = (CurrentNode.ClassName or "?") .. "  " .. (CurrentNode.Name or ""),
        FullPath = "__Header",
        Depth = 0,
        Raw = nil,
        Type = "Header",
    }, RowIndex)
    RowIndex = RowIndex + 1
    for Index = 1, #Props do
        BuildRow(ContainerFrame, Props[Index], RowIndex)
        RowIndex = RowIndex + 1
    end
    local AttrExpanded = IsExpanded("__Attributes")
    BuildRow(ContainerFrame, {
        Kind = "Group",
        Display = "Attributes",
        FullPath = "__Attributes",
        Depth = 0,
        Raw = Attrs,
        Type = "Attributes",
    }, RowIndex)
    RowIndex = RowIndex + 1
    if AttrExpanded then
        for Index = 1, #Attrs do
            BuildRow(ContainerFrame, Attrs[Index], RowIndex)
            RowIndex = RowIndex + 1
        end
        local AddFrame = Instance.new("Frame", ContainerFrame)
        AddFrame.Position = UDim.New(0, 0, 0, RowIndex * RowHeight - ScrollY)
        AddFrame.Size = UDim.New(1, 0, 0, RowHeight)
        AddFrame.BackgroundColor = Color.FromRGBA(40, 40, 44)
        local AddLab = Instance.new("TextLabel", AddFrame)
        AddLab.Text = "+  Add Attribute"
        AddLab.TextSize = 12
        AddLab.TextColor = Color.FromRGBA(120, 170, 255)
        AddLab.BackgroundColor = Color.FromRGBA(0, 0, 0, 0)
        AddLab.Size = UDim.FromScale(1, 1)
        AddLab.Position = UDim.New(0, 12, 0, 0)
        AddLab.TextAlignment = { "Left", "Center" }
        AddFrame.OnClick:Connect(function()
            local Mx, My = love.mouse.getPosition()
            OpenAttrDialog(Mx, My, nil)
        end)
        RowIndex = RowIndex + 1
    end
    LastRowCount = RowIndex
    ContentHeight = RowIndex * RowHeight
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
    _G.Properties = Properties
:Commit()
end

function Properties:Cancel()
    Editing = nil
    CloseColorPicker()
    CloseAttrDialog()
    CloseEnumDropdown()
    Properties:Refresh()
end

function Properties:HandleTextInput(Text)
    if TextBox and TextBox.IsActive and TextBox.IsActive() then
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
    if ColorPicker or AttrDialog then return true end
    return false
end

local _LastCaretBlink = -1
local _LastPanelW = -1
function Properties:Tick()
    local Pw = GetPanelWidth()
    if Pw ~= _LastPanelW and _LastPanelW > 0 and ContainerFrame then
        _LastPanelW = Pw
        Properties:Refresh()
        return
    end
    _LastPanelW = Pw
    if ColorPicker and ColorPicker.frame then
        local Mx, My = love.mouse.getPosition()
        local Down = love.mouse.isDown(1)
        if Down then
            local Px = ColorPicker.panelX or 0
            local Py = ColorPicker.panelY or 0
            local SvSize = ColorPicker.svSize or 140
            local HueW = ColorPicker.hueW or 18
            local Lx = Mx - Px - 12
            local Ly = My - Py - 30
            if ColorPicker.dragging == "sv" or (not ColorPicker.dragging and Lx >= 0 and Ly >= 0 and Lx < SvSize and Ly < SvSize) then
                ColorPicker.dragging = "sv"
                if ColorPicker.HitSv then ColorPicker.HitSv(Mx, My) end
            elseif ColorPicker.dragging == "hue" or (not ColorPicker.dragging and Lx >= (SvSize + 8) and Lx < (SvSize + 10 + HueW + 4) and Ly >= 0 and Ly < SvSize) then
                ColorPicker.dragging = "hue"
                if ColorPicker.HitHue then ColorPicker.HitHue(Mx, My) end
            end
        else
            ColorPicker.dragging = nil
        end
    end
    if not Editing then
        if TextBox and TextBox.IsActive and TextBox.IsActive() then
            local A = TextBox.Get()
            if A and (A.id == "attr" or A.id == "color") then
                local Tag = A.Tag
                if Tag and Tag.Label then
                    Tag.Buffer = A.Buffer
                    Tag.Cursor = A.Cursor
                    Tag.SelectAll = A.SelectAll
                    Tag.Label.Text = Tag.Buffer or ""
                    UpdateCaretOverlay(Tag, Tag.Label, Tag.ValueFrame or Tag.Label)
                end
            end
        end
        return
    end
    if TextBox and TextBox.IsActive and TextBox.IsActive() then
        local A = TextBox.Get()
        if A then
            Editing.Buffer = A.Buffer
            Editing.Cursor = A.Cursor
            Editing.SelectAll = A.SelectAll
        end
    end
    if Editing.Label then
        Editing.Label.Text = Editing.Buffer or ""
        UpdateCaretOverlay(Editing, Editing.Label, Editing.ValueFrame)
    end
    if Editing.FocusRing then
        PulseFocusRing(Editing.FocusRing, Editing.Error)
    end
end

function Properties:MousePressed(X, Y, Button)
    if Button ~= 1 then
        return false
    end
    if EnumDropdown and EnumDropdown.frame then
        local F = EnumDropdown.frame
        local Pos = F.Position
        local Size = F.Size
        local Ox = Pos and (Pos[2] or 0) or 0
        local Oy = Pos and (Pos[4] or 0) or 0
        local W = Size and (Size[2] or 0) or 0
        local H = Size and (Size[4] or 0) or 0
        if not (X >= Ox and X < Ox + W and Y >= Oy and Y < Oy + H) then
            CloseEnumDropdown()
        end
    end
    if ColorPicker and ColorPicker.frame then
        local Px = ColorPicker.panelX or 0
        local Py = ColorPicker.panelY or 0
        local SvSize = ColorPicker.svSize or 140
        local HueW = ColorPicker.hueW or 18
        local Lx = X - Px - 12
        local Ly = Y - Py - 30
        if Lx >= 0 and Ly >= 0 and Lx < SvSize and Ly < SvSize then
            ColorPicker.dragging = "sv"
            if ColorPicker.HitSv then ColorPicker.HitSv(X, Y) end
            return true
        end
        local Hx = X - Px - (12 + SvSize + 10)
        if Hx >= -2 and Ly >= 0 and Hx < HueW + 4 and Ly < SvSize then
            ColorPicker.dragging = "hue"
            if ColorPicker.HitHue then ColorPicker.HitHue(X, Y) end
            return true
        end
    end
    return false
end

function Properties:MouseReleased(X, Y, Button)
    if ColorPicker then
        ColorPicker.dragging = nil
    end
end

function Properties:MouseMoved(X, Y)
    if ColorPicker and ColorPicker.dragging then
        if ColorPicker.dragging == "sv" and ColorPicker.HitSv then
            ColorPicker.HitSv(X, Y)
        elseif ColorPicker.dragging == "hue" and ColorPicker.HitHue then
            ColorPicker.HitHue(X, Y)
        end
        return true
    end
    return false
end

function Properties:HasModal()
    return ColorPicker ~= nil or AttrDialog ~= nil
end

function Properties:ClosePopups()
    CloseColorPicker()
    CloseAttrDialog()
    if CloseEnumDropdown then
        CloseEnumDropdown()
    end
end

_G.Properties = Properties
return Properties
