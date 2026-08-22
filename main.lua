local Instance = require("Services.Instance")
require("Services.Enum")

local Fabric = _G.Fabric
local Gui = require("Services.Gui")
local Color = require("Services.Color")
local Vector3 = require("Services.Vector3")
local Pixel = require("Services.Pixel")
local UDim = require("Services.UDim")
local Explorer = require("Services.Explorer")
local Properties = require("Services.Properties")
local Visuals = require("Services.Visuals")
local Clipboard = require("Services.Clipboard")
local Tools = require("Services.Tools")
local ScriptEditor = require("Services.ScriptEditor")
local WindowTabs = require("Services.WindowTabs")
local Ribbon = require("Services.Ribbon")
local Dock = require("Services.Dock")
local Gizmos = require("Services.Gizmos")

local CurrentCamera

local function GetActiveCamera()
    local cam = Workspace and Workspace.CurrentCamera
    if cam and cam.ClassName == "Camera" then
        CurrentCamera = cam
        return cam
    end
    return CurrentCamera
end

local MoveSpeed = 32
local LookSensitivity = 0.002
local PositionSmoothing = 18
local RotationSmoothing = 24

local TargetPosition = {0, 4, 0}
local TargetRotation = {0, 0, 0}
local SmoothPosition = {0, 4, 0}
local SmoothRotation = {0, 0, 0}

local SnapSize = 2
local Geometry = require("Services.Geometry")

local function SnapValue(Value, Size)
    if Size <= 0 then
        return Value
    end
    return math.floor(Value / Size + 0.5) * Size
end

local FreeDrag = nil
local ToArr3 = Geometry.ToArr3
local WorkspaceRaycast = Geometry.WorkspaceRaycast
local CameraRay = Geometry.CameraRay
local IntersectPlaneY = Geometry.IntersectPlaneY

local function TopBarHeight()
    -- Prefer Dock layout; fall back to Ribbon intrinsic height
    if Dock and Dock.TopH then
        return Dock.TopH
    end
    return (Ribbon and Ribbon.GetHeight and Ribbon:GetHeight()) or 84
end

local function CenterRect()
    if Dock and Dock.GetCenter then
        return Dock:GetCenter()
    end
    local W, H = love.graphics.getDimensions()
    local top = TopBarHeight()
    local right = (Dock and Dock.RightW) or 256
    return { X = 0, Y = top, W = W - right, H = H - top }
end

function love.load()
    love.keyboard.setKeyRepeat(true)
    love.window.setTitle("Molten")
    love.window.setIcon(love.image.newImageData("Assets/Decals/Icon.png"))
    love.window.setMode(1250, 750, {resizable = true, depth = 24})

    Gui:Font("Assets/Fonts/Font.ttf", 14)
    Gui.Console.Offset = {4, 40}

    CurrentCamera = Instance.new("Camera", Workspace)
    CurrentCamera.Name = "Camera"
    CurrentCamera:SetAttribute("Position", {0, 4, 0})
    CurrentCamera:SetAttribute("Rotation", {0, 0, 0})
    CurrentCamera:SetAttribute("Fov", math.pi / 1.75)
    CurrentCamera:SetAttribute("Opt", false)
    Workspace.CurrentCamera = CurrentCamera

    Workspace.Raycast = function(self, Origin, Direction, Params)
        if self and self.Px then
            return WorkspaceRaycast(self, Origin, Direction)
        end
        if Origin and Origin.Px then
            return WorkspaceRaycast(Origin, Direction, Params)
        else
            return WorkspaceRaycast(self, Origin, Direction)
        end
    end
    _G.WorkspaceRaycast = WorkspaceRaycast

    local Baseplate = Instance.new("Part", Workspace)
    Baseplate.Name = "Baseplate"
    Baseplate.Size = Vector3.new(512, 2, 512)
    Baseplate.Position = Vector3.new(0, -1, 0)
    Baseplate.Color = Color.FromRGBA(120, 120, 120)
    Baseplate.Material = {Reflectivity = 0, Roughness = 1}
    Baseplate.Anchored = true
    Baseplate.Locked = true

    local Decal = Instance.new("Decal", Baseplate)
    Decal.Face = "Top"
    Decal.Texture = "Assets/Decals/Grid.png"
    Decal.UvStuds = {8, 8}

    local SelectionHighlight = Instance.new("Highlight", CoreGui)
    SelectionHighlight.Name = "SelectionHighlight"
    SelectionHighlight.Enabled = true
    SelectionHighlight.DepthMode = "AlwaysOnTop"
    SelectionHighlight.FillTransparency = 1
    SelectionHighlight.OutlineColor = Color.FromRGBA(80, 140, 255)
    SelectionHighlight.OutlineTransparency = 0
    SelectionHighlight.Adornee = nil
    _G.SelectionHighlight = SelectionHighlight

    TargetPosition = {0, 4, 0}
    SmoothPosition = {0, 4, 0}
    TargetRotation = {0, 0, 0}
    SmoothRotation = {0, 0, 0}

    Gui.Console.Offset = {6, 28}
    love.mouse.setRelativeMode(false)
    love.mouse.setVisible(true)

    Explorer:Refresh()
end

local Keys = {}

function love.keypressed(Key)
    if Explorer and Explorer.HasInsertMenu and Explorer:HasInsertMenu() then
        if Explorer:HandleInsertKey(Key) then
            return
        end
    end
    if Properties and Properties:IsEditing() then
        if Properties:HandleKey(Key) then
            return
        end
    end
    if Explorer and Explorer:IsRenaming() then
        if Explorer:HandleRenameKey(Key) then
            return
        end
    end
    if (ScriptEditor and ScriptEditor.IsFocused and ScriptEditor:IsFocused()) or (WindowTabs and WindowTabs.IsScript and WindowTabs:IsScript() and ScriptEditor and ScriptEditor.GetActive and ScriptEditor:GetActive()) then
        local Handled = false
        if ScriptEditor.HandleKey then
            Handled = ScriptEditor:HandleKey(Key)
        end
        if Key == "return" or Key == "kpenter" then
            if not Handled and ScriptEditor.HandleTextInput then
                ScriptEditor:HandleTextInput("\n")
            end
            return
        end
        if Handled then
            return
        end
        if ScriptEditor.IsFocused and ScriptEditor:IsFocused() then
            return
        end
    end
    if Tools:HandleKey(Key) then
        return
    end

    local CtrlDown = love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")
    local ShiftDown = love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift")

    if Key == "escape" then
        if Explorer and Explorer:IsRenaming() then
            Explorer:CancelRename()
            return
        end
        if WindowTabs and WindowTabs.IsScript and WindowTabs:IsScript() then
            WindowTabs:SelectViewport()
            return
        end
        love.event.quit()

    elseif Key == "return" or Key == "kpenter" then
        if Explorer and Explorer.Selected and Explorer.Selected.IsA and Explorer.Selected:IsA("Script") then
            WindowTabs:OpenScript(Explorer.Selected)
            return
        end

    elseif Key == "f2" then
        if Explorer and Explorer.Selected then
            Explorer:StartRename(Explorer.Selected)
        end

    elseif Key == "backspace" or Key == "delete" then
        if Explorer and Explorer.Selected and not Explorer:IsRenaming() then
            Explorer:DeleteSelected()
        end

    elseif Key == "c" and CtrlDown then
        local Targets = {}
        if Explorer.SelectedSet and next(Explorer.SelectedSet) then
            for Node, _ in pairs(Explorer.SelectedSet) do
                Targets[#Targets + 1] = Node
            end
        elseif Explorer.Selected then
            Targets[1] = Explorer.Selected
        end
        if #Targets > 0 then
            Clipboard:Copy(Targets)
        end

    elseif Key == "v" and CtrlDown then
        if Clipboard:HasData() then
            local PasteParent = nil
            if ShiftDown then
                PasteParent = Explorer.Selected
            elseif Explorer.Selected then
                PasteParent = rawget(Explorer.Selected, "_Parent") or Explorer.Selected.Parent
            end
            if not PasteParent then
                PasteParent = Workspace
            end
            local Created = Clipboard:Paste(PasteParent)
            if #Created > 0 then
                local NewSet = {}
                for _, Obj in ipairs(Created) do
                    NewSet[Obj] = true
                end
                Explorer.SelectedSet = NewSet
                Explorer.Selected = Created[1]
                if Explorer.OnSelect then
                    Explorer.OnSelect(Explorer.Selected, Explorer.SelectedSet)
                end
                Explorer:Refresh()
                if Visuals and Visuals.Invalidate then
                    Visuals.Invalidate()
                end
                Properties:Cancel()
                Explorer:CancelRename()
                if CurrentCamera then
                    CurrentCamera:SetAttribute("Opt", false)
                end
            end
        end

    elseif Key == "c" then
        CurrentCamera:SetAttribute("Opt", true)

    elseif Key == "]" or Key == "=" or Key == "+" then
        SnapSize = math.min(64, SnapSize + 1)

    elseif Key == "[" or Key == "-" or Key == "_" then
        SnapSize = math.max(1, SnapSize - 1)
    end

    Keys[Key] = true
end

function love.keyreleased(Key)
    if Key == "c" then
        CurrentCamera:SetAttribute("Opt", false)
    end
    Keys[Key] = nil
end

function love.mousepressed(X, Y, Button)
    local W, H = love.graphics.getDimensions()
    local TabH = WindowTabs and WindowTabs.TabHeight or 24
    local center = CenterRect()
    local PanelLeft = center.X + center.W
    local ViewportTop = center.Y + TabH
    local ViewportH = math.max(0, center.H - TabH)

    if Button == 1 then
        -- Always arm Gui click routing so Properties / overlays / dropdowns receive OnClick
        if Gui and Gui.NotifyMousePressed then
            Gui:NotifyMousePressed()
        end

        -- Dock splitter drag takes priority
        local split = Dock and Dock.HitSplitter and Dock:HitSplitter(X, Y)
        if split then
            Dock:BeginResize(split, X, Y)
            return
        end

        -- Transform gizmos (Move / Scale / Rotate) take priority over free-drag
        if WindowTabs and WindowTabs.IsViewport and WindowTabs:IsViewport()
            and X >= center.X and X < PanelLeft and Y >= ViewportTop then
            CurrentCamera = GetActiveCamera()
            if CurrentCamera and Gizmos and Gizmos.MousePressed then
                Gizmos.SnapSize = SnapSize
                if Gizmos.MousePressed(CurrentCamera, X, Y) then
                    return
                end
            end
        end

        if WindowTabs and WindowTabs.IsScript and WindowTabs:IsScript() and X >= center.X and X < PanelLeft and Y >= ViewportTop then
            if TextBox and TextBox.IsActive and TextBox.IsActive() then
                local A = TextBox.Get()
                if A and A.id ~= "scripteditor" then
                    TextBox.Commit()
                end
            end
            if ScriptEditor and ScriptEditor.Click then
                ScriptEditor:Click(X, Y, center.X, ViewportTop, center.W, ViewportH)
            end
            return
        end

        if TextBox and TextBox.IsActive and TextBox.IsActive() then
            local A = TextBox.Get()
            if A and A.id == "scripteditor" then
                if ScriptEditor and ScriptEditor.SyncFromTextBox then ScriptEditor:SyncFromTextBox() end
                if ScriptEditor and ScriptEditor.SetFocused then ScriptEditor:SetFocused(false) end
                if TextBox.End then TextBox.End() end
            else
                if TextBox.Commit then TextBox.Commit() end
            end
        end

        if Explorer and Explorer.HasInsertMenu and Explorer:HasInsertMenu() then
            Explorer:HandleInsertClick(X, Y)
            return
        end

        if WindowTabs and WindowTabs.HandleClick and WindowTabs:HandleClick(X, Y) then
            return
        end

        if Explorer and not Explorer:IsRenaming() and Explorer:ContainsPoint(X, Y) then
            local ListLeft, ListTop, _, ListH = Explorer:GetListBounds()

            if Explorer:TryToggleExpand(X, Y, ListLeft, ListTop, ListH) then
                return
            end
            if Explorer:TryOpenInsert(X, Y, ListLeft, ListTop, ListH) then
                return
            end

            local Node = Explorer:RowNodeAt(Y, ListTop, ListH)
            if Node then
                local multi = love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")
                Explorer:SetSelection(Node, multi)
                Explorer:BeginDrag(Node, X, Y)
                Explorer:Refresh()

                if Node.IsA and Node:IsA("Script") and not multi then
                    local Dx = love.timer.getTime()
                    if Node._LastClickTime and (Dx - Node._LastClickTime) < 0.35 then
                        if WindowTabs and WindowTabs.OpenScript then WindowTabs:OpenScript(Node) end
                    end
                    Node._LastClickTime = Dx
                end
            end
        else
            Gui:NotifyMousePressed()
            CurrentCamera = GetActiveCamera()

            if WindowTabs and WindowTabs.IsViewport and WindowTabs:IsViewport() and X >= center.X and X < PanelLeft and Y >= ViewportTop and CurrentCamera and not (Explorer and Explorer:IsRenaming()) then
                local Hit = Pixel.Pick(CurrentCamera, X, Y)
                local multi = love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")

                if Hit then
                    Explorer:SetSelection(Hit, multi)
                    Explorer:Refresh()

                    -- Free-drag only in Select tool; Move/Scale/Rotate use gizmos
                    if not multi and Tools:Is("Select") and Hit.IsA and (Hit:IsA("BasePart") or Hit:IsA("Part")) and Hit.Locked ~= true then
                        local Ro, Rd = CameraRay(CurrentCamera, X, Y)
                        local PartPos = ToArr3(Hit.Position)
                        local PartSize = ToArr3(Hit.Size)
                        local PlaneY = PartPos[2]
                        local GrabPoint = IntersectPlaneY(Ro, Rd, PlaneY)
                        local halfY = (PartSize[2] or 4) * 0.5

                        if GrabPoint then
                            FreeDrag = {
                                Part = Hit,
                                PlaneY = PlaneY,
                                OffsetX = PartPos[1] - GrabPoint[1],
                                OffsetZ = PartPos[3] - GrabPoint[3],
                                StartY = PartPos[2],
                                LastY = PartPos[2],
                                HalfY = halfY
                            }
                        else
                            FreeDrag = {
                                Part = Hit,
                                PlaneY = PlaneY,
                                OffsetX = 0,
                                OffsetZ = 0,
                                StartY = PartPos[2],
                                LastY = PartPos[2],
                                HalfY = halfY
                            }
                        end
                    end
                elseif not multi then
                    Explorer:ClearSelection()
                    if Explorer.OnSelect then
                        Explorer.OnSelect(nil, Explorer.SelectedSet)
                    end
                    Explorer:Refresh()
                end
            end
        end
    end

    if Button == 2 then
        love.mouse.setRelativeMode(true)
        love.mouse.setVisible(false)
    end
end

function love.mousereleased(X, Y, Button)
    if Button == 1 then
        if Gizmos and Gizmos.MouseReleased then
            Gizmos.MouseReleased()
        end
        if Dock and Dock.IsResizing and Dock:IsResizing() then
            Dock:EndResize()
        end
        if Explorer and Explorer.EndDrag then
            local Target = nil
            if Explorer:ContainsPoint(X, Y) then
                local _, ListTop, _, ListH = Explorer:GetListBounds()
                Target = Explorer:RowNodeAt(Y, ListTop, ListH)
            end
            Explorer:EndDrag(X, Y, Target)
        end
        if FreeDrag then
            if Visuals and Visuals.Invalidate then
                Visuals.Invalidate()
            end
            FreeDrag = nil
        end
    end

    if Button == 2 then
        love.mouse.setRelativeMode(false)
        love.mouse.setVisible(true)
    end
end

function love.mousemoved(X, Y, DeltaX, DeltaY)
    if Dock and Dock.IsResizing and Dock:IsResizing() then
        Dock:UpdateResize(X, Y)
        return
    end

    -- Cursor feedback over splitters
    if Dock and Dock.CursorFor and not love.mouse.isDown(2) then
        local cur = Dock:CursorFor(X, Y)
        if cur == "sizewe" then
            love.mouse.setCursor(love.mouse.getSystemCursor("sizewe"))
        elseif cur == "sizens" then
            love.mouse.setCursor(love.mouse.getSystemCursor("sizens"))
        else
            love.mouse.setCursor()
        end
    end

    if Explorer and Explorer.UpdateDrag then
        Explorer:UpdateDrag(X, Y)
    end

    -- Gizmo drag / hover
    CurrentCamera = GetActiveCamera()
    if CurrentCamera and Gizmos and Gizmos.MouseMoved then
        Gizmos.SnapSize = SnapSize
        if Gizmos.MouseMoved(CurrentCamera, X, Y) then
            return
        end
    end

    if FreeDrag then
        CurrentCamera = GetActiveCamera()

        if CurrentCamera then
            local Ro, Rd = CameraRay(CurrentCamera, X, Y)
            local Origin = Vector3.new(Ro[1], Ro[2], Ro[3])
            local Dir = Vector3.new(Rd[1] * 1000, Rd[2] * 1000, Rd[3] * 1000)

            local Params = RaycastParams.new()
            Params.FilterType = Enum.RaycastFilterMode.Exclude
            Params.FilterDescendantsInstances = {FreeDrag.Part}

            local Result = WorkspaceRaycast(Origin, Dir, Params)

            if Result then
                local hitPos = ToArr3(Result.Position)
                local normal = ToArr3(Result.Normal)
                local halfY = FreeDrag.HalfY or 2

                local newX = hitPos[1] + normal[1] * (halfY + 0.02)
                local newY = hitPos[2] + normal[2] * (halfY + 0.02)
                local newZ = hitPos[3] + normal[3] * (halfY + 0.02)

                if math.abs(normal[2]) < 0.5 then
                    newY = FreeDrag.LastY or FreeDrag.StartY
                end

                newX = SnapValue(newX, SnapSize)
                newZ = SnapValue(newZ, SnapSize)

                FreeDrag.Part.Position = Vector3.new(newX, newY, newZ)
                FreeDrag.LastY = newY

                if Visuals and Visuals.Invalidate then
                    Visuals.Invalidate()
                end
            else
                local planeY = FreeDrag.LastY or FreeDrag.StartY
                local Point = IntersectPlaneY(Ro, Rd, planeY)

                if Point then
                    local rawX = Point[1] + FreeDrag.OffsetX
                    local rawZ = Point[3] + FreeDrag.OffsetZ

                    FreeDrag.Part.Position = Vector3.new(
                        SnapValue(rawX, SnapSize),
                        planeY,
                        SnapValue(rawZ, SnapSize)
                    )

                    if Visuals and Visuals.Invalidate then
                        Visuals.Invalidate()
                    end
                end
            end
        end
    end

    if Properties and Properties.IsEditing and Properties:IsEditing() then
        return
    end
    if Explorer and Explorer.IsRenaming and Explorer:IsRenaming() then
        return
    end
    if ScriptEditor and ScriptEditor.IsFocused and ScriptEditor:IsFocused() then
        return
    end

    CurrentCamera = GetActiveCamera()
    if not love.mouse.isDown(2) or not CurrentCamera then
        return
    end

    local Pitch = TargetRotation[1] - DeltaY * LookSensitivity
    local Yaw = TargetRotation[2] + DeltaX * LookSensitivity
    local Limit = math.pi * 0.49

    if Pitch > Limit then
        Pitch = Limit
    end
    if Pitch < -Limit then
        Pitch = -Limit
    end

    TargetRotation = {Pitch, Yaw, 0}
end

function love.textinput(Text)
    if Explorer and Explorer.HasInsertMenu and Explorer:HasInsertMenu() then
        if Explorer:HandleInsertTextInput(Text) then
            return
        end
    end
    if Properties and Properties.IsEditing and Properties:IsEditing() and Properties:HandleTextInput(Text) then
        return
    end
    if Explorer and Explorer.IsRenaming and Explorer:IsRenaming() and Explorer:HandleRenameTextInput(Text) then
        return
    end
    if WindowTabs and WindowTabs.IsScript and WindowTabs:IsScript() and ScriptEditor and ScriptEditor.HandleTextInput and ScriptEditor:HandleTextInput(Text) then
        return
    end
end

function love.wheelmoved(X, Y)
    local MouseX, MouseY = love.mouse.getPosition()
    local center = CenterRect()
    local PanelLeft = center.X + center.W
    local L = Dock and Dock.GetLayout and Dock:GetLayout()

    if Explorer and Explorer:ContainsPoint(MouseX, MouseY) then
        Explorer:HandleWheel(Y)
    elseif (L and L.RightBottom and MouseX >= L.RightBottom.X and MouseX < L.RightBottom.X + L.RightBottom.W
        and MouseY >= L.RightBottom.Y and MouseY < L.RightBottom.Y + L.RightBottom.H)
        or (Properties and Properties.ContainsPoint and Properties:ContainsPoint(MouseX, MouseY)) then
        if Properties and Properties.HandleWheel then Properties:HandleWheel(Y) end
    elseif WindowTabs and WindowTabs.IsScript and WindowTabs:IsScript()
        and MouseX >= center.X and MouseX < PanelLeft and MouseY >= center.Y then
        if ScriptEditor and ScriptEditor.HandleWheel then
            ScriptEditor:HandleWheel(Y)
        end
    end
end

local Framerate = 0
local DeltaTime = 0

function love.update(Delta)
    Framerate = Fabric.Lerp(Framerate, 1 / Delta, Delta * 8)
    DeltaTime = Fabric.Lerp(DeltaTime, Delta, Delta * 8)

    if not CurrentCamera then
        return
    end

    local TextFocus = (Properties and Properties.IsEditing and Properties:IsEditing()) or (Explorer and Explorer.IsRenaming and Explorer:IsRenaming()) or (ScriptEditor and ScriptEditor.IsFocused and ScriptEditor:IsFocused()) or (WindowTabs and WindowTabs.IsScript and WindowTabs:IsScript() and ScriptEditor and ScriptEditor.GetActive and ScriptEditor:GetActive())

    CurrentCamera:SetAttribute("Fov", Fabric.Lerp(
        CurrentCamera:GetAttribute("Fov"),
        CurrentCamera:GetAttribute("Opt") and math.pi / 4 or math.pi / 1.75,
        Delta * 8
    ))

    SmoothRotation[1] = Fabric.Lerp(SmoothRotation[1], TargetRotation[1], Delta * RotationSmoothing)
    SmoothRotation[2] = Fabric.Lerp(SmoothRotation[2], TargetRotation[2], Delta * RotationSmoothing)
    SmoothRotation[3] = Fabric.Lerp(SmoothRotation[3], TargetRotation[3], Delta * RotationSmoothing)
    CurrentCamera:SetAttribute("Rotation", SmoothRotation)

    local Pitch = TargetRotation[1] or 0
    local Yaw = TargetRotation[2] or 0
    local Forward = {
        math.cos(Pitch) * math.sin(Yaw),
        math.sin(Pitch),
        -math.cos(Pitch) * math.cos(Yaw)
    }
    local Right = {math.cos(Yaw), 0, math.sin(Yaw)}

    local MoveX, MoveY, MoveZ = 0, 0, 0

    if love.keyboard.isDown("w") then
        MoveX = MoveX + Forward[1]
        MoveY = MoveY + Forward[2]
        MoveZ = MoveZ + Forward[3]
    end
    if love.keyboard.isDown("s") then
        MoveX = MoveX - Forward[1]
        MoveY = MoveY - Forward[2]
        MoveZ = MoveZ - Forward[3]
    end
    if love.keyboard.isDown("d") then
        MoveX = MoveX + Right[1]
        MoveZ = MoveZ + Right[3]
    end
    if love.keyboard.isDown("a") then
        MoveX = MoveX - Right[1]
        MoveZ = MoveZ - Right[3]
    end
    if love.keyboard.isDown("space") or love.keyboard.isDown("e") then
        MoveY = MoveY + 1
    end
    if love.keyboard.isDown("lshift") or love.keyboard.isDown("q") then
        MoveY = MoveY - 1
    end

    if TextFocus then
        MoveX, MoveY, MoveZ = 0, 0, 0
    end

    local Length = math.sqrt(MoveX * MoveX + MoveY * MoveY + MoveZ * MoveZ)
    if Length > 0 then
        local Scale = MoveSpeed * Delta / Length
        TargetPosition[1] = TargetPosition[1] + MoveX * Scale
        TargetPosition[2] = TargetPosition[2] + MoveY * Scale
        TargetPosition[3] = TargetPosition[3] + MoveZ * Scale
    end

    SmoothPosition[1] = Fabric.Lerp(SmoothPosition[1], TargetPosition[1], Delta * PositionSmoothing)
    SmoothPosition[2] = Fabric.Lerp(SmoothPosition[2], TargetPosition[2], Delta * PositionSmoothing)
    SmoothPosition[3] = Fabric.Lerp(SmoothPosition[3], TargetPosition[3], Delta * PositionSmoothing)
    CurrentCamera:SetAttribute("Position", SmoothPosition)

    local mx, my = love.mouse.getPosition()
    local center = CenterRect()
    local PanelLeft = center.X + center.W

    if mx >= center.X and mx < PanelLeft and my >= center.Y and my < center.Y + center.H
        and not TextFocus and not love.mouse.isDown(2) and CurrentCamera
        and not (Dock and Dock.IsResizing and Dock:IsResizing()) then
        local Hit = Pixel.Pick(CurrentCamera, mx, my)
        _G.HoverPart = (Hit and Hit.Locked ~= true) and Hit or nil
    else
        _G.HoverPart = nil
    end
end

local ScreenGui = Instance.new("ScreenGui", CoreGui)
ScreenGui.Name = "ScreenGui"

local ToolsFrame = Instance.new("Frame", ScreenGui)
ToolsFrame.BackgroundColor = Color.FromRGBA(40, 40, 40)
ToolsFrame.Name = "Tools"
ToolsFrame.ClipsDescendants = true
ToolsFrame.ClipDescendants = true

-- Ribbon (Home / Model / Testing / View) owns the top toolbar.
-- Tools is initialised in silent mode so only keyboard shortcuts (1-4) remain;
-- the visual strip is driven entirely by Ribbon.
Tools:Init(ToolsFrame, { silent = true })
Ribbon:Init(ToolsFrame)

-- Dock system: Top = ribbon, Right = Explorer + Properties (split), Center = viewport
if Ribbon and Ribbon.GetHeight then
    Dock:SetTopHeight(Ribbon:GetHeight())
end
Dock:SetRightWidth(256)
Dock:SetLeftWidth(0)
Dock:SetBottomHeight(0)
Dock:SetContent("Top", ToolsFrame)

Ribbon:OnAction(function(action, tab)
    if action == "Copy" then
        if Explorer and Explorer.CopySelected then Explorer:CopySelected() end
    elseif action == "Paste" then
        if Explorer and Explorer.Paste then Explorer:Paste() end
    elseif action == "Duplicate" then
        if Explorer and Explorer.DuplicateSelected then Explorer:DuplicateSelected() end
    elseif action == "Part" then
        if Explorer and Explorer.InsertObject then
            local parent = (Explorer.Selected and not Explorer.Selected:IsA("Script")) and Explorer.Selected or Workspace
            Explorer:InsertObject(parent, "Part")
        end
    elseif action == "Explorer" or action == "Properties" or action == "Output" then
        -- windows live in the right dock; visibility is layout-driven
    end
end)

local ExplorerFrame = Instance.new("Frame", ScreenGui)
ExplorerFrame.BackgroundColor = Color.FromRGBA(40, 40, 40)
ExplorerFrame.Name = "Explorer"
ExplorerFrame.ClipsDescendants = true
ExplorerFrame.ClipDescendants = true

local Header1 = Instance.new("TextLabel", ExplorerFrame)
Header1.Name = "Header"
Header1.Text = "Explorer"
Header1.Position = UDim.FromScale(0, 0)
Header1.Size = UDim.New(1, 0, 0, 17)
Header1.BackgroundColor = Color.FromRGBA(60, 60, 60)
Header1.TextColor = Color.FromRGBA(200, 200, 200)
Header1.TextAlignment = {"Center", "Center"}
Header1.TextSize = 12

local Header1Padding = Instance.new("UiPadding", Header1)
Header1Padding.PaddingLeft = UDim.New(0, 4)

local ExplorerList = Instance.new("Frame", ExplorerFrame)
ExplorerList.Name = "List"
ExplorerList.BackgroundColor = Color.FromRGBA(40, 40, 40)
ExplorerList.Position = UDim.New(0, 0, 0, 17)
ExplorerList.Size = UDim.New(1, 0, 1, -17)
ExplorerList.ClipsDescendants = true
ExplorerList.ClipDescendants = true

local PropertiesFrame = Instance.new("Frame", ScreenGui)
PropertiesFrame.BackgroundColor = Color.FromRGBA(40, 40, 40)
PropertiesFrame.Name = "Properties"
PropertiesFrame.ClipsDescendants = true
PropertiesFrame.ClipDescendants = true

local Header2 = Instance.new("TextLabel", PropertiesFrame)
Header2.Name = "Header"
Header2.Text = "Properties"
Header2.Position = UDim.FromScale(0, 0)
Header2.Size = UDim.New(1, 0, 0, 17)
Header2.BackgroundColor = Color.FromRGBA(60, 60, 60)
Header2.TextColor = Color.FromRGBA(200, 200, 200)
Header2.TextAlignment = {"Center", "Center"}
Header2.TextSize = 12

local Header2Padding = Instance.new("UiPadding", Header2)
Header2Padding.PaddingLeft = UDim.New(0, 4)

local PropertiesList = Instance.new("Frame", PropertiesFrame)
PropertiesList.Name = "List"
PropertiesList.BackgroundColor = Color.FromRGBA(40, 40, 40)
PropertiesList.Position = UDim.New(0, 0, 0, 17)
PropertiesList.Size = UDim.New(1, 0, 1, -17)
PropertiesList.ClipsDescendants = true
PropertiesList.ClipDescendants = true

Explorer:Init(ExplorerList, Game)
Properties:Init(PropertiesList)

Dock:SetContent("RightTop", ExplorerFrame)
Dock:SetContent("RightBottom", PropertiesFrame)

Explorer.OnSelect = function(Node, SelectedSet)
    Properties:Select(Node, SelectedSet)

    local HL = _G.SelectionHighlight
    if HL then
        if Node and (Node:IsA("BasePart") or Node:IsA("Model") or Node:IsA("Part")) then
            HL.Adornee = Node
            HL.Enabled = true
        else
            HL.Adornee = nil
            HL.Enabled = false
        end
    end

    _G.SelectionSet = SelectedSet or (Node and {[Node] = true} or {})

    if Visuals and Visuals.Invalidate then
        Visuals.Invalidate()
    end
end

function love.draw()
    local TabH = WindowTabs and WindowTabs.TabHeight or 24
    local L = Dock:GetLayout()
    local center = L.Center
    local ViewportTop = center.Y + TabH
    local ViewportH = math.max(0, center.H - TabH)

    -- Keep Dock top height in sync with ribbon intrinsic size when not user-resized
    -- (user can still drag the top splitter to grow/shrink)
    if Ribbon and Ribbon.GetHeight and not Dock:IsResizing() then
        local rh = Ribbon:GetHeight()
        if Dock.TopH < rh then
            Dock:SetTopHeight(rh)
            L = Dock:GetLayout()
            center = L.Center
            ViewportTop = center.Y + TabH
            ViewportH = math.max(0, center.H - TabH)
        end
    end

    CurrentCamera = GetActiveCamera()

    if WindowTabs and WindowTabs.IsViewport and WindowTabs:IsViewport() then
        if CurrentCamera then
            Pixel.Render(CurrentCamera)
            -- Studio-style Move / Scale / Rotate gizmos over the viewport
            if Gizmos and Gizmos.Render then
                Gizmos.SnapSize = SnapSize
                Gizmos.Render(CurrentCamera)
            end
        end
    else
        if ScriptEditor and ScriptEditor.Draw then
            ScriptEditor:Draw(center.X, ViewportTop, center.W, ViewportH)
        end
    end

    if WindowTabs and WindowTabs.Draw then
        WindowTabs:Draw(center.X, center.Y, center.W)
    end

    -- Apply dock rects to registered frames (ribbon, explorer, properties)
    Dock:Apply()

    Gui:Render(StarterGui)
    Gui:Render(CoreGui)
    Gui:ClearClickFlag()
    Gui.Console:Draw()

    -- Splitter handles (drawn above panels)
    Dock:DrawSplitters()

    if Explorer and Explorer.DrawInsertMenu then
        Explorer:DrawInsertMenu()
    end
    if Explorer and Explorer.DrawDragGhost then
        Explorer:DrawDragGhost()
    end
end

function love.run()
    if love.load then
        love.load(love.arg.parseGameArguments(arg))
    end
    if love.timer then
        love.timer.step()
    end

    local Dt = 0

    return function()
        if love.event then
            love.event.pump()
            for Name, Ax, Bx, Cx, Dx, Ex, Fx in love.event.poll() do
                if Name == "quit" then
                    if not love.quit or not love.quit() then
                        return Ax or 0
                    end
                end
                if love.handlers[Name] then
                    love.handlers[Name](Ax, Bx, Cx, Dx, Ex, Fx)
                end
            end
        end

        if love.timer then
            Dt = love.timer.step()
        end
        if love.update then
            love.update(Dt)
        end

        if love.graphics and love.graphics.isActive() then
            love.graphics.origin()
            love.graphics.clear(love.graphics.getBackgroundColor())
            if love.draw then
                love.draw()
            end
            love.graphics.present()
        end
    end
end
