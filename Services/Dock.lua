local Dock = {}

local SplitterW = 4
local MinSide = 120
local MinCenterW = 200
local MinCenterH = 120
local MinTop = 40
local MinBottom = 0

-- Layout state (pixels)
Dock.TopH = 84
Dock.BottomH = 0
Dock.LeftW = 0
Dock.RightW = 256

-- Right column internal split: fraction of right-dock height given to Explorer
-- (rest goes to Properties). 0.55 ≈ Studio default.
Dock.RightSplit = 0.55
Dock.MinRightPane = 80

-- Active drag: "left" | "right" | "top" | "bottom" | "rightSplit" | nil
local Drag = nil
local DragStart = 0
local DragStartSize = 0

-- Registered content frames (optional; Dock only computes rects)
local Content = {
    Top = nil,
    Bottom = nil,
    Left = nil,
    RightTop = nil,    -- Explorer
    RightBottom = nil, -- Properties
    Center = nil,
}

function Dock:SetContent(slot, frame)
    if Content[slot] ~= nil or frame then
        Content[slot] = frame
    end
end

function Dock:GetContent(slot)
    return Content[slot]
end

-- ---------------------------------------------------------------------------
-- Geometry
-- ---------------------------------------------------------------------------

function Dock:GetScreenSize()
    return love.graphics.getDimensions()
end

--- Returns absolute pixel rects for every region.
--- Each rect is { X, Y, W, H }
function Dock:GetLayout()
    local SW, SH = self:GetScreenSize()

    local topH = math.max(MinTop, math.min(self.TopH, SH - MinCenterH - self.BottomH))
    local botH = math.max(MinBottom, math.min(self.BottomH, SH - topH - MinCenterH))
    local leftW = math.max(0, math.min(self.LeftW, SW - MinCenterW - self.RightW - SplitterW * 2))
    local rightW = math.max(0, math.min(self.RightW, SW - MinCenterW - leftW - SplitterW * 2))

    -- If a side is zero-width, hide its splitter contribution for center
    local leftSplit = (leftW > 0) and SplitterW or 0
    local rightSplit = (rightW > 0) and SplitterW or 0
    local botSplit = (botH > 0) and SplitterW or 0

    local centerX = leftW + leftSplit
    local centerY = topH
    local centerW = SW - leftW - leftSplit - rightW - rightSplit
    local centerH = SH - topH - botH - botSplit

    if centerW < MinCenterW then
        local overflow = MinCenterW - centerW
        if rightW > MinSide then
            local take = math.min(overflow, rightW - MinSide)
            rightW = rightW - take
            overflow = overflow - take
        end
        if overflow > 0 and leftW > MinSide then
            leftW = math.max(MinSide, leftW - overflow)
        end
        centerX = leftW + leftSplit
        centerW = SW - leftW - leftSplit - rightW - rightSplit
    end

    local rightX = SW - rightW
    local rightY = topH
    local rightH = centerH

    -- Internal right split
    local splitY = rightY
    local expH, propH = 0, 0
    if rightW > 0 and rightH > 0 then
        local avail = rightH - SplitterW
        expH = math.floor(avail * self.RightSplit)
        expH = math.max(self.MinRightPane, math.min(expH, avail - self.MinRightPane))
        propH = avail - expH
        splitY = rightY + expH
    end

    return {
        Screen = { X = 0, Y = 0, W = SW, H = SH },
        Top = { X = 0, Y = 0, W = SW, H = topH },
        Bottom = { X = 0, Y = SH - botH, W = SW, H = botH },
        Left = { X = 0, Y = centerY, W = leftW, H = centerH },
        Right = { X = rightX, Y = rightY, W = rightW, H = rightH },
        RightTop = { X = rightX, Y = rightY, W = rightW, H = expH },
        RightBottom = { X = rightX, Y = splitY + SplitterW, W = rightW, H = propH },
        Center = { X = centerX, Y = centerY, W = centerW, H = centerH },
        -- Splitter hit-rects
        SplitLeft = leftW > 0 and { X = leftW, Y = centerY, W = SplitterW, H = centerH } or nil,
        SplitRight = rightW > 0 and { X = rightX - SplitterW, Y = rightY, W = SplitterW, H = rightH } or nil,
        SplitBottom = botH > 0 and { X = centerX, Y = centerY + centerH, W = centerW, H = SplitterW } or nil,
        SplitRightInner = (rightW > 0 and expH > 0) and { X = rightX, Y = splitY, W = rightW, H = SplitterW } or nil,
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

-- ---------------------------------------------------------------------------
-- Apply layout to registered frames (UDim positions)
-- ---------------------------------------------------------------------------

local function ApplyFrame(frame, rect)
    if not frame or not rect then return end
    local UDim = require("Services.UDim")
    frame.Position = UDim.New(0, rect.X, 0, rect.Y)
    frame.Size = UDim.New(0, rect.W, 0, rect.H)
end

function Dock:Apply()
    local L = self:GetLayout()
    ApplyFrame(Content.Top, L.Top)
    ApplyFrame(Content.Bottom, L.Bottom)
    ApplyFrame(Content.Left, L.Left)
    ApplyFrame(Content.RightTop, L.RightTop)
    ApplyFrame(Content.RightBottom, L.RightBottom)
    -- Center is usually drawn manually (viewport / script), not a Frame
end

-- ---------------------------------------------------------------------------
-- Hit-testing helpers for other systems
-- ---------------------------------------------------------------------------

local function InRect(r, x, y)
    return r and x >= r.X and x < r.X + r.W and y >= r.Y and y < r.Y + r.H
end

function Dock:Contains(region, x, y)
    local L = self:GetLayout()
    return InRect(L[region], x, y)
end

function Dock:HitSplitter(x, y)
    local L = self:GetLayout()
    if InRect(L.SplitRight, x, y) then return "right" end
    if InRect(L.SplitLeft, x, y) then return "left" end
    if InRect(L.SplitBottom, x, y) then return "bottom" end
    if InRect(L.SplitRightInner, x, y) then return "rightSplit" end
    -- Top edge of center can resize top dock (grab bottom edge of top)
    local topEdge = { X = 0, Y = L.Top.H - 2, W = L.Screen.W, H = 4 }
    if InRect(topEdge, x, y) and L.Top.H > MinTop then return "top" end
    return nil
end

-- ---------------------------------------------------------------------------
-- Input: drag splitters
-- ---------------------------------------------------------------------------

function Dock:BeginResize(which, mouseX, mouseY)
    if not which then return false end
    Drag = which
    if which == "right" then
        DragStart = mouseX
        DragStartSize = self.RightW
    elseif which == "left" then
        DragStart = mouseX
        DragStartSize = self.LeftW
    elseif which == "top" then
        DragStart = mouseY
        DragStartSize = self.TopH
    elseif which == "bottom" then
        DragStart = mouseY
        DragStartSize = self.BottomH
    elseif which == "rightSplit" then
        DragStart = mouseY
        DragStartSize = self.RightSplit
    end
    return true
end

function Dock:UpdateResize(mouseX, mouseY)
    if not Drag then return false end
    local SW, SH = self:GetScreenSize()
    local L = self:GetLayout()

    if Drag == "right" then
        local delta = DragStart - mouseX
        local newW = DragStartSize + delta
        newW = math.max(MinSide, math.min(newW, SW - MinCenterW - self.LeftW - SplitterW * 2))
        self.RightW = math.floor(newW + 0.5)
    elseif Drag == "left" then
        local delta = mouseX - DragStart
        local newW = DragStartSize + delta
        newW = math.max(0, math.min(newW, SW - MinCenterW - self.RightW - SplitterW * 2))
        self.LeftW = math.floor(newW + 0.5)
    elseif Drag == "top" then
        local delta = mouseY - DragStart
        local newH = DragStartSize + delta
        newH = math.max(MinTop, math.min(newH, SH - MinCenterH - self.BottomH))
        self.TopH = math.floor(newH + 0.5)
    elseif Drag == "bottom" then
        local delta = DragStart - mouseY
        local newH = DragStartSize + delta
        newH = math.max(0, math.min(newH, SH - MinCenterH - self.TopH))
        self.BottomH = math.floor(newH + 0.5)
    elseif Drag == "rightSplit" then
        local rightH = L.Right.H
        if rightH > SplitterW + self.MinRightPane * 2 then
            local rel = (mouseY - L.Right.Y) / (rightH - SplitterW)
            self.RightSplit = math.max(0.15, math.min(0.85, rel))
        end
    end
    return true
end

function Dock:EndResize()
    local was = Drag ~= nil
    Drag = nil
    return was
end

function Dock:IsResizing()
    return Drag ~= nil
end

function Dock:GetDragKind()
    return Drag
end

-- ---------------------------------------------------------------------------
-- Cursor feedback
-- ---------------------------------------------------------------------------

function Dock:CursorFor(x, y)
    local kind = Drag or self:HitSplitter(x, y)
    if kind == "left" or kind == "right" then
        return "sizewe"
    elseif kind == "top" or kind == "bottom" or kind == "rightSplit" then
        return "sizens"
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Drawing splitters (subtle handles)
-- ---------------------------------------------------------------------------

function Dock:DrawSplitters()
    local L = self:GetLayout()
    local mx, my = love.mouse.getPosition()
    local hover = self:HitSplitter(mx, my)

    local function drawSplit(rect, kind, vertical)
        if not rect or rect.W <= 0 or rect.H <= 0 then return end
        local active = (Drag == kind) or (hover == kind)
        if active then
            love.graphics.setColor(0.35, 0.55, 0.95, 0.85)
        else
            love.graphics.setColor(0.18, 0.18, 0.20, 1)
        end
        love.graphics.rectangle("fill", rect.X, rect.Y, rect.W, rect.H)

        -- grip marks
        if active or hover == kind then
            love.graphics.setColor(0.75, 0.78, 0.90, 0.9)
            if vertical then
                local cx = rect.X + rect.W * 0.5
                local cy = rect.Y + rect.H * 0.5
                for i = -1, 1 do
                    love.graphics.rectangle("fill", cx - 0.5, cy + i * 6 - 1, 1, 3)
                end
            else
                local cx = rect.X + rect.W * 0.5
                local cy = rect.Y + rect.H * 0.5
                for i = -1, 1 do
                    love.graphics.rectangle("fill", cx + i * 6 - 1, cy - 0.5, 3, 1)
                end
            end
        end
    end

    drawSplit(L.SplitLeft, "left", true)
    drawSplit(L.SplitRight, "right", true)
    drawSplit(L.SplitBottom, "bottom", false)
    drawSplit(L.SplitRightInner, "rightSplit", false)
end

-- ---------------------------------------------------------------------------
-- Public size setters (for ribbon height sync etc.)
-- ---------------------------------------------------------------------------

function Dock:SetTopHeight(h)
    self.TopH = math.max(MinTop, h or self.TopH)
end

function Dock:SetRightWidth(w)
    self.RightW = math.max(MinSide, w or self.RightW)
end

function Dock:SetLeftWidth(w)
    self.LeftW = math.max(0, w or self.LeftW)
end

function Dock:SetBottomHeight(h)
    self.BottomH = math.max(0, h or self.BottomH)
end

-- Expose constants for other modules
Dock.SplitterWidth = SplitterW

_G.Dock = Dock
return Dock