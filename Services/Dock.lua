local Theme = _G.Theme or require("Services.Theme")
local UDim = require("Services.UDim")
local Dock = {}

local SplitterW = 1
local HitPad = 3
local MinSide = 120
local MinCenterW = 200
local MinCenterH = 120
local MinTop = 40
local MinBottom = 0

Dock.TopH = 84
Dock.BottomH = 22
Dock.OutputH = 0
Dock.AnimOutputH = 0
Dock.TargetOutputH = 0
Dock.TweenSpeed = 14
Dock.LeftW = 0
Dock.RightW = 256

Dock.RightSplit = 0.55
Dock.MinRightPane = 80

Dock.PanelVisible = {
    RightTop = true,
    RightBottom = true,
    Left = false,
    Bottom = true,
    Output = false,
}

Dock.Floating = {}

local Drag = nil
local DragStart = 0
local DragStartSize = 0
local FloatDrag = nil

local Content = {
    Top = nil,
    Bottom = nil,
    Output = nil,
    Left = nil,
    RightTop = nil,
    RightBottom = nil,
    Center = nil,
}

function Dock:SetContent(Slot, Frame)
    if Content[Slot] ~= nil or Frame then
        Content[Slot] = Frame
    end
end

function Dock:GetContent(Slot)
    return Content[Slot]
end

function Dock:GetScreenSize()
    return love.graphics.getDimensions()
end

function Dock:IsPanelVisible(Slot)
    if self.Floating[Slot] then
        return true
    end
    if Slot == "Output" then
        return self.PanelVisible.Output == true
    end
    return self.PanelVisible[Slot] ~= false
end

function Dock:SetPanelVisible(Slot, Visible)
    self.PanelVisible[Slot] = Visible and true or false
    if not Visible then
        self.Floating[Slot] = nil
    end
    if Slot == "Output" then
        if Visible then
            if (self.TargetOutputH or 0) < 80 then
                self.TargetOutputH = 180
            end
            self.OutputH = self.TargetOutputH
        else
            self.TargetOutputH = 0
            self.OutputH = 0
        end
    end
    self:SyncRightWidth()
end

function Dock:TogglePanel(Slot)
    if self.Floating[Slot] then
        self.Floating[Slot] = nil
        self.PanelVisible[Slot] = true
        self:SyncRightWidth()
        return
    end
    if Slot == "Output" then
        local Vis = self.PanelVisible.Output == true
        self.PanelVisible.Output = not Vis
        if self.PanelVisible.Output then
            if (self.TargetOutputH or 0) < 80 then
                self.TargetOutputH = 180
            end
            self.OutputH = self.TargetOutputH
        else
            self.TargetOutputH = 0
            self.OutputH = 0
        end
        return
    end
    local Vis = self.PanelVisible[Slot] ~= false
    self.PanelVisible[Slot] = not Vis
    self:SyncRightWidth()
end

function Dock:FloatPanel(Slot, X, Y, W, H)
    local Frame = Content[Slot]
    if not Frame then return end
    local SW, SH = self:GetScreenSize()
    W = W or 280
    H = H or 320
    X = math.max(0, math.min(X or 80, SW - 40))
    Y = math.max(0, math.min(Y or 80, SH - 40))
    self.Floating[Slot] = {
        X = X,
        Y = Y,
        W = W,
        H = H,
    }
    self.PanelVisible[Slot] = false
    self:SyncRightWidth()
end

function Dock:DockPanel(Slot)
    if self.Floating[Slot] then
        self.Floating[Slot] = nil
        self.PanelVisible[Slot] = true
        self:SyncRightWidth()
    end
end

function Dock:SyncRightWidth()
    local TopVis = self.PanelVisible.RightTop ~= false and not self.Floating.RightTop
    local BotVis = self.PanelVisible.RightBottom ~= false and not self.Floating.RightBottom
    if not TopVis and not BotVis then
        if self._SavedRightW == nil then
            self._SavedRightW = self.RightW
        end
        self.RightW = 0
    else
        if self.RightW <= 0 then
            self.RightW = self._SavedRightW or 256
        end
        self._SavedRightW = self.RightW
    end
end

function Dock:GetLayout()
    local SW, SH = self:GetScreenSize()

    local BotH = math.max(MinBottom, math.min(self.BottomH, 40))
    if self.PanelVisible.Bottom == false then
        BotH = 0
    end
    local OutH = math.max(0, math.min(self.AnimOutputH or self.OutputH or 0, SH - MinCenterH - BotH - MinTop))
    if OutH < 1 then OutH = 0 end
    local TopH = math.max(MinTop, math.min(self.TopH, SH - MinCenterH - BotH - OutH))
    local LeftW = math.max(0, math.min(self.LeftW, SW - MinCenterW - self.RightW - SplitterW * 2))
    local RightW = math.max(0, math.min(self.RightW, SW - MinCenterW - LeftW - SplitterW * 2))

    local TopVis = self.PanelVisible.RightTop ~= false and not self.Floating.RightTop
    local BotVis = self.PanelVisible.RightBottom ~= false and not self.Floating.RightBottom
    if not TopVis and not BotVis then
        RightW = 0
    end

    local LeftSplit = (LeftW > 0) and SplitterW or 0
    local RightSplit = (RightW > 0) and SplitterW or 0
    local BotSplit = (BotH > 0) and SplitterW or 0

    local OutSplit = (OutH > 0) and SplitterW or 0
    local CenterX = LeftW + LeftSplit
    local CenterY = TopH
    local CenterW = SW - LeftW - LeftSplit - RightW - RightSplit
    local CenterH = SH - TopH - BotH - BotSplit - OutH - OutSplit

    if CenterW < MinCenterW then
        local Overflow = MinCenterW - CenterW
        if RightW > MinSide then
            local Take = math.min(Overflow, RightW - MinSide)
            RightW = RightW - Take
            Overflow = Overflow - Take
        end
        if Overflow > 0 and LeftW > MinSide then
            LeftW = math.max(MinSide, LeftW - Overflow)
        end
        CenterX = LeftW + LeftSplit
        CenterW = SW - LeftW - LeftSplit - RightW - RightSplit
    end

    local RightX = SW - RightW
    local RightY = TopH
    local RightH = SH - TopH - BotH

    local SplitY = RightY
    local ExpH, PropH = 0, 0
    if RightW > 0 and RightH > 0 then
        local Avail = RightH - SplitterW
        if TopVis and BotVis then
            ExpH = math.floor(Avail * self.RightSplit)
            ExpH = math.max(self.MinRightPane, math.min(ExpH, Avail - self.MinRightPane))
            PropH = Avail - ExpH
            SplitY = RightY + ExpH
        elseif TopVis then
            ExpH = Avail
            PropH = 0
            SplitY = RightY + ExpH
        elseif BotVis then
            ExpH = 0
            PropH = Avail
            SplitY = RightY
        end
    end

    return {
        Screen = { X = 0, Y = 0, W = SW, H = SH },
        Top = { X = 0, Y = 0, W = SW, H = TopH },
        Bottom = { X = 0, Y = SH - BotH, W = SW, H = BotH },
        Output = { X = CenterX, Y = CenterY + CenterH, W = CenterW, H = OutH },
        Left = { X = 0, Y = CenterY, W = LeftW, H = CenterH },
        Right = { X = RightX, Y = RightY, W = RightW, H = RightH },
        RightTop = { X = RightX, Y = RightY, W = RightW, H = ExpH },
        RightBottom = { X = RightX, Y = SplitY + ((TopVis and BotVis) and SplitterW or 0), W = RightW, H = PropH },
        Center = { X = CenterX, Y = CenterY, W = CenterW, H = CenterH },
        SplitLeft = LeftW > 0 and { X = LeftW, Y = CenterY, W = SplitterW, H = CenterH } or nil,
        SplitRight = RightW > 0 and { X = RightX - SplitterW, Y = RightY, W = SplitterW, H = RightH } or nil,
        SplitOutput = OutH > 0 and { X = CenterX, Y = CenterY + CenterH, W = CenterW, H = SplitterW } or nil,
        SplitBottom = BotH > 0 and { X = 0, Y = SH - BotH - (BotH > 0 and 0 or 0), W = SW, H = 0 } or nil,
        SplitRightInner = (RightW > 0 and ExpH > 0 and PropH > 0) and { X = RightX, Y = SplitY, W = RightW, H = SplitterW } or nil,
    }
end

function Dock:GetCenter()
    return self:GetLayout().Center
end

function Dock:GetTop()
    return self:GetLayout().Top
end

function Dock:GetRight()
    return self:GetLayout().Right
end

local function ApplyFrame(Frame, Rect, Visible)
    if not Frame then return end
    if Visible == false or not Rect or Rect.W <= 0 or Rect.H <= 0 then
        Frame.Visible = false
        return
    end
    Frame.Visible = true
    Frame.Position = UDim.New(0, Rect.X, 0, Rect.Y)
    Frame.Size = UDim.New(0, Rect.W, 0, Rect.H)
end

function Dock:Apply()
    local L = self:GetLayout()
    ApplyFrame(Content.Top, L.Top, true)
    ApplyFrame(Content.Bottom, L.Bottom, self.PanelVisible.Bottom ~= false)
    ApplyFrame(Content.Output, L.Output, (self.AnimOutputH or 0) > 1 or self.PanelVisible.Output == true)
    ApplyFrame(Content.Left, L.Left, true)

    if self.Floating.RightTop then
        local F = self.Floating.RightTop
        ApplyFrame(Content.RightTop, { X = F.X, Y = F.Y, W = F.W, H = F.H }, true)
    else
        ApplyFrame(Content.RightTop, L.RightTop, self.PanelVisible.RightTop ~= false)
    end

    if self.Floating.RightBottom then
        local F = self.Floating.RightBottom
        ApplyFrame(Content.RightBottom, { X = F.X, Y = F.Y, W = F.W, H = F.H }, true)
    else
        ApplyFrame(Content.RightBottom, L.RightBottom, self.PanelVisible.RightBottom ~= false)
    end
end

local function InRect(R, X, Y)
    return R and X >= R.X and X < R.X + R.W and Y >= R.Y and Y < R.Y + R.H
end

function Dock:Contains(Region, X, Y)
    local L = self:GetLayout()
    return InRect(L[Region], X, Y)
end

local function InflateRect(R, Pad, Axis)
    if not R then return nil end
    Pad = Pad or HitPad
    if Axis == "x" then
        return { X = R.X - Pad, Y = R.Y, W = R.W + Pad * 2, H = R.H }
    elseif Axis == "y" then
        return { X = R.X, Y = R.Y - Pad, W = R.W, H = R.H + Pad * 2 }
    end
    return { X = R.X - Pad, Y = R.Y - Pad, W = R.W + Pad * 2, H = R.H + Pad * 2 }
end

function Dock:HitSplitter(X, Y)
    local Modal = false
    pcall(function()
        local P = package.loaded["Services.Properties"] or _G.Properties
        if P and P.HasModal and P:HasModal() then Modal = true end
    end)
    if Modal then
        return nil
    end
    local L = self:GetLayout()
    if InRect(InflateRect(L.SplitRight, HitPad, "x"), X, Y) then return "right" end
    if InRect(InflateRect(L.SplitLeft, HitPad, "x"), X, Y) then return "left" end
    if InRect(InflateRect(L.SplitBottom, HitPad, "y"), X, Y) then return "bottom" end
    if InRect(InflateRect(L.SplitRightInner, HitPad, "y"), X, Y) then return "rightSplit" end
    if InRect(InflateRect(L.SplitOutput, HitPad, "y"), X, Y) then return "output" end
    return nil
end

function Dock:HitFloatHeader(X, Y)
    for Slot, F in pairs(self.Floating) do
        if F and Y >= F.Y and Y < F.Y + 17 and X >= F.X and X < F.X + F.W then
            local CloseX = F.X + F.W - 18
            if X >= CloseX then
                return Slot, "close"
            end
            return Slot, "drag"
        end
    end
    return nil
end

function Dock:HitDockHeaderClose(X, Y)
    local L = self:GetLayout()
    local function Check(Slot, Rect)
        if not Rect or Rect.W <= 0 or Rect.H <= 0 then return nil end
        if Y >= Rect.Y and Y < Rect.Y + 17 and X >= Rect.X + Rect.W - 18 and X < Rect.X + Rect.W then
            return Slot, "close"
        end
        return nil
    end
    if self.PanelVisible.RightTop ~= false and not self.Floating.RightTop then
        local S, A = Check("RightTop", L.RightTop)
        if S then return S, A end
    end
    if self.PanelVisible.RightBottom ~= false and not self.Floating.RightBottom then
        local S, A = Check("RightBottom", L.RightBottom)
        if S then return S, A end
    end
    return nil
end

function Dock:BeginResize(Which, MouseX, MouseY)
    if not Which then return false end
    Drag = Which
    if Which == "right" then
        DragStart = MouseX
        DragStartSize = self.RightW
    elseif Which == "left" then
        DragStart = MouseX
        DragStartSize = self.LeftW
    elseif Which == "bottom" then
        DragStart = MouseY
        DragStartSize = self.BottomH
    elseif Which == "output" then
        DragStart = MouseY
        DragStartSize = self.OutputH or 0
    elseif Which == "rightSplit" then
        DragStart = MouseY
        DragStartSize = self.RightSplit
    end
    return true
end

function Dock:BeginFloatDrag(Slot, MouseX, MouseY)
    local F = self.Floating[Slot]
    if not F then return false end
    FloatDrag = {
        Slot = Slot,
        OffsetX = MouseX - F.X,
        OffsetY = MouseY - F.Y,
    }
    return true
end

function Dock:UpdateResize(MouseX, MouseY)
    if FloatDrag then
        local F = self.Floating[FloatDrag.Slot]
        if F then
            local SW, SH = self:GetScreenSize()
            F.X = math.max(0, math.min(MouseX - FloatDrag.OffsetX, SW - 40))
            F.Y = math.max(0, math.min(MouseY - FloatDrag.OffsetY, SH - 40))
        end
        return true
    end
    if not Drag then return false end
    local SW, SH = self:GetScreenSize()
    local L = self:GetLayout()

    if Drag == "right" then
        local Delta = DragStart - MouseX
        local NewW = DragStartSize + Delta
        NewW = math.max(MinSide, math.min(NewW, SW - MinCenterW - self.LeftW - SplitterW * 2))
        self.RightW = math.floor(NewW + 0.5)
        self._SavedRightW = self.RightW
    elseif Drag == "left" then
        local Delta = MouseX - DragStart
        local NewW = DragStartSize + Delta
        NewW = math.max(0, math.min(NewW, SW - MinCenterW - self.RightW - SplitterW * 2))
        self.LeftW = math.floor(NewW + 0.5)
    elseif Drag == "bottom" then
        local Delta = DragStart - MouseY
        local NewH = DragStartSize + Delta
        NewH = math.max(0, math.min(NewH, SH - MinCenterH - self.TopH))
        self.BottomH = math.floor(NewH + 0.5)
    elseif Drag == "output" then
        local Delta = DragStart - MouseY
        local NewH = DragStartSize + Delta
        NewH = math.max(80, math.min(NewH, SH - MinCenterH - self.TopH - self.BottomH))
        self.OutputH = math.floor(NewH + 0.5)
        self.TargetOutputH = self.OutputH
        self.AnimOutputH = self.OutputH
        self.PanelVisible.Output = true
    elseif Drag == "rightSplit" then
        local RightH = L.Right.H
        if RightH > SplitterW + self.MinRightPane * 2 then
            local Rel = (MouseY - L.Right.Y) / (RightH - SplitterW)
            self.RightSplit = math.max(0.15, math.min(0.85, Rel))
        end
    end
    return true
end

function Dock:EndResize()
    local Was = Drag ~= nil or FloatDrag ~= nil
    Drag = nil
    FloatDrag = nil
    return Was
end

function Dock:IsResizing()
    return Drag ~= nil or FloatDrag ~= nil
end

function Dock:GetDragKind()
    return Drag
end

function Dock:CursorFor(X, Y)
    local Kind = Drag or self:HitSplitter(X, Y)
    if Kind == "left" or Kind == "right" then
        return "sizewe"
    elseif Kind == "bottom" or Kind == "rightSplit" or Kind == "output" then
        return "sizens"
    end
    return nil
end

function Dock:DrawSplitters()
    local Modal = false
    pcall(function()
        local P = package.loaded["Services.Properties"] or _G.Properties
        if P and P.HasModal and P:HasModal() then Modal = true end
    end)
    if Modal then
        return
    end
    local L = self:GetLayout()
    local Mx, My = love.mouse.getPosition()
    local Hover = self:HitSplitter(Mx, My)

    local function DrawSplit(Rect, Kind, Vertical)
        if not Rect or Rect.W <= 0 or Rect.H <= 0 then return end
        local Active = (Drag == Kind) or (Hover == Kind)
        if Active then
            local C = Theme.Get("SplitterHover")
            love.graphics.setColor(C[1], C[2], C[3], C[4] or 1)
        else
            local C = Theme.Get("Splitter")
            love.graphics.setColor(C[1], C[2], C[3], C[4] or 1)
        end
        if Vertical then
            local X = math.floor(Rect.X + Rect.W * 0.5)
            love.graphics.rectangle("fill", X, Rect.Y, 1, Rect.H)
        else
            local Y = math.floor(Rect.Y + Rect.H * 0.5)
            love.graphics.rectangle("fill", Rect.X, Y, Rect.W, 1)
        end
    end

    DrawSplit(L.SplitLeft, "left", true)
    DrawSplit(L.SplitRight, "right", true)
    DrawSplit(L.SplitBottom, "bottom", false)
    DrawSplit(L.SplitOutput, "output", false)
    DrawSplit(L.SplitRightInner, "rightSplit", false)
end

local CloseImage = nil
local function GetCloseImage()
    if CloseImage ~= nil then return CloseImage end
    local Ok, Img = pcall(love.graphics.newImage, "Assets/Decals/Close.png")
    if Ok and Img then
        CloseImage = Img
    else
        CloseImage = false
    end
    return CloseImage
end

function Dock:DrawPanelChrome()
    local function Chrome(Rect)
        if not Rect or Rect.W <= 0 then return end
        local Hx = Rect.X
        local Hy = Rect.Y
        local Hw = Rect.W
        local Img = GetCloseImage()
        local Cx = Hx + Hw - 16
        local Cy = Hy + 1
        if Img then
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(Img, Cx, Cy, 0, 14 / Img:getWidth(), 14 / Img:getHeight())
        else
            love.graphics.setColor(0.9, 0.45, 0.45, 1)
            love.graphics.print("X", Cx + 2, Cy + 1)
        end
    end

    local L = self:GetLayout()
    if self.PanelVisible.RightTop ~= false and not self.Floating.RightTop then
        Chrome(L.RightTop)
    end
    if self.PanelVisible.RightBottom ~= false and not self.Floating.RightBottom then
        Chrome(L.RightBottom)
    end
    for Slot, F in pairs(self.Floating) do
        if F then
            Chrome({ X = F.X, Y = F.Y, W = F.W, H = F.H })
            love.graphics.setColor(0.15, 0.15, 0.17, 1)
            love.graphics.rectangle("line", F.X, F.Y, F.W, F.H)
        end
    end
end

function Dock:SetTopHeight(H)
    self.TopH = math.max(MinTop, H or self.TopH)
end

function Dock:SetRightWidth(W)
    self.RightW = math.max(MinSide, W or self.RightW)
    self._SavedRightW = self.RightW
end

function Dock:SetLeftWidth(W)
    self.LeftW = math.max(0, W or self.LeftW)
end

function Dock:SetBottomHeight(H)
    self.BottomH = math.max(0, H or self.BottomH)
end

function Dock:SetOutputHeight(H)
    local V = math.max(0, H or self.OutputH or 0)
    self.OutputH = V
    self.TargetOutputH = V
end

function Dock:Tick(Dt)
    Dt = math.min(Dt or 0.016, 0.05)
    local Target = 0
    if self.PanelVisible.Output then
        Target = math.max(0, self.TargetOutputH or self.OutputH or 0)
        if Target < 80 and (self.OutputH or 0) >= 80 then
            Target = self.OutputH
        end
        if Target < 80 then
            Target = self.OutputH or 180
            self.TargetOutputH = Target
        end
    else
        Target = 0
    end
    local Cur = self.AnimOutputH or 0
    local Speed = self.TweenSpeed or 14
    local T = 1 - math.exp(-Speed * Dt)
    local Next = Cur + (Target - Cur) * T
    if math.abs(Next - Target) < 0.5 then
        Next = Target
    end
    self.AnimOutputH = Next
    self.OutputH = Target
end

Dock.SplitterWidth = SplitterW

_G.Dock = Dock
return Dock