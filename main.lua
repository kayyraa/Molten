local Instance = require("Services.Instance")
require("Services.Enum")

local Fabric = _G.Fabric
local Gui = require("Services.Gui")
local Color = require("Services.Color")
local Theme = _G.Theme or require("Services.Theme")
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
local Runtime = require("Services.Runtime")
local Output = require("Services.Output")
local CSG = require("Services.CSG")
local Replication = require("Services.Replication")
local Physics = require("Services.Physics")
local TextBox = _G.TextBox or require("Services.TextBox")

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
local CameraZoomSpeed = 4
local CameraZoomSmooth = 0
local PlayZoomDistance = 12
local PlayZoomTarget = 12

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

local function IsUnderAncestor(Node, Ancestor)
    if not Node or not Ancestor then return false end
    if Node == Ancestor then return true end
    local Cur = Node
    for _ = 1, 48 do
        Cur = rawget(Cur, "_Parent") or Cur.Parent
        if not Cur then return false end
        if Cur == Ancestor then return true end
        if Cur == Workspace or Cur == Game then return false end
    end
    return false
end

local function ResolveViewportTarget(Inst)
    if not Inst then return nil end
    if Inst.Locked == true then return nil end
    local Cur = Inst
    local ModelHit = nil
    for _ = 1, 48 do
        if not Cur then break end
        if Cur == Workspace or Cur == Game then break end
        if Cur.ClassName == "Model" then
            ModelHit = Cur
        end
        Cur = rawget(Cur, "_Parent") or Cur.Parent
    end
    if ModelHit then return ModelHit end
    return Inst
end

local function CollectBaseParts(Node, Into)
    Into = Into or {}
    if not Node then return Into end
    if Node.IsA and Node:IsA("BasePart") then
        Into[Node] = true
        Into[#Into + 1] = Node
    end
    local Kids = rawget(Node, "Children")
    if Kids then
        for I = 1, #Kids do
            CollectBaseParts(Kids[I], Into)
        end
    end
    return Into
end

local function BuildSelectionSet(Node, SelectedSet)
    local Set = {}
    if SelectedSet then
        for N, On in pairs(SelectedSet) do
            if On and N then
                Set[N] = true
                if N.IsA and (N:IsA("Model") or N:IsA("Folder")) then
                    CollectBaseParts(N, Set)
                end
            end
        end
    end
    if Node then
        Set[Node] = true
        if Node.IsA and (Node:IsA("Model") or Node:IsA("Folder")) then
            CollectBaseParts(Node, Set)
        end
    end
    return Set
end

local function IsUiTextBusy()
    if TextBox and TextBox.IsActive and TextBox.IsActive() then return true end
    if Properties and Properties.IsEditing and Properties:IsEditing() then return true end
    if Explorer and Explorer.IsRenaming and Explorer:IsRenaming() then return true end
    if ScriptEditor and ScriptEditor.IsFocused and ScriptEditor:IsFocused() then return true end
    if ScriptEditor and ScriptEditor.IsEditing and ScriptEditor:IsEditing() then return true end
    return false
end

local function ClampFov(deg)
    deg = tonumber(deg) or 70
    if deg < 45 then return 45 end
    if deg > 135 then return 135 end
    return deg
end

local function TopBarHeight()
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
    CurrentCamera.FieldOfView = 90
    CurrentCamera._RestFov = 90
    CurrentCamera:SetAttribute("_Opt", false)
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

    do
        local Terrain = nil
        for _, Ch in ipairs(Workspace:GetChildren()) do
            if Ch.ClassName == "Terrain" or Ch.Name == "Terrain" then
                Terrain = Ch
                break
            end
        end
        if not Terrain then
            Terrain = Instance.new("Terrain", Workspace)
            Terrain.Name = "Terrain"
        end
        local function EnsureChild(Parent, Class, Name)
            for _, Ch in ipairs(Parent:GetChildren()) do
                if Ch.ClassName == Class or Ch.Name == Name then
                    return Ch
                end
            end
            local E = Instance.new(Class, Parent)
            E.Name = Name
            return E
        end
        EnsureChild(Terrain, "Clouds", "Clouds")
        local Lighting = rawget(_G, "Lighting")
        if not Lighting and rawget(_G, "Game") then
            for _, Ch in ipairs(_G.Game:GetChildren()) do
                if Ch.ClassName == "Lighting" or Ch.Name == "Lighting" then
                    Lighting = Ch
                    _G.Lighting = Lighting
                    break
                end
            end
        end
        if Lighting then
            EnsureChild(Lighting, "Atmosphere", "Atmosphere")
            EnsureChild(Lighting, "BloomEffect", "Bloom")
            EnsureChild(Lighting, "SunRaysEffect", "SunRays")
            EnsureChild(Lighting, "ColorCorrectionEffect", "ColorCorrection")
            EnsureChild(Lighting, "DepthOfFieldEffect", "DepthOfField")
        end
    end

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

    if Key == "escape" and Properties and Properties.IsObjectPicking and Properties:IsObjectPicking() then
        Properties:CancelObjectPick()
        if Properties.Refresh then Properties:Refresh() end
        return
    end

    local textBusy = (TextBox and TextBox.IsActive and TextBox.IsActive())
        or (Properties and Properties.IsEditing and Properties:IsEditing())
        or (Explorer and Explorer.IsRenaming and Explorer:IsRenaming())

    if textBusy then
        if Properties and Properties.HandleKey and Properties:HandleKey(Key) then
            return
        end
        if TextBox and TextBox.IsActive and TextBox.IsActive() and TextBox.HandleKey then
            if TextBox.HandleKey(Key) then
                return
            end
        end
        if Explorer and Explorer.IsRenaming and Explorer:IsRenaming() and Explorer.HandleRenameKey then
            if Explorer:HandleRenameKey(Key) then
                return
            end
        end
        return
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
                    CurrentCamera:SetAttribute("_Opt", false)
                end
            end
        end

    elseif Key == "c" then
        CurrentCamera:SetAttribute("_Opt", true)

    elseif Key == "f5" then
        if love.keyboard.isDown("lshift") or love.keyboard.isDown("rshift") then
            Runtime:Stop()
        elseif Runtime:IsPlay() and Runtime:IsPaused() then
            Runtime:Resume()
        elseif not Runtime:IsPlay() then
            Runtime:StartPlay(false)
        end
    elseif Key == "f6" then
        if Runtime:IsPlay() and Runtime:IsPaused() then
            Runtime:Resume()
        else
            Runtime:StartPlay(true)
        end
    elseif Key == "f7" then
        if Runtime:IsRun() and Runtime:IsPaused() then
            Runtime:Resume()
        elseif not Runtime:IsRun() then
            Runtime:StartRun()
        end
    elseif Key == "f8" then
        Runtime:Stop()
        if Ribbon and Ribbon.RefreshMezzanine then Ribbon:RefreshMezzanine() end
    elseif Key == "f9" then
        if Runtime.TogglePause then Runtime:TogglePause() end
        if Ribbon and Ribbon.RefreshMezzanine then Ribbon:RefreshMezzanine() end
    elseif Key == "]" or Key == "=" or Key == "+" then
        SnapSize = math.min(64, SnapSize + 1)

    elseif Key == "[" or Key == "-" or Key == "_" then
        SnapSize = math.max(1, SnapSize - 1)
    end

    Keys[Key] = true
end

function love.keyreleased(Key)
    if Key == "c" then
        CurrentCamera:SetAttribute("_Opt", false)
    end
    Keys[Key] = nil
end

function love.mousepressed(X, Y, Button)
    if IsUiTextBusy and IsUiTextBusy() then
        if TextBox and TextBox.NotifyMousePressed then
            TextBox.NotifyMousePressed(X, Y, Button)
        end
        if Gui and Gui.NotifyMousePressed then
            Gui:NotifyMousePressed()
        end
        return
    end
    local W, H = love.graphics.getDimensions()
    local TabH = WindowTabs and WindowTabs.TabHeight or 24
    local center = CenterRect()
    local PanelLeft = center.X + center.W
    local ViewportTop = center.Y + TabH
    local ViewportH = math.max(0, center.H - TabH)

    if Button == 1 then
        if HandleDockChromeClick and HandleDockChromeClick(X, Y) then
            return
        end
        if Gui and Gui.NotifyMousePressed then
            Gui:NotifyMousePressed()
        end
        if Properties and Properties.DismissPopupsIfOutside then
            Properties:DismissPopupsIfOutside(X, Y)
        end
        if Properties and Properties.MousePressed and Properties:MousePressed(X, Y, Button) then
            return
        end

        local split = Dock and Dock.HitSplitter and Dock:HitSplitter(X, Y)
        if split then
            Dock:BeginResize(split, X, Y)
            return
        end

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
                if Gui and Gui.CancelClick then Gui:CancelClick() end
                return
            end
            if Explorer:TryOpenInsert(X, Y, ListLeft, ListTop, ListH) then
                if Gui and Gui.CancelClick then Gui:CancelClick() end
                return
            end

            local Node = Explorer:RowNodeAt(Y, ListTop, ListH)
            if Node then
                local multi = love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")
                Explorer:SetSelection(Node, multi)
                Explorer:BeginDrag(Node, X, Y)
                Explorer:Refresh()
                if Gui and Gui.CancelClick then Gui:CancelClick() end

                if Node.IsA and Node:IsA("Script") and not multi then
                    local Dx = love.timer.getTime()
                    if Node._LastClickTime and (Dx - Node._LastClickTime) < 0.35 then
                        if WindowTabs and WindowTabs.OpenScript then WindowTabs:OpenScript(Node) end
                    end
                    Node._LastClickTime = Dx
                end
            end
        else
            CurrentCamera = GetActiveCamera()

            if WindowTabs and WindowTabs.IsViewport and WindowTabs:IsViewport() and X >= center.X and X < PanelLeft and Y >= ViewportTop and CurrentCamera and not (Explorer and Explorer:IsRenaming()) then
                local Hit = Pixel.Pick(CurrentCamera, X, Y)
                local multi = love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")
                local Target = ResolveViewportTarget(Hit)

                if Properties and Properties.IsObjectPicking and Properties:IsObjectPicking() then
                    if Target and Target.Locked ~= true then
                        Properties:TryAssignObject(Target)
                    end
                    return
                end

                if Target and Target.Locked ~= true then
                    Explorer:SetSelection(Target, multi)
                    Explorer:Refresh()

                    if not multi and (Tools:Is("Select") or Tools:Is("Move")) and Hit.IsA and Hit:IsA("BasePart") then
                        local Ro, Rd = CameraRay(CurrentCamera, X, Y)
                        local DragPart = Hit
                        if Target and Target.IsA and Target:IsA("BasePart") then
                            DragPart = Target
                        end
                        local PartPos = ToArr3(DragPart.Position)
                        local PartSize = ToArr3(DragPart.Size)
                        local PlaneY = PartPos[2]
                        local GrabPoint = IntersectPlaneY(Ro, Rd, PlaneY)
                        local halfY = (PartSize[2] or 4) * 0.5
                        local Gx, Gz = PartPos[1], PartPos[3]
                        if GrabPoint then
                            Gx, Gz = GrabPoint[1], GrabPoint[3]
                        end
                        FreeDrag = {
                            Part = DragPart,
                            PlaneY = PlaneY,
                            OffsetX = PartPos[1] - Gx,
                            OffsetZ = PartPos[3] - Gz,
                            StartY = PartPos[2],
                            LastY = PartPos[2],
                            HalfY = halfY,
                        }
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
        if Properties and Properties.MouseReleased then
            Properties:MouseReleased(X, Y, Button)
        end
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

    if Properties and Properties.MouseMoved then
        Properties:MouseMoved(X, Y)
    end

    do
        local cur = nil
        if Properties and Properties.GetCursor then
            cur = Properties:GetCursor(X, Y)
        end
        if not cur and Gui and Gui.GetHoverCursor then
            cur = Gui:GetHoverCursor()
        end
        if Dock and Dock.CursorFor and not love.mouse.isDown(2) then
            local d = Dock:CursorFor(X, Y)
            if d == "sizewe" or d == "sizens" then
                cur = d
            end
        end
        if cur == "hand" then
            love.mouse.setCursor(love.mouse.getSystemCursor("hand"))
        elseif cur == "ibeam" then
            love.mouse.setCursor(love.mouse.getSystemCursor("ibeam"))
        elseif cur == "sizewe" then
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
            local planeY = FreeDrag.StartY or FreeDrag.LastY or 0
            local Point = IntersectPlaneY(Ro, Rd, planeY)
            if Point then
                local rawX = Point[1] + (FreeDrag.OffsetX or 0)
                local rawZ = Point[3] + (FreeDrag.OffsetZ or 0)
                FreeDrag.Part.Position = Vector3.new(
                    SnapValue(rawX, SnapSize),
                    planeY,
                    SnapValue(rawZ, SnapSize)
                )
                FreeDrag.LastY = planeY
                if Visuals and Visuals.Invalidate then
                    Visuals.Invalidate()
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
    if IsUiTextBusy and IsUiTextBusy() then
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
    if Properties and Properties.HandleTextInput and Properties:HandleTextInput(Text) then
        return
    end
    if TextBox and TextBox.IsActive and TextBox.IsActive() then
        TextBox.HandleTextInput(Text)
        return
    end
    if Explorer and Explorer.IsRenaming and Explorer:IsRenaming() and Explorer.HandleRenameText then
        Explorer:HandleRenameText(Text)
        return
    end
end

function love.wheelmoved(X, Y)
    if IsUiTextBusy and IsUiTextBusy() then
        if ScriptEditor and ScriptEditor.HandleWheel and ScriptEditor:IsFocused() then
            ScriptEditor:HandleWheel(Y)
        end
        return
    end
    local MouseX, MouseY = love.mouse.getPosition()
    local center = CenterRect()
    local PanelLeft = center.X + center.W
    local L = Dock and Dock.GetLayout and Dock:GetLayout()

    if Explorer and Explorer.HasInsertMenu and Explorer:HasInsertMenu() then
        if Explorer:HandleInsertWheel(Y) then
            return
        end
    end

    if Output and Output.ContainsPoint and Output:ContainsPoint(MouseX, MouseY) then
        if Output.HandleWheel then Output:HandleWheel(Y) end
        return
    end

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
    elseif MouseX >= center.X and MouseX < PanelLeft and MouseY >= center.Y
        and (not L or not L.Output or MouseY < (L.Output.Y or 1e9)) then
        local Sp = rawget(_G, "StarterPlayer")
        local MinZ = (Sp and tonumber(Sp.CameraMinZoomDistance)) or 0.5
        local MaxZ = (Sp and tonumber(Sp.CameraMaxZoomDistance)) or 128
        if Runtime and Runtime:IsPlay() then
            local Step = Y * CameraZoomSpeed * 0.75
            PlayZoomTarget = math.max(MinZ, math.min(MaxZ, (PlayZoomTarget or 12) - Step))
        else
            CameraZoomSmooth = (CameraZoomSmooth or 0) + Y * CameraZoomSpeed
        end
    end
end

local Framerate = 0
local DeltaTime = 0
local ClientPing = 0
local PingTimer = 0

function love.update(Delta)
    Framerate = Fabric.Lerp(Framerate, 1 / Delta, Delta * 8)
    DeltaTime = Fabric.Lerp(DeltaTime, Delta, Delta * 8)

    if Dock and Dock.Tick then
        Dock:Tick(Delta)
    end
    if Ribbon and Ribbon.Tick then
        Ribbon:Tick(Delta)
    end
    if Explorer and Explorer.Tick then
        Explorer:Tick(Delta)
    end

    if Runtime and Runtime:IsPlay() then
        PingTimer = PingTimer + Delta
        if PingTimer >= 0.25 then
            PingTimer = 0
            local simulated = (DeltaTime * 1000) * 0.5 + (math.random() * 2.0)
            ClientPing = Fabric.Lerp(ClientPing, simulated, 0.35)
        end
    end

    if not CurrentCamera then
        return
    end

    local TextFocus = IsUiTextBusy()

    if Properties and Properties.Tick then
        Properties:Tick()
    end

    local opt = CurrentCamera:GetAttribute("_Opt")
    local targetFov = opt and 70 or 90
    CurrentCamera.FieldOfView = ClampFov(Fabric.Lerp(
        ClampFov(CurrentCamera.FieldOfView or 90),
        targetFov,
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

    if CameraZoomSmooth and math.abs(CameraZoomSmooth) > 0.0001 and not (Runtime and Runtime:IsPlay()) then
        local Z = CameraZoomSmooth
        CameraZoomSmooth = CameraZoomSmooth * math.max(0, 1 - Delta * 14)
        if math.abs(CameraZoomSmooth) < 0.01 then CameraZoomSmooth = 0 end
        TargetPosition[1] = TargetPosition[1] + Forward[1] * Z
        TargetPosition[2] = TargetPosition[2] + Forward[2] * Z
        TargetPosition[3] = TargetPosition[3] + Forward[3] * Z
    end

    if Runtime and Runtime:IsPlay() then
        PlayZoomDistance = Fabric.Lerp(PlayZoomDistance or 12, PlayZoomTarget or 12, Delta * 12)
    end

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

    if TextFocus or (Runtime and Runtime:IsPlay()) then
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
        _G.HoverPart = ResolveViewportTarget(Hit)
    else
        _G.HoverPart = nil
    end

    if Physics and Physics.Step and Runtime and not Runtime:IsEdit() and not Runtime:IsPaused() then
        Physics:Step(Delta)
    end

    do
        local fps = math.floor(Framerate + 0.5)
        local dtMs = DeltaTime * 1000
        local fpsStr = string.format("%04d", math.min(fps, 9999))
        local dtStr = string.format("%05.2f", math.min(dtMs, 999.99))
        local pingStr = "--"
        if Runtime and Runtime:IsPlay() then
            pingStr = string.format("%05.2f ms", math.min(ClientPing, 999.99))
        end
        local text = string.format("FPS %s  |  DT %s ms  |  Ping %s", fpsStr, dtStr, pingStr)
        _G.DiagnosticsText = text
        local label = _G.DiagLabel
        if label then
            label.Text = text
        end
    end

    if Runtime then
        Runtime:Tick(Delta)
        if Runtime:IsPlay() and not Runtime:IsPaused() and Runtime.CharacterParts then
            local moveX, moveZ = 0, 0
            local yaw = TargetRotation[2] or 0
            local Fwd = {math.sin(yaw), 0, -math.cos(yaw)}
            local Right = {math.cos(yaw), 0, math.sin(yaw)}
            if love.keyboard.isDown("w") then moveX = moveX + Fwd[1]; moveZ = moveZ + Fwd[3] end
            if love.keyboard.isDown("s") then moveX = moveX - Fwd[1]; moveZ = moveZ - Fwd[3] end
            if love.keyboard.isDown("d") then moveX = moveX + Right[1]; moveZ = moveZ + Right[3] end
            if love.keyboard.isDown("a") then moveX = moveX - Right[1]; moveZ = moveZ - Right[3] end
            local jump = love.keyboard.isDown("space")
            Runtime:MoveCharacter(Delta, moveX, moveZ, jump)
            local subject = Runtime.CharacterParts.Torso or Runtime.CharacterParts.HumanoidRootPart
            if subject then
                local pos = subject.Position
                if type(pos) == "table" and pos.ToArray then pos = pos:ToArray() end
                local px, py, pz = pos[1] or 0, pos[2] or 5, pos[3] or 0
                local camDist = 12
                local pitch = TargetRotation[1] or 0
                TargetPosition[1] = px - math.sin(yaw) * camDist * math.cos(pitch)
                TargetPosition[2] = py + 2 - math.sin(pitch) * camDist
                TargetPosition[3] = pz + math.cos(yaw) * camDist * math.cos(pitch)
            end
        end
    end
end

local ScreenGui = Instance.new("ScreenGui", CoreGui)
ScreenGui.Name = "ScreenGui"

local ToolsFrame = Instance.new("Frame", ScreenGui)
ToolsFrame.BackgroundColor = Theme.Get("MainBackground")
ToolsFrame.Name = "Tools"
ToolsFrame.ClipsDescendants = true
ToolsFrame.ClipDescendants = true

Tools:Init(ToolsFrame, { silent = true })
Ribbon:Init(ToolsFrame)

if Ribbon and Ribbon.GetHeight then
    Dock:SetTopHeight(Ribbon:GetHeight())
end
Dock:SetRightWidth(256)
Dock:SetLeftWidth(0)
Dock:SetBottomHeight(22)
Dock:SetContent("Top", ToolsFrame)

local DiagnosticsFrame = Instance.new("Frame", ScreenGui)
DiagnosticsFrame.Name = "Diagnostics"
DiagnosticsFrame.BackgroundColor = Color.FromRGBA(28, 28, 30)
DiagnosticsFrame.ClipsDescendants = true
DiagnosticsFrame.ClipDescendants = true

_G.DiagLabel = Instance.new("TextLabel", DiagnosticsFrame)
_G.DiagLabel.Name = "Stats"
_G.DiagLabel.Text = "FPS 0000  |  DT 00.00 ms  |  Ping --"
_G.DiagLabel.TextSize = 11
_G.DiagLabel.TextColor = Color.FromRGBA(180, 185, 195)
_G.DiagLabel.BackgroundColor = Color.FromRGBA(0, 0, 0, 0)
_G.DiagLabel.Position = UDim.New(0, 8, 0, 0)
_G.DiagLabel.Size = UDim.New(1, -16, 1, 0)
_G.DiagLabel.TextAlignment = {"Left", "Center"}
_G.DiagnosticsText = _G.DiagLabel.Text

Dock:SetContent("Bottom", DiagnosticsFrame)

local OutputFrame = Instance.new("Frame", ScreenGui)
OutputFrame.Name = "Output"
OutputFrame.BackgroundColor = Color.FromRGBA(30, 30, 32)
OutputFrame.ClipsDescendants = true
OutputFrame.ClipDescendants = true
OutputFrame.Visible = false
Output:Init(OutputFrame)
Dock:SetContent("Output", OutputFrame)
Dock:SetPanelVisible("Output", false)
Dock:SetOutputHeight(0)

do
    local OldPrint = Gui.Console.Print
    function Gui.Console:Print(...)
        if OldPrint then OldPrint(self, ...) end
        if Output and Output.Print then Output:Print(...) end
    end
    local OldDraw = Gui.Console.Draw
    function Gui.Console:Draw()
    end
end

local function HandleDockChromeClick(X, Y)
    local Slot, Action = Dock:HitFloatHeader(X, Y)
    if Slot then
        if Action == "close" then
            Dock:SetPanelVisible(Slot, false)
            return true
        elseif Action == "drag" then
            Dock:BeginFloatDrag(Slot, X, Y)
            return true
        end
    end
    Slot, Action = Dock:HitDockHeaderClose(X, Y)
    if Slot then
        Dock:SetPanelVisible(Slot, false)
        return true
    end
    return false
end

Ribbon:OnAction(function(Action, Tab)
    if Action == "Copy" then
        if Explorer and Explorer.CopySelected then Explorer:CopySelected() end
    elseif Action == "Paste" then
        if Explorer and Explorer.Paste then Explorer:Paste() end
    elseif Action == "Duplicate" then
        if Explorer and Explorer.DuplicateSelected then Explorer:DuplicateSelected() end
    elseif Action == "Part" then
        if Explorer and Explorer.InsertObject then
            local Parent = (Explorer.Selected and not Explorer.Selected:IsA("Script")) and Explorer.Selected or Workspace
            Explorer:InsertObject(Parent, "Part")
        end
    elseif Action == "Play" then
        if Runtime:IsPlay() and Runtime:IsPaused() then
            Runtime:Resume()
        elseif not Runtime:IsPlay() then
            Runtime:StartPlay(false)
        end
    elseif Action == "PlayHere" then
        if Runtime:IsPlay() and Runtime:IsPaused() then
            Runtime:Resume()
        else
            Runtime:StartPlay(true)
        end
    elseif Action == "Run" then
        if Runtime:IsRun() and Runtime:IsPaused() then
            Runtime:Resume()
        elseif not Runtime:IsRun() then
            Runtime:StartRun()
        end
    elseif Action == "Pause" then
        if Runtime and Runtime.TogglePause then
            Runtime:TogglePause()
        end
    elseif Action == "Stop" then
        Runtime:Stop()
        if Ribbon and Ribbon.RefreshMezzanine then Ribbon:RefreshMezzanine() end
    elseif Action == "Explorer" then
        Dock:TogglePanel("RightTop")
    elseif Action == "Properties" then
        Dock:TogglePanel("RightBottom")
    elseif Action == "Output" then
        if Output and Output.Toggle then
            Output:Toggle()
        else
            Dock:TogglePanel("Output")
        end
    elseif Action == "Client" then
        if Runtime then
            Runtime.ViewSide = "Client"
            if Runtime.IsEdit and Runtime:IsEdit() then
                Runtime:StartPlay(false)
            end
            if Output and Output.Print then Output:Print("[Testing] Client view") end
            if Gui and Gui.Console then Gui.Console:Print("[Testing] Client view") end
            if Ribbon and Ribbon.RefreshMezzanine then Ribbon:RefreshMezzanine() end
        end
    elseif Action == "Server" then
        if Runtime then
            Runtime.ViewSide = "Server"
            if Runtime.IsEdit and Runtime:IsEdit() then
                Runtime:StartRun()
            end
            if Output and Output.Print then Output:Print("[Testing] Server view") end
            if Gui and Gui.Console then Gui.Console:Print("[Testing] Server view") end
            if Ribbon and Ribbon.RefreshMezzanine then Ribbon:RefreshMezzanine() end
        end
    elseif Action == "Union" then
        if CSG and CSG.Union then CSG:Union() end
    elseif Action == "Separate" then
        if CSG and CSG.Separate then CSG:Separate() end
    end
end)

local ExplorerFrame = Instance.new("Frame", ScreenGui)
ExplorerFrame.BackgroundColor = Theme.Get("MainBackground")
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
ExplorerList.BackgroundColor = Theme.Get("MainBackground")
ExplorerList.Position = UDim.New(0, 0, 0, 17)
ExplorerList.Size = UDim.New(1, 0, 1, -17)
ExplorerList.ClipsDescendants = true
ExplorerList.ClipDescendants = true

local PropertiesFrame = Instance.new("Frame", ScreenGui)
PropertiesFrame.BackgroundColor = Theme.Get("MainBackground")
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
PropertiesList.BackgroundColor = Theme.Get("MainBackground")
PropertiesList.Position = UDim.New(0, 0, 0, 17)
PropertiesList.Size = UDim.New(1, 0, 1, -17)
PropertiesList.ClipsDescendants = true
PropertiesList.ClipDescendants = true

do
    if not rawget(_G, "StarterPlayer") and rawget(_G, "Game") then
        local Sp = Instance.new("StarterPlayer", _G.Game)
        Sp.Name = "StarterPlayer"
        _G.StarterPlayer = Sp
    end
    if _G.StarterPlayer then
        if not _G.StarterPlayer:FindFirstChild("StarterPlayerScripts") then
            local Sps = Instance.new("StarterPlayerScripts", _G.StarterPlayer)
            Sps.Name = "StarterPlayerScripts"
        end
        if not _G.StarterPlayer:FindFirstChild("StarterCharacterScripts") then
            local Scs = Instance.new("StarterCharacterScripts", _G.StarterPlayer)
            Scs.Name = "StarterCharacterScripts"
        end
        _G.StarterPlayerScripts = _G.StarterPlayer:FindFirstChild("StarterPlayerScripts")
        _G.StarterCharacterScripts = _G.StarterPlayer:FindFirstChild("StarterCharacterScripts")
    end
    if not rawget(_G, "Players") and rawget(_G, "Game") then
        local Pl = Instance.new("Players", _G.Game)
        Pl.Name = "Players"
        _G.Players = Pl
    end
end

Explorer:Init(ExplorerList, Game)
Properties:Init(PropertiesList)

Dock:SetContent("RightTop", ExplorerFrame)
Dock:SetContent("RightBottom", PropertiesFrame)

Explorer.OnSelect = function(Node, SelectedSet)
    Properties:Select(Node, SelectedSet)

    local HL = _G.SelectionHighlight
    if HL then
        if Node and (Node:IsA("BasePart") or Node:IsA("Model") or Node:IsA("Folder")) then
            HL.Adornee = Node
            HL.Enabled = true
        else
            HL.Adornee = nil
            HL.Enabled = false
        end
    end

    _G.SelectionSet = BuildSelectionSet(Node, SelectedSet)

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

    Dock:Apply()

    Gui:Render(StarterGui)
    Gui:Render(CoreGui)
    Gui:ClearClickFlag()
    if Ribbon and Ribbon.SyncToolColors then
        Ribbon:SyncToolColors()
    end
    Gui.Console:Draw()

    Dock:DrawSplitters()
    if Dock.DrawPanelChrome then
        Dock:DrawPanelChrome()
    end

    if Explorer and Explorer.DrawInsertMenu then
        Explorer:DrawInsertMenu()
    end
    if Explorer and Explorer.DrawDragGhost then
        Explorer:DrawDragGhost()
    end

    do
        local L = Dock and Dock.GetLayout and Dock:GetLayout()
        local bot = L and L.Bottom
        if bot and bot.H and bot.H > 0 then
            love.graphics.setColor(0.11, 0.11, 0.12, 1)
            love.graphics.rectangle("fill", bot.X, bot.Y, bot.W, bot.H)
            love.graphics.setColor(0.72, 0.74, 0.78, 1)
            local text = _G.DiagnosticsText or "FPS 0000  |  DT 00.00 ms  |  Ping --"
            pcall(love.graphics.print, text, bot.X + 8, bot.Y + math.max(2, (bot.H - 14) * 0.5))
        end
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