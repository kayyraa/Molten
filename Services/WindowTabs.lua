local Color = require("Services.Color")
local ScriptEditor = require("Services.ScriptEditor")

local WindowTabs = {}

WindowTabs.Active = "Viewport"
WindowTabs.TabHeight = 24

local function TabLabel(Node)
    if not Node then
        return "Viewport"
    end
    local Name = Node.Name or Node.ClassName or "Script"
    if not Name:match("%.luau$") and not Name:match("%.lua$") then
        Name = Name .. ".luau"
    end
    return Name
end

function WindowTabs:IsViewport()
    return self.Active == "Viewport"
end

function WindowTabs:IsScript()
    return self.Active ~= "Viewport"
end

function WindowTabs:SelectViewport()
    self.Active = "Viewport"
    if ScriptEditor.SetFocused then
        ScriptEditor:SetFocused(false)
    end
    if TextBox and TextBox.IsActive and TextBox.IsActive() then
        local A = TextBox.Get and TextBox.Get()
        if A and A.id == "scripteditor" then
            if ScriptEditor.SyncFromTextBox then
                ScriptEditor:SyncFromTextBox()
            end
            TextBox.End()
        end
    end
end

function WindowTabs:SelectScript(Node)
    if not Node then
        return
    end
    ScriptEditor:Open(Node)
    self.Active = Node
end

function WindowTabs:CloseTab(Node)
    if Node == "Viewport" then
        return
    end
    ScriptEditor:Close(Node)
    if self.Active == Node then
        local Open = ScriptEditor:GetOpenList()
        if #Open > 0 then
            self.Active = Open[1]
            ScriptEditor:SetActive(Open[1])
        else
            self.Active = "Viewport"
        end
    end
end

function WindowTabs:GetTabs()
    local Tabs = {{Kind = "Viewport", Label = "Viewport", Node = nil}}
    local Open = ScriptEditor:GetOpenList()
    for _, Node in ipairs(Open) do
        Tabs[#Tabs + 1] = {
            Kind = "Script",
            Label = TabLabel(Node),
            Node = Node,
        }
    end
    return Tabs
end

function WindowTabs:Draw(X, Y, W)
    local H = self.TabHeight
    local Tabs = self:GetTabs()
    local TabW = math.min(160, math.max(80, math.floor((W - 8) / math.max(#Tabs, 1))))

    love.graphics.setColor(0.14, 0.14, 0.16, 1)
    love.graphics.rectangle("fill", X, Y, W, H)

    local Mx, My = love.mouse.getPosition()
    local CursorX = X + 4

    for _, Tab in ipairs(Tabs) do
        local Selected = (Tab.Kind == "Viewport" and self.Active == "Viewport")
            or (Tab.Node and self.Active == Tab.Node)

        local Tw = math.min(TabW, W - (CursorX - X) - 4)
        if Tw < 40 then
            break
        end

        local Hover = Mx >= CursorX and Mx <= CursorX + Tw and My >= Y and My <= Y + H

        if Selected then
            love.graphics.setColor(0.22, 0.28, 0.38, 1)
        elseif Hover then
            love.graphics.setColor(0.2, 0.2, 0.24, 1)
        else
            love.graphics.setColor(0.16, 0.16, 0.18, 1)
        end
        love.graphics.rectangle("fill", CursorX, Y + 2, Tw - 2, H - 2)

        if Selected then
            love.graphics.setColor(0.35, 0.55, 0.95, 1)
            love.graphics.rectangle("fill", CursorX, Y + H - 2, Tw - 2, 2)
        end

        love.graphics.setColor(Selected and 1 or 0.75, Selected and 1 or 0.75, Selected and 1 or 0.8, 1)
        local Label = Tab.Label
        if #Label > 18 then
            Label = Label:sub(1, 16) .. ".."
        end
        pcall(love.graphics.print, Label, CursorX + 8, Y + 6)

        if Tab.Kind == "Script" then
            local Cx = CursorX + Tw - 18
            local CloseHover = Mx >= Cx - 2 and Mx <= Cx + 12 and My >= Y + 4 and My <= Y + H - 4
            love.graphics.setColor(CloseHover and 1 or 0.6, CloseHover and 0.4 or 0.6, CloseHover and 0.4 or 0.65, 1)
            pcall(love.graphics.print, "x", Cx, Y + 5)
        end

        Tab._X = CursorX
        Tab._W = Tw - 2
        CursorX = CursorX + Tw
    end

    self._Layout = {X = X, Y = Y, W = W, H = H, Tabs = Tabs, TabW = TabW}
end

function WindowTabs:HandleClick(MouseX, MouseY)
    local L = self._Layout
    if not L then
        return false
    end
    if MouseY < L.Y or MouseY > L.Y + L.H or MouseX < L.X or MouseX > L.X + L.W then
        return false
    end

    for _, Tab in ipairs(L.Tabs) do
        if Tab._X and MouseX >= Tab._X and MouseX <= Tab._X + Tab._W then
            if Tab.Kind == "Script" then
                local Cx = Tab._X + Tab._W - 16
                if MouseX >= Cx - 2 then
                    self:CloseTab(Tab.Node)
                    return true
                end
                self:SelectScript(Tab.Node)
                return true
            else
                self:SelectViewport()
                return true
            end
        end
    end
    return true
end

function WindowTabs:OpenScript(Node)
    if not Node or not Node.IsA or not Node:IsA("Script") then
        return false
    end
    self:SelectScript(Node)
    return true
end

return WindowTabs