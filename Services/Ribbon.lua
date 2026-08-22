local Color = require("Services.Color")
local UDim = require("Services.UDim")
local Instance = require("Services.Instance")
local Tools = require("Services.Tools")

local Ribbon = {}

Ribbon.ActiveTab = "Home"
Ribbon.TabHeight = 28
Ribbon.ToolbarHeight = 56
Ribbon.TotalHeight = 28 + 56 -- tab strip + tool strip

local TabOrder = { "Home", "Model", "Testing", "View" }

local TabMeta = {
    Home = {
        label = "Home",
        showTools = true,
        groups = {
            { name = "Clipboard", actions = { "Copy", "Paste", "Duplicate" } },
            { name = "Tools", actions = { "Select", "Move", "Scale", "Rotate" } },
            { name = "Insert", actions = { "Part" } },
        },
    },
    Model = {
        label = "Model",
        showTools = true,
        groups = {
            { name = "Tools", actions = { "Select", "Move", "Scale", "Rotate" } },
            { name = "Pivot", actions = { "Pivot" } },
            { name = "Solid Modeling", actions = { "Union", "Separate" } },
        },
    },
    Testing = {
        label = "Testing",
        showTools = false,
        groups = {
            { name = "Simulation", actions = { "Play", "Run", "Stop" } },
            { name = "Clients", actions = { "Client", "Server" } },
        },
    },
    View = {
        label = "View",
        showTools = false,
        groups = {
            { name = "Windows", actions = { "Explorer", "Properties", "Output" } },
            { name = "Display", actions = { "Grid", "Wireframe" } },
        },
    },
}

local Frame
local TabButtons = {}
local ToolStrip
local ActionButtons = {}
local OnAction = nil

-- Optional custom icons for any action (tools fall back to Tools.Images)
local ActionImages = {
    Select = "Assets/Decals/Select.png",
    Move = "Assets/Decals/Move.png",
    Scale = "Assets/Decals/Scale.png",
    Rotate = "Assets/Decals/Rotate.png",
}

function Ribbon:SetActionImage(action, path)
    if action and path then
        ActionImages[action] = path
        if Tools and Tools.SetImage and (action == "Select" or action == "Move" or action == "Scale" or action == "Rotate") then
            Tools:SetImage(action, path)
        end
        if self.ActiveTab then
            self:RebuildToolbar()
        end
    end
end

function Ribbon:GetActionImage(action)
    if ActionImages[action] then return ActionImages[action] end
    if Tools and Tools.GetImage then return Tools:GetImage(action) end
    return nil
end

local function SetTabVisuals()
    for name, btn in pairs(TabButtons) do
        if name == Ribbon.ActiveTab then
            btn.BackgroundColor = Color.FromRGBA(45, 55, 75)
            if btn.Underline then
                btn.Underline.Visible = true
            end
        else
            btn.BackgroundColor = Color.FromRGBA(35, 35, 38)
            if btn.Underline then
                btn.Underline.Visible = false
            end
        end
    end
end

function Ribbon:GetActiveTab()
    return self.ActiveTab
end

function Ribbon:Is(name)
    return self.ActiveTab == name
end

function Ribbon:ShowsTools()
    local meta = TabMeta[self.ActiveTab]
    return meta and meta.showTools
end

function Ribbon:SetTab(name)
    if not TabMeta[name] then
        return
    end
    self.ActiveTab = name
    SetTabVisuals()
    self:RebuildToolbar()
end

function Ribbon:OnAction(cb)
    OnAction = cb
end

local function FireAction(action)
    if OnAction then
        pcall(OnAction, action, Ribbon.ActiveTab)
    end
    if action == "Select" or action == "Move" or action == "Scale" or action == "Rotate" then
        if Tools and Tools.SetTool then
            Tools:SetTool(action)
        end
    end
end

function Ribbon:RebuildToolbar()
    if not ToolStrip then
        return
    end
    local kids = rawget(ToolStrip, "Children")
    if kids then
        for i = #kids, 1, -1 do
            kids[i]:Destroy()
        end
    end
    ActionButtons = {}

    local meta = TabMeta[self.ActiveTab]
    if not meta then
        return
    end

    local x = 8
    for gi, group in ipairs(meta.groups or {}) do
        local gl = Instance.new("TextLabel", ToolStrip)
        gl.Name = "Group_" .. group.name
        gl.Text = group.name
        gl.TextSize = 11
        gl.TextColor = Color.FromRGBA(160, 160, 170)
        gl.BackgroundColor = Color.FromRGBA(0, 0, 0, 0)
        gl.Position = UDim.New(0, x, 0, 0)
        gl.Size = UDim.New(0, 200, 0, 13)
        gl.TextAlignment = { "Left", "Center" }

        local bx = x
        for _, action in ipairs(group.actions or {}) do
            local isTool = (action == "Select" or action == "Move" or action == "Scale" or action == "Rotate")
            local iconPath = Ribbon:GetActionImage(action)
            local btnW = isTool and 48 or 64
            local btnH = 38

            local btn = Instance.new("Frame", ToolStrip)
            btn.Name = "Action_" .. action
            btn.Position = UDim.New(0, bx, 0, 14)
            btn.Size = UDim.FromOffset(btnW, btnH)
            btn.BackgroundColor = Color.FromRGBA(50, 50, 54)
            btn.ZIndex = 2

            if iconPath then
                local icon = Instance.new("ImageLabel", btn)
                icon.Name = "Icon"
                icon.Image = iconPath
                icon.Anchor = {0.5, 0}
                icon.Position = UDim.New(0.5, 0, 0, 2)
                icon.Size = UDim.FromOffset(22, 22)
                icon.BackgroundColor = Color.FromRGBA(0, 0, 0, 0)
                icon.ZIndex = 3

                local label = Instance.new("TextLabel", btn)
                label.Name = "Label"
                label.Text = action
                label.TextSize = 10
                label.TextColor = Color.FromRGBA(200, 200, 210)
                label.BackgroundColor = Color.FromRGBA(0, 0, 0, 0)
                label.Position = UDim.New(0, 0, 1, -14)
                label.Size = UDim.New(1, 0, 0, 12)
                label.TextAlignment = { "Center", "Center" }
            else
                local label = Instance.new("TextLabel", btn)
                label.Name = "Label"
                label.Text = action
                label.TextSize = 11
                label.TextColor = Color.FromRGBA(220, 220, 225)
                label.BackgroundColor = Color.FromRGBA(0, 0, 0, 0)
                label.Position = UDim.FromScale(0, 0)
                label.Size = UDim.FromScale(1, 1)
                label.TextAlignment = { "Center", "Center" }
            end

            if isTool and Tools and Tools.GetTool and Tools:GetTool() == action then
                btn.BackgroundColor = Color.FromRGBA(53, 83, 143)
            end

            btn.OnClick:Connect(function()
                FireAction(action)
                if isTool then
                    for an, ab in pairs(ActionButtons) do
                        if an == "Select" or an == "Move" or an == "Scale" or an == "Rotate" then
                            ab.BackgroundColor = (an == action) and Color.FromRGBA(53, 83, 143) or Color.FromRGBA(50, 50, 54)
                        end
                    end
                end
            end)

            btn.OnEnter:Connect(function()
                if not (isTool and Tools and Tools:GetTool() == action) then
                    btn.BackgroundColor = Color.FromRGBA(65, 65, 72)
                end
            end)
            btn.OnLeave:Connect(function()
                if isTool and Tools and Tools:GetTool() == action then
                    btn.BackgroundColor = Color.FromRGBA(53, 83, 143)
                else
                    btn.BackgroundColor = Color.FromRGBA(50, 50, 54)
                end
            end)

            ActionButtons[action] = btn
            bx = bx + (isTool and 52 or 68)
        end

        x = bx + 8
        if gi ~= #meta.groups then
            local sep = Instance.new("Frame", ToolStrip)
            sep.Name = "Sep"
            sep.BackgroundColor = Color.FromRGBA(70, 70, 75)
            sep.Position = UDim.New(0, x - 6, 0, 18)
            sep.Size = UDim.New(0, 1, 0, 28)
        end
    end
end

function Ribbon:Init(parentFrame)
    Frame = parentFrame
    Frame.BackgroundColor = Color.FromRGBA(32, 32, 35)

    local tabStrip = Instance.new("Frame", Frame)
    tabStrip.Name = "TabStrip"
    tabStrip.BackgroundColor = Color.FromRGBA(28, 28, 30)
    tabStrip.Position = UDim.New(0, 0, 0, 0)
    tabStrip.Size = UDim.New(1, 0, 0, self.TabHeight)

    local tx = 2
    for _, name in ipairs(TabOrder) do
        local btn = Instance.new("Frame", tabStrip)
        btn.Name = "Tab_" .. name
        btn.Position = UDim.New(0, tx, 0, 2)
        btn.Size = UDim.New(0, 72, 0, self.TabHeight - 4)
        btn.BackgroundColor = Color.FromRGBA(35, 35, 38)
        btn.ZIndex = 2

        local lab = Instance.new("TextLabel", btn)
        lab.Text = name
        lab.TextSize = 12
        lab.TextColor = Color.FromRGBA(210, 210, 220)
        lab.BackgroundColor = Color.FromRGBA(0, 0, 0, 0)
        lab.Position = UDim.FromScale(0, 0)
        lab.Size = UDim.FromScale(1, 1)
        lab.TextAlignment = { "Center", "Center" }

        local under = Instance.new("Frame", btn)
        under.Name = "Underline"
        under.BackgroundColor = Color.FromRGBA(80, 140, 255)
        under.Position = UDim.New(0, 0, 1, -2)
        under.Size = UDim.New(1, 0, 0, 2)
        under.Visible = false
        btn.Underline = under

        local tabName = name
        btn.OnClick:Connect(function()
            Ribbon:SetTab(tabName)
        end)

        TabButtons[name] = btn
        tx = tx + 76
    end

    ToolStrip = Instance.new("Frame", Frame)
    ToolStrip.Name = "ToolStrip"
    ToolStrip.BackgroundColor = Color.FromRGBA(40, 40, 44)
    ToolStrip.Position = UDim.New(0, 0, 0, self.TabHeight)
    ToolStrip.Size = UDim.New(1, 0, 0, self.ToolbarHeight)
    ToolStrip.ClipsDescendants = true

    SetTabVisuals()
    self:RebuildToolbar()
end

function Ribbon:HandleClick(mx, my)
    return false
end

function Ribbon:GetHeight()
    return self.TotalHeight
end

return Ribbon