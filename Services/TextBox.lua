local TextBox = {}
local Active = nil

local function ClampCursor(s)
    local len = #s.Buffer
    if s.Cursor < 1 then s.Cursor = 1 end
    if s.Cursor > len + 1 then s.Cursor = len + 1 end
end

local function FilterChar(ch, filter)
    if not filter or filter == "text" then return ch end
    if filter == "number" then
        if ch:match("[%d%.%-,%s]") then return ch end
        return ""
    end
    return ch
end

local function SplitLines(Source)
    local Lines = {}
    if Source == "" then
        return {""}
    end
    for Line in (Source .. "\n"):gmatch("(.-)\n") do
        Lines[#Lines + 1] = Line
    end
    if #Lines == 0 then
        Lines[1] = ""
    end
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

local function CursorFromLineCol(Lines, Line, Col)
    Line = math.max(1, math.min(#Lines, Line))
    local LineText = Lines[Line] or ""
    Col = math.max(1, math.min(#LineText + 1, Col))

    local Cursor = 1
    for I = 1, Line - 1 do
        Cursor = Cursor + #(Lines[I] or "") + 1
    end
    Cursor = Cursor + Col - 1

    return Cursor, Col
end

function TextBox.Begin(opts)
    opts = opts or {}
    Active = {
        id = opts.id or "default",
        Buffer = opts.text or "",
        Cursor = (opts.cursor or (#(opts.text or "") + 1)),
        SelectAll = opts.selectAll or false,
        Filter = opts.filter or "text",
        Multiline = opts.multiline or false,
        DesiredCol = nil,
        Tag = opts.tag,
        OnChange = opts.onChange,
        OnCommit = opts.onCommit,
        OnCancel = opts.onCancel,
        AutocompleteHandler = opts.autocompleteHandler,
    }
    ClampCursor(Active)
end

function TextBox.IsActive()
    return Active ~= nil
end

function TextBox.Get()
    return Active
end

function TextBox.End()
    Active = nil
end

local function Fire(s)
    if s.OnChange then
        pcall(s.OnChange, {Buffer = s.Buffer, Cursor = s.Cursor, SelectAll = s.SelectAll, Tag = s.Tag, id = s.id})
    end
end

function TextBox.HandleTextInput(Text)
    if not Active then return false end
    if not Text or Text == "" then return true end

    if Active.AutocompleteHandler and Active.AutocompleteHandler("textinput", Text) then
        return true
    end

    if Active.SelectAll then
        Active.Buffer = ""
        Active.Cursor = 1
        Active.SelectAll = false
    end
    if Active.Cursor < 1 then Active.Cursor = 1 end
    if Active.Cursor > #Active.Buffer + 1 then Active.Cursor = #Active.Buffer + 1 end
    local filtered = ""
    for i = 1, #Text do
        local c = Text:sub(i, i)
        filtered = filtered .. FilterChar(c, Active.Filter)
    end
    if filtered == "" then return true end
    local before = Active.Buffer:sub(1, Active.Cursor - 1)
    local after = Active.Buffer:sub(Active.Cursor)
    Active.Buffer = before .. filtered .. after
    Active.Cursor = Active.Cursor + #filtered
    Active.DesiredCol = nil
    Fire(Active)
    return true
end

function TextBox.HandleKey(Key)
    if not Active then return false end
    local s = Active

    if s.AutocompleteHandler and s.AutocompleteHandler("key", Key) then
        return true
    end

    if Key == "return" or Key == "kpenter" then
        if s.Multiline then
            if s.SelectAll then
                s.Buffer = ""
                s.Cursor = 1
                s.SelectAll = false
            end
            local before = s.Buffer:sub(1, s.Cursor - 1)
            local after = s.Buffer:sub(s.Cursor)
            s.Buffer = before .. "\n" .. after
            s.Cursor = s.Cursor + 1
            s.DesiredCol = nil
            Fire(s)
            return true
        end

        local cb = s.OnCommit
        local text = s.Buffer
        local copy = {Buffer = s.Buffer, Cursor = s.Cursor, SelectAll = s.SelectAll, Tag = s.Tag, id = s.id}
        Active = nil
        if cb then pcall(cb, text, copy) end
        return true

    elseif Key == "escape" then
        local cb = s.OnCancel
        Active = nil
        if cb then pcall(cb) end
        return true

    elseif Key == "left" then
        if s.SelectAll then s.SelectAll = false; s.Cursor = 1 else s.Cursor = math.max(1, s.Cursor - 1) end
        s.DesiredCol = nil
        Fire(s)
        return true

    elseif Key == "right" then
        if s.SelectAll then s.SelectAll = false; s.Cursor = #s.Buffer + 1 else s.Cursor = math.min(#s.Buffer + 1, s.Cursor + 1) end
        s.DesiredCol = nil
        Fire(s)
        return true

    elseif Key == "up" or Key == "down" then
        if not s.Multiline then
            return true
        end

        s.SelectAll = false

        local Lines = SplitLines(s.Buffer)
        local Line, Col = CursorLineCol(s.Buffer, s.Cursor)

        local TargetCol = s.DesiredCol or Col
        s.DesiredCol = TargetCol

        local TargetLine = Line + (Key == "up" and -1 or 1)
        if TargetLine < 1 or TargetLine > #Lines then
            return true
        end

        local NewCursor = CursorFromLineCol(Lines, TargetLine, TargetCol)
        s.Cursor = NewCursor
        Fire(s)
        return true

    elseif Key == "home" then
        s.SelectAll = false
        if s.Multiline then
            local _, Col = CursorLineCol(s.Buffer, s.Cursor)
            s.Cursor = s.Cursor - (Col - 1)
        else
            s.Cursor = 1
        end
        s.DesiredCol = nil
        Fire(s)
        return true

    elseif Key == "end" then
        s.SelectAll = false
        if s.Multiline then
            local Lines = SplitLines(s.Buffer)
            local Line = CursorLineCol(s.Buffer, s.Cursor)
            local Cursor = CursorFromLineCol(Lines, Line, #(Lines[Line] or "") + 1)
            s.Cursor = Cursor
        else
            s.Cursor = #s.Buffer + 1
        end
        s.DesiredCol = nil
        Fire(s)
        return true

    elseif Key == "backspace" then
        if s.SelectAll then
            s.Buffer = ""; s.Cursor = 1; s.SelectAll = false
        else
            if s.Cursor > 1 then
                s.Buffer = s.Buffer:sub(1, s.Cursor - 2) .. s.Buffer:sub(s.Cursor)
                s.Cursor = s.Cursor - 1
            end
        end
        s.DesiredCol = nil
        Fire(s)
        return true

    elseif Key == "delete" then
        if s.SelectAll then
            s.Buffer = ""; s.Cursor = 1; s.SelectAll = false
        else
            if s.Cursor <= #s.Buffer then
                s.Buffer = s.Buffer:sub(1, s.Cursor - 1) .. s.Buffer:sub(s.Cursor + 1)
            end
        end
        s.DesiredCol = nil
        Fire(s)
        return true

    elseif Key == "tab" then
        if s.Multiline then
            if s.SelectAll then
                s.Buffer = ""
                s.Cursor = 1
                s.SelectAll = false
            end
            local before = s.Buffer:sub(1, s.Cursor - 1)
            local after = s.Buffer:sub(s.Cursor)
            s.Buffer = before .. "    " .. after
            s.Cursor = s.Cursor + 4
            s.DesiredCol = nil
            Fire(s)
            return true
        end
    end

    return false
end


function TextBox.FormatDisplay(state)
    state = state or Active
    if not state then
        return ""
    end
    return state.Buffer or ""
end

function TextBox.GetCaretInfo(state)
    state = state or Active
    if not state then
        return false, 1, ""
    end
    local Buf = state.Buffer or ""
    local Cur = state.Cursor or (#Buf + 1)
    if Cur < 1 then Cur = 1 end
    if Cur > #Buf + 1 then Cur = #Buf + 1 end
    local Show = (math.floor(love.timer.getTime() * 2) % 2) == 0
    if state.SelectAll and #Buf > 0 then
        Show = true
    end
    return Show, Cur, Buf
end

function TextBox.Commit()
    if not Active then return false end
    local cb = Active.OnCommit
    local text = Active.Buffer
    local copy = {
        Buffer = Active.Buffer,
        Cursor = Active.Cursor,
        SelectAll = Active.SelectAll,
        Tag = Active.Tag,
        id = Active.id
    }
    Active = nil
    if cb then pcall(cb, text, copy) end
    return true
end

function TextBox.Cancel()
    if not Active then return false end
    local cb = Active.OnCancel
    Active = nil
    if cb then pcall(cb) end
    return true
end

TextBox.SplitLines = SplitLines
TextBox.CursorLineCol = CursorLineCol
TextBox.CursorFromLineCol = CursorFromLineCol

_G.TextBox = TextBox
return TextBox