local Color = require("Services.Color")
local UDim = require("Services.UDim")
local Instance = require("Services.Instance")
local Tools = require("Services.Tools")

local Ribbon = {}

Ribbon.ActiveTab = "Home"
Ribbon.TabHeight = 28
Ribbon.ToolbarHeight = 56
Ribbon.TotalHeight = 28 + 56

local TabOrder = { "Home", "Model", "Testing", "View" }

local TabMeta = {
    Home = {
        Label = "Home",
        ShowTools = true,
        Groups = {
            { Name = "Clipboard", Actions = { "Copy", "Paste", "Duplicate" } },
            { Name = "Tools", Actions = { "Select", "Move", "Scale", "Rotate" } },
            { Name = "Insert", Actions = { "Part" } },
        },
    },
    Model = {
        Label = "Model",
        ShowTools = true,
        Groups = {
            { Name = "Tools", Actions = { "Select", "Move", "Scale", "Rotate" } },
            { Name = "Pivot", Actions = { "Pivot" } },
            { Name = "Solid Modeling", Actions = { "Union", "Separate" } },
        },
    },
    Testing = {
        Label = "Testing",
        ShowTools = false,
        Groups = {
            { Name = "Clients", Actions = { "Client", "Server" } },
        },
    },
    View = {
        Label = "View",
        ShowTools = false,
        Groups = {
            { Name = "Windows", Actions = { "Explorer", "Properties", "Output" } },
            { Name = "Display", Actions = { "Grid", "Wireframe" } },
        },
    },
}

local MezzanineActions = { "Play", "PlayHere", "Run", "Pause", "Stop" }
local MezzanineLabels = {
    Play = "Play",
    PlayHere = "Play Here",
    Run = "Run",
    Pause = "Pause",
    Stop = "Stop",
}

local Frame
local TabStrip
local TabButtons = {}
local ToolStrip
local ContentHost
local MezzanineStrip
local ActionButtons = {}
local MezzanineButtons = {}
local OnAction = nil
local UnderlineBar

local SlideX = 0
local SlideTarget = 0
local ContentAlpha = 1
local UnderlineX = 2
local UnderlineTargetX = 2
local TabAnimColors = {}

local function C(R, G, B, A)
    return Color.FromRGBA(R, G, B, A)
end

local function ColIdle()
    return C(50, 50, 54)
end
local function ColHover()
    return C(65, 65, 72)
end
local function ColActive()
    return C(53, 83, 143)
end
local function ColMezzIdle()
    return C(40, 40, 46)
end
local function ColMezzHover()
    return C(58, 70, 95)
end
local function ColTabIdle()
    return C(35, 35, 38)
end
local function ColTabActive()
    return C(45, 55, 75)
end
local function ColTabHover()
    return C(48, 52, 62)
end

local ActionImages = {
    Select = "Assets/Decals/Select.png",
    Move = "Assets/Decals/Move.png",
    Scale = "Assets/Decals/Scale.png",
    Rotate = "Assets/Decals/Rotate.png",
}

local function TabIndex(Name)
    for I, N in ipairs(TabOrder) do
        if N == Name then
            return I
        end
    end
    return 1
end

local function Lerp(A, B, T)
    return A + (B - A) * T
end

local function ExpAlpha(Speed, Dt)
    return 1 - math.exp(-Speed * math.min(Dt or 0.016, 0.05))
end

function Ribbon:SetActionImage(Action, Path)
    if Action and Path then
        ActionImages[Action] = Path
        if Tools and Tools.SetImage and (Action == "Select" or Action == "Move" or Action == "Scale" or Action == "Rotate") then
            Tools:SetImage(Action, Path)
        end
        if self.ActiveTab then
            self:RebuildToolbar(true)
        end
    end
end

function Ribbon:GetActionImage(Action)
    if ActionImages[Action] then
        return ActionImages[Action]
    end
    if Tools and Tools.GetImage then
        local P = Tools:GetImage(Action)
        if P then
            return P
        end
    end
    return nil
end

local function IsToolAction(Action)
    return Action == "Select" or Action == "Move" or Action == "Scale" or Action == "Rotate"
end

local function CurrentTool()
    if Tools and Tools.GetTool then
        return Tools:GetTool()
    end
    return nil
end

local function UpdateUnderlineTarget()
    local Btn = TabButtons[Ribbon.ActiveTab]
    if Btn and Btn.Position and Btn.Position.X then
        UnderlineTargetX = (Btn.Position.X.Offset or 0)
    else
        local Idx = TabIndex(Ribbon.ActiveTab)
        UnderlineTargetX = 2 + (Idx - 1) * 76
    end
end

local function SetTabVisuals()
    for Name, Btn in pairs(TabButtons) do
        local Active = (Name == Ribbon.ActiveTab)
        TabAnimColors[Name] = TabAnimColors[Name] or (Active and ColTabActive() or ColTabIdle())
        if Btn.Underline then
            Btn.Underline.Visible = false
        end
    end
    UpdateUnderlineTarget()
end

function Ribbon:GetActiveTab()
    return self.ActiveTab
end

function Ribbon:Is(Name)
    return self.ActiveTab == Name
end

function Ribbon:ShowsTools()
    local Meta = TabMeta[self.ActiveTab]
    return Meta and Meta.ShowTools
end

function Ribbon:SetTab(Name)
    if not TabMeta[Name] then
        return
    end
    if Name == self.ActiveTab then
        return
    end
    local From = TabIndex(self.ActiveTab)
    local To = TabIndex(Name)
    local Dir = (To >= From) and 1 or -1
    self.ActiveTab = Name
    SlideX = Dir * 72
    SlideTarget = 0
    ContentAlpha = 1
    SetTabVisuals()
    self:RebuildToolbar(true)
end

function Ribbon:OnAction(Cb)
    OnAction = Cb
end

local function FireAction(Action)
    if OnAction then
        pcall(OnAction, Action, Ribbon.ActiveTab)
    end
    if IsToolAction(Action) then
        if Tools and Tools.SetTool then
            Tools:SetTool(Action)
        end
        for An, Ab in pairs(ActionButtons) do
            if IsToolAction(An) then
                local Sel = (An == Action)
                rawset(Ab, "_Selected", Sel)
                Ab.BackgroundColor = Sel and ColActive() or ColIdle()
            end
        end
    end
    if Action == "Play" or Action == "PlayHere" or Action == "Run" or Action == "Pause" or Action == "Stop" then
        if Ribbon.RefreshMezzanine then
            Ribbon:RefreshMezzanine()
        end
    end
end

function Ribbon:FireAction(Action)
    FireAction(Action)
end

local function PulseButton(Btn)
    if not Btn then
        return
    end
    rawset(Btn, "_Pulse", 1)
end

function Ribbon:RefreshMezzanine()
    local PauseBtn = MezzanineButtons["Pause"]
    if not PauseBtn then
        return
    end
    local Lab = nil
    local Kids = rawget(PauseBtn, "Children")
    if Kids then
        for I = 1, #Kids do
            if Kids[I].Name == "Label" then
                Lab = Kids[I]
                break
            end
        end
    end
    local Runtime = package.loaded["Services.Runtime"] or rawget(_G, "Runtime")
    local Paused = Runtime and Runtime.IsPaused and Runtime:IsPaused()
    local InSession = Runtime and not Runtime:IsEdit()
    if Lab then
        if InSession and Paused then
            Lab.Text = "Resume"
        else
            Lab.Text = "Pause"
        end
    end
end

local function BuildMezzanine()
    if not MezzanineStrip then
        return
    end
    local Kids = rawget(MezzanineStrip, "Children")
    if Kids then
        for I = #Kids, 1, -1 do
            if Kids[I] and Kids[I].Destroy then
                Kids[I]:Destroy()
            end
        end
    end
    MezzanineButtons = {}

    local Bx = 0
    for _, Action in ipairs(MezzanineActions) do
        local Btn = Instance.new("Frame", MezzanineStrip)
        Btn.Name = "Mezz_" .. Action
        Btn.Position = UDim.New(0, Bx, 0, 2)
        Btn.Size = UDim.New(0, 72, 0, Ribbon.TabHeight - 4)
        Btn.BackgroundColor = ColMezzIdle()
        Btn.ZIndex = 5
        Btn.MouseCursor = "hand"
        rawset(Btn, "_BaseX", Bx)
        rawset(Btn, "_BaseY", 2)
        rawset(Btn, "_Pulse", 0)

        local Lab = Instance.new("TextLabel", Btn)
        Lab.Name = "Label"
        Lab.Text = MezzanineLabels[Action] or Action
        Lab.TextSize = 11
        Lab.TextColor = Color.FromRGBA(200, 210, 230)
        Lab.BackgroundColor = Color.FromRGBA(0, 0, 0, 0)
        Lab.Position = UDim.FromScale(0, 0)
        Lab.Size = UDim.FromScale(1, 1)
        Lab.TextAlignment = { "Center", "Center" }
        Lab.ZIndex = 6

        local Act = Action
        Btn.OnClick:Connect(function()
            PulseButton(Btn)
            FireAction(Act)
            Ribbon:RefreshMezzanine()
        end)
        Btn.OnEnter:Connect(function()
            rawset(Btn, "_IsHovered", true)
            if (rawget(Btn, "_Pulse") or 0) <= 0 then
                Btn.BackgroundColor = ColMezzHover()
            end
        end)
        Btn.OnLeave:Connect(function()
            rawset(Btn, "_IsHovered", false)
            if (rawget(Btn, "_Pulse") or 0) <= 0 then
                Btn.BackgroundColor = ColMezzIdle()
            end
        end)

        MezzanineButtons[Action] = Btn
        Bx = Bx + 76
    end

    local TotalW = Bx
    MezzanineStrip.Size = UDim.New(0, TotalW, 1, 0)
    MezzanineStrip.Position = UDim.New(1, -TotalW, 0, 0)
    Ribbon:RefreshMezzanine()
end

function Ribbon:RebuildToolbar(Animated)
    if not ContentHost then
        return
    end
    local Kids = rawget(ContentHost, "Children")
    if Kids then
        for I = #Kids, 1, -1 do
            if Kids[I] and Kids[I].Destroy then
                Kids[I]:Destroy()
            end
        end
    end
    ActionButtons = {}

    local Meta = TabMeta[self.ActiveTab]
    if not Meta then
        return
    end

    local X = 8
    local Stagger = 0
    for Gi, Group in ipairs(Meta.Groups or {}) do
        local Gl = Instance.new("TextLabel", ContentHost)
        Gl.Name = "Group_" .. Group.Name
        Gl.Text = Group.Name
        Gl.TextSize = 11
        Gl.TextColor = Color.FromRGBA(160, 160, 170)
        Gl.BackgroundColor = Color.FromRGBA(0, 0, 0, 0)
        Gl.Position = UDim.New(0, X, 0, 0)
        Gl.Size = UDim.New(0, 200, 0, 13)
        Gl.TextAlignment = { "Left", "Center" }
        rawset(Gl, "_BaseX", X)
        rawset(Gl, "_BaseY", 0)
        rawset(Gl, "_Stagger", Stagger)
        Stagger = Stagger + 1

        local Bx = X
        for _, Action in ipairs(Group.Actions or {}) do
            local ToolBtn = IsToolAction(Action)
            local IconPath = Ribbon:GetActionImage(Action)
            local BtnW = ToolBtn and 48 or 64
            local BtnH = 38
            local Selected = ToolBtn and CurrentTool() == Action

            local Btn = Instance.new("Frame", ContentHost)
            Btn.Name = "Action_" .. Action
            Btn.Position = UDim.New(0, Bx, 0, 14)
            Btn.Size = UDim.FromOffset(BtnW, BtnH)
            Btn.BackgroundColor = Selected and ColActive() or ColIdle()
            Btn.ZIndex = 2
            Btn.MouseCursor = "hand"
            rawset(Btn, "_BaseX", Bx)
            rawset(Btn, "_BaseY", 14)
            rawset(Btn, "_Stagger", Stagger)
            rawset(Btn, "_Pulse", 0)
            rawset(Btn, "_BtnW", BtnW)
            rawset(Btn, "_BtnH", BtnH)
            rawset(Btn, "_IsTool", ToolBtn and true or false)
            rawset(Btn, "_Action", Action)
            rawset(Btn, "_Selected", Selected and true or false)
            Stagger = Stagger + 1

            if IconPath then
                local Icon = Instance.new("ImageLabel", Btn)
                Icon.Name = "Icon"
                Icon.Image = IconPath
                Icon.Anchor = {0.5, 0}
                Icon.Position = UDim.New(0.5, 0, 0, 2)
                Icon.Size = UDim.FromOffset(22, 22)
                Icon.BackgroundColor = Color.FromRGBA(0, 0, 0, 0)
                Icon.ZIndex = 3

                local Label = Instance.new("TextLabel", Btn)
                Label.Name = "Label"
                Label.Text = Action
                Label.TextSize = 10
                Label.TextColor = Color.FromRGBA(200, 200, 210)
                Label.BackgroundColor = Color.FromRGBA(0, 0, 0, 0)
                Label.Position = UDim.New(0, 0, 1, -14)
                Label.Size = UDim.New(1, 0, 0, 12)
                Label.TextAlignment = { "Center", "Center" }
                Label.ZIndex = 3
            else
                local Label = Instance.new("TextLabel", Btn)
                Label.Name = "Label"
                Label.Text = Action
                Label.TextSize = 11
                Label.TextColor = Color.FromRGBA(220, 220, 225)
                Label.BackgroundColor = Color.FromRGBA(0, 0, 0, 0)
                Label.Position = UDim.FromScale(0, 0)
                Label.Size = UDim.FromScale(1, 1)
                Label.TextAlignment = { "Center", "Center" }
                Label.ZIndex = 3
            end

            local Act = Action
            Btn.OnClick:Connect(function()
                PulseButton(Btn)
                FireAction(Act)
                if ToolBtn then
                    for An, Ab in pairs(ActionButtons) do
                        local Sel = IsToolAction(An) and (CurrentTool() == An)
                        rawset(Ab, "_Selected", Sel)
                        Ab.BackgroundColor = Sel and ColActive() or ColIdle()
                    end
                end
            end)
            Btn.OnEnter:Connect(function()
                rawset(Btn, "_IsHovered", true)
            end)
            Btn.OnLeave:Connect(function()
                rawset(Btn, "_IsHovered", false)
            end)

            ActionButtons[Action] = Btn
            Bx = Bx + (ToolBtn and 52 or 68)
        end

        X = Bx + 8
        if Gi ~= #Meta.Groups then
            local Sep = Instance.new("Frame", ContentHost)
            Sep.Name = "Sep"
            Sep.BackgroundColor = Color.FromRGBA(70, 70, 75)
            Sep.Position = UDim.New(0, X - 6, 0, 18)
            Sep.Size = UDim.New(0, 1, 0, 28)
            rawset(Sep, "_BaseX", X - 6)
            rawset(Sep, "_BaseY", 18)
            rawset(Sep, "_Stagger", Stagger)
            Stagger = Stagger + 1
        end
    end

    if not Animated then
        SlideX = 0
        ContentAlpha = 1
    end
    self:ApplySlide()
end

function Ribbon:ApplySlide()
    if not ContentHost then
        return
    end
    local Kids = rawget(ContentHost, "Children")
    if not Kids then
        return
    end
    for I = 1, #Kids do
        local Child = Kids[I]
        local Bx = rawget(Child, "_BaseX")
        local By = rawget(Child, "_BaseY")
        if Bx ~= nil and By ~= nil then
            local St = rawget(Child, "_Stagger") or 0
            local Extra = SlideX * (1 + St * 0.035)
            local Bw = rawget(Child, "_BtnW")
            local Bh = rawget(Child, "_BtnH")
            local Pulse = rawget(Child, "_Pulse") or 0
            if Bw and Bh then
                if Pulse > 0 then
                    local S = 1 - Pulse * 0.06
                    local Nw = math.floor(Bw * S + 0.5)
                    local Nh = math.floor(Bh * S + 0.5)
                    Child.Size = UDim.FromOffset(Nw, Nh)
                    Child.Position = UDim.New(0, math.floor(Bx + Extra + (Bw - Nw) * 0.5 + 0.5), 0, math.floor(By + (Bh - Nh) * 0.5 + 0.5))
                else
                    Child.Size = UDim.FromOffset(Bw, Bh)
                    Child.Position = UDim.New(0, math.floor(Bx + Extra + 0.5), 0, By)
                end
            else
                Child.Position = UDim.New(0, math.floor(Bx + Extra + 0.5), 0, By)
            end
        end
    end
end

function Ribbon:SyncToolColors()
    local CurTool = CurrentTool()
    for An, Ab in pairs(ActionButtons) do
        if rawget(Ab, "_IsTool") then
            local Sel = (CurTool == An)
            rawset(Ab, "_Selected", Sel)
            if Sel then
                Ab.BackgroundColor = ColActive()
            elseif rawget(Ab, "_IsHovered") then
                Ab.BackgroundColor = ColHover()
            else
                Ab.BackgroundColor = ColIdle()
            end
        end
    end
end

function Ribbon:Tick(Dt)
    Dt = math.min(Dt or 0.016, 0.05)
    local T = ExpAlpha(18, Dt)
    SlideX = Lerp(SlideX, SlideTarget, T)
    if math.abs(SlideX - SlideTarget) < 0.2 then
        SlideX = SlideTarget
    end
    ContentAlpha = 1

    UnderlineX = Lerp(UnderlineX, UnderlineTargetX, ExpAlpha(18, Dt))
    if UnderlineBar then
        UnderlineBar.Position = UDim.New(0, math.floor(UnderlineX + 0.5), 1, -2)
    end

    for Name, Btn in pairs(TabButtons) do
        local Target = (Name == self.ActiveTab) and ColTabActive() or ColTabIdle()
        local Cur = TabAnimColors[Name] or Target
        local A = ExpAlpha(14, Dt)
        local Next = {
            Lerp(Cur[1] or 0, Target[1] or 0, A),
            Lerp(Cur[2] or 0, Target[2] or 0, A),
            Lerp(Cur[3] or 0, Target[3] or 0, A),
            Lerp(Cur[4] or 1, Target[4] or 1, A),
        }
        TabAnimColors[Name] = Next
        if rawget(Btn, "_IsHovered") and Name ~= self.ActiveTab then
            Btn.BackgroundColor = ColTabHover()
        else
            Btn.BackgroundColor = Next
        end
    end

    local function DecayPulse(Map)
        for _, Btn in pairs(Map) do
            local P = rawget(Btn, "_Pulse") or 0
            if P > 0 then
                P = P - Dt * 8
                if P < 0 then
                    P = 0
                end
                rawset(Btn, "_Pulse", P)
            end
        end
    end
    DecayPulse(ActionButtons)
    DecayPulse(MezzanineButtons)

    self:SyncToolColors()

    for _, Btn in pairs(MezzanineButtons) do
        local P = rawget(Btn, "_Pulse") or 0
        local Bx = rawget(Btn, "_BaseX") or 0
        local By = rawget(Btn, "_BaseY") or 2
        if P > 0 then
            local S = 1 - P * 0.08
            local Nw = math.floor(72 * S + 0.5)
            local Nh = math.floor((Ribbon.TabHeight - 4) * S + 0.5)
            Btn.Size = UDim.FromOffset(Nw, Nh)
            Btn.Position = UDim.New(0, math.floor(Bx + (72 - Nw) * 0.5 + 0.5), 0, math.floor(By + ((Ribbon.TabHeight - 4) - Nh) * 0.5 + 0.5))
            Btn.BackgroundColor = ColMezzHover()
        else
            Btn.Size = UDim.New(0, 72, 0, Ribbon.TabHeight - 4)
            Btn.Position = UDim.New(0, Bx, 0, By)
            if rawget(Btn, "_IsHovered") then
                Btn.BackgroundColor = ColMezzHover()
            else
                Btn.BackgroundColor = ColMezzIdle()
            end
        end
    end

    self:ApplySlide()
end

function Ribbon:Init(ParentFrame)
    Frame = ParentFrame
    Frame.BackgroundColor = Color.FromRGBA(32, 32, 35)

    TabStrip = Instance.new("Frame", Frame)
    TabStrip.Name = "TabStrip"
    TabStrip.BackgroundColor = Color.FromRGBA(28, 28, 30)
    TabStrip.Position = UDim.New(0, 0, 0, 0)
    TabStrip.Size = UDim.New(1, 0, 0, self.TabHeight)
    TabStrip.ZIndex = 2

    local Tx = 2
    for _, Name in ipairs(TabOrder) do
        local Btn = Instance.new("Frame", TabStrip)
        Btn.Name = "Tab_" .. Name
        Btn.Position = UDim.New(0, Tx, 0, 2)
        Btn.Size = UDim.New(0, 72, 0, self.TabHeight - 4)
        Btn.BackgroundColor = ColTabIdle()
        Btn.ZIndex = 3
        Btn.MouseCursor = "hand"
        TabAnimColors[Name] = ColTabIdle()

        local Lab = Instance.new("TextLabel", Btn)
        Lab.Text = Name
        Lab.TextSize = 12
        Lab.TextColor = Color.FromRGBA(210, 210, 220)
        Lab.BackgroundColor = Color.FromRGBA(0, 0, 0, 0)
        Lab.Position = UDim.FromScale(0, 0)
        Lab.Size = UDim.FromScale(1, 1)
        Lab.TextAlignment = { "Center", "Center" }
        Lab.ZIndex = 4

        local Under = Instance.new("Frame", Btn)
        Under.Name = "Underline"
        Under.BackgroundColor = Color.FromRGBA(80, 140, 255)
        Under.Position = UDim.New(0, 0, 1, -2)
        Under.Size = UDim.New(1, 0, 0, 2)
        Under.Visible = false
        Under.ZIndex = 5
        Btn.Underline = Under

        local TabName = Name
        Btn.OnClick:Connect(function()
            Ribbon:SetTab(TabName)
        end)
        Btn.OnEnter:Connect(function()
            rawset(Btn, "_IsHovered", true)
            if Ribbon.ActiveTab == TabName then
                Btn.BackgroundColor = ColTabActive()
            else
                Btn.BackgroundColor = ColTabHover()
            end
        end)
        Btn.OnLeave:Connect(function()
            rawset(Btn, "_IsHovered", false)
            if Ribbon.ActiveTab == TabName then
                Btn.BackgroundColor = ColTabActive()
                TabAnimColors[TabName] = ColTabActive()
            else
                Btn.BackgroundColor = ColTabIdle()
                TabAnimColors[TabName] = ColTabIdle()
            end
        end)

        TabButtons[Name] = Btn
        Tx = Tx + 76
    end

    UnderlineBar = Instance.new("Frame", TabStrip)
    UnderlineBar.Name = "ActiveUnderline"
    UnderlineBar.BackgroundColor = Color.FromRGBA(80, 140, 255)
    UnderlineBar.Position = UDim.New(0, 2, 1, -2)
    UnderlineBar.Size = UDim.New(0, 72, 0, 2)
    UnderlineBar.ZIndex = 6

    local MezzW = 76 * #MezzanineActions
    MezzanineStrip = Instance.new("Frame", TabStrip)
    MezzanineStrip.Name = "Mezzanine"
    MezzanineStrip.BackgroundColor = Color.FromRGBA(0, 0, 0, 0)
    MezzanineStrip.Position = UDim.New(1, -MezzW, 0, 0)
    MezzanineStrip.Size = UDim.New(0, MezzW, 1, 0)
    MezzanineStrip.ZIndex = 4
    BuildMezzanine()

    ToolStrip = Instance.new("Frame", Frame)
    ToolStrip.Name = "ToolStrip"
    ToolStrip.BackgroundColor = Color.FromRGBA(40, 40, 44)
    ToolStrip.Position = UDim.New(0, 0, 0, self.TabHeight)
    ToolStrip.Size = UDim.New(1, 0, 0, self.ToolbarHeight)
    ToolStrip.ClipsDescendants = true
    ToolStrip.ZIndex = 2

    ContentHost = Instance.new("Frame", ToolStrip)
    ContentHost.Name = "ContentHost"
    ContentHost.BackgroundColor = Color.FromRGBA(0, 0, 0, 0)
    ContentHost.Position = UDim.New(0, 0, 0, 0)
    ContentHost.Size = UDim.New(1, 0, 1, 0)
    ContentHost.ClipsDescendants = true
    ContentHost.ZIndex = 2

    SetTabVisuals()
    UnderlineX = UnderlineTargetX
    self:RebuildToolbar(false)
end

function Ribbon:HandleClick(Mx, My)
    return false
end

function Ribbon:GetHeight()
    return self.TotalHeight
end

return Ribbon