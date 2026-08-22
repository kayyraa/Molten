local TextBox = require("Services.TextBox")
local Autocomplete = require("Services.Autocomplete")
local Instance = require("Services.Instance")
local Color = require("Services.Color")
local UDim = require("Services.UDim")
local Gui = require("Services.Gui")

local ScriptEditor = {}

local OpenScripts = {}
local ActiveScript = nil
local LineHeight = 18
local GutterWidth = 52
local Padding = 8
local Dirty = {}
local CharW = 7.2

-- ---------------------------------------------------------------------------
-- Syntax highlighting tables
-- ---------------------------------------------------------------------------
local Keywords = {
    ["and"] = true, ["break"] = true, ["do"] = true, ["else"] = true,
    ["elseif"] = true, ["end"] = true, ["false"] = true, ["for"] = true,
    ["function"] = true, ["if"] = true, ["in"] = true, ["local"] = true,
    ["nil"] = true, ["not"] = true, ["or"] = true, ["repeat"] = true,
    ["return"] = true, ["then"] = true, ["true"] = true, ["until"] = true,
    ["while"] = true, ["const"] = true, ["type"] = true, ["export"] = true,
    ["continue"] = true,
}

local Types = {
    ["number"] = true, ["string"] = true, ["boolean"] = true, ["table"] = true,
    ["thread"] = true, ["userdata"] = true, ["vector"] = true, ["buffer"] = true,
    ["any"] = true, ["unknown"] = true, ["never"] = true, ["nil"] = true,
}

local Colors = {
    Default   = {0.86, 0.87, 0.90, 1},
    Keyword   = {0.80, 0.50, 0.95, 1},
    Type      = {0.40, 0.85, 0.70, 1},
    String    = {0.82, 0.65, 0.42, 1},
    Comment   = {0.42, 0.55, 0.38, 1},
    Number    = {0.72, 0.82, 0.55, 1},
    Builtin   = {0.72, 0.58, 0.90, 1},
    Operator  = {0.70, 0.72, 0.78, 1},
    Gutter    = {0.75, 0.75, 0.85, 1},
    Cursor    = {0.95, 0.95, 1.0, 1},
    Selection = {0.22, 0.38, 0.62, 0.55},
}

local Builtins = {
    ["print"] = true, ["warn"] = true, ["error"] = true, ["assert"] = true,
    ["type"] = true, ["typeof"] = true, ["pairs"] = true, ["ipairs"] = true,
    ["next"] = true, ["pcall"] = true, ["xpcall"] = true, ["select"] = true,
    ["unpack"] = true, ["require"] = true, ["tonumber"] = true, ["tostring"] = true,
    ["setmetatable"] = true, ["getmetatable"] = true, ["rawget"] = true,
    ["rawset"] = true, ["rawequal"] = true, ["rawlen"] = true,
    ["math"] = true, ["string"] = true, ["table"] = true, ["coroutine"] = true,
    ["bit32"] = true, ["utf8"] = true, ["os"] = true, ["debug"] = true,
    ["buffer"] = true, ["vector"] = true, ["game"] = true, ["workspace"] = true,
    ["script"] = true,
}

local GlobalNames = {}
for _, g in ipairs(Autocomplete.Globals) do
    GlobalNames[g.Name] = g
end

-- ---------------------------------------------------------------------------
-- Utility functions
-- ---------------------------------------------------------------------------
local function SplitLines(Source)
    local Lines = {}
    if Source == "" then return {""} end
    for Line in (Source .. "\n"):gmatch("(.-)\n") do
        Lines[#Lines + 1] = Line
    end
    if #Lines == 0 then Lines[1] = "" end
    return Lines
end

local function CursorLineCol(Source, Cursor)
    local Line = 1
    local Col = 1
    local Limit = math.min(Cursor - 1, #Source)
    for I = 1, Limit do
        if Source:sub(I, I) == "\n" then
            Line = Line + 1
            Col = 1
        else
            Col = Col + 1
        end
    end
    return Line, Col
end

local function TokenizeLine(Line)
    local Tokens = {}
    local I = 1
    local Len = #Line
    while I <= Len do
        local C = Line:sub(I, I)
        if C == "-" and Line:sub(I + 1, I + 1) == "-" then
            Tokens[#Tokens + 1] = {Kind = "Comment", Text = Line:sub(I)}
            break
        elseif C == '"' or C == "'" or C == "`" then
            local Quote = C
            local J = I + 1
            while J <= Len do
                local Cj = Line:sub(J, J)
                if Cj == "\\" then
                    J = J + 2
                elseif Cj == Quote then
                    J = J + 1
                    break
                else
                    J = J + 1
                end
            end
            Tokens[#Tokens + 1] = {Kind = "String", Text = Line:sub(I, J - 1)}
            I = J
        elseif C:match("%d") then
            local J = I
            while J <= Len and Line:sub(J, J):match("[%w%.xX_]") do
                J = J + 1
            end
            Tokens[#Tokens + 1] = {Kind = "Number", Text = Line:sub(I, J - 1)}
            I = J
        elseif C:match("[%a_]") then
            local J = I
            while J <= Len and Line:sub(J, J):match("[%w_]") do
                J = J + 1
            end
            local Word = Line:sub(I, J - 1)
            local Kind = "Default"
            if Keywords[Word] then
                Kind = "Keyword"
            elseif Types[Word] then
                Kind = "Type"
            elseif Builtins[Word] then
                Kind = "Builtin"
            end
            Tokens[#Tokens + 1] = {Kind = Kind, Text = Word}
            I = J
        elseif C:match("[%+%-%*/%%%^=<>~#]") then
            local J = I
            while J <= Len and Line:sub(J, J):match("[%+%-%*/%%%^=<>~#%.]") do
                J = J + 1
            end
            Tokens[#Tokens + 1] = {Kind = "Operator", Text = Line:sub(I, J - 1)}
            I = J
        else
            Tokens[#Tokens + 1] = {Kind = "Default", Text = C}
            I = I + 1
        end
    end
    return Tokens
end

-- ---------------------------------------------------------------------------
-- Local variable tracking
-- ---------------------------------------------------------------------------
local function ParseLocalVariables(Source)
    local Locals = {}
    local Lines = SplitLines(Source)

    for _, Line in ipairs(Lines) do
        local Clean = Line:gsub("%-%-.*$", "")
        local Name, TypeHint = Clean:match("^%s*local%s+([%a_][%w_]*)%s*:%s*([%a_][%w_]*)")
        if not Name then
            Name = Clean:match("^%s*local%s+([%a_][%w_]*)")
        end
        if Name then
            local Init = Clean:match("^%s*local%s+" .. Name .. "%s*=%s*(.+)")
            local InferredType = nil
            if Init then
                local ClassName = Init:match('Instance%.new%("%s*([%w_]+)%s*")')
                if ClassName then
                    InferredType = ClassName
                elseif Init:match("^Vector3%.") then
                    InferredType = "Vector3"
                elseif Init:match("^CFrame%.") then
                    InferredType = "CFrame"
                elseif Init:match("^Color3%.") then
                    InferredType = "Color3"
                elseif Init:match("^Enum%.") then
                    InferredType = "Enum"
                else
                    for Global, _ in pairs(GlobalNames) do
                        if Init:match("^" .. Global .. "%.") then
                            InferredType = Global
                            break
                        end
                    end
                end
            end
            local FinalType = TypeHint or InferredType or "*Instance"
            Locals[Name] = FinalType
        end

        -- Function parameters
        local Params = Clean:match("^%s*function%s+[%a_][%w_]*%s*%((.*)%)")
        if Params then
            for Param in Params:gmatch("[^,]+") do
                local pName, pType = Param:match("^%s*([%a_][%w_]*)%s*:%s*([%a_][%w_]*)")
                if not pName then
                    pName = Param:match("^%s*([%a_][%w_]*)")
                    pType = "*Instance"
                end
                if pName then
                    Locals[pName] = pType
                end
            end
        end
    end
    return Locals
end

-- ---------------------------------------------------------------------------
-- Indentation / block completion helpers (Roblox Studio-like)
-- Only auto-insert "end"/"until" when the current line is a complete block
-- opener AND the cursor is at (or past) the end of that line, AND a simple
-- balance check shows the new block is still open.
-- ---------------------------------------------------------------------------
local function GetIndent(Line)
    return #Line:match("^%s*")
end

-- Returns the block keyword only when the line is a *complete* opener.
-- Incomplete lines (e.g. "if foo" without "then") do NOT trigger end insertion.
local function IsCompleteBlockStart(Line)
    local Clean = Line:gsub("%-%-.*$", ""):match("^%s*(.-)%s*$") or ""
    if Clean == "" then return nil end

    -- function name(...)  or  local function name(...)
    if Clean:match("^local%s+function%s+[%w_.:]+%s*%b()%s*$")
        or Clean:match("^function%s+[%w_.:]+%s*%b()%s*$")
        or Clean:match("^[%w_.:]+%s*=%s*function%s*%b()%s*$") then
        return "function"
    end
    -- if ... then
    if Clean:match("^if%s+.+%s+then%s*$") then return "if" end
    -- elseif ... then
    if Clean:match("^elseif%s+.+%s+then%s*$") then return "elseif" end
    -- else
    if Clean:match("^else%s*$") then return "else" end
    -- for ... do
    if Clean:match("^for%s+.+%s+do%s*$") then return "for" end
    -- while ... do
    if Clean:match("^while%s+.+%s+do%s*$") then return "while" end
    -- do
    if Clean:match("^do%s*$") then return "do" end
    -- repeat
    if Clean:match("^repeat%s*$") then return "repeat" end

    return nil
end

local function BlockEnd(Keyword)
    if Keyword == "repeat" then return "until" end
    return "end"
end

local function ShouldDedent(Line)
    local Clean = Line:gsub("%-%-.*$", "")
    return Clean:match("^%s*end%s*$") or Clean:match("^%s*until%s*$")
        or Clean:match("^%s*else%s*$") or Clean:match("^%s*elseif%s+")
end

-- Rough balance: count net open blocks from a slice of source.
-- Used so we don't keep stacking "end" when one already exists.
local function NetOpenBlocks(SourceSlice)
    local open = 0
    for line in (SourceSlice .. "\n"):gmatch("(.-)\n") do
        local c = line:gsub("%-%-.*$", "")
        if IsCompleteBlockStart(c) then
            local k = IsCompleteBlockStart(c)
            if k ~= "else" and k ~= "elseif" then
                open = open + 1
            end
        end
        if c:match("^%s*end%s*$") or c:match("^%s*end%s+") or c:match("^%s*until%s+") or c:match("^%s*until%s*$") then
            open = open - 1
        end
    end
    return open
end

local function OnlyWhitespace(s)
    return (s or ""):match("^%s*$") ~= nil
end

-- ---------------------------------------------------------------------------
-- ScriptEditor public API
-- ---------------------------------------------------------------------------
function ScriptEditor:IsOpen(Node)
    return OpenScripts[Node] ~= nil
end

function ScriptEditor:GetActive()
    return ActiveScript
end

function ScriptEditor:GetOpenList()
    local List = {}
    for Node, _ in pairs(OpenScripts) do
        List[#List + 1] = Node
    end
    table.sort(List, function(A, B)
        return tostring(A.Name) < tostring(B.Name)
    end)
    return List
end

function ScriptEditor:Open(Node)
    if not Node or not Node.IsA or not Node:IsA("Script") then
        return false
    end
    if not OpenScripts[Node] then
        OpenScripts[Node] = {
            Source = Node.Source or "",
            Cursor = 1,
            ScrollY = 0,
            Locals = {},
        }
        Dirty[Node] = false
    end
    ActiveScript = Node
    return true
end

function ScriptEditor:Close(Node)
    if not Node then return end
    if Dirty[Node] then
        local State = OpenScripts[Node]
        if State then
            Node.Source = State.Source
        end
    end
    OpenScripts[Node] = nil
    Dirty[Node] = nil
    if ActiveScript == Node then
        ActiveScript = nil
        local List = self:GetOpenList()
        if #List > 0 then
            ActiveScript = List[1]
        end
    end
end

function ScriptEditor:CloseActive()
    if ActiveScript then
        self:Close(ActiveScript)
    end
end

function ScriptEditor:SetActive(Node)
    if OpenScripts[Node] then
        ActiveScript = Node
        return true
    end
    return false
end

function ScriptEditor:IsEditing()
    if ActiveScript == nil then return false end
    if not TextBox.IsActive() then return false end
    local Active = TextBox.Get()
    return Active ~= nil and Active.id == "scripteditor"
end

function ScriptEditor:IsFocused()
    return self:IsEditing()
end

function ScriptEditor:SetFocused(focused)
    if not focused then
        if TextBox.IsActive and TextBox.IsActive() then
            local A = TextBox.Get and TextBox.Get()
            if A and A.id == "scripteditor" then
                self:SyncFromTextBox()
                TextBox.End()
            end
        end
        self:HidePopup()
    else
        self:BeginEdit()
    end
end

function ScriptEditor:SyncFromTextBox()
    if not ActiveScript then return end
    local State = OpenScripts[ActiveScript]
    if not State then return end
    if TextBox.IsActive and TextBox.IsActive() then
        local A = TextBox.Get and TextBox.Get()
        if A and A.id == "scripteditor" then
            State.Source = A.Buffer or State.Source
            State.Cursor = A.Cursor or State.Cursor
            Dirty[ActiveScript] = true
        end
    end
end

function ScriptEditor:SaveActive()
    if not ActiveScript then return false end
    local State = OpenScripts[ActiveScript]
    if not State then return false end
    ActiveScript.Source = State.Source
    Dirty[ActiveScript] = false
    return true
end

-- ---------------------------------------------------------------------------
-- Input handling
-- ---------------------------------------------------------------------------
function ScriptEditor:HandleTextInput(Text)
    if not ActiveScript then return false end
    if not TextBox.IsActive() then
        self:BeginEdit()
    end
    local A = TextBox.Get()
    if not A or A.id ~= "scripteditor" then
        return false
    end

    -- AutoΓÇæpairing
    local pairs = {
        ["("] = ")", ["["] = "]", ["{"] = "}", ['"'] = '"', ["'"] = "'",
    }
    if pairs[Text] then
        local Buffer = A.Buffer or ""
        local Cursor = A.Cursor or 1
        local NextChar = Buffer:sub(Cursor, Cursor)
        if NextChar == pairs[Text] then
            A.Cursor = Cursor + 1
            if A.onChange then A.onChange(A) end
            return true
        end
        A.Buffer = Buffer:sub(1, Cursor - 1) .. Text .. pairs[Text] .. Buffer:sub(Cursor)
        A.Cursor = Cursor + 1
        if A.onChange then A.onChange(A) end
        return true
    end

    return TextBox.HandleTextInput(Text)
end

function ScriptEditor:HandleKey(Key)
    if not ActiveScript then return false end

    if Key == "s" and (love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl")) then
        self:SaveActive()
        return true
    end

    local A = TextBox.Get()
    if not A or A.id ~= "scripteditor" then
        self:BeginEdit()
        A = TextBox.Get()
        if not A then return false end
    end

    -- Popup handling
    if self.Popup and self.Popup.Visible then
        if Key == "up" then
            self.Popup.SelectedIndex = math.max(1, self.Popup.SelectedIndex - 1)
            if self.Popup.SelectedIndex < self.Popup.ScrollOffset + 1 then
                self.Popup.ScrollOffset = math.max(0, self.Popup.ScrollOffset - 1)
            end
            return true
        elseif Key == "down" then
            self.Popup.SelectedIndex = math.min(#self.Popup.Entries, self.Popup.SelectedIndex + 1)
            if self.Popup.SelectedIndex > self.Popup.ScrollOffset + self.Popup.MaxVisible then
                self.Popup.ScrollOffset = self.Popup.SelectedIndex - self.Popup.MaxVisible
            end
            return true
        elseif Key == "return" or Key == "kpenter" or Key == "tab" then
            local entry = self.Popup.Entries[self.Popup.SelectedIndex]
            if entry then
                self:InsertCompletion(entry)
                return true
            end
        elseif Key == "escape" then
            self:HidePopup()
            return true
        elseif Key == "backspace" then
            self:UpdatePopupFilter()
            -- fall through to let TextBox handle deletion
        end
    end

    -- Enter: intelligent newline + indentation + safe block completion
    -- Matches Roblox Studio behaviour more closely:
    --   * Always insert a newline with proper indent.
    --   * Only auto-append "end"/"until" when:
    --       - the current line is a *complete* block opener
    --       - the cursor is at the end of that line (or only whitespace follows)
    --       - a balance check shows the new block still needs a closer
    --   * Never rewrite or delete existing text after the cursor.
    if Key == "return" or Key == "kpenter" then
        self:HidePopup()

        local Buffer = A.Buffer or ""
        local Cursor = A.Cursor or 1
        local Before = Buffer:sub(1, Cursor - 1)
        local After = Buffer:sub(Cursor)

        local LineStart = Before:match(".*\n()") or 1
        local LineText = Before:sub(LineStart)
        local baseIndent = GetIndent(LineText)
        local Indent = (" "):rep(baseIndent)

        local BlockType = IsCompleteBlockStart(LineText)
        local atEndOfLine = OnlyWhitespace(After:match("^[^\n]*") or "")

        local ExtraIndent = ""
        local ClosingKeyword = nil

        if BlockType and atEndOfLine then
            -- else / elseif re-use the same indent level; other openers go one level deeper
            if BlockType ~= "else" and BlockType ~= "elseif" then
                ExtraIndent = "    "
            end

            -- Only insert a closer if this newly opened block is still unbalanced
            -- relative to everything after the cursor (avoid stacking ends).
            local openAfter = NetOpenBlocks(After)
            if BlockType ~= "else" and BlockType ~= "elseif" and openAfter <= 0 then
                ClosingKeyword = BlockEnd(BlockType)
            end
        elseif ShouldDedent(LineText) and atEndOfLine then
            -- pressing enter on a bare "end" / "else" line keeps same indent
            ExtraIndent = ""
        end

        local NewLine = "\n" .. Indent .. ExtraIndent
        if ClosingKeyword then
            -- Structure:  <opener>\n<indent+4>|<cursor>\n<indent>end  + whatever was after cursor
            -- After is preserved exactly so we never delete or duplicate user text.
            local Closer = "\n" .. Indent .. ClosingKeyword
            A.Buffer = Before .. NewLine .. After .. Closer
            A.Cursor = Cursor + #NewLine
        else
            A.Buffer = Before .. NewLine .. After
            A.Cursor = Cursor + #NewLine
        end

        if A.onChange then
            A.onChange(A)
        end
        return true
    end

    return TextBox.HandleKey(Key)
end

function ScriptEditor:HandleWheel(DeltaY)
    -- If popup is visible and mouse is over it, scroll the popup
    if self.Popup and self.Popup.Visible then
        local mx, my = love.mouse.getPosition()
        local popupX, popupY = self:GetPopupPosition()
        local popupW = self.Popup.Width
        local entries = self.Popup.Entries
        local maxVisible = self.Popup.MaxVisible
        local numVisible = math.min(#entries - (self.Popup.ScrollOffset or 0), maxVisible)
        local popupH = numVisible * self.Popup.ItemHeight + 6
        if mx >= popupX and mx <= popupX + popupW and my >= popupY and my <= popupY + popupH then
            local maxScroll = math.max(0, #entries - maxVisible)
            self.Popup.ScrollOffset = math.max(0, math.min(maxScroll, (self.Popup.ScrollOffset or 0) - DeltaY))
            return true
        end
    end

    -- Otherwise handle editor scrolling
    if not ActiveScript then return false end
    local State = OpenScripts[ActiveScript]
    if not State then return false end
    local Lines = SplitLines(State.Source or "")
    local H = love.graphics.getHeight()
    local Visible = math.floor((H - 100) / LineHeight)
    local Max = math.max(0, #Lines - Visible)
    State.ScrollY = math.max(0, math.min(Max, (State.ScrollY or 0) - DeltaY * 3))
    return true
end

-- ---------------------------------------------------------------------------
-- Editing session management
-- ---------------------------------------------------------------------------
function ScriptEditor:BeginEdit()
    if not ActiveScript then return end
    local State = OpenScripts[ActiveScript]
    if not State then return end

    TextBox.Begin({
        id = "scripteditor",
        text = State.Source or "",
        filter = "multiline",
        multiline = true,
        selectAll = false,
        cursor = State.Cursor or 1,
        autocompleteHandler = function(event, data)
            return false
        end,
        onChange = function(S)
            State.Source = S.Buffer
            State.Cursor = S.Cursor
            Dirty[ActiveScript] = true

            State.Locals = ParseLocalVariables(S.Buffer)

            local Line = CursorLineCol(S.Buffer, S.Cursor)
            local Visible = math.floor((love.graphics.getHeight() - 100) / LineHeight)
            local Scroll = State.ScrollY or 0
            if Line - 1 < Scroll then
                State.ScrollY = math.max(0, Line - 1)
            elseif Line > Scroll + Visible then
                State.ScrollY = Line - Visible
            end

            self:CheckAutocomplete(S.Buffer, S.Cursor)
        end,
        onCommit = function(Text)
            State.Source = Text
            ActiveScript.Source = Text
            Dirty[ActiveScript] = false
            self:HidePopup()
        end,
        onCancel = function()
            self:HidePopup()
        end,
    })
end

-- ---------------------------------------------------------------------------
-- Autocomplete engine (supports both '.' and ':')
-- ---------------------------------------------------------------------------
function ScriptEditor:CheckAutocomplete(buffer, cursor)
    if not ActiveScript then
        self:HidePopup()
        return
    end

    local before = buffer:sub(1, cursor - 1)

    -- Look for '.' or ':' after a base identifier
    local base, trigger, afterDot = before:match("([%a_][%w_]*)%s*([.:])([%w_]*)$")
    if base and trigger then
        local members = nil
        local State = OpenScripts[ActiveScript]
        if State and State.Locals then
            local VarType = State.Locals[base]
            if VarType then
                if VarType == "Vector3" or VarType == "CFrame" or VarType == "Color3" or VarType == "Enum" then
                    members = Autocomplete.Members[VarType]
                else
                    members = Autocomplete.Members["*Instance"]
                end
            end
        end
        if not members then
            local global = GlobalNames[base]
            if global and global.Kind == "class" then
                if base == "Instance" or base == "Vector3" or base == "CFrame" or base == "Color3" or base == "Enum" then
                    members = Autocomplete.Members[base]
                elseif base == "Workspace" then
                    members = Autocomplete.Members["Workspace"]
                else
                    members = Autocomplete.Members["*Instance"]
                end
            end
        end
        if not members and Autocomplete.BasePartClasses and Autocomplete.BasePartClasses[base] then
            members = Autocomplete.Members["*BasePart"]
        end

        if members and #members > 0 then
            local filtered = {}
            for _, m in ipairs(members) do
                if m.Name:lower():find(afterDot:lower(), 1, true) then
                    -- Colon triggers prefer methods; if CallType is unset treat functions as methods
                    if trigger == ":" then
                        if m.Kind == "function" or m.CallType == "colon" or not m.CallType then
                            table.insert(filtered, m)
                        end
                    else
                        table.insert(filtered, m)
                    end
                end
            end
            if #filtered > 0 then
                local start = cursor - #afterDot
                self:ShowPopup(filtered, base, start, afterDot, trigger)
                return
            end
        end
        self:HidePopup()
        return
    end

    -- Global / local variable completion (no dot/colon)
    -- Require at least 2 characters so single-letter typing stays quiet.
    local word = before:match("([%a_][%w_]*)$")
    if word and #word >= 2 then
        local entries = {}
        local wl = word:lower()
        for _, g in ipairs(Autocomplete.Globals) do
            if g.Name:lower():sub(1, #wl) == wl or g.Name:lower():find(wl, 1, true) then
                table.insert(entries, g)
            end
        end
        local State = OpenScripts[ActiveScript]
        if State and State.Locals then
            for VarName, VarType in pairs(State.Locals) do
                if VarName:lower():find(wl, 1, true) then
                    table.insert(entries, {Name = VarName, Kind = "local", Detail = VarType})
                end
            end
        end
        -- Prefer prefix matches first
        table.sort(entries, function(a, b)
            local ap = a.Name:lower():sub(1, #wl) == wl
            local bp = b.Name:lower():sub(1, #wl) == wl
            if ap ~= bp then return ap end
            return a.Name:lower() < b.Name:lower()
        end)
        if #entries > 0 then
            local start = cursor - #word
            self:ShowPopup(entries, nil, start, word, nil)
            return
        end
    end
    self:HidePopup()
end

function ScriptEditor:ShowPopup(entries, triggerBase, startPos, filterText, triggerChar)
    local Popup = {
        Entries = entries,
        SelectedIndex = 1,
        TriggerBase = triggerBase,
        TriggerStart = startPos,
        Filter = filterText or "",
        TriggerChar = triggerChar,
        Visible = true,
        ScrollOffset = 0,
        MaxVisible = 10,
        ItemHeight = 20,
        Width = 260,
    }
    self.Popup = Popup
    self:UpdatePopupFilter()
end

function ScriptEditor:UpdatePopupFilter()
    if not self.Popup or not self.Popup.Visible then return end
    local A = TextBox.Get()
    if not A then return end
    local buffer = A.Buffer or ""
    local cursor = A.Cursor or 1
    local before = buffer:sub(1, cursor - 1)
    local filter = ""
    local trigger = self.Popup.TriggerChar
    if trigger then
        filter = before:match(".*[" .. trigger .. "]([%w_]*)$") or ""
    else
        filter = before:match("([%w_]*)$") or ""
    end
    self.Popup.Filter = filter
    local filtered = {}
    for _, m in ipairs(self.Popup.Entries) do
        if m.Name:lower():find(filter:lower(), 1, true) then
            table.insert(filtered, m)
        end
    end
    table.sort(filtered, function(a, b)
        return a.Name:lower() < b.Name:lower()
    end)
    self.Popup.Entries = filtered
    self.Popup.SelectedIndex = math.min(self.Popup.SelectedIndex, #filtered)
    if #filtered == 0 then
        self:HidePopup()
    else
        self.Popup.ScrollOffset = math.min(self.Popup.ScrollOffset, math.max(0, #filtered - self.Popup.MaxVisible))
    end
end

function ScriptEditor:InsertCompletion(entry)
    if not self.Popup or not self.Popup.Visible then return end
    local A = TextBox.Get()
    if not A then return end
    local buffer = A.Buffer or ""
    local cursor = A.Cursor or 1
    local start = self.Popup.TriggerStart or cursor
    -- Guard against stale start positions that would wipe the buffer
    if start < 1 or start > cursor then
        start = cursor
    end
    local before = buffer:sub(1, start - 1)
    local after = buffer:sub(cursor)
    local insertText = entry.Name or ""
    if entry.Kind == "function" then
        -- Don't double-insert "(" if the next char is already "("
        if after:sub(1, 1) ~= "(" then
            insertText = insertText .. "()"
            -- place cursor between the parens
            A.Buffer = before .. insertText .. after
            A.Cursor = start + #insertText - 1
        else
            A.Buffer = before .. insertText .. after
            A.Cursor = start + #insertText
        end
    else
        A.Buffer = before .. insertText .. after
        A.Cursor = start + #insertText
    end
    if A.onChange then
        A.onChange(A)
    end
    self:HidePopup()
end

function ScriptEditor:HidePopup()
    if self.Popup then
        self.Popup.Visible = false
        self.Popup = nil
    end
end

-- ---------------------------------------------------------------------------
-- Rendering
-- ---------------------------------------------------------------------------
function ScriptEditor:Draw(X, Y, W, H)
    if not ActiveScript then return end
    local State = OpenScripts[ActiveScript]
    if not State then return end

    love.graphics.setColor(0.11, 0.11, 0.13, 1)
    love.graphics.rectangle("fill", X, Y, W, H)

    local Source = State.Source or ""
    if TextBox.IsActive() then
        local A = TextBox.Get()
        if A and A.id == "scripteditor" then
            Source = A.Buffer
            State.Source = Source
            State.Cursor = A.Cursor
        end
    end

    local Lines = SplitLines(Source)
    local Scroll = State.ScrollY or 0
    local VisibleLines = math.floor((H - Padding * 2) / LineHeight)
    local StartLine = math.floor(Scroll) + 1
    local EndLine = math.min(#Lines, StartLine + VisibleLines)
    local Cursor = State.Cursor or 1
    local CurLine, CurCol = CursorLineCol(Source, Cursor)

    -- Draw gutter background
    love.graphics.setColor(0.14, 0.14, 0.16, 1)
    love.graphics.rectangle("fill", X, Y, GutterWidth, H)

    -- Draw line numbers (no scissor, so they appear in the gutter)
    for I = StartLine, EndLine do
        local Ly = Y + Padding + (I - StartLine) * LineHeight
        local Num = tostring(I)
        love.graphics.setColor(Colors.Gutter)
        pcall(love.graphics.print, Num, X + GutterWidth - 8 - #Num * 7, Ly)
    end

    -- Clip the code area (excluding gutter)
    love.graphics.setScissor(X + GutterWidth, Y, W - GutterWidth, H)

    for I = StartLine, EndLine do
        local Ly = Y + Padding + (I - StartLine) * LineHeight

        -- Highlight current line
        if I == CurLine and TextBox.IsActive() then
            love.graphics.setColor(0.16, 0.18, 0.24, 1)
            love.graphics.rectangle("fill", X + GutterWidth, Ly - 1, W - GutterWidth, LineHeight)
        end

        -- Syntax highlighting
        local Tokens = TokenizeLine(Lines[I] or "")
        local Tx = X + GutterWidth + Padding
        for _, Tok in ipairs(Tokens) do
            local Col = Colors[Tok.Kind] or Colors.Default
            love.graphics.setColor(Col[1], Col[2], Col[3], Col[4] or 1)
            pcall(love.graphics.print, Tok.Text, Tx, Ly)
            Tx = Tx + #Tok.Text * CharW
        end
    end

    -- Cursor
    if TextBox.IsActive() and CurLine >= StartLine and CurLine <= EndLine then
        local Blink = (math.floor(love.timer.getTime() * 2) % 2 == 0)
        if Blink then
            local Cx = X + GutterWidth + Padding + (CurCol - 1) * CharW
            local Cy = Y + Padding + (CurLine - StartLine) * LineHeight
            love.graphics.setColor(Colors.Cursor[1], Colors.Cursor[2], Colors.Cursor[3], Colors.Cursor[4] or 1)
            love.graphics.rectangle("fill", Cx, Cy, 2, LineHeight - 2)
        end
    end

    love.graphics.setScissor()

    -- Dirty indicator
    if Dirty[ActiveScript] then
        love.graphics.setColor(0.9, 0.7, 0.2, 1)
        pcall(love.graphics.print, "*", X + W - 18, Y + 4)
    end

    -- Autocomplete popup
    if self.Popup and self.Popup.Visible and #self.Popup.Entries > 0 then
        local popupX, popupY = self:GetPopupPosition()
        local itemH = self.Popup.ItemHeight
        local popupW = self.Popup.Width
        local entries = self.Popup.Entries
        local maxVisible = self.Popup.MaxVisible
        local scrollOff = self.Popup.ScrollOffset or 0
        local numVisible = math.min(#entries - scrollOff, maxVisible)
        local popupH = numVisible * itemH + 6
        local bg = {0.16, 0.16, 0.18, 0.95}
        love.graphics.setColor(bg[1], bg[2], bg[3], bg[4])
        love.graphics.rectangle("fill", popupX, popupY, popupW, popupH)
        love.graphics.setColor(0.3, 0.3, 0.35, 1)
        love.graphics.rectangle("line", popupX, popupY, popupW, popupH)

        love.graphics.setScissor(popupX + 1, popupY + 3, popupW - 2, numVisible * itemH)

        for i = 1, numVisible do
            local idx = i + scrollOff
            if idx > #entries then break end
            local entry = entries[idx]
            local yOff = popupY + 3 + (i - 1) * itemH
            if idx == self.Popup.SelectedIndex then
                love.graphics.setColor(0.0, 0.47, 0.84, 1)
                love.graphics.rectangle("fill", popupX + 1, yOff, popupW - 2, itemH)
            end
            love.graphics.setColor(1, 1, 1, 1)
            local label = entry.Name
            if entry.Kind then
                label = label .. " (" .. entry.Kind .. ")"
            end
            if entry.CallType == "colon" then
                label = label .. "  :"
            elseif entry.CallType == "dot" then
                label = label .. "  ."
            end
            local maxLabelWidth = popupW - 12
            local font = love.graphics.getFont()
            if font:getWidth(label) > maxLabelWidth then
                while #label > 3 and font:getWidth(label .. "ΓÇª") > maxLabelWidth do
                    label = label:sub(1, -2)
                end
                label = label .. "ΓÇª"
            end
            pcall(love.graphics.print, label, popupX + 6, yOff + 2)
        end

        love.graphics.setScissor()

        if #entries > maxVisible then
            local barH = math.max(10, popupH * (maxVisible / #entries))
            local barY = popupY + 3 + (popupH - 6 - barH) * (scrollOff / (#entries - maxVisible))
            love.graphics.setColor(0.5, 0.5, 0.5, 0.6)
            love.graphics.rectangle("fill", popupX + popupW - 6, barY, 4, barH)
        end
    end
end

function ScriptEditor:GetPopupPosition()
    local State = OpenScripts[ActiveScript]
    if not State then return 0, 0 end
    local Source = State.Source or ""
    local Cursor = State.Cursor or 1
    local Line, Col = CursorLineCol(Source, Cursor)
    local Scroll = State.ScrollY or 0
    local visibleLine = Line - math.floor(Scroll)
    local x = GutterWidth + Padding + (Col - 1) * CharW
    local y = Padding + (visibleLine - 1) * LineHeight
    return x + 4, y + LineHeight
end

function ScriptEditor:Click(X, Y, PanelX, PanelY, PanelW, PanelH)
    if not ActiveScript then return false end
    if X < PanelX or X > PanelX + PanelW or Y < PanelY or Y > PanelY + PanelH then
        return false
    end
    local State = OpenScripts[ActiveScript]
    if not State then return false end

    if self.Popup and self.Popup.Visible then
        local popupX, popupY = self:GetPopupPosition()
        local popupW = self.Popup.Width
        local itemH = self.Popup.ItemHeight
        local entries = self.Popup.Entries
        local maxVisible = self.Popup.MaxVisible
        local scrollOff = self.Popup.ScrollOffset or 0
        local numVisible = math.min(#entries - scrollOff, maxVisible)
        local popupH = numVisible * itemH + 6
        if X >= popupX and X <= popupX + popupW and Y >= popupY and Y <= popupY + popupH then
            local idx = math.floor((Y - popupY - 3) / itemH) + 1 + scrollOff
            if idx >= 1 and idx <= #entries then
                self.Popup.SelectedIndex = idx
                self:InsertCompletion(entries[idx])
                return true
            end
        end
    end

    local LocalY = Y - PanelY - Padding
    local LineIdx = math.floor(LocalY / LineHeight) + (State.ScrollY or 0) + 1
    local Lines = SplitLines(State.Source or "")
    LineIdx = math.max(1, math.min(#Lines, LineIdx))
    local LocalX = X - PanelX - GutterWidth - Padding
    local Col = math.max(1, math.floor(LocalX / CharW) + 1)
    local LineText = Lines[LineIdx] or ""
    Col = math.min(Col, #LineText + 1)
    local Cursor = 1
    for I = 1, LineIdx - 1 do
        Cursor = Cursor + #(Lines[I] or "") + 1
    end
    Cursor = Cursor + Col - 1
    State.Cursor = Cursor
    self:BeginEdit()
    local A = TextBox.Get()
    if A then
        A.Cursor = Cursor
        A.SelectAll = false
    end
    return true
end

return ScriptEditor