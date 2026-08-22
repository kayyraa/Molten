local Color = require("Services.Color")
local UDim = require("Services.UDim")
local Instance = require("Services.Instance")
local Gui = require("Services.Gui")

local Explorer = {}

local RowHeight = 22
local IndentSize = 16
local ArrowSize = 16
local IconSize = 16
local TextPad = 38

local ServiceIcons = {
    Workspace = "Assets/Instances/Workspace.png",
    StarterGui = "Assets/Instances/StarterGui.png",
    Game = "Assets/Instances/Game.png"
}

local DeleteBlacklist = {
    Game = true,
    Workspace = true,
    Terrain = true,
    ReplicatedStorage = true,
    Lighting = true,
    ServerScriptService = true,
    ServerStorage = true,
    StarterGui = true,
    CoreGui = true,
    SelectionHighlight = true
}

local WarnedPaths = {}

local function GetIconPath(Node)
    local Override = ServiceIcons[Node.Name]
    if Override then
        return Override
    end
    return string.format("Assets/Instances/%s.png", Node.ClassName)
end

local function WarnIfMissing(Path)
    if WarnedPaths[Path] then
        return
    end

    if love.filesystem and love.filesystem.getInfo and not love.filesystem.getInfo(Path) then
        WarnedPaths[Path] = true
        Gui.Console:Print(string.format("[Explorer] Missing image: %s", Path))
    end
end

local ExpandedState = {}
local RootNode
local ContainerFrame

local Renaming = nil

function Explorer:GetKey(Node)
    return tostring(Node)
end

local function HasChildren(Node)
    local Children = rawget(Node, "Children")
    return Children and #Children > 0
end

-- ---------------------------------------------------------------------------
-- Insert Object menu
-- ---------------------------------------------------------------------------

local InsertMenu = nil
local MenuIconCache = {}

local InsertUsage = {}

local InsertGroups = {
    {
        Name = "Most Used",
        Dynamic = true,
    },
    {
        Name = "Parts",
        Items = {"Part", "WedgePart", "MeshPart"},
    },
    {
        Name = "Models",
        Items = {"Model", "Folder"},
    },
    {
        Name = "Scripts",
        Items = {"Script", "LocalScript", "ModuleScript"},
    },
    {
        Name = "Effects",
        Items = {"Attachment", "HandleAdornment", "Highlight", "PointLight", "SpotLight", "SurfaceLight"},
    },
    {
        Name = "Appearance",
        Items = {"Decal", "SurfaceAppearance", "Texture"},
    },
    {
        Name = "Camera",
        Items = {"Camera"},
    },
}

local function AllInsertClasses()
    local list, seen = {}, {}

    for _, g in ipairs(InsertGroups) do
        if g.Items then
            for _, c in ipairs(g.Items) do
                if not seen[c] then
                    seen[c] = true
                    list[#list + 1] = c
                end
            end
        end
    end

    return list
end

local function BuildInsertEntries(filter)
    filter = (filter or ""):lower()

    local entries = {}
    local used = {}

    for name, count in pairs(InsertUsage) do
        used[#used + 1] = {name = name, count = count}
    end

    table.sort(used, function(a, b)
        if a.count == b.count then
            return a.name < b.name
        end
        return a.count > b.count
    end)

    local function match(name)
        return filter == "" or name:lower():find(filter, 1, true)
    end

    if #used > 0 then
        local any = false
        for i = 1, math.min(6, #used) do
            if match(used[i].name) then
                if not any then
                    entries[#entries + 1] = {Kind = "header", Text = "Most Used"}
                    any = true
                end
                entries[#entries + 1] = {Kind = "item", ClassName = used[i].name}
            end
        end
    end

    for _, g in ipairs(InsertGroups) do
        if g.Dynamic then
            goto cont
        end

        local any = false
        for _, className in ipairs(g.Items or {}) do
            if match(className) then
                if not any then
                    entries[#entries + 1] = {Kind = "header", Text = g.Name}
                    any = true
                end
                entries[#entries + 1] = {Kind = "item", ClassName = className}
            end
        end

        ::cont::
    end

    return entries
end

local DragState = nil

Explorer.ScrollY = 0
Explorer.Selected = nil
Explorer.SelectedSet = {}
Explorer.OnSelect = nil
Explorer.OnDeleted = nil
Explorer.Clipboard = {} -- list of cloned roots for paste

function Explorer:IsSelected(Node)
    return Node ~= nil and (self.SelectedSet[Node] == true or self.Selected == Node)
end

function Explorer:ClearSelection()
    self.Selected = nil
    self.SelectedSet = {}

    if _G.Selection then
        pcall(function()
            _G.Selection:Clear()
        end)
    end
end

function Explorer:SetSelection(Node, multi)
    if not Node then
        self:ClearSelection()
        if self.OnSelect then
            self.OnSelect(nil, self.SelectedSet)
        end
        return
    end

    if multi then
        if self.SelectedSet[Node] then
            self.SelectedSet[Node] = nil
            if self.Selected == Node then
                self.Selected = nil
                for n, _ in pairs(self.SelectedSet) do
                    self.Selected = n
                    break
                end
            end
        else
            self.SelectedSet[Node] = true
            self.Selected = Node
        end
    else
        self.SelectedSet = {[Node] = true}
        self.Selected = Node
    end

    if _G.Selection then
        local list = {}
        for n, _ in pairs(self.SelectedSet) do
            list[#list + 1] = n
        end
        pcall(function()
            _G.Selection:Set(list)
        end)
    end

    if self.OnSelect then
        self.OnSelect(self.Selected, self.SelectedSet)
    end
end

local function IsBlacklisted(Node)
    if not Node then
        return true
    end
    if DeleteBlacklist[Node.Name] then
        return true
    end
    if DeleteBlacklist[Node.ClassName] then
        return true
    end
    if Node.ClassName == "Highlight" and Node.Name == "SelectionHighlight" then
        return true
    end

    local Parent = rawget(Node, "_Parent") or rawget(Node, "Parent")
    if Parent and (Parent.Name == "Game" or Parent.Name == "CoreGui") then
        if Node.ClassName == "Workspace" or Node.ClassName == "StarterGui"
            or Node.ClassName == "Folder" and (Node.Name == "CoreGui" or Node.Name == "Game") then
            return true
        end
    end

    return false
end

-- ---------------------------------------------------------------------------
-- Row building
-- ---------------------------------------------------------------------------

local RowList = {}

local function BuildRow(Parent, Node, Depth, RowIndex)
    local Key = tostring(Node)
    local IsSelected = Explorer:IsSelected(Node)
    local IsRenaming = Renaming and Renaming.Node == Node

    local Frame = Instance.new("Frame", Parent)
    Frame.Name = Node.Name

    local RowY = RowIndex * RowHeight - Explorer.ScrollY
    Frame.Position = UDim.New(0, 0, 0, RowY)
    Frame.Size = UDim.New(1, 0, 0, RowHeight - 2)

    local IndentX = Depth * IndentSize
    local AddX = IndentX + ArrowSize + IconSize + math.min(#(Node.Name or ""), 24) * 8 + 16

    RowList[#RowList + 1] = {
        Node = Node,
        Y = RowY,
        H = RowHeight - 2,
        Frame = Frame,
        Depth = Depth,
        Expandable = HasChildren(Node),
        AddX = AddX,
        AddW = IconSize,
    }

    Frame.BackgroundColor = IsSelected and Color.FromRGBA(53, 83, 143) or Color.FromRGBA(40, 40, 40)
    Frame.ZIndex = 2

    local Label = Instance.new("TextLabel", Frame)
    Label.BackgroundColor = Color.FromRGBA(0, 0, 0, 0)
    Label.Position = UDim.New(0, IndentX + TextPad, 0, 0)
    Label.Size = UDim.New(1, -(IndentX + TextPad), 1, 0)
    Label.TextAlignment = {"Left", "Center"}
    Label.TextSize = 14

    if IsRenaming and Renaming then
        local Buf = Renaming.Buffer or ""
        local Cur = math.max(1, math.min((Renaming.Cursor or 1), #Buf + 1))
        local Before = Buf:sub(1, Cur - 1)
        local After = Buf:sub(Cur)
        local Blink = (math.floor(love.timer.getTime() * 2) % 2 == 0) and "_" or " "

        Label.Text = Before .. Blink .. After
        Label.TextColor = Color.FromRGBA(255, 255, 160)
        Frame.BackgroundColor = Color.FromRGBA(40, 60, 90)
        Renaming.Label = Label
    else
        Label.Text = Node.Name
        Label.TextColor = IsSelected and Color.FromRGBA(255, 255, 255) or Color.FromRGBA(210, 210, 210)
    end

    if HasChildren(Node) then
        local ArrowPath = ExpandedState[Key] and "Assets/Decals/ArrowDown.png" or "Assets/Decals/ArrowRight.png"
        WarnIfMissing(ArrowPath)

        local Arrow = Instance.new("ImageLabel", Frame)
        Arrow.Image = ArrowPath
        Arrow.Anchor = {0, 0.5}
        Arrow.Position = UDim.New(0, IndentX, 0.5, 0)
        Arrow.Size = UDim.FromOffset(ArrowSize, ArrowSize)
        Arrow.ZIndex = 3

        Arrow.OnClick:Connect(function()
            if Renaming then
                return
            end
            ExpandedState[Key] = not ExpandedState[Key]
            Explorer:Refresh()
        end)
    end

    local IconPath = GetIconPath(Node)
    WarnIfMissing(IconPath)

    local Icon = Instance.new("ImageLabel", Frame)
    Icon.Image = IconPath
    Icon.Anchor = {0, 0.5}
    Icon.Position = UDim.New(0, IndentX + ArrowSize, 0.5, 0)
    Icon.Size = UDim.FromOffset(IconSize, IconSize)

    local Add = Instance.new("ImageLabel", Frame)
    Add.Image = "Assets/Decals/Add.png"
    Add.Anchor = {0, 0.5}
    Add.Position = UDim.New(0, IndentX + ArrowSize + IconSize + math.min(#Node.Name, 24) * 8 + 16, 0.5, 0)
    Add.Size = UDim.FromOffset(IconSize, IconSize)
    Add.Visible = false
    Add.ZIndex = 3

    Frame.OnEnter:Connect(function()
        if not IsRenaming then
            Add.Visible = true
            if not IsSelected then
                Frame.BackgroundColor = Color.FromRGBA(60, 60, 60)
            end
        end
    end)

    Frame.OnLeave:Connect(function()
        Add.Visible = false
        if not IsSelected and not IsRenaming then
            Frame.BackgroundColor = Color.FromRGBA(40, 40, 40)
        end
    end)

    Add.OnClick:Connect(function()
        local mx, my = love.mouse.getPosition()
        InsertMenu = {
            ParentNode = Node,
            Y = my,
            Search = "",
            Cursor = 1,
            Searching = true,
        }
    end)

    Frame.OnClick:Connect(function()
        if Renaming and Renaming.Node ~= Node then
            Explorer:CommitRename()
        end

        local multi = love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")
        Explorer:SetSelection(Node, multi)
        Explorer:Refresh()
    end)

    return Frame
end

local function Walk(Parent, Node, Depth, RowIndex)
    local Children = rawget(Node, "Children")
    if not Children then
        return RowIndex
    end

    for _, Child in ipairs(Children) do
        BuildRow(Parent, Child, Depth, RowIndex)
        RowIndex = RowIndex + 1

        if ExpandedState[tostring(Child)] and HasChildren(Child) then
            RowIndex = Walk(Parent, Child, Depth + 1, RowIndex)
        end
    end

    return RowIndex
end

local function CountRecursive(Node)
    local Count = 0
    local Children = rawget(Node, "Children")
    if not Children then
        return 0
    end

    for _, Child in ipairs(Children) do
        Count = Count + 1
        if ExpandedState[tostring(Child)] then
            Count = Count + CountRecursive(Child)
        end
    end

    return Count
end

-- ---------------------------------------------------------------------------
-- Init / Refresh / scroll
-- ---------------------------------------------------------------------------

function Explorer:Init(Container, Root)
    ContainerFrame = Container
    RootNode = Root
    ExpandedState[tostring(Root)] = true
    Explorer:Refresh()
end

function Explorer:Refresh()
    if not ContainerFrame or not RootNode then
        return
    end

    local OldChildren = rawget(ContainerFrame, "Children")
    if OldChildren then
        for Index = #OldChildren, 1, -1 do
            OldChildren[Index]:Destroy()
        end
    end

    RowList = {}
    Walk(ContainerFrame, RootNode, 0, 0)
end

function Explorer:HandleWheel(DeltaY)
    local Total = CountRecursive(RootNode)
    local _, _, _, VisibleH = self:GetListBounds()

    local Max = math.max(0, Total * RowHeight - VisibleH)
    self.ScrollY = math.max(0, math.min(Max, self.ScrollY - DeltaY * RowHeight))
    self:Refresh()
end

-- ---------------------------------------------------------------------------
-- Renaming
-- ---------------------------------------------------------------------------

function Explorer:IsRenaming()
    return Renaming ~= nil
end

function Explorer:StartRename(Node)
    Node = Node or self.Selected
    if not Node then
        return false
    end

    if IsBlacklisted(Node) and Node.Name ~= "Baseplate" then
        if DeleteBlacklist[Node.Name] or DeleteBlacklist[Node.ClassName] then
            Gui.Console:Print("[Explorer] Cannot rename protected instance: " .. tostring(Node.Name))
            return false
        end
    end

    Renaming = {
        Node = Node,
        Buffer = Node.Name or "",
        Cursor = #(Node.Name or "") + 1
    }
    self.Selected = Node
    self:Refresh()

    return true
end

function Explorer:CommitRename()
    if not Renaming then
        return false
    end

    local NewName = Renaming.Buffer:match("^%s*(.-)%s*$") or ""
    if NewName == "" then
        Gui.Console:Print("[Explorer] Name cannot be empty")
        Renaming = nil
        self:Refresh()
        return false
    end

    Renaming.Node.Name = NewName
    Renaming = nil
    self:Refresh()

    if self.OnSelect then
        self.OnSelect(self.Selected)
    end

    return true
end

function Explorer:CancelRename()
    Renaming = nil
    self:Refresh()
end

function Explorer:HandleRenameTextInput(Text)
    if not Renaming then
        return false
    end
    if type(Text) ~= "string" then
        return true
    end

    local Clean = Text:gsub("[^%w%-%._ ]", "")
    if Clean == "" then
        return true
    end

    local Before = Renaming.Buffer:sub(1, Renaming.Cursor - 1)
    local After = Renaming.Buffer:sub(Renaming.Cursor)

    Renaming.Buffer = Before .. Clean .. After
    Renaming.Cursor = Renaming.Cursor + #Clean
    self:Refresh()

    return true
end

function Explorer:HandleRenameKey(Key)
    if not Renaming then
        return false
    end

    if Key == "return" or Key == "kpenter" then
        return self:CommitRename()

    elseif Key == "escape" then
        self:CancelRename()
        return true

    elseif Key == "left" then
        Renaming.Cursor = math.max(1, Renaming.Cursor - 1)
        self:Refresh()
        return true

    elseif Key == "right" then
        Renaming.Cursor = math.min(#Renaming.Buffer + 1, Renaming.Cursor + 1)
        self:Refresh()
        return true

    elseif Key == "home" then
        Renaming.Cursor = 1
        self:Refresh()
        return true

    elseif Key == "end" then
        Renaming.Cursor = #Renaming.Buffer + 1
        self:Refresh()
        return true

    elseif Key == "backspace" then
        if Renaming.Cursor > 1 then
            Renaming.Buffer = Renaming.Buffer:sub(1, Renaming.Cursor - 2) .. Renaming.Buffer:sub(Renaming.Cursor)
            Renaming.Cursor = Renaming.Cursor - 1
            self:Refresh()
        end
        return true

    elseif Key == "delete" then
        if Renaming.Cursor <= #Renaming.Buffer then
            Renaming.Buffer = Renaming.Buffer:sub(1, Renaming.Cursor - 1) .. Renaming.Buffer:sub(Renaming.Cursor + 1)
            self:Refresh()
        end
        return true
    end

    return false
end

-- ---------------------------------------------------------------------------
-- Delete / copy / paste / duplicate
-- ---------------------------------------------------------------------------

function Explorer:DeleteSelected()
    pcall(function()
        local V = require("Services.Visuals")
        if V and V.Invalidate then
            V.Invalidate()
        end
    end)

    local ToDelete = {}
    for Node, _ in pairs(self.SelectedSet) do
        ToDelete[#ToDelete + 1] = Node
    end
    if #ToDelete == 0 and self.Selected then
        ToDelete[1] = self.Selected
    end
    if #ToDelete == 0 then
        return false
    end

    local deleted = 0
    for _, Node in ipairs(ToDelete) do
        if IsBlacklisted(Node) then
            Gui.Console:Print("[Explorer] Cannot delete protected instance: " .. tostring(Node.Name))
        else
            local Parent = rawget(Node, "_Parent") or Node.Parent
            if Parent then
                if self.OnDeleted then
                    self.OnDeleted(Node)
                end
                Node:Destroy()
                deleted = deleted + 1
            end
        end
    end

    self:ClearSelection()
    if self.OnSelect then
        self.OnSelect(nil, self.SelectedSet)
    end

    self:Refresh()

    return deleted > 0
end

function Explorer:CopySelected()
    local list = {}
    for Node, _ in pairs(self.SelectedSet) do
        if Node and not IsBlacklisted(Node) then
            list[#list + 1] = Node
        end
    end
    if #list == 0 and self.Selected and not IsBlacklisted(self.Selected) then
        list[1] = self.Selected
    end
    if #list == 0 then
        return false
    end

    self.Clipboard = {}
    for _, Node in ipairs(list) do
        local ok, cloned = pcall(function()
            return Node:Clone()
        end)
        if ok and cloned then
            self.Clipboard[#self.Clipboard + 1] = cloned
        end
    end

    return #self.Clipboard > 0
end

function Explorer:Paste(parentOverride)
    if not self.Clipboard or #self.Clipboard == 0 then
        return false
    end

    local parent = parentOverride
    if not parent then
        parent = self.Selected
        if not parent or IsBlacklisted(parent) then
            -- prefer Workspace as default paste target
            parent = rawget(_G, "Workspace") or RootNode
        end
    end
    if not parent then
        return false
    end

    local pasted = {}
    for _, template in ipairs(self.Clipboard) do
        local ok, copy = pcall(function()
            return template:Clone()
        end)

        if ok and copy then
            -- slight offset for BaseParts so they don't stack exactly
            if copy:IsA("BasePart") and copy.Position then
                local pos = copy.Position
                local arr = pos.ToArray and pos:ToArray() or {pos.Px or pos[1] or 0, pos.Py or pos[2] or 0, pos.Pz or pos[3] or 0}
                local Vector3 = require("Services.Vector3")

                copy.Position = Vector3.new((arr[1] or 0) + 2, arr[2] or 0, (arr[3] or 0) + 2)
            end

            copy.Parent = parent
            pasted[#pasted + 1] = copy
        end
    end

    if #pasted == 0 then
        return false
    end

    ExpandedState[tostring(parent)] = true

    self.SelectedSet = {}
    for _, n in ipairs(pasted) do
        self.SelectedSet[n] = true
        self.Selected = n
    end

    if self.OnSelect then
        self.OnSelect(self.Selected, self.SelectedSet)
    end

    self:Refresh()

    pcall(function()
        local V = require("Services.Visuals")
        if V and V.Invalidate then
            V.Invalidate()
        end
    end)

    return true
end

function Explorer:DuplicateSelected()
    if not self:CopySelected() then
        return false
    end

    -- paste under the same parent as the first selected
    local parent = nil
    for Node, _ in pairs(self.SelectedSet) do
        parent = rawget(Node, "_Parent") or Node.Parent
        break
    end
    if not parent and self.Selected then
        parent = rawget(self.Selected, "_Parent") or self.Selected.Parent
    end

    return self:Paste(parent)
end

-- ---------------------------------------------------------------------------
-- Insert menu
-- ---------------------------------------------------------------------------

function Explorer:HasInsertMenu()
    return InsertMenu ~= nil
end

function Explorer:CloseInsertMenu()
    InsertMenu = nil
end

function Explorer:InsertObject(ParentNode, ClassName)
    if not ParentNode or not ClassName then
        return nil
    end

    local ok, Obj = pcall(function()
        return Instance.new(ClassName, ParentNode)
    end)
    if not ok or not Obj then
        Gui.Console:Print("[Explorer] Failed to create " .. tostring(ClassName))
        return nil
    end

    if Obj:IsA("BasePart") then
        local Vector3 = require("Services.Vector3")
        local pos = Vector3.new(0, 2, 0)
        local Ws = rawget(_G, "Workspace")

        if Ws and Ws.Raycast then
            local Cam = nil
            for _, ch in ipairs(Ws:GetChildren()) do
                if ch.ClassName == "Camera" then
                    Cam = ch
                    break
                end
            end

            if Cam then
                local Cp = Cam:GetAttribute("Position") or {0, 4, 0}
                local Cr = Cam:GetAttribute("Rotation") or {0, 0, 0}
                local pitch, yaw = Cr[1] or 0, Cr[2] or 0

                local origin = Vector3.new(Cp[1], Cp[2], Cp[3])
                local direction = Vector3.new(
                    math.cos(pitch) * math.sin(yaw) * 256,
                    math.sin(pitch) * 256,
                    -math.cos(pitch) * math.cos(yaw) * 256
                )

                local params = RaycastParams.new()
                params.FilterType = Enum.RaycastFilterMode.Exclude
                params.FilterDescendantsInstances = {Obj}

                local result = Ws:Raycast(origin, direction, params)
                if result then
                    local hp, n = result.Position, result.Normal
                    local sz = Obj.Size
                    local halfY = 2

                    if sz and sz.ToArray then
                        halfY = (sz:ToArray()[2] or 4) * 0.5
                    elseif type(sz) == "table" then
                        halfY = (sz[2] or 4) * 0.5
                    end

                    pos = Vector3.new(hp.Px + n.Px * halfY, hp.Py + n.Py * halfY, hp.Pz + n.Pz * halfY)
                end
            end
        end

        Obj.Position = pos
    end

    ExpandedState[tostring(ParentNode)] = true
    self:SetSelection(Obj, false)
    self:Refresh()

    pcall(function()
        local V = require("Services.Visuals")
        if V and V.Invalidate then
            V.Invalidate()
        end
    end)

    return Obj
end

function Explorer:HandleInsertClick(MouseX, MouseY)
    if not InsertMenu then
        return false
    end

    local ItemH, MenuW = 22, 200
    local SearchH = 26
    local entries = BuildInsertEntries(InsertMenu.Search or "")
    local MenuH = SearchH + 6 + #entries * ItemH + 6
    local X, Y = InsertMenu.X, InsertMenu.Y

    if MouseX < X or MouseX > X + MenuW or MouseY < Y or MouseY > Y + MenuH then
        InsertMenu = nil
        return true
    end

    if MouseY >= Y + 3 and MouseY < Y + 3 + SearchH then
        InsertMenu.Searching = true
        return true
    end

    local Index = math.floor((MouseY - Y - 3 - SearchH) / ItemH) + 1
    if Index >= 1 and Index <= #entries then
        local e = entries[Index]
        if e.Kind == "item" then
            self:InsertObject(InsertMenu.ParentNode, e.ClassName)
            InsertMenu = nil
            return true
        end
    end

    return true
end

function Explorer:HandleInsertTextInput(Text)
    if not InsertMenu or not InsertMenu.Searching then
        return false
    end
    if type(Text) ~= "string" then
        return true
    end

    local Clean = Text:gsub("[\r\n]", "")
    local Before = (InsertMenu.Search or ""):sub(1, (InsertMenu.Cursor or 1) - 1)
    local After = (InsertMenu.Search or ""):sub(InsertMenu.Cursor or 1)

    InsertMenu.Search = Before .. Clean .. After
    InsertMenu.Cursor = (InsertMenu.Cursor or 1) + #Clean

    return true
end

function Explorer:HandleInsertKey(Key)
    if not InsertMenu then
        return false
    end

    if Key == "escape" then
        InsertMenu = nil
        return true
    end

    if not InsertMenu.Searching then
        return false
    end

    if Key == "return" or Key == "kpenter" then
        local entries = BuildInsertEntries(InsertMenu.Search or "")
        for _, e in ipairs(entries) do
            if e.Kind == "item" then
                self:InsertObject(InsertMenu.ParentNode, e.ClassName)
                InsertMenu = nil
                return true
            end
        end
        return true

    elseif Key == "backspace" then
        local cur = InsertMenu.Cursor or 1
        local s = InsertMenu.Search or ""

        if cur > 1 then
            InsertMenu.Search = s:sub(1, cur - 2) .. s:sub(cur)
            InsertMenu.Cursor = cur - 1
        end
        return true

    elseif Key == "left" then
        InsertMenu.Cursor = math.max(1, (InsertMenu.Cursor or 1) - 1)
        return true

    elseif Key == "right" then
        InsertMenu.Cursor = math.min(#(InsertMenu.Search or "") + 1, (InsertMenu.Cursor or 1) + 1)
        return true
    end

    return false
end

function Explorer:GetPanelBounds()
    -- Prefer the Dock right-top pane when available
    local ok, DockMod = pcall(require, "Services.Dock")
    if ok and DockMod and DockMod.GetLayout then
        local L = DockMod:GetLayout()
        if L.RightTop and L.RightTop.W > 0 then
            return L.RightTop.X, L.RightTop.Y, L.RightTop.W, L.RightTop.H
        end
    end
    -- Fallback (pre-dock layout)
    local W, H = love.graphics.getDimensions()
    local PanelW = 256
    local PanelLeft = W - PanelW
    local TopH = 84
    local PanelTop = TopH
    local PanelH = 0.625 * H - TopH
    if PanelH < 50 then
        PanelH = 50
    end
    return PanelLeft, PanelTop, PanelW, PanelH
end

function Explorer:GetListBounds()
    local PanelLeft, PanelTop, PanelW, PanelH = self:GetPanelBounds()
    local HeaderH = 17
    local ListTop = PanelTop + HeaderH
    local ListH = PanelH - HeaderH
    if ListH < 20 then
        ListH = 20
    end
    return PanelLeft, ListTop, PanelW, ListH
end

function Explorer:ContainsPoint(MouseX, MouseY)
    local PanelLeft, PanelTop, PanelW, PanelH = self:GetPanelBounds()
    return MouseX >= PanelLeft and MouseX <= PanelLeft + PanelW
        and MouseY >= PanelTop and MouseY <= PanelTop + PanelH
end

function Explorer:DrawInsertMenu()
    if not InsertMenu then
        return
    end

    local ItemH, MenuW = 22, 200
    local SearchH = 26
    local entries = BuildInsertEntries(InsertMenu.Search or "")
    local MenuH = SearchH + 6 + math.max(#entries, 1) * ItemH + 6
    local PanelLeft, PanelTop, PanelW, PanelH = self:GetPanelBounds()
    local W, H = love.graphics.getDimensions()

    -- Fixed horizontal position: left edge of Explorer panel
    -- (menu opens to the left of panel if needed)
    local X = PanelLeft - MenuW - 4
    if X < 4 then
        X = PanelLeft + 4
    end
    if X + MenuW > W - 4 then
        X = math.max(4, W - MenuW - 4)
    end

    local Y = InsertMenu.Y or (PanelTop + 20)
    if Y + MenuH > H - 4 then
        Y = math.max(4, Y - MenuH)
    end
    if Y < 4 then
        Y = 4
    end

    InsertMenu.X = X
    InsertMenu.Y = Y

    local mx, my = love.mouse.getPosition()

    love.graphics.setColor(0, 0, 0, 0.45)
    love.graphics.rectangle("fill", X + 2, Y + 2, MenuW, MenuH)
    love.graphics.setColor(0.16, 0.16, 0.17, 1)
    love.graphics.rectangle("fill", X, Y, MenuW, MenuH)
    love.graphics.setColor(0.32, 0.32, 0.34, 1)
    love.graphics.rectangle("line", X, Y, MenuW, MenuH)

    love.graphics.setColor(0.12, 0.12, 0.13, 1)
    love.graphics.rectangle("fill", X + 4, Y + 4, MenuW - 8, SearchH)
    love.graphics.setColor(0.35, 0.35, 0.38, 1)
    love.graphics.rectangle("line", X + 4, Y + 4, MenuW - 8, SearchH)

    local search = InsertMenu.Search or ""
    local cur = InsertMenu.Cursor or (#search + 1)
    local blink = (math.floor(love.timer.getTime() * 2) % 2 == 0) and "_" or " "
    local shown = search:sub(1, cur - 1) .. blink .. search:sub(cur)

    if search == "" and blink == " " then
        love.graphics.setColor(0.45, 0.45, 0.48, 1)
        pcall(love.graphics.print, "Search classes...", X + 10, Y + 9)
    else
        love.graphics.setColor(1, 1, 1, 1)
        pcall(love.graphics.print, shown, X + 10, Y + 9)
    end

    if #entries == 0 then
        love.graphics.setColor(0.5, 0.5, 0.55, 1)
        pcall(love.graphics.print, "No matches", X + 10, Y + 3 + SearchH + 6)
        return
    end

    for i, e in ipairs(entries) do
        local iy = Y + 3 + SearchH + (i - 1) * ItemH

        if e.Kind == "header" then
            love.graphics.setColor(0.55, 0.55, 0.6, 1)
            pcall(love.graphics.print, tostring(e.Text or ""), X + 8, iy + 4)
        else
            local hovered = mx >= X and mx <= X + MenuW and my >= iy and my < iy + ItemH

            if hovered then
                love.graphics.setColor(0.0, 0.47, 0.84, 1)
                love.graphics.rectangle("fill", X + 1, iy, MenuW - 2, ItemH)
            end

            local iconPath = string.format("Assets/Instances/%s.png", e.ClassName)
            local img = MenuIconCache[iconPath]

            if img == nil then
                if love.filesystem and love.filesystem.getInfo and love.filesystem.getInfo(iconPath) then
                    local ok, result = pcall(love.graphics.newImage, iconPath)
                    img = ok and result or false
                else
                    img = false
                end
                MenuIconCache[iconPath] = img
            end

            if img then
                love.graphics.setColor(1, 1, 1, 1)
                love.graphics.draw(img, X + 8, iy + 3, 0, 16 / img:getWidth(), 16 / img:getHeight())
            else
                love.graphics.setColor(0.35, 0.55, 0.85, 1)
                love.graphics.rectangle("fill", X + 8, iy + 3, 16, 16)
            end

            love.graphics.setColor(1, 1, 1, 1)
            pcall(love.graphics.print, tostring(e.ClassName or ""), X + 30, iy + 3)
        end
    end
end

function Explorer:HitTestRow(MouseX, MouseY)
    if not ContainerFrame then
        return nil
    end
    -- Rows are in panel coordinates relative to list; use absolute via love mouse vs frame layout
    return nil
end

-- ---------------------------------------------------------------------------
-- Drag & drop reparenting
-- ---------------------------------------------------------------------------

function Explorer:BeginDrag(Node, X, Y)
    if not Node or IsBlacklisted(Node) then
        return
    end
    if Renaming then
        return
    end

    DragState = {
        Node = Node,
        StartX = X,
        StartY = Y,
        Active = false,
        Target = nil
    }
end

function Explorer:UpdateDrag(X, Y)
    if not DragState then
        return
    end

    local dx = X - DragState.StartX
    local dy = Y - DragState.StartY

    if not DragState.Active and (dx * dx + dy * dy) > 36 then
        DragState.Active = true
    end

    if DragState.Active then
        DragState.X = X
        DragState.Y = Y
    end
end

function Explorer:IsDragging()
    return DragState ~= nil and DragState.Active == true
end

function Explorer:CancelDrag()
    DragState = nil
end

local function IsDescendantOf(Node, PossibleAncestor)
    local Cur = Node
    while Cur do
        if Cur == PossibleAncestor then
            return true
        end
        Cur = rawget(Cur, "_Parent") or Cur.Parent
    end
    return false
end

function Explorer:TryReparent(Node, NewParent)
    if not Node or not NewParent then
        return false
    end
    if Node == NewParent then
        return false
    end
    if IsBlacklisted(Node) then
        return false
    end
    if IsDescendantOf(NewParent, Node) then
        Gui.Console:Print("[Explorer] Cannot parent into own descendant")
        return false
    end

    local ok, err = pcall(function()
        Node.Parent = NewParent
    end)
    if not ok then
        Gui.Console:Print("[Explorer] Reparent failed")
        return false
    end

    ExpandedState[tostring(NewParent)] = true
    self:SetSelection(Node, false)
    self:Refresh()

    return true
end

function Explorer:EndDrag(X, Y, TargetNode)
    if not DragState then
        return false
    end

    local Node = DragState.Node
    local WasActive = DragState.Active
    DragState = nil

    if not WasActive then
        return false
    end
    if TargetNode and TargetNode ~= Node then
        return self:TryReparent(Node, TargetNode)
    end

    return true
end

function Explorer:RowNodeAt(MouseY, ListTop, ListHeight)
    if ListTop == nil then
        local _, Lt, _, Lh = self:GetListBounds()
        ListTop = Lt
        ListHeight = Lh
    end
    if not RowList then
        return nil
    end

    local LocalY = MouseY - ListTop
    if LocalY < 0 or LocalY > ListHeight then
        return nil
    end

    for _, Row in ipairs(RowList) do
        if LocalY >= Row.Y and LocalY < Row.Y + Row.H then
            return Row.Node
        end
    end

    return nil
end

function Explorer:RowAt(MouseX, MouseY, ListLeft, ListTop, ListHeight)
    if ListLeft == nil then
        local Ll, Lt, _, Lh = self:GetListBounds()
        ListLeft = Ll
        ListTop = Lt
        ListHeight = Lh
    end
    if not RowList then
        return nil
    end

    local LocalY = MouseY - ListTop
    if LocalY < 0 or LocalY > ListHeight then
        return nil
    end

    for _, Row in ipairs(RowList) do
        if LocalY >= Row.Y and LocalY < Row.Y + Row.H then
            return Row
        end
    end

    return nil
end

function Explorer:TryToggleExpand(MouseX, MouseY, ListLeft, ListTop, ListHeight)
    if ListLeft == nil then
        local Ll, Lt, _, Lh = self:GetListBounds()
        ListLeft = Ll
        ListTop = Lt
        ListHeight = Lh
    end
    local Row = self:RowAt(MouseX, MouseY, ListLeft, ListTop, ListHeight)
    if not Row or not Row.Expandable then
        return false
    end

    local IndentX = (Row.Depth or 0) * IndentSize
    local LocalX = MouseX - ListLeft

    if LocalX >= IndentX and LocalX < IndentX + ArrowSize + 4 then
        local Key = tostring(Row.Node)
        ExpandedState[Key] = not ExpandedState[Key]
        self:Refresh()
        return true
    end

    return false
end

function Explorer:TryOpenInsert(MouseX, MouseY, ListLeft, ListTop, ListHeight)
    if ListLeft == nil then
        local Ll, Lt, _, Lh = self:GetListBounds()
        ListLeft = Ll
        ListTop = Lt
        ListHeight = Lh
    end
    local Row = self:RowAt(MouseX, MouseY, ListLeft, ListTop, ListHeight)
    if not Row then
        return false
    end

    local LocalX = MouseX - ListLeft
    local Ax = Row.AddX or 0
    local Aw = Row.AddW or IconSize

    if LocalX >= Ax - 2 and LocalX < Ax + Aw + 6 then
        InsertMenu = {
            ParentNode = Row.Node,
            Y = MouseY,
            Search = "",
            Cursor = 1,
            Searching = true,
        }
        return true
    end

    return false
end

function Explorer:DrawDragGhost()
    if not DragState or not DragState.Active or not DragState.Node then
        return
    end

    local Node = DragState.Node
    local X = DragState.X or DragState.StartX
    local Y = DragState.Y or DragState.StartY
    local W, H = 180, 22

    love.graphics.setColor(0, 0, 0, 0.35)
    love.graphics.rectangle("fill", X + 12, Y + 4, W, H, 3, 3)
    love.graphics.setColor(0.18, 0.22, 0.32, 0.92)
    love.graphics.rectangle("fill", X + 10, Y + 2, W, H, 3, 3)
    love.graphics.setColor(0.0, 0.47, 0.84, 1)
    love.graphics.rectangle("line", X + 10, Y + 2, W, H, 3, 3)

    local iconPath = GetIconPath(Node)
    local img = MenuIconCache and MenuIconCache[iconPath]

    if img == nil then
        if love.filesystem and love.filesystem.getInfo and love.filesystem.getInfo(iconPath) then
            local ok, result = pcall(love.graphics.newImage, iconPath)
            img = ok and result or false
        else
            img = false
        end
        if MenuIconCache then
            MenuIconCache[iconPath] = img
        end
    end

    if img then
        love.graphics.setColor(1, 1, 1, 1)
        pcall(love.graphics.draw, img, X + 14, Y + 5, 0, 16 / img:getWidth(), 16 / img:getHeight())
    else
        love.graphics.setColor(0.35, 0.55, 0.85, 1)
        love.graphics.rectangle("fill", X + 14, Y + 5, 16, 16)
    end

    love.graphics.setColor(1, 1, 1, 1)
    local label = tostring(Node.Name or Node.ClassName or "Instance")
    if #label > 22 then
        label = label:sub(1, 21) .. "..."
    end
    pcall(love.graphics.print, label, X + 36, Y + 6)
end

return Explorer
