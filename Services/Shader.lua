local ShaderService = {}
local ShaderInstance = {}
ShaderInstance.__index = ShaderInstance

local Gui = require("Services.Gui")
local ShaderCache = {}

local function FlattenUniform(Value)
    if type(Value) ~= "table" then return Value end
    local IsFlat = true
    for I = 1, #Value do
        if type(Value[I]) == "table" then
            IsFlat = false
            break
        end
    end
    if IsFlat then return Value end

    local Flat = {}
    local function Traverse(Table)
        for I = 1, #Table do
            if type(Table[I]) == "table" then
                Traverse(Table[I])
            else
                table.insert(Flat, Table[I])
            end
        end
    end
    Traverse(Value)
    return Flat
end

function ShaderService.New(VertexPath, PixelPath)
    local Key = tostring(VertexPath) .. tostring(PixelPath)
    if ShaderCache[Key] then return ShaderCache[Key] end

    local Success, LoveProgram
    if PixelPath then
        Success, LoveProgram = pcall(love.graphics.newShader, VertexPath, PixelPath)
    else
        Success, LoveProgram = pcall(love.graphics.newShader, VertexPath)
    end

    if not Success then
        error(string.format("[Shader Error] Failed to compile graphics program:\n%s", tostring(LoveProgram)))
    end

    local Instance = setmetatable({
        _Program = LoveProgram,
        Uniforms = {}
    }, ShaderInstance)

    ShaderCache[Key] = Instance
    return Instance
end

function ShaderInstance:Bind()
    love.graphics.setShader(self._Program)
end

function ShaderInstance:Unbind()
    love.graphics.setShader()
end

function ShaderInstance:Send(UniformsTable)
    if not UniformsTable then return end

    for Name, Value in pairs(UniformsTable) do
        if self._Program:hasUniform(Name) then
            local CleanValue = FlattenUniform(Value)

            local Ok, Err = pcall(function()
                if type(CleanValue) == "table" and #CleanValue == 16 and (Name == "ViewProjection" or Name == "Model") then
                    self._Program:send(Name, "column", CleanValue)
                elseif type(CleanValue) == "table" and (Name == "EntityMat" or Name == "EntityCastShadow") then
                    local Padded = {}
                    for i = 1, 16 do
                        Padded[i] = CleanValue[i] or 0
                    end
                    self._Program:send(Name, unpack(Padded))
                else
                    self._Program:send(Name, CleanValue)
                end
            end)
            if not Ok then
                Gui.Console:Print(string.format("[Shader Warning] Failed to update uniform '%s': %s", Name, Err))
            end
        end
    end
end

return ShaderService