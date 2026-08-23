local Color = require("Services.Color")

local Theme = {}

local function Rgba(R, G, B, A)
    return Color.FromRGBA(R, G, B, A or 255)
end

local Schemes = {
    StudioDark = {
        Name = "StudioDark",
        MainBackground = Rgba(37, 37, 37),
        Titlebar = Rgba(46, 46, 46),
        Dropdown = Rgba(46, 46, 46),
        Tooltip = Rgba(53, 53, 53),
        ScrollBar = Rgba(80, 80, 80),
        ScrollBarBackground = Rgba(30, 30, 30),
        TabBar = Rgba(37, 37, 37),
        Tab = Rgba(46, 46, 46),
        ViewPortBackground = Rgba(25, 26, 31),
        InputFieldBackground = Rgba(30, 30, 30),
        Border = Rgba(34, 34, 34),
        BorderHover = Rgba(60, 60, 60),
        Shadow = Rgba(0, 0, 0, 180),
        Button = Rgba(45, 45, 45),
        ButtonHover = Rgba(60, 60, 60),
        ButtonPressed = Rgba(38, 38, 38),
        MainButton = Rgba(0, 162, 255),
        MainButtonHover = Rgba(30, 175, 255),
        RibbonTab = Rgba(37, 37, 37),
        RibbonButton = Rgba(45, 45, 45),
        RibbonButtonHover = Rgba(60, 60, 60),
        RibbonButtonSelected = Rgba(11, 90, 175),
        Item = Rgba(37, 37, 37),
        ItemHover = Rgba(55, 55, 55),
        ItemSelected = Rgba(11, 90, 175),
        ItemSelectedText = Rgba(255, 255, 255),
        CategoryHeader = Rgba(46, 46, 46),
        RowEven = Rgba(37, 37, 37),
        RowOdd = Rgba(34, 34, 34),
        Splitter = Rgba(28, 28, 28),
        SplitterHover = Rgba(0, 162, 255),
        MainText = Rgba(204, 204, 204),
        SubText = Rgba(140, 140, 140),
        TitlebarText = Rgba(220, 220, 220),
        BrightText = Rgba(255, 255, 255),
        DimmedText = Rgba(102, 102, 102),
        LinkText = Rgba(53, 148, 255),
        WarningText = Rgba(255, 170, 0),
        ErrorText = Rgba(255, 80, 80),
        InfoText = Rgba(100, 180, 255),
        ValueText = Rgba(220, 220, 220),
        NumberText = Rgba(170, 210, 255),
        ObjectText = Rgba(100, 180, 255),
        FocusRing = Rgba(0, 162, 255),
        FocusRingError = Rgba(220, 60, 60),
        Checked = Rgba(0, 162, 255),
        ScriptBackground = Rgba(37, 37, 37),
        ScriptText = Rgba(204, 204, 204),
        ScriptSelectionBackground = Rgba(11, 90, 175),
        ColorPickerFrame = Rgba(46, 46, 46),
        ModalOverlay = Rgba(40, 40, 46),
        Danger = Rgba(180, 50, 50),
        DangerHover = Rgba(200, 70, 70),
    },
    StudioLight = {
        Name = "StudioLight",
        MainBackground = Rgba(240, 240, 240),
        Titlebar = Rgba(227, 227, 227),
        Dropdown = Rgba(255, 255, 255),
        Tooltip = Rgba(255, 255, 225),
        ScrollBar = Rgba(180, 180, 180),
        ScrollBarBackground = Rgba(230, 230, 230),
        TabBar = Rgba(240, 240, 240),
        Tab = Rgba(227, 227, 227),
        ViewPortBackground = Rgba(200, 200, 200),
        InputFieldBackground = Rgba(255, 255, 255),
        Border = Rgba(180, 180, 180),
        BorderHover = Rgba(140, 140, 140),
        Shadow = Rgba(0, 0, 0, 80),
        Button = Rgba(230, 230, 230),
        ButtonHover = Rgba(210, 210, 210),
        ButtonPressed = Rgba(200, 200, 200),
        MainButton = Rgba(0, 162, 255),
        MainButtonHover = Rgba(30, 175, 255),
        RibbonTab = Rgba(240, 240, 240),
        RibbonButton = Rgba(230, 230, 230),
        RibbonButtonHover = Rgba(210, 210, 210),
        RibbonButtonSelected = Rgba(180, 210, 255),
        Item = Rgba(255, 255, 255),
        ItemHover = Rgba(230, 240, 255),
        ItemSelected = Rgba(180, 210, 255),
        ItemSelectedText = Rgba(0, 0, 0),
        CategoryHeader = Rgba(227, 227, 227),
        RowEven = Rgba(255, 255, 255),
        RowOdd = Rgba(245, 245, 245),
        Splitter = Rgba(200, 200, 200),
        SplitterHover = Rgba(0, 162, 255),
        MainText = Rgba(0, 0, 0),
        SubText = Rgba(80, 80, 80),
        TitlebarText = Rgba(0, 0, 0),
        BrightText = Rgba(0, 0, 0),
        DimmedText = Rgba(140, 140, 140),
        LinkText = Rgba(0, 100, 200),
        WarningText = Rgba(180, 100, 0),
        ErrorText = Rgba(180, 0, 0),
        InfoText = Rgba(0, 80, 160),
        ValueText = Rgba(0, 0, 0),
        NumberText = Rgba(0, 80, 160),
        ObjectText = Rgba(0, 100, 200),
        FocusRing = Rgba(0, 162, 255),
        FocusRingError = Rgba(200, 40, 40),
        Checked = Rgba(0, 162, 255),
        ScriptBackground = Rgba(255, 255, 255),
        ScriptText = Rgba(0, 0, 0),
        ScriptSelectionBackground = Rgba(180, 210, 255),
        ColorPickerFrame = Rgba(240, 240, 240),
        ModalOverlay = Rgba(245, 245, 245),
        Danger = Rgba(200, 60, 60),
        DangerHover = Rgba(220, 80, 80),
    },
}

local CurrentName = "StudioDark"
local Current = Schemes.StudioDark
local Listeners = {}

function Theme.GetSchemes()
    local Names = {}
    for Name in pairs(Schemes) do
        Names[#Names + 1] = Name
    end
    table.sort(Names)
    return Names
end

function Theme.GetName()
    return CurrentName
end

function Theme.Get(Key)
    local C = Current[Key]
    if C then
        return { C[1], C[2], C[3], C[4] or 1 }
    end
    return { 1, 1, 1, 1 }
end

function Theme.Color(Key)
    return Theme.Get(Key)
end

function Theme.Set(Name)
    if not Schemes[Name] then
        return false
    end
    CurrentName = Name
    Current = Schemes[Name]
    for I = 1, #Listeners do
        pcall(Listeners[I], CurrentName, Current)
    end
    return true
end

function Theme.OnChanged(Fn)
    Listeners[#Listeners + 1] = Fn
    return function()
        for I = #Listeners, 1, -1 do
            if Listeners[I] == Fn then
                table.remove(Listeners, I)
                break
            end
        end
    end
end

function Theme.Register(Name, Palette)
    if type(Name) ~= "string" or type(Palette) ~= "table" then
        return false
    end
    local Copy = {}
    for K, V in pairs(Schemes.StudioDark) do
        Copy[K] = Palette[K] or V
    end
    Copy.Name = Name
    Schemes[Name] = Copy
    return true
end

Theme.Set("StudioDark")

_G.Theme = Theme
return Theme