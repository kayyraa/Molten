local Color = require("Services.Color")
local UDim = require("Services.UDim")

local Gui = {}

local function SafeText(s)
    if s == nil then
        return ""
    end

    s = tostring(s)

    local out = {}
    local i = 1
    local n = #s

    while i <= n do
        local c = s:byte(i)

        if c < 128 then
            if c >= 32 or c == 9 or c == 10 then
                out[#out + 1] = string.char(c)
            else
                out[#out + 1] = "?"
            end
            i = i + 1
        elseif c >= 194 and c <= 244 then
            local len = (c < 224) and 2 or ((c < 240) and 3 or 4)
            if i + len - 1 <= n then
                out[#out + 1] = s:sub(i, i + len - 1)
                i = i + len
            else
                out[#out + 1] = "?"
                i = i + 1
            end
        else
            out[#out + 1] = "?"
            i = i + 1
        end
    end

    return table.concat(out)
end

Gui.Console = {
    Output = {},
    Offset = {0, 0}
}

local CachedFontPath
local FontCache = {}
local ClickedThisFrame = false

-- Global topmost hit target for this frame (ZIndex + DisplayOrder aware)
local HitNode = nil
local HitScore = -1e18
local HitSerial = 0
local PrevHover = nil
local RenderDepth = 0

local function HitConsider(node, score)
    HitSerial = HitSerial + 1
    -- Later same-score nodes win (drawn on top when equal ZIndex)
    local s = score + HitSerial * 1e-6
    if s >= HitScore then
        HitScore = s
        HitNode = node
    end
end

local function HasClickHandler(node)
    if not node then return false end
    local sig = rawget(node, "OnClick")
    if not sig then return false end
    if type(sig.HasConnections) == "function" then
        return sig:HasConnections()
    end
    -- Fallback: treat as connected if Fire exists (legacy)
    return false
end

local function FindClickable(node)
    local cur = node
    local guard = 0
    while cur and guard < 32 do
        guard = guard + 1
        if HasClickHandler(cur) then
            return cur
        end
        cur = rawget(cur, "_Parent") or rawget(cur, "Parent")
    end
    return nil
end

local function HitFinalize()
    local top = HitNode

    -- Hover enter/leave only for the true topmost node
    if PrevHover and PrevHover ~= top then
        rawset(PrevHover, "_IsHovered", false)
        if PrevHover.OnLeave then
            pcall(function() PrevHover.OnLeave:Fire() end)
        end
    end
    if top and top ~= PrevHover then
        rawset(top, "_IsHovered", true)
        if top.OnEnter then
            pcall(function() top.OnEnter:Fire() end)
        end
    end
    if top then
        rawset(top, "_IsHovered", true)
    end
    PrevHover = top

    -- Click: bubble to nearest ancestor with OnClick (labels often cover buttons)
    if ClickedThisFrame and top then
        local clickable = FindClickable(top)
        if clickable and clickable.OnClick then
            pcall(function() clickable.OnClick:Fire() end)
        end
    end
end

function Gui:NotifyMousePressed()
    ClickedThisFrame = true
end

function Gui:ClearClickFlag()
    -- Finalize input AFTER all Gui:Render roots this frame (StarterGui + CoreGui)
    HitFinalize()
    ClickedThisFrame = false
    HitNode = nil
    HitScore = -1e18
end

local function GetProp(Node, Name)
    local Direct = rawget(Node, Name)
    if Direct ~= nil then
        return Direct
    end

    local Attributes = rawget(Node, "Attributes")
    if Attributes and Attributes[Name] ~= nil then
        return Attributes[Name]
    end

    if Node.GetAttribute then
        return Node:GetAttribute(Name)
    end

    return nil
end

local function ResolveUDim2(Val, ParentW, ParentH)
    if not Val then
        return 0, 0
    end

    local Sx = Val[1] or 0
    local Ox = Val[2] or 0
    local Sy = Val[3] or 0
    local Oy = Val[4] or 0

    return Sx * ParentW + Ox, Sy * ParentH + Oy
end

local function ResolveAnchor(Val)
    if not Val then
        return 0, 0
    end

    return Val[1] or 0, Val[2] or 0
end

local function IsGuiObjectClass(ClassName)
    return ClassName == "Frame"
        or ClassName == "TextLabel"
        or ClassName == "ImageLabel"
        or ClassName == "GuiObject"
        or ClassName == "ScreenGui"
end

local function GetUiPadding(Node)
    local Children = rawget(Node, "Children")
    if not Children then
        return 0, 0, 0, 0
    end

    for Index = 1, #Children do
        local Child = Children[Index]
        if rawget(Child, "ClassName") == "UiPadding" then
            local Pl = GetProp(Child, "PaddingLeft") or {0, 0, 0, 0}
            local Pr = GetProp(Child, "PaddingRight") or {0, 0, 0, 0}
            local Pt = GetProp(Child, "PaddingTop") or {0, 0, 0, 0}
            local Pb = GetProp(Child, "PaddingBottom") or {0, 0, 0, 0}
            return (Pl[2] or 0), (Pr[2] or 0), (Pt[2] or 0), (Pb[2] or 0)
        end
    end

    return 0, 0, 0, 0
end

-- ---------------------------------------------------------------------------
-- Render
-- ---------------------------------------------------------------------------

function Gui:Render(Node, ParentX, ParentY, ParentW, ParentH)
    local CanvasW, CanvasH = UDim.CanvasDimentions()
    Node = Node or _G.Gui or _G.StarterGui

    if not Node then
        return
    end

    if RenderDepth == 0 then
        -- First root Render this frame: start fresh hit accumulation
        HitNode = nil
        HitScore = -1e18
        HitSerial = 0
    end
    RenderDepth = RenderDepth + 1

    ParentX = ParentX or 0
    ParentY = ParentY or 0
    ParentW = ParentW or CanvasW
    ParentH = ParentH or CanvasH

    local MouseX, MouseY = love.mouse.getPosition()
    local MouseLocked = love.mouse.getRelativeMode()

    local Children = rawget(Node, "Children")
    if not Children and Node.GetChildren then
        Children = Node:GetChildren()
    end
    if not Children then
        RenderDepth = RenderDepth - 1
        return
    end

    local GuiList = {}
    local ObjectList = {}

    for Index = 1, #Children do
        local Child = Children[Index]
        local ClassName = rawget(Child, "ClassName")

        if ClassName == "ScreenGui" or ClassName == "StarterGui" then
            GuiList[#GuiList + 1] = Child
        else
            ObjectList[#ObjectList + 1] = Child
        end
    end

    if #GuiList > 1 then
        table.sort(GuiList, function(A, B)
            return (GetProp(A, "DisplayOrder") or 0) < (GetProp(B, "DisplayOrder") or 0)
        end)
    end

    for Index = 1, #GuiList do
        local GuiElement = GuiList[Index]
        if GetProp(GuiElement, "Enabled") ~= false then
            local dorder = GetProp(GuiElement, "DisplayOrder") or 0
            -- Stamp layer onto this ScreenGui so descendants can inherit via parent walk
            rawset(GuiElement, "_LayerOrder", dorder)
            Gui:Render(GuiElement, ParentX, ParentY, ParentW, ParentH)
        end
    end

    if #ObjectList > 1 then
        table.sort(ObjectList, function(A, B)
            return (GetProp(A, "ZIndex") or 1) < (GetProp(B, "ZIndex") or 1)
        end)
    end

    for Index = 1, #ObjectList do
        local Child = ObjectList[Index]

        -- Floating overlays parented under CoreGui/Folder: boost layer so they beat ScreenGui
        if rawget(Child, "_LayerOrder") == nil then
            local z = GetProp(Child, "ZIndex") or 1
            if z >= 100 then
                rawset(Child, "_LayerOrder", 100 + math.floor(z / 100))
            end
        end

        if GetProp(Child, "Visible") == false then
            if rawget(Child, "_IsHovered") then
                rawset(Child, "_IsHovered", false)
                if Child.OnLeave then
                    Child.OnLeave:Fire()
                end
            end
            goto ContinueChild
        end

        local ClassName = rawget(Child, "ClassName")
        local AbsX, AbsY = ParentX, ParentY
        local W, H = ParentW, ParentH

        if IsGuiObjectClass(ClassName) then
            local PosX, PosY = ResolveUDim2(GetProp(Child, "Position"), ParentW, ParentH)
            local SizeW, SizeH = ResolveUDim2(GetProp(Child, "Size"), ParentW, ParentH)
            local AncX, AncY = ResolveAnchor(GetProp(Child, "Anchor"))

            W, H = SizeW, SizeH
            AbsX = ParentX + PosX - W * AncX
            AbsY = ParentY + PosY - H * AncY

            -- Inherit ScreenGui / parent layer so overlays on CoreGui beat ScreenGui content
            if rawget(Child, "_LayerOrder") == nil then
                local parentLayer = rawget(Node, "_LayerOrder")
                if parentLayer ~= nil then
                    rawset(Child, "_LayerOrder", parentLayer)
                end
            end

            local IsHovered = not MouseLocked
                and (MouseX >= AbsX and MouseX <= AbsX + W and MouseY >= AbsY and MouseY <= AbsY + H)

            if IsHovered then
                -- Effective depth: DisplayOrder (ScreenGui layer) + ZIndex
                -- Higher ZIndex always wins over lower, regardless of tree order.
                local z = GetProp(Child, "ZIndex") or 1
                local layer = rawget(Child, "_LayerOrder") or 0
                -- Prefer nodes that actually handle clicks when ZIndex ties
                local interactive = HasClickHandler(Child) and 1 or 0
                HitConsider(Child, layer * 1000000 + z * 1000 + interactive * 0.5)
            end

            local BgColor = GetProp(Child, "BackgroundColor")
            if BgColor then
                local Alpha = BgColor[4]
                if Alpha == nil or Alpha > 0 then
                    Gui:DrawRect({AbsX, AbsY}, {W, H}, BgColor)
                end
            end

            local PadL, PadR, PadT, PadB = GetUiPadding(Child)
            local ContentX = AbsX + PadL
            local ContentY = AbsY + PadT
            local ContentW = math.max(0, W - PadL - PadR)
            local ContentH = math.max(0, H - PadT - PadB)

            local ShouldClip = GetProp(Child, "ClipsDescendants")
                or GetProp(Child, "ClipDescendants")
                or rawget(Child, "ClipsDescendants")
                or rawget(Child, "ClipDescendants")
            local HadClip, ClipX, ClipY, ClipW, ClipH

            if ShouldClip then
                local Sx, Sy, Sw, Sh = love.graphics.getScissor()
                HadClip = Sx ~= nil
                ClipX, ClipY, ClipW, ClipH = Sx, Sy, Sw, Sh

                if HadClip then
                    local X2 = math.min(Sx + Sw, ContentX + ContentW)
                    local Y2 = math.min(Sy + Sh, ContentY + ContentH)
                    local Nx = math.max(Sx, ContentX)
                    local Ny = math.max(Sy, ContentY)
                    love.graphics.setScissor(Nx, Ny, math.max(0, X2 - Nx), math.max(0, Y2 - Ny))
                else
                    love.graphics.setScissor(ContentX, ContentY, ContentW, ContentH)
                end
            end

            if ClassName == "ImageLabel" then
                local Image = GetProp(Child, "Image")
                if Image then
                    local ImageColor = GetProp(Child, "ImageColor") or {1, 1, 1, 1}
                    -- Integer size + center so scaled icons don't smear
                    local iw = math.max(1, math.floor(W + 0.5))
                    local ih = math.max(1, math.floor(H + 0.5))
                    local cx = math.floor(AbsX + W * 0.5 + 0.5)
                    local cy = math.floor(AbsY + H * 0.5 + 0.5)
                    Gui:DrawImage(Image, {cx, cy, 0}, {iw, ih}, ImageColor)
                end
            elseif ClassName == "TextLabel" then
                local Text = GetProp(Child, "Text") or ""
                local TextColor = GetProp(Child, "TextColor") or {0, 0, 0, 1}
                local TextSize = GetProp(Child, "TextSize") or 14
                local FontPath = GetProp(Child, "Font") or CachedFontPath

                if FontPath then
                    Gui:Font(FontPath, TextSize)
                end

                local Alignment = GetProp(Child, "TextAlignment") or {"Left", "Center"}
                local XAlign = Alignment[1] or "Left"
                local YAlign = Alignment[2] or "Center"
                local FontObj = love.graphics.getFont()
                local Th = FontObj:getHeight()
                local DrawX = ContentX
                local DrawY = ContentY

                if YAlign == "Top" then
                    DrawY = ContentY
                elseif YAlign == "Bottom" then
                    DrawY = ContentY + ContentH - Th
                else
                    DrawY = ContentY + (ContentH - Th) * 0.5
                end

                -- Whole-pixel placement prevents blurry sub-pixel glyphs
                DrawX = math.floor(DrawX + 0.5)
                DrawY = math.floor(DrawY + 0.5)
                local TextW = math.max(1, math.floor(ContentW + 0.5))

                local AlignString = string.lower(XAlign)
                if AlignString ~= "center" and AlignString ~= "right" then
                    AlignString = "left"
                end

                love.graphics.setColor(TextColor[1], TextColor[2], TextColor[3], TextColor[4] or 1)
                pcall(love.graphics.printf, SafeText(Text), DrawX, DrawY, TextW, AlignString)
            end

            local Nested = rawget(Child, "Children")
            if Nested and #Nested > 0 then
                Gui:Render(Child, ContentX, ContentY, ContentW, ContentH)
            end

            if ShouldClip then
                if HadClip then
                    love.graphics.setScissor(ClipX, ClipY, ClipW, ClipH)
                else
                    love.graphics.setScissor()
                end
            end
        else
            local Nested = rawget(Child, "Children")
            if Nested and #Nested > 0 then
                Gui:Render(Child, AbsX, AbsY, W, H)
            end
        end

        ::ContinueChild::
    end

    RenderDepth = RenderDepth - 1
end

-- ---------------------------------------------------------------------------
-- Primitive drawing
-- ---------------------------------------------------------------------------

function Gui:DrawText(Text, Position, ColorValue, Align, Background, FontSize)
    local PrevFont = love.graphics.getFont()

    if FontSize and CachedFontPath then
        Gui:Font(CachedFontPath, FontSize)
    end

    local Font = love.graphics.getFont()
    Text = SafeText(Text)

    local Tw = Font:getWidth(Text)
    local Th = Font:getHeight()
    local Padding = Background and Background.Padding or 0
    local Rw = Tw + Padding * 2
    local Rh = Th + Padding * 2

    if Background then
        local Bc = Background.Color
        love.graphics.setColor(Bc[1], Bc[2], Bc[3], Bc[4] or 1)
        love.graphics.rectangle("fill", Position[1], Position[2], Rw, Rh)
    end

    love.graphics.setColor(ColorValue[1], ColorValue[2], ColorValue[3], ColorValue[4] or 1)
    local tx = math.floor((Position[1] or 0) + Padding + 0.5)
    local ty = math.floor((Position[2] or 0) + Padding + 0.5)
    pcall(love.graphics.printf, SafeText(Text), tx, ty, math.max(math.floor(Tw + 0.5), 1), Align or "left")

    if PrevFont then
        love.graphics.setFont(PrevFont)
    end

    return Rw, Rh
end

function Gui:DrawRect(Position, Size, ColorValue, Outline, Draw)
    love.graphics.setColor(ColorValue[1] or 1, ColorValue[2] or 1, ColorValue[3] or 1, ColorValue[4] or 1)
    love.graphics.rectangle(Draw or "fill", Position[1] or 0, Position[2] or 0, Size[1] or 0, Size[2] or 0)

    if Outline then
        local Line = love.graphics.getLineWidth()
        local Tx = Outline.Thickness or 1
        local Ox = (Tx % 2 ~= 0) and 0.5 or 0

        love.graphics.setColor(Outline.Color)
        love.graphics.setLineWidth(Tx)
        love.graphics.rectangle(
            "line",
            (Position[1] or 0) + Ox,
            (Position[2] or 0) + Ox,
            (Size[1] or 0) - (Ox * 2),
            (Size[2] or 0) - (Ox * 2)
        )
        love.graphics.setLineWidth(Line)
    end

    return Size[1] or 0, Size[2] or 0
end

function Gui:DrawArch(Position, Radius, Angle, Segments, ColorValue, Draw)
    love.graphics.setColor(ColorValue[1] or 1, ColorValue[2] or 1, ColorValue[3] or 1, ColorValue[4] or 1)
    love.graphics.arc(Draw or "fill", Position[1] or 0, Position[2] or 0, Radius or 0, Angle[1] or 0, Angle[2] or 0, Segments or 64)
    return Radius or 0, Radius or 0
end

local Assets = {}

function Gui:DrawImage(Path, Position, Size, ColorValue)
    if not Path or Path == "" then
        return 0, 0
    end

    local Image = Assets[Path]
    if not Image then
        if love.filesystem and love.filesystem.getInfo and not love.filesystem.getInfo(Path) then
            return Size[1] or 0, Size[2] or 0
        end

        local Success, Result = pcall(love.graphics.newImage, Path)
        if Success then
            Image = Result
            -- Smooth resampling (not blocky nearest) for UI icons
            pcall(function()
                Image:setFilter("linear", "linear")
            end)
            Assets[Path] = Image
        else
            return Size[1] or 0, Size[2] or 0
        end
    end

    local dstW = Size[1] or 0
    local dstH = Size[2] or 0
    local srcW = Image:getWidth()
    local srcH = Image:getHeight()
    if srcW < 1 or srcH < 1 then
        return dstW, dstH
    end

    local ScaleX = dstW / srcW
    local ScaleY = dstH / srcH

    -- Snap to whole pixels so scaled icons stay sharp
    local px = math.floor((Position[1] or 0) + 0.5)
    local py = math.floor((Position[2] or 0) + 0.5)

    love.graphics.setColor(ColorValue[1] or 1, ColorValue[2] or 1, ColorValue[3] or 1, ColorValue[4] or 1)
    love.graphics.draw(
        Image,
        px,
        py,
        Position[3] or 0,
        ScaleX,
        ScaleY,
        srcW * 0.5,
        srcH * 0.5
    )

    return dstW, dstH
end

function Gui:DrawLine(Position1, Position2, Thickness, ColorValue)
    love.graphics.setColor(ColorValue[1] or 1, ColorValue[2] or 1, ColorValue[3] or 1, ColorValue[4] or 1)
    love.graphics.setLineWidth(Thickness or 1)
    love.graphics.line(Position1[1] or 0, Position1[2] or 0, Position2[1] or 0, Position2[2] or 0)
    return math.abs(Position2[1] - Position1[1]), math.abs(Position2[2] - Position1[2])
end

function Gui:Font(Path, Size)
    Size = Size or 16
    -- Rasterize at integer pixel size for crisp glyphs
    Size = math.max(1, math.floor(Size + 0.5))
    CachedFontPath = Path

    local Key = Path .. "\0" .. tostring(Size)
    local Font = FontCache[Key]

    if not Font then
        Font = love.graphics.newFont(Path, Size)
        -- Linear filter keeps small anti-aliased text smooth instead of chunky
        pcall(function()
            Font:setFilter("linear", "linear")
        end)
        FontCache[Key] = Font
    end

    love.graphics.setFont(Font)
end

function Gui:Flex(Position, Config, Elements)
    local Gap = Config.Gap or 0
    local Padding = Config.Padding or 0
    local Direction = Config.Direction or "row"
    local CurrentX = Position[1] + Padding
    local CurrentY = Position[2] + Padding

    for Index = 1, #Elements do
        local Width, Height = Elements[Index]({CurrentX, CurrentY})
        if Direction == "row" then
            CurrentX = CurrentX + Width + Gap
        else
            CurrentY = CurrentY + Height + Gap
        end
    end
end

function Gui.Console:Print(...)
    local Args = {...}
    local Options = {}
    local TextParts = {}

    for _, Arg in ipairs(Args) do
        if type(Arg) == "table" and Arg.Color then
            Options = Arg
        else
            TextParts[#TextParts + 1] = tostring(Arg)
        end
    end

    Gui.Console.Output[#Gui.Console.Output + 1] = {
        Text = table.concat(TextParts, " "),
        Time = os.time(),
        Color = Options.Color or {1, 0, 1, 1}
    }

    local MaxLines = Gui.Console.MaxLines or 32
    while #Gui.Console.Output > MaxLines do
        table.remove(Gui.Console.Output, 1)
    end
end

function Gui.Console:Draw()
    local Offset = Gui.Console.Offset or {0, 0}
    local LineHeight = love.graphics.getFont():getHeight()
    local CurrentY = Offset[2]

    for Index = 1, #Gui.Console.Output do
        local Line = Gui.Console.Output[Index]
        Gui:DrawText(Line.Text, {Offset[1], CurrentY}, Line.Color, "left", nil, 14)
        CurrentY = CurrentY + LineHeight
    end
end

return Gui
