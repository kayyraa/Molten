local Color = require("Services.Color")
local UDim = require("Services.UDim")
local Instance = require("Services.Instance")
local Gui = require("Services.Gui")

local Tools = {}

Tools.Current = "Select"
Tools.OnToolChanged = nil

local ToolOrder = {"Select", "Move", "Scale", "Rotate"}
local ToolImages = {
    Select = "Assets/Decals/Select.png",
    Move = "Assets/Decals/Move.png",
    Scale = "Assets/Decals/Scale.png",
    Rotate = "Assets/Decals/Rotate.png",
}

-- Public so Ribbon / other UI can resolve icons
Tools.Images = ToolImages
Tools.Order = ToolOrder

function Tools:GetImage(name)
    return ToolImages[name]
end

function Tools:SetImage(name, path)
    if name and path then
        ToolImages[name] = path
    end
end

local Buttons = {}
local Frame

function Tools:SetTool(Name)
    if not ToolImages[Name] then
        return
    end
    self.Current = Name
    for ToolName, Btn in pairs(Buttons) do
        if ToolName == Name then
            Btn.BackgroundColor = Color.FromRGBA(53, 83, 143)
        else
            Btn.BackgroundColor = Color.FromRGBA(40, 40, 40)
        end
    end
    if self.OnToolChanged then
        self.OnToolChanged(Name)
    end
end

function Tools:GetTool()
    return self.Current
end

function Tools:Is(Name)
    return self.Current == Name
end

function Tools:Init(ParentFrame, opts)
    Frame = ParentFrame
    Buttons = {}
    opts = opts or {}
    -- When the Ribbon owns the visual toolbar, skip creating the old icon strip
    -- so we don't stack two rows of tools. Keyboard shortcuts still work.
    if opts.silent then
        return
    end

    for Index, Name in ipairs(ToolOrder) do
        local Btn = Instance.new("ImageLabel", ParentFrame)
        Btn.Name = Name .. "Tool"
        Btn.Position = UDim.New(0, 4 + (Index - 1) * (48 + 4), 0.5, 0)
        Btn.Size = UDim.FromOffset(48, 48)
        Btn.Anchor = {0, 0.5}
        Btn.Image = ToolImages[Name]
        Btn.ZIndex = 2
        Btn.BackgroundColor = Name == self.Current and Color.FromRGBA(53, 83, 143) or Color.FromRGBA(40, 40, 40)

        Btn.OnClick:Connect(function()
            Tools:SetTool(Name)
        end)

        Buttons[Name] = Btn
    end
end

function Tools:HandleKey(Key)
    if Key == "1" then
        self:SetTool("Select")
        return true
    elseif Key == "2" then
        self:SetTool("Move")
        return true
    elseif Key == "3" then
        self:SetTool("Scale")
        return true
    elseif Key == "4" then
        self:SetTool("Rotate")
        return true
    end
    return false
end

return Tools
