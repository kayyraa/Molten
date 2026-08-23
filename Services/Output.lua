local Color = require("Services.Color")
local UDim = require("Services.UDim")
local Instance = require("Services.Instance")
local Theme = _G.Theme or require("Services.Theme")

local Output = {}

Output.MaxLines = 500
Output.Lines = {}
Output.Scroll = 0
Output.Frame = nil
Output.ListFrame = nil
Output.OpenHeight = 180
Output.RowHeight = 16

local TypeColors = {
    Print = {0.85, 0.85, 0.90, 1},
    Info = {0.55, 0.75, 1.0, 1},
    Warn = {1.0, 0.78, 0.25, 1},
    Error = {1.0, 0.40, 0.40, 1},
    Message = {0.70, 0.70, 0.75, 1},
}

local function Timestamp()
    local T = os.date("*t")
    return string.format("%02d:%02d:%02d", T.hour or 0, T.min or 0, T.sec or 0)
end

function Output:Clear()
    self.Lines = {}
    self.Scroll = 0
    self:Refresh()
end

function Output:Append(Text, Kind, ColorOverride)
    Kind = Kind or "Print"
    local Entry = {
        Text = tostring(Text or ""),
        Kind = Kind,
        Color = ColorOverride or TypeColors[Kind] or TypeColors.Print,
        Time = Timestamp(),
    }
    self.Lines[#self.Lines + 1] = Entry
    while #self.Lines > self.MaxLines do
        table.remove(self.Lines, 1)
    end
    local Dock = package.loaded["Services.Dock"] or rawget(_G, "Dock")
    if Dock and Dock.IsPanelVisible and Dock:IsPanelVisible("Output") then
        self.Scroll = 0
        self:Refresh()
    end
end

function Output:Print(...)
    local Parts = {}
    for I = 1, select("#", ...) do
        local Arg = select(I, ...)
        if type(Arg) == "table" and Arg.Color then
        else
            Parts[#Parts + 1] = tostring(Arg)
        end
    end
    self:Append(table.concat(Parts, " "), "Print")
end

function Output:Warn(...)
    local Parts = {}
    for I = 1, select("#", ...) do
        Parts[#Parts + 1] = tostring(select(I, ...))
    end
    self:Append(table.concat(Parts, " "), "Warn")
end

function Output:Error(...)
    local Parts = {}
    for I = 1, select("#", ...) do
        Parts[#Parts + 1] = tostring(select(I, ...))
    end
    self:Append(table.concat(Parts, " "), "Error")
end

function Output:Info(...)
    local Parts = {}
    for I = 1, select("#", ...) do
        Parts[#Parts + 1] = tostring(select(I, ...))
    end
    self:Append(table.concat(Parts, " "), "Info")
end

function Output:HandleWheel(DeltaY)
    local Dock = package.loaded["Services.Dock"] or rawget(_G, "Dock")
    if not Dock or not Dock:IsPanelVisible("Output") then return false end
    local Visible = math.max(1, math.floor(((Dock.OutputH or 0) - 20) / self.RowHeight))
    local MaxScroll = math.max(0, #self.Lines - Visible)
    self.Scroll = math.max(0, math.min(MaxScroll, self.Scroll - DeltaY))
    self:Refresh()
    return true
end

function Output:ContainsPoint(Mx, My)
    local Dock = package.loaded["Services.Dock"] or rawget(_G, "Dock")
    if not Dock or not Dock:IsPanelVisible("Output") then return false end
    local L = Dock:GetLayout()
    local R = L.Output
    if not R or R.H <= 0 then return false end
    return Mx >= R.X and Mx < R.X + R.W and My >= R.Y and My < R.Y + R.H
end

function Output:Refresh()
    if not self.ListFrame then return end
    local Kids = rawget(self.ListFrame, "Children")
    if Kids then
        for I = #Kids, 1, -1 do
            if Kids[I] and Kids[I].Destroy then Kids[I]:Destroy() end
        end
    end

    local Dock = package.loaded["Services.Dock"] or rawget(_G, "Dock")
    local Visible = 12
    if Dock and Dock.OutputH then
        Visible = math.max(1, math.floor((Dock.OutputH - 20) / self.RowHeight))
    end
    local MaxScroll = math.max(0, #self.Lines - Visible)
    if self.Scroll > MaxScroll then self.Scroll = MaxScroll end

    local Start = math.max(1, #self.Lines - Visible - self.Scroll + 1)
    local End = math.min(#self.Lines, Start + Visible - 1)
    local Row = 0
    for I = Start, End do
        local Entry = self.Lines[I]
        if Entry then
            local Line = Instance.new("TextLabel", self.ListFrame)
            Line.Name = "Line_" .. I
            Line.Text = string.format("%s  %s", Entry.Time or "", Entry.Text or "")
            Line.TextSize = 12
            Line.TextColor = Entry.Color or TypeColors.Print
            Line.BackgroundColor = Color.FromRGBA(0, 0, 0, 0)
            Line.Position = UDim.New(0, 6, 0, Row * self.RowHeight)
            Line.Size = UDim.New(1, -12, 0, self.RowHeight)
            Line.TextAlignment = { "Left", "Center" }
            Row = Row + 1
        end
    end
end

function Output:Init(ParentFrame)
    self.Frame = ParentFrame
    ParentFrame.BackgroundColor = Color.FromRGBA(30, 30, 32)
    ParentFrame.ClipsDescendants = true
    ParentFrame.ClipDescendants = true

    local Header = Instance.new("TextLabel", ParentFrame)
    Header.Name = "Header"
    Header.Text = "Output"
    Header.Position = UDim.FromScale(0, 0)
    Header.Size = UDim.New(1, 0, 0, 18)
    Header.BackgroundColor = Color.FromRGBA(45, 45, 48)
    Header.TextColor = Color.FromRGBA(200, 200, 205)
    Header.TextAlignment = { "Left", "Center" }
    Header.TextSize = 12

    local HeaderPad = Instance.new("UiPadding", Header)
    HeaderPad.PaddingLeft = UDim.New(0, 8)

    local ClearBtn = Instance.new("Frame", ParentFrame)
    ClearBtn.Name = "Clear"
    ClearBtn.Position = UDim.New(1, -70, 0, 1)
    ClearBtn.Size = UDim.New(0, 52, 0, 16)
    ClearBtn.BackgroundColor = Color.FromRGBA(55, 55, 60)
    ClearBtn.ZIndex = 3
    ClearBtn.MouseCursor = "hand"

    local ClearLab = Instance.new("TextLabel", ClearBtn)
    ClearLab.Text = "Clear"
    ClearLab.TextSize = 11
    ClearLab.TextColor = Color.FromRGBA(200, 200, 210)
    ClearLab.BackgroundColor = Color.FromRGBA(0, 0, 0, 0)
    ClearLab.Position = UDim.FromScale(0, 0)
    ClearLab.Size = UDim.FromScale(1, 1)
    ClearLab.TextAlignment = { "Center", "Center" }
    ClearLab.ZIndex = 4

    ClearBtn.OnClick:Connect(function()
        Output:Clear()
    end)
    ClearBtn.OnEnter:Connect(function()
        ClearBtn.BackgroundColor = Color.FromRGBA(70, 70, 78)
    end)
    ClearBtn.OnLeave:Connect(function()
        ClearBtn.BackgroundColor = Color.FromRGBA(55, 55, 60)
    end)

    self.ListFrame = Instance.new("Frame", ParentFrame)
    self.ListFrame.Name = "List"
    self.ListFrame.BackgroundColor = Color.FromRGBA(30, 30, 32)
    self.ListFrame.Position = UDim.New(0, 0, 0, 18)
    self.ListFrame.Size = UDim.New(1, 0, 1, -18)
    self.ListFrame.ClipsDescendants = true
    self.ListFrame.ClipDescendants = true

    self:Refresh()
end

function Output:IsOpen()
    local Dock = package.loaded["Services.Dock"] or rawget(_G, "Dock")
    return Dock and Dock:IsPanelVisible("Output")
end

function Output:Open()
    local Dock = package.loaded["Services.Dock"] or rawget(_G, "Dock")
    if not Dock then return end
    if (Dock.TargetOutputH or 0) < 80 then
        Dock:SetOutputHeight(self.OpenHeight)
    end
    Dock:SetPanelVisible("Output", true)
    self:Refresh()
end

function Output:Close()
    local Dock = package.loaded["Services.Dock"] or rawget(_G, "Dock")
    if not Dock then return end
    Dock:SetPanelVisible("Output", false)
end

function Output:Toggle()
    if self:IsOpen() then
        self:Close()
    else
        self:Open()
    end
end

_G.Output = Output
return Output