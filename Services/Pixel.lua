local Pixel = {}

local ShaderService = require("Services.Shader")
local CFrame = require("Services.CFrame")
local Geometry = require("Services.Geometry")

local PixelShader = ShaderService.New("Shaders/Pixel.glsl")
local PostShader = ShaderService.New("Shaders/Post.glsl")

local TextureCache = {}
local DefaultTexture
local DefaultNormal
local SceneCanvas
local HistoryCanvas
local OutputCanvas
local CanvasW, CanvasH = 0, 0
local FrameIndex = 0
local PrevCamPos = {0, 0, 0}
local PrevCamFwd = {0, 0, 1}

Pixel.DenoiseStrength = 2
Pixel.FxaaQuality = 16.0

local function InitDefaults()
    if not DefaultTexture then
        local ImgData = love.image.newImageData(1, 1)
        ImgData:setPixel(0, 0, 1, 1, 1, 1)
        DefaultTexture = love.graphics.newImage(ImgData)
        DefaultTexture:setWrap("repeat", "repeat")
        DefaultTexture:setFilter("nearest", "nearest")
    end

    if not DefaultNormal then
        local ImgData = love.image.newImageData(1, 1)
        ImgData:setPixel(0, 0, 0.5, 0.5, 1, 1)
        DefaultNormal = love.graphics.newImage(ImgData)
        DefaultNormal:setWrap("repeat", "repeat")
        DefaultNormal:setFilter("nearest", "nearest")
    end
end

local function EnsureCanvas(Width, Height)
    if SceneCanvas and CanvasW == Width and CanvasH == Height then
        return SceneCanvas
    end

    local function tryCanvas(fmt)
        local ok, c = pcall(love.graphics.newCanvas, Width, Height, {format = fmt})
        if ok and c then
            c:setFilter("linear", "linear")
            return c
        end
        return nil
    end

    SceneCanvas = tryCanvas("rgba16f") or tryCanvas("rgba8") or love.graphics.newCanvas(Width, Height)
    SceneCanvas:setFilter("linear", "linear")
    HistoryCanvas = tryCanvas("rgba16f") or tryCanvas("rgba8") or love.graphics.newCanvas(Width, Height)
    HistoryCanvas:setFilter("linear", "linear")
    OutputCanvas = tryCanvas("rgba16f") or tryCanvas("rgba8") or love.graphics.newCanvas(Width, Height)
    OutputCanvas:setFilter("linear", "linear")
    love.graphics.setCanvas(HistoryCanvas)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.setCanvas()
    CanvasW, CanvasH = Width, Height

    return SceneCanvas
end

local function GetOrientationRad(Child)
    local raw = Child.Orientation
        or (Child.GetAttribute and Child:GetAttribute("Orientation"))
        or Child.Rotation
        or (Child.GetAttribute and Child:GetAttribute("Rotation"))

    if raw then
        local arr = nil

        if type(raw) == "table" and raw.ToArray then
            arr = raw:ToArray()
        elseif type(raw) == "table" and raw.Px then
            arr = {raw.Px, raw.Py, raw.Pz}
        else
            arr = raw
        end

        if type(arr) == "table" then
            local x = tonumber(arr[1]) or 0
            local y = tonumber(arr[2]) or 0
            local z = tonumber(arr[3]) or 0

            -- auto-detect degrees vs radians: if any abs > 2pi, assume degrees
            if math.abs(x) > 6.2831853 or math.abs(y) > 6.2831853 or math.abs(z) > 6.2831853 then
                x = math.rad(x)
                y = math.rad(y)
                z = math.rad(z)
            end

            return {x, y, z}
        end
    end

    -- Try CFrame with Euler extraction (if CFrame has Rotation)
    local cf = Child.CFrame or (Child.GetAttribute and Child:GetAttribute("CFrame"))
    if cf and type(cf) == "table" then
        if cf.ToEulerAnglesYXZ then
            local rx, ry, rz = cf:ToEulerAnglesYXZ()
            return {rx or 0, ry or 0, rz or 0}
        end

        if cf.Orientation then
            local o = cf.Orientation
            local arr = o.ToArray and o:ToArray() or o
            if arr then
                local x = math.rad(arr[1] or 0)
                local y = math.rad(arr[2] or 0)
                local z = math.rad(arr[3] or 0)
                return {x, y, z}
            end
        end
    end

    return {0, 0, 0}
end

-- ---------------------------------------------------------------------------
-- Pixel.Render
-- ---------------------------------------------------------------------------

function Pixel.Render(Camera)
    InitDefaults()

    local Width, Height = love.graphics.getDimensions()
    local Fov = Camera:GetAttribute("Fov")
    local Position = Camera:GetAttribute("Position")
    local Rotation = Camera:GetAttribute("Rotation")

    local Cf = CFrame.FromPositionRotation(Position, Rotation[1], Rotation[2])

    local Boxes = {}
    local TextureSlots = {DefaultTexture, DefaultNormal}
    local TexturePathMap = {}
    TexturePathMap["__default_white"] = 0
    TexturePathMap["__default_normal"] = 1

    local function GetOrAddTexture(Path, defaultIndex)
        if not Path or Path == "" then
            return defaultIndex or 0
        end
        if TexturePathMap[Path] then
            return TexturePathMap[Path]
        end

        if TextureCache[Path] then
            local Img = TextureCache[Path]
            if #TextureSlots < 16 then
                table.insert(TextureSlots, Img)
                local Idx = #TextureSlots - 1
                TexturePathMap[Path] = Idx
                return Idx
            end
        end

        local Success, Img = pcall(love.graphics.newImage, Path)
        if Success then
            Img:setWrap("repeat", "repeat")
            Img:setFilter("nearest", "nearest")
            TextureCache[Path] = Img

            if #TextureSlots < 16 then
                table.insert(TextureSlots, Img)
                local Idx = #TextureSlots - 1
                TexturePathMap[Path] = Idx
                return Idx
            end
        end

        return defaultIndex or 0
    end

    local function ToRgbColor(ColRaw)
        if not ColRaw then
            return {1, 1, 1}
        end

        local Col = ColRaw
        if type(Col) == "table" and Col[1] and Col[1] > 1 then
            Col = {Col[1] / 255, Col[2] / 255, Col[3] / 255}
        end

        return {Col[1] or 1, Col[2] or 1, Col[3] or 1}
    end

    local STREAM_MAX = 16
    local STREAM_BASE_DIST = 400
    local CamPos = Cf.Position
    local Candidates = {}

    -- -----------------------------------------------------------------------
    -- Collect part candidates
    -- -----------------------------------------------------------------------

    for _, Child in ipairs(Workspace:GetChildren()) do
        if Child:IsA("Part") then
            local PosRaw = Child.Position or Child:GetAttribute("Position")
            local Pos = type(PosRaw) == "table" and PosRaw.ToArray and PosRaw:ToArray() or PosRaw

            local SizeRaw = Child.Size or Child:GetAttribute("Size")
            local Size = type(SizeRaw) == "table" and SizeRaw.ToArray and SizeRaw:ToArray() or SizeRaw

            local Transparency = Child.Transparency or Child:GetAttribute("Transparency") or 0
            if type(Transparency) ~= "number" then
                Transparency = 0
            end
            Transparency = math.max(0, math.min(1, Transparency))
            if Transparency >= 0.999 then
                goto continue_part
            end

            local Dx = (Pos[1] or 0) - CamPos[1]
            local Dy = (Pos[2] or 0) - CamPos[2]
            local Dz = (Pos[3] or 0) - CamPos[3]
            local Dist = math.sqrt(Dx * Dx + Dy * Dy + Dz * Dz)

            local Extent = 0.5 * math.sqrt((Size[1] or 1) ^ 2 + (Size[2] or 1) ^ 2 + (Size[3] or 1) ^ 2)
            local MaxDist = STREAM_BASE_DIST + Extent * 2.0
            if Dist > 4.0 and Dist - Extent > MaxDist then
                goto continue_part
            end

            local Col = ToRgbColor(Child.Color or Child:GetAttribute("Color"))
            local Mat = Child.Material or Child:GetAttribute("Material") or {}
            local ColorTexIndex = GetOrAddTexture(Mat.Color, 0)
            local NormalTexIndex = GetOrAddTexture(Mat.Normal, 1)

            local Roughness = Mat.Roughness or Child:GetAttribute("Roughness") or 0.5
            local Reflectivity = Mat.Reflectivity or Child:GetAttribute("Reflectivity") or 0
            local Refractivity = Mat.Refractivity or Child:GetAttribute("Refractivity") or 0

            if type(Roughness) == "number" then
                Roughness = math.max(0, math.min(1, Roughness))
            else
                Roughness = 0.5
            end
            if type(Reflectivity) == "number" then
                Reflectivity = math.max(0, math.min(1, Reflectivity))
            else
                Reflectivity = 0
            end
            if type(Refractivity) == "number" then
                Refractivity = math.max(0, math.min(1, Refractivity))
            else
                Refractivity = 0
            end

            local HasDecal = 0
            local UvStuds = {16, 16}
            local UvOffset = {0, 0}
            local DecalTexIndex = 0
            local DecalColor = {1, 1, 1}

            local Decal = Child:GetChildrenOfClass("Decal")[1]
            if not Decal then
                Decal = Child:GetChildrenOfClass("Texture")[1]
            end

            local DecalAlpha = 1
            if Decal then
                HasDecal = 1

                if Decal.UvStuds then
                    UvStuds = Decal.UvStuds
                end
                if Decal.UvOffset then
                    local uo = Decal.UvOffset
                    if type(uo) == "table" then
                        UvOffset = {uo[1] or 0, uo[2] or 0}
                    end
                end
                if Decal.Texture and Decal.Texture ~= "" then
                    DecalTexIndex = GetOrAddTexture(Decal.Texture, 0)
                end

                local Dc = Decal.Color or Decal:GetAttribute("Color")
                if Dc then
                    DecalColor = ToRgbColor(Dc)
                end

                local DT = Decal.Transparency
                if type(DT) == "number" then
                    DecalAlpha = 1 - math.max(0, math.min(1, DT))
                end
            end

            local ShapeRaw = Child.Shape or Child:GetAttribute("Shape") or "Block"
            local ShapeType = 0

            if type(ShapeRaw) == "string" then
                local S = string.lower(ShapeRaw)
                if S == "sphere" or S == "ball" then
                    ShapeType = 1
                elseif S == "cylinder" then
                    ShapeType = 2
                elseif S == "wedge" then
                    ShapeType = 3
                elseif S == "cone" then
                    ShapeType = 4
                elseif S == "cornerwedge" then
                    ShapeType = 5
                end
            end

            local IsHighlighted = 0
            do
                local SelSet = _G.SelectionSet
                local HL = _G.SelectionHighlight

                if SelSet and SelSet[Child] then
                    IsHighlighted = 1
                elseif HL and HL.Enabled ~= false and HL.Adornee == Child then
                    IsHighlighted = 1
                elseif _G.HoverPart == Child and Child.Locked ~= true then
                    IsHighlighted = 1
                end
            end

            local RankDist = Dist - Extent
            if Dist < 50 then
                RankDist = RankDist - 1000
            elseif Dist < 120 then
                RankDist = RankDist - 200
            end

            local Orient = GetOrientationRad(Child)

            table.insert(Candidates, {
                Dist = RankDist,
                Position = {Pos[1], Pos[2], Pos[3]},
                Size = {Size[1], Size[2], Size[3]},
                Orientation = Orient,
                Color = {Col[1], Col[2], Col[3]},
                HasDecal = HasDecal,
                UvStuds = UvStuds,
                UvOffset = UvOffset,
                ColorTexIndex = ColorTexIndex,
                NormalTexIndex = NormalTexIndex,
                DecalTexIndex = DecalTexIndex,
                DecalColor = DecalColor,
                DecalAlpha = DecalAlpha,
                Roughness = Roughness,
                Reflectivity = Reflectivity,
                Refractivity = Refractivity,
                Transparency = Transparency,
                ShapeType = ShapeType,
                IsHighlighted = IsHighlighted,
                AlwaysOnTop = 0,
                CastShadows = 1,
                TriStart = -1,
                TriCount = 0,
                _Part = Child
            })

            ::continue_part::
        end
    end

    -- -----------------------------------------------------------------------
    -- Editor-only adornments (attachments, handle adornments)
    -- -----------------------------------------------------------------------

    local function ToPos3(v)
        if not v then
            return 0, 0, 0
        end
        if type(v) == "table" and v.ToArray then
            v = v:ToArray()
        end
        if type(v) == "table" then
            return tonumber(v[1]) or 0, tonumber(v[2]) or 0, tonumber(v[3]) or 0
        end
        return 0, 0, 0
    end

    local function WorldPosOf(Node)
        if not Node then
            return 0, 0, 0
        end

        local lx, ly, lz = ToPos3(Node.Position or (Node.GetAttribute and Node:GetAttribute("Position")))
        local Parent = rawget(Node, "_Parent") or Node.Parent
        if not Parent then
            return lx, ly, lz
        end

        if Parent.IsA and Parent:IsA("BasePart") then
            local px, py, pz = ToPos3(Parent.Position)
            return px + lx, py + ly, pz + lz
        end

        local px, py, pz = WorldPosOf(Parent)
        return px + lx, py + ly, pz + lz
    end

    local AdornBoxes = {}

    local function PushAdorn(Pos, Size, Col, ShapeType, Tr, Orient)
        if #AdornBoxes >= 8 then
            return
        end

        AdornBoxes[#AdornBoxes + 1] = {
            Position = {Pos[1], Pos[2], Pos[3]},
            Size = {Size[1] or 1, Size[2] or 1, Size[3] or 1},
            Orientation = Orient or {0, 0, 0},
            Color = Col,
            HasDecal = 0,
            UvStuds = {1, 1},
            UvOffset = {0, 0},
            ColorTexIndex = 0,
            NormalTexIndex = 1,
            DecalTexIndex = 0,
            DecalColor = {1, 1, 1},
            DecalAlpha = 1,
            Roughness = 0.4,
            Reflectivity = 0,
            Refractivity = 0,
            Transparency = math.max(0, math.min(0.95, Tr or 0.25)),
            ShapeType = ShapeType or 0,
            IsHighlighted = 0,
            AlwaysOnTop = 1,
            CastShadows = 0,
            TriStart = -1,
            TriCount = 0,
        }
    end

    local function CollectAdorns(Node)
        if not Node or #AdornBoxes >= 8 then
            return
        end

        local cn = rawget(Node, "ClassName")

        if cn == "Attachment" and Node.Visible ~= false then
            local x, y, z = WorldPosOf(Node)
            PushAdorn({x, y, z}, {0.35, 0.35, 0.35}, {1.0, 0.85, 0.15}, 1, 0.15, {0, 0, 0})
            PushAdorn({x, y + 0.4, z}, {0.08, 0.7, 0.08}, {1, 0.2, 0.2}, 0, 0.2, {0, 0, 0})
            PushAdorn({x + 0.4, y, z}, {0.7, 0.08, 0.08}, {0.2, 1, 0.2}, 0, 0.2, {0, 0, 0})
            PushAdorn({x, y, z + 0.4}, {0.08, 0.08, 0.7}, {0.25, 0.45, 1}, 0, 0.2, {0, 0, 0})

        elseif cn == "HandleAdornment" and Node.Visible ~= false then
            local PosX, PosY, PosZ = 0, 2, 0
            local Adornee = Node.Adornee

            if Adornee and Adornee.IsA and Adornee:IsA("BasePart") then
                PosX, PosY, PosZ = ToPos3(Adornee.Position)
            elseif Adornee and rawget(Adornee, "ClassName") == "Attachment" then
                PosX, PosY, PosZ = WorldPosOf(Adornee)
            else
                local Parent = rawget(Node, "_Parent") or Node.Parent
                if Parent and Parent.IsA and Parent:IsA("BasePart") then
                    PosX, PosY, PosZ = ToPos3(Parent.Position)
                else
                    PosX, PosY, PosZ = WorldPosOf(Node)
                end
            end

            local ox, oy, oz = ToPos3(Node.CFrameOffset)
            local OriArr = nil
            if Adornee and Adornee.IsA and Adornee:IsA("BasePart") and Adornee.Orientation then
                local OA = Adornee.Orientation
                OriArr = OA.ToArray and OA:ToArray() or OA
            end

            -- apply CFrameOffset rotation roughly
            local RotOff = {ox, oy, oz}
            PosX, PosY, PosZ = PosX + RotOff[1], PosY + RotOff[2], PosZ + RotOff[3]

            local sx, sy, sz = ToPos3(Node.Size)
            if sx == 0 and sy == 0 and sz == 0 then
                sx, sy, sz = 1, 1, 1
            end

            local col = Node.Color
            local r, g, b = 0, 0.67, 1

            if type(col) == "table" then
                if col.R then
                    r, g, b = col.R or 0, col.G or 0.67, col.B or 1
                else
                    r, g, b = col[1] or 0, col[2] or 0.67, col[3] or 1
                end
                if r > 1 or g > 1 or b > 1 then
                    r, g, b = r / 255, g / 255, b / 255
                end
            end

            local ShapeRaw = string.lower(tostring(Node.Shape or "Sphere"))
            local ST = 1

            if ShapeRaw == "cube" or ShapeRaw == "block" then
                ST = 0
            elseif ShapeRaw == "cylinder" then
                ST = 2
            elseif ShapeRaw == "wedge" then
                ST = 3
            elseif ShapeRaw == "cone" then
                ST = 4
            elseif ShapeRaw == "plane" then
                ST = 0
                sy = 0.05
            end

            local Tr = type(Node.Transparency) == "number" and Node.Transparency or 0.3
            local orient = {0, 0, 0}
            if OriArr then
                orient = {math.rad(OriArr[1] or 0), math.rad(OriArr[2] or 0), math.rad(OriArr[3] or 0)}
            end

            PushAdorn({PosX, PosY, PosZ}, {sx, sy, sz}, {r, g, b}, ST, Tr, orient)
        end

        local ch = rawget(Node, "Children")
        if ch then
            for i = 1, #ch do
                CollectAdorns(ch[i])
            end
        end
    end

    if Workspace then
        CollectAdorns(Workspace)
    end
    if CoreGui then
        CollectAdorns(CoreGui)
    end

    table.sort(Candidates, function(A, B)
        return A.Dist < B.Dist
    end)

    for i = 1, math.min(STREAM_MAX, #Candidates) do
        local C = Candidates[i]
        C.Dist = nil
        table.insert(Boxes, C)
    end

    -- -----------------------------------------------------------------------
    -- Triangle pool (custom mesh geometry, currently disabled via `false and`)
    -- -----------------------------------------------------------------------

    local TriPool = {}
    local TRI_POOL_MAX = 96

    for _, Box in ipairs(Boxes) do
        local Part = Box._Part
        local ShapeName = nil

        if Box.ShapeType == 5 then
            ShapeName = "CornerWedge"
        end

        -- Pack triangle mesh for shapes without an analytical shader path
        if ShapeName and Part then
            local SizeArr = Box.Size
            if type(SizeArr) == "table" and SizeArr.ToArray then
                SizeArr = SizeArr:ToArray()
            end

            local Mesh = Geometry.GetMesh(ShapeName, SizeArr or {4, 4, 4})
            local StartTri = math.floor(#TriPool / 3)
            local Added = 0

            for _, Tri in ipairs(Mesh.Triangles) do
                if #TriPool + 3 > TRI_POOL_MAX then
                    break
                end

                local A = Mesh.Vertices[Tri[1]]
                local B = Mesh.Vertices[Tri[2]]
                local C = Mesh.Vertices[Tri[3]]

                TriPool[#TriPool + 1] = {A[1], A[2], A[3]}
                TriPool[#TriPool + 1] = {B[1], B[2], B[3]}
                TriPool[#TriPool + 1] = {C[1], C[2], C[3]}
                Added = Added + 1
            end

            Box.TriStart = StartTri
            Box.TriCount = Added
            -- Route through mesh intersector (Shape >= 10)
            Box.ShapeType = 10
        else
            Box.TriStart = -1
            Box.TriCount = 0
        end

        Box._Part = nil
    end

    Pixel._TriPool = TriPool

    local function ToArray(V)
        if not V then
            return {0, 0, 0}
        end
        if type(V) == "table" and V.ToArray then
            return V:ToArray()
        end
        return {V[1] or 0, V[2] or 0, V[3] or 0}
    end

    local function ResolveWorldPosition(Node)
        if not Node then
            return {0, 0, 0}
        end

        local Local = ToArray(Node.Position or Node:GetAttribute("Position"))
        local Parent = rawget(Node, "_Parent")
        if not Parent and Node.Parent then
            Parent = Node.Parent
        end
        if not Parent then
            return Local
        end

        local ParentClass = rawget(Parent, "ClassName")

        if ParentClass == "Workspace" or ParentClass == "Game" or ParentClass == "DataModel" or ParentClass == "Folder" then
            if ParentClass == "Folder" or ParentClass == "Model" then
                local Pp = ResolveWorldPosition(Parent)
                return {Pp[1] + Local[1], Pp[2] + Local[2], Pp[3] + Local[3]}
            end
            return Local
        end

        if Parent.IsA and Parent:IsA("BasePart") then
            local Pp = ToArray(Parent.Position or Parent:GetAttribute("Position"))
            return {Pp[1] + Local[1], Pp[2] + Local[2], Pp[3] + Local[3]}
        end

        if ParentClass == "Attachment" then
            local Pp = ResolveWorldPosition(Parent)
            return {Pp[1] + Local[1], Pp[2] + Local[2], Pp[3] + Local[3]}
        end

        local Pp = ResolveWorldPosition(Parent)
        return {Pp[1] + Local[1], Pp[2] + Local[2], Pp[3] + Local[3]}
    end

    -- -----------------------------------------------------------------------
    -- Lights
    -- -----------------------------------------------------------------------

    local Lights = {}

    local function CollectLights(Node)
        if not Node then
            return
        end

        local ClassName = rawget(Node, "ClassName")

        if ClassName == "Attachment" then
            local Wp = ResolveWorldPosition(Node)
            Node:SetAttribute("WorldPosition", Wp)
        end

        if ClassName == "PointLight" or ClassName == "SpotLight" or ClassName == "SurfaceLight" then
            local Enabled = Node.Enabled
            if Enabled == nil then
                Enabled = Node:GetAttribute("Enabled")
            end

            if Enabled ~= false and #Lights < 8 then
                local Parent = rawget(Node, "_Parent") or Node.Parent
                local WorldPos

                if Parent and (rawget(Parent, "ClassName") == "Attachment" or (Parent.IsA and Parent:IsA("BasePart"))) then
                    WorldPos = ResolveWorldPosition(Parent)
                else
                    WorldPos = ResolveWorldPosition(Node)
                end

                local Brightness = Node.Brightness or Node:GetAttribute("Brightness") or 1
                local Range = Node.Range or Node:GetAttribute("Range") or 16
                local Col = ToRgbColor(Node.Color or Node:GetAttribute("Color"))

                local Shadows = Node.Shadows
                if Shadows == nil then
                    Shadows = Node:GetAttribute("Shadows")
                end
                if Shadows == nil then
                    Shadows = true
                end

                table.insert(Lights, {
                    Position = WorldPos,
                    Color = Col,
                    Brightness = Brightness,
                    Range = Range,
                    Shadows = Shadows and 1 or 0
                })
            end
        end

        local Children = rawget(Node, "Children")
        if Children then
            for _, Child in ipairs(Children) do
                CollectLights(Child)
            end
        end
    end

    if Workspace then
        CollectLights(Workspace)
    end

    local ClockTime = 12
    if Lighting then
        ClockTime = Lighting.ClockTime
            or Lighting:GetAttribute("Time")
            or Lighting:GetAttribute("ClockTime")
            or 12
        if Lighting.Brightness ~= nil then
            -- reserved for future exposure scaling
        end
    end
    ClockTime = ClockTime % 24
    if ClockTime < 0 then
        ClockTime = ClockTime + 24
    end

    local GlobalShadows = 1.0
    if Lighting then
        local gs = rawget(Lighting, "GlobalShadows")
        if gs == nil and Lighting.GetAttribute then
            gs = Lighting:GetAttribute("GlobalShadows")
        end
        if gs == false then
            GlobalShadows = 0.0
        else
            GlobalShadows = 1.0
        end
    end

    -- -----------------------------------------------------------------------
    -- Selection highlight config
    -- -----------------------------------------------------------------------

    local HL = _G.SelectionHighlight
    local HLEnabled = 0

    if (_G.SelectionSet and next(_G.SelectionSet)) or (_G.SelectionHighlight and _G.SelectionHighlight.Adornee) or _G.HoverPart then
        HLEnabled = 1
    end

    local HLFill = {1.0, 0.4, 0.15}
    local HLOutline = {1.0, 0.85, 0.3}
    local HLFillAlpha = 0.25
    local HLOutlineAlpha = 1.0

    if HL then
        local fc = HL.FillColor
        if type(fc) == "table" then
            HLFill = {fc[1] or 1, fc[2] or 0.4, fc[3] or 0.15}
        end

        local oc = HL.OutlineColor
        if type(oc) == "table" then
            HLOutline = {oc[1] or 1, oc[2] or 0.85, oc[3] or 0.3}
        end

        local ft = HL.FillTransparency
        if type(ft) == "number" then
            HLFillAlpha = 1.0 - math.max(0, math.min(1, ft))
        end

        local ot = HL.OutlineTransparency
        if type(ot) == "number" then
            HLOutlineAlpha = 1.0 - math.max(0, math.min(1, ot))
        end
    end

    -- -----------------------------------------------------------------------
    -- Send uniforms to shader
    -- -----------------------------------------------------------------------

    PixelShader:Bind()
    PixelShader:Send({
        Resolution = {Width, Height},
        CameraPos = Cf.Position,
        CameraForward = Cf.Forward,
        CameraRight = Cf.Right,
        CameraUp = Cf.Up,
        Fov = Fov,
        BoxCount = #Boxes,
        AdornCount = #AdornBoxes,
        LightCount = #Lights,
        ClockTime = ClockTime,
        GlobalShadows = GlobalShadows,
        Time = love.timer.getTime(),
        HighlightEnabled = HLEnabled,
        HighlightFillColor = HLFill,
        HighlightOutlineColor = HLOutline,
        HighlightFillAlpha = HLFillAlpha,
        HighlightOutlineAlpha = HLOutlineAlpha
    })

    pcall(function()
        PixelShader._Program:send("GlobalTextures", unpack(TextureSlots))
    end)

    for i, Box in ipairs(Boxes) do
        local Prefix = string.format("Boxes[%d].", i - 1)
        PixelShader:Send({
            [Prefix .. "Position"] = Box.Position,
            [Prefix .. "Size"] = Box.Size,
            [Prefix .. "Orientation"] = Box.Orientation,
            [Prefix .. "Color"] = Box.Color,
            [Prefix .. "HasDecal"] = Box.HasDecal,
            [Prefix .. "UvStuds"] = Box.UvStuds,
            [Prefix .. "UvOffset"] = Box.UvOffset or {0, 0},
            [Prefix .. "ColorTexIndex"] = Box.ColorTexIndex,
            [Prefix .. "NormalTexIndex"] = Box.NormalTexIndex,
            [Prefix .. "DecalTexIndex"] = Box.DecalTexIndex,
            [Prefix .. "DecalColor"] = Box.DecalColor,
            [Prefix .. "DecalAlpha"] = Box.DecalAlpha or 1,
            [Prefix .. "Roughness"] = Box.Roughness,
            [Prefix .. "Reflectivity"] = Box.Reflectivity,
            [Prefix .. "Refractivity"] = Box.Refractivity,
            [Prefix .. "Transparency"] = Box.Transparency,
            [Prefix .. "ShapeType"] = Box.ShapeType,
            [Prefix .. "IsHighlighted"] = Box.IsHighlighted or 0,
            [Prefix .. "AlwaysOnTop"] = Box.AlwaysOnTop or 0,
            [Prefix .. "CastShadows"] = 1.0,
            [Prefix .. "TriStart"] = Box.TriStart or -1,
            [Prefix .. "TriCount"] = Box.TriCount or 0
        })
    end

    local TriPoolSend = Pixel._TriPool or {}
    local TriUniforms = {TriPoolCount = #TriPoolSend}

    for _, Value in ipairs(TriPoolSend) do
        TriUniforms[string.format("TriPool[%d]", _ - 1)] = {Value[1], Value[2], Value[3], 0}
    end
    for _ = #TriPoolSend, 95 do
        TriUniforms[string.format("TriPool[%d]", _)] = {0, 0, 0, 0}
    end
    PixelShader:Send(TriUniforms)

    for Index = 1, 8 do
        local Prefix = string.format("AdornBoxes[%d].", Index - 1)
        local Box = AdornBoxes[Index]

        if Box then
            PixelShader:Send({
                [Prefix .. "Position"] = Box.Position,
                [Prefix .. "Size"] = Box.Size,
                [Prefix .. "Orientation"] = Box.Orientation,
                [Prefix .. "Color"] = Box.Color,
                [Prefix .. "HasDecal"] = 0,
                [Prefix .. "UvStuds"] = {1, 1},
                [Prefix .. "UvOffset"] = {0, 0},
                [Prefix .. "ColorTexIndex"] = 0,
                [Prefix .. "NormalTexIndex"] = 1,
                [Prefix .. "DecalTexIndex"] = 0,
                [Prefix .. "DecalColor"] = {1, 1, 1},
                [Prefix .. "DecalAlpha"] = 1,
                [Prefix .. "Roughness"] = 0.4,
                [Prefix .. "Reflectivity"] = 0,
                [Prefix .. "Refractivity"] = 0,
                [Prefix .. "Transparency"] = Box.Transparency,
                [Prefix .. "ShapeType"] = Box.ShapeType,
                [Prefix .. "IsHighlighted"] = 0,
                [Prefix .. "AlwaysOnTop"] = 1,
                [Prefix .. "CastShadows"] = 0,
                [Prefix .. "TriStart"] = -1,
                [Prefix .. "TriCount"] = 0,
            })
        else
            PixelShader:Send({
                [Prefix .. "Position"] = {0, -9999, 0},
                [Prefix .. "Size"] = {0, 0, 0},
                [Prefix .. "Orientation"] = {0, 0, 0},
                [Prefix .. "Transparency"] = 1,
                [Prefix .. "ShapeType"] = 0,
            })
        end
    end

    for i, Light in ipairs(Lights) do
        local Prefix = string.format("Lights[%d].", i - 1)
        PixelShader:Send({
            [Prefix .. "Position"] = Light.Position,
            [Prefix .. "Color"] = Light.Color,
            [Prefix .. "Brightness"] = Light.Brightness,
            [Prefix .. "Range"] = Light.Range,
            [Prefix .. "Shadows"] = Light.Shadows
        })
    end

    local Canvas = EnsureCanvas(Width, Height)
    love.graphics.setCanvas(Canvas)
    love.graphics.clear(0, 0, 0, 1)
    love.graphics.rectangle("fill", 0, 0, Width, Height)
    PixelShader:Unbind()
    love.graphics.setCanvas()

    -- Camera motion factor for temporal reservoir trust
    local CamPos = Cf.Position or {0, 0, 0}
    local CamFwd = Cf.Forward or {0, 0, 1}
    local motion = 0
    if type(CamPos) == "table" and type(PrevCamPos) == "table" then
        local dx = (CamPos[1] or 0) - (PrevCamPos[1] or 0)
        local dy = (CamPos[2] or 0) - (PrevCamPos[2] or 0)
        local dz = (CamPos[3] or 0) - (PrevCamPos[3] or 0)
        motion = math.sqrt(dx * dx + dy * dy + dz * dz)
        local df = 0
        if type(CamFwd) == "table" and type(PrevCamFwd) == "table" then
            df = 1 - ((CamFwd[1] or 0) * (PrevCamFwd[1] or 0)
                + (CamFwd[2] or 0) * (PrevCamFwd[2] or 0)
                + (CamFwd[3] or 0) * (PrevCamFwd[3] or 0))
            if df < 0 then df = -df end
        end
        motion = motion + df * 8
    end
    PrevCamPos = {CamPos[1] or 0, CamPos[2] or 0, CamPos[3] or 0}
    PrevCamFwd = {CamFwd[1] or 0, CamFwd[2] or 0, CamFwd[3] or 0}
    FrameIndex = FrameIndex + 1

    -- Temporal weight: high when still, low when moving
    local temporalAlpha = 0.12 + math.min(0.75, motion * 0.35)

    PostShader:Bind()
    PostShader:Send({
        Resolution = {Width, Height},
        DenoiseStrength = Pixel.DenoiseStrength or 0.55,
        FxaaQuality = Pixel.FxaaQuality or 8.0,
        TemporalAlpha = temporalAlpha,
        FrameIndex = FrameIndex % 1024,
        RestirRadius = Pixel.RestirRadius or 3.0,
        RestirSamples = Pixel.RestirSamples or 8.0,
    })
    -- History as second texture unit if shader supports it
    pcall(function()
        PostShader._Program:send("HistoryTex", HistoryCanvas)
    end)

    -- Post into OutputCanvas (HistoryTex is previous frame — no read/write hazard)
    love.graphics.setCanvas(OutputCanvas)
    love.graphics.clear(0, 0, 0, 1)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(Canvas, 0, 0)
    love.graphics.setCanvas()
    PostShader:Unbind()

    -- Present
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(OutputCanvas, 0, 0)

    -- Ping history for next frame
    love.graphics.setCanvas(HistoryCanvas)
    love.graphics.clear(0, 0, 0, 1)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.draw(OutputCanvas, 0, 0)
    love.graphics.setCanvas()
end

-- ---------------------------------------------------------------------------
-- Pixel.Pick (mouse-ray picking, CPU-side)
-- ---------------------------------------------------------------------------

local function ToArr(V)
    if not V then
        return {0, 0, 0}
    end
    if type(V) == "table" and V.ToArray then
        return V:ToArray()
    end
    return {V[1] or 0, V[2] or 0, V[3] or 0}
end

local function IntersectAABB(Ro, Rd, Pos, Half)
    local inv = {
        Rd[1] ~= 0 and 1 / Rd[1] or 1e12,
        Rd[2] ~= 0 and 1 / Rd[2] or 1e12,
        Rd[3] ~= 0 and 1 / Rd[3] or 1e12
    }

    local t0 = {
        (Pos[1] - Half[1] - Ro[1]) * inv[1],
        (Pos[2] - Half[2] - Ro[2]) * inv[2],
        (Pos[3] - Half[3] - Ro[3]) * inv[3]
    }
    local t1 = {
        (Pos[1] + Half[1] - Ro[1]) * inv[1],
        (Pos[2] + Half[2] - Ro[2]) * inv[2],
        (Pos[3] + Half[3] - Ro[3]) * inv[3]
    }

    local tmin = {math.min(t0[1], t1[1]), math.min(t0[2], t1[2]), math.min(t0[3], t1[3])}
    local tmax = {math.max(t0[1], t1[1]), math.max(t0[2], t1[2]), math.max(t0[3], t1[3])}

    local tNear = math.max(tmin[1], math.max(tmin[2], tmin[3]))
    local tFar = math.min(tmax[1], math.min(tmax[2], tmax[3]))

    if tNear > tFar or tFar < 0 then
        return -1
    end

    return tNear > 0 and tNear or tFar
end

local function IntersectSphere(Ro, Rd, Pos, Size)
    local r = math.min(Size[1], math.min(Size[2], Size[3])) * 0.5
    local oc = {Ro[1] - Pos[1], Ro[2] - Pos[2], Ro[3] - Pos[3]}
    local b = oc[1] * Rd[1] + oc[2] * Rd[2] + oc[3] * Rd[3]
    local c = oc[1] * oc[1] + oc[2] * oc[2] + oc[3] * oc[3] - r * r
    local h = b * b - c

    if h < 0 then
        return -1
    end
    h = math.sqrt(h)

    local t = -b - h
    if t < 0 then
        t = -b + h
    end

    return t >= 0 and t or -1
end

local function IntersectCylinder(Ro, Rd, Pos, Size)
    local radius = math.min(Size[1], Size[3]) * 0.5
    local halfH = Size[2] * 0.5
    local ocx, ocz = Ro[1] - Pos[1], Ro[3] - Pos[3]

    local a = Rd[1] * Rd[1] + Rd[3] * Rd[3]
    local b = ocx * Rd[1] + ocz * Rd[3]
    local c = ocx * ocx + ocz * ocz - radius * radius

    local tSide = -1
    if a > 1e-8 then
        local h = b * b - a * c
        if h >= 0 then
            h = math.sqrt(h)
            local t0 = (-b - h) / a
            local t1 = (-b + h) / a
            if t0 > t1 then
                t0, t1 = t1, t0
            end

            local y0 = Ro[2] + Rd[2] * t0
            if t0 > 0 and math.abs(y0 - Pos[2]) <= halfH then
                tSide = t0
            else
                local y1 = Ro[2] + Rd[2] * t1
                if t1 > 0 and math.abs(y1 - Pos[2]) <= halfH then
                    tSide = t1
                end
            end
        end
    end

    local tCap = -1
    if math.abs(Rd[2]) > 1e-8 then
        for _, sign in ipairs({1, -1}) do
            local yp = Pos[2] + sign * halfH
            local t = (yp - Ro[2]) / Rd[2]

            if t > 0 and (tCap < 0 or t < tCap) then
                local hx = Ro[1] + Rd[1] * t - Pos[1]
                local hz = Ro[3] + Rd[3] * t - Pos[3]
                if hx * hx + hz * hz <= radius * radius then
                    tCap = t
                end
            end
        end
    end

    if tSide < 0 and tCap < 0 then
        return -1
    end
    if tSide < 0 then
        return tCap
    end
    if tCap < 0 then
        return tSide
    end

    return math.min(tSide, tCap)
end


local function RotateVecEulerXYZ(v, ori)
    -- ori in radians, R = Rz * Ry * Rx applied to column vector
    local cx, sx = math.cos(ori[1] or 0), math.sin(ori[1] or 0)
    local cy, sy = math.cos(ori[2] or 0), math.sin(ori[2] or 0)
    local cz, sz = math.cos(ori[3] or 0), math.sin(ori[3] or 0)
    -- first Rx
    local x, y, z = v[1], v[2], v[3]
    local y1 = y * cx - z * sx
    local z1 = y * sx + z * cx
    local x1 = x
    -- then Ry
    local x2 = x1 * cy + z1 * sy
    local z2 = -x1 * sy + z1 * cy
    local y2 = y1
    -- then Rz
    local x3 = x2 * cz - y2 * sz
    local y3 = x2 * sz + y2 * cz
    return {x3, y3, z2}
end

local function RotateVecEulerXYZInv(v, ori)
    -- transpose = inverse for rotation: apply Rx^-1 * Ry^-1 * Rz^-1 = Rx(-) Ry(-) Rz(-)
    local neg = { -(ori[1] or 0), -(ori[2] or 0), -(ori[3] or 0) }
    -- apply in reverse order with negated angles: first Rz(-), then Ry(-), then Rx(-)
    local cx, sx = math.cos(neg[1]), math.sin(neg[1])
    local cy, sy = math.cos(neg[2]), math.sin(neg[2])
    local cz, sz = math.cos(neg[3]), math.sin(neg[3])
    local x, y, z = v[1], v[2], v[3]
    -- Rz(-)
    local x1 = x * cz - y * sz
    local y1 = x * sz + y * cz
    local z1 = z
    -- Ry(-)
    local x2 = x1 * cy + z1 * sy
    local z2 = -x1 * sy + z1 * cy
    local y2 = y1
    -- Rx(-)
    local y3 = y2 * cx - z2 * sx
    local z3 = y2 * sx + z2 * cx
    return {x2, y3, z3}
end

local function IntersectOrientedAABB(Ro, Rd, Pos, Half, Ori)
    -- Transform ray into local (unrotated) space
    local has = math.abs(Ori[1] or 0) > 1e-5 or math.abs(Ori[2] or 0) > 1e-5 or math.abs(Ori[3] or 0) > 1e-5
    local ro, rd = Ro, Rd
    if has then
        local off = {Ro[1] - Pos[1], Ro[2] - Pos[2], Ro[3] - Pos[3]}
        local offL = RotateVecEulerXYZInv(off, Ori)
        ro = {Pos[1] + offL[1], Pos[2] + offL[2], Pos[3] + offL[3]}
        rd = RotateVecEulerXYZInv(Rd, Ori)
    end
    return IntersectAABB(ro, rd, Pos, Half)
end

function Pixel.Pick(Camera, ScreenX, ScreenY)
    if not Camera or not Workspace then
        return nil
    end

    local Width, Height = love.graphics.getDimensions()
    local Fov = Camera:GetAttribute("Fov") or (math.pi / 1.75)
    local Position = Camera:GetAttribute("Position") or {0, 4, 0}
    local Rotation = Camera:GetAttribute("Rotation") or {0, 0, 0}

    local Cf = CFrame.FromPositionRotation(Position, Rotation[1], Rotation[2])

    local UvX = (ScreenX - 0.5 * Width) / Height
    local UvY = (ScreenY - 0.5 * Height) / Height
    local TanFov = math.tan(Fov * 0.5)

    local Rd = {
        Cf.Forward[1] + Cf.Right[1] * UvX * TanFov - Cf.Up[1] * UvY * TanFov,
        Cf.Forward[2] + Cf.Right[2] * UvX * TanFov - Cf.Up[2] * UvY * TanFov,
        Cf.Forward[3] + Cf.Right[3] * UvX * TanFov - Cf.Up[3] * UvY * TanFov
    }

    local len = math.sqrt(Rd[1] * Rd[1] + Rd[2] * Rd[2] + Rd[3] * Rd[3])
    if len < 1e-8 then
        return nil
    end
    Rd[1], Rd[2], Rd[3] = Rd[1] / len, Rd[2] / len, Rd[3] / len

    local Ro = {Cf.Position[1], Cf.Position[2], Cf.Position[3]}
    local bestT, bestPart = 1e12, nil

    for _, Child in ipairs(Workspace:GetChildren()) do
        if Child:IsA("Part") or Child:IsA("BasePart") then
            if Child.Locked == true then
                goto continue
            end

            local Pos = ToArr(Child.Position or Child:GetAttribute("Position"))
            local Size = ToArr(Child.Size or Child:GetAttribute("Size"))
            local Shape = tostring(Child.Shape or Child:GetAttribute("Shape") or "Block"):lower()
            local Ori = GetOrientationRad(Child)

            local t = -1
            if Shape == "sphere" or Shape == "ball" then
                t = IntersectSphere(Ro, Rd, Pos, Size)
            elseif Shape == "cylinder" then
                t = IntersectCylinder(Ro, Rd, Pos, Size)
            else
                t = IntersectOrientedAABB(Ro, Rd, Pos, {Size[1] * 0.5, Size[2] * 0.5, Size[3] * 0.5}, Ori)
            end

            if t > 0.001 and t < bestT then
                bestT = t
                bestPart = Child
            end

            ::continue::
        end
    end

    return bestPart
end

return Pixel
