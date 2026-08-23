local Instance = require("Services.Instance")
local Vector3 = require("Services.Vector3")
local Color = require("Services.Color")

local CSG = {}

local VoxelSize = 0.25

local function ToArr(V)
    if not V then return {0, 0, 0} end
    if type(V) == "table" then
        if V.ToArray then return V:ToArray() end
        return {V[1] or 0, V[2] or 0, V[3] or 0}
    end
    return {0, 0, 0}
end

local function PartBox(Part)
    local P = ToArr(Part.Position)
    local S = ToArr(Part.Size)
    return P[1], P[2], P[3], math.abs(S[1]), math.abs(S[2]), math.abs(S[3])
end

local function CollectSelectedParts()
    local Parts = {}
    local Seen = {}
    local Explorer = package.loaded["Services.Explorer"] or rawget(_G, "Explorer")
    local Set = Explorer and Explorer.SelectedSet
    local Primary = Explorer and Explorer.Selected

    local function Add(N)
        if not N or Seen[N] then return end
        if N.IsA and N:IsA("UnionOperation") then
            Seen[N] = true
            Parts[#Parts + 1] = N
            return
        end
        if N.IsA and N:IsA("BasePart") then
            Seen[N] = true
            Parts[#Parts + 1] = N
        elseif N.IsA and N:IsA("Model") then
            local Kids = rawget(N, "Children") or (N.GetChildren and N:GetChildren())
            if Kids then
                for I = 1, #Kids do Add(Kids[I]) end
            end
        end
    end

    if Set then
        for N, On in pairs(Set) do
            if On then Add(N) end
        end
    end
    if #Parts == 0 and Primary then
        Add(Primary)
    end
    return Parts
end

local function SnapshotPart_Color(Part)
    local Col = Part.Color
    if type(Col) == "table" then
        return Col[1] or 0.64, Col[2] or 0.64, Col[3] or 0.64
    end
    return 0.64, 0.64, 0.64
end

local function DeepClone(Value)
    if type(Value) ~= "table" then
        return Value
    end
    if Value.ToArray then
        local Arr = Value:ToArray()
        return {Arr[1], Arr[2], Arr[3]}
    end
    local Copy = {}
    for Key, Val in pairs(Value) do
        Copy[Key] = DeepClone(Val)
    end
    return Copy
end

local function SnapshotPart(Part, Origin)
    Origin = Origin or {0, 0, 0}
    if Part.IsA and Part:IsA("UnionOperation") then
        local U = ToArr(Part.Position)
        local S = ToArr(Part.Size)
        local O = ToArr(Part.Orientation)
        local Cr, Cg, Cb = SnapshotPart_Color(Part)
        local Solids = {}
        if type(Part.SolidPieces) == "table" then
            for I = 1, #Part.SolidPieces do
                local Sp = Part.SolidPieces[I]
                local P = ToArr(Sp.Position)
                local Sz = ToArr(Sp.Size)
                Solids[#Solids + 1] = {
                    Position = {P[1], P[2], P[3]},
                    Size = {Sz[1], Sz[2], Sz[3]},
                }
            end
        end
        local Operands = Part:GetAttribute("CSGOperands")
        if type(Operands) ~= "table" then
            Operands = {}
        end
        return {
            Kind = "union",
            ClassName = "UnionOperation",
            Name = Part.Name or "Union",
            Position = {U[1] - Origin[1], U[2] - Origin[2], U[3] - Origin[3]},
            Size = {S[1], S[2], S[3]},
            Orientation = {O[1], O[2], O[3]},
            Color = {Cr, Cg, Cb},
            Material = Part.Material,
            Anchored = Part.Anchored ~= false,
            CanCollide = Part.CanCollide ~= false,
            Transparency = Part.Transparency or 0,
            SolidPieces = Solids,
            CSGOperands = DeepClone(Operands),
        }
    end

    local P = ToArr(Part.Position)
    local S = ToArr(Part.Size)
    local O = ToArr(Part.Orientation)
    local Cr, Cg, Cb = SnapshotPart_Color(Part)
    return {
        Kind = "part",
        ClassName = Part.ClassName or "Part",
        Name = Part.Name or "Part",
        Position = {P[1] - Origin[1], P[2] - Origin[2], P[3] - Origin[3]},
        Size = {S[1], S[2], S[3]},
        Orientation = {O[1], O[2], O[3]},
        Color = {Cr, Cg, Cb},
        Material = Part.Material,
        Anchored = Part.Anchored ~= false,
        CanCollide = Part.CanCollide ~= false,
        Transparency = Part.Transparency or 0,
        Shape = Part.Shape,
    }
end

local function RestoreOperand(Data, Parent)
    if not Data then return nil end
    if Data.Kind == "union" then
        local Union = Instance.new("UnionOperation", Parent)
        Union.Name = Data.Name or "Union"
        Union.Position = Vector3.new(Data.Position[1], Data.Position[2], Data.Position[3])
        Union.Size = Vector3.new(Data.Size[1], Data.Size[2], Data.Size[3])
        Union.Orientation = Vector3.new((Data.Orientation or {0, 0, 0})[1], (Data.Orientation or {0, 0, 0})[2], (Data.Orientation or {0, 0, 0})[3])
        if Data.Color then
            Union.Color = Color.Float(Data.Color[1], Data.Color[2], Data.Color[3], 1)
        end
        if Data.Material then Union.Material = Data.Material end
        Union.Anchored = Data.Anchored ~= false
        Union.CanCollide = Data.CanCollide ~= false
        if Data.Transparency then Union.Transparency = Data.Transparency end
        local Solids = {}
        if type(Data.SolidPieces) == "table" then
            for I = 1, #Data.SolidPieces do
                local Sp = Data.SolidPieces[I]
                Solids[#Solids + 1] = {
                    Position = {Sp.Position[1], Sp.Position[2], Sp.Position[3]},
                    Size = {Sp.Size[1], Sp.Size[2], Sp.Size[3]},
                }
            end
        end
        Union.SolidPieces = Solids
        Union:SetAttribute("IsUnion", true)
        if type(Data.CSGOperands) == "table" then
            Union:SetAttribute("CSGOperands", DeepClone(Data.CSGOperands))
        end
        return Union
    end
    if Data.Kind == "pieces" and Data.Pieces then
        local Restored = {}
        for I = 1, #Data.Pieces do
            Restored[#Restored + 1] = RestoreOperand(Data.Pieces[I], Parent)
        end
        return Restored
    end
    local Part = Instance.new(Data.ClassName or "Part", Parent)
    Part.Name = Data.Name or "Part"
    Part.Position = Vector3.new(Data.Position[1], Data.Position[2], Data.Position[3])
    Part.Size = Vector3.new(Data.Size[1], Data.Size[2], Data.Size[3])
    Part.Orientation = Vector3.new((Data.Orientation or {0, 0, 0})[1], (Data.Orientation or {0, 0, 0})[2], (Data.Orientation or {0, 0, 0})[3])
    if Data.Color then
        Part.Color = Color.Float(Data.Color[1], Data.Color[2], Data.Color[3], 1)
    end
    if Data.Material then Part.Material = Data.Material end
    Part.Anchored = Data.Anchored ~= false
    Part.CanCollide = Data.CanCollide ~= false
    if Data.Transparency then Part.Transparency = Data.Transparency end
    if Data.Shape then Part.Shape = Data.Shape end
    return Part
end

local function ExpandToBoxes(Part, Into)
    if Part.IsA and Part:IsA("UnionOperation") and type(Part.SolidPieces) == "table" then
        local U = ToArr(Part.Position)
        for I = 1, #Part.SolidPieces do
            local Sp = Part.SolidPieces[I]
            local P = ToArr(Sp.Position)
            local S = ToArr(Sp.Size)
            Into[#Into + 1] = {U[1] + P[1], U[2] + P[2], U[3] + P[3], math.abs(S[1]), math.abs(S[2]), math.abs(S[3])}
        end
        return
    end
    local Px, Py, Pz, Sx, Sy, Sz = PartBox(Part)
    Into[#Into + 1] = {Px, Py, Pz, Sx, Sy, Sz}
end

local function FillBoxVoxels(Grid, Origin, Cell, Px, Py, Pz, Sx, Sy, Sz)
    local Hx, Hy, Hz = Sx * 0.5, Sy * 0.5, Sz * 0.5
    local X0 = math.floor((Px - Hx - Origin[1]) / Cell + 1e-9)
    local Y0 = math.floor((Py - Hy - Origin[2]) / Cell + 1e-9)
    local Z0 = math.floor((Pz - Hz - Origin[3]) / Cell + 1e-9)
    local X1 = math.floor((Px + Hx - Origin[1]) / Cell - 1e-9)
    local Y1 = math.floor((Py + Hy - Origin[2]) / Cell - 1e-9)
    local Z1 = math.floor((Pz + Hz - Origin[3]) / Cell - 1e-9)
    if X1 < X0 then X1 = X0 end
    if Y1 < Y0 then Y1 = Y0 end
    if Z1 < Z0 then Z1 = Z0 end
    for X = X0, X1 do
        for Y = Y0, Y1 do
            for Z = Z0, Z1 do
                Grid[X .. "," .. Y .. "," .. Z] = true
            end
        end
    end
end

local function GreedyMesh(Grid, DimX, DimY, DimZ)
    local Visited = {}
    local Boxes = {}
    local function Occ(X, Y, Z)
        return Grid[X .. "," .. Y .. "," .. Z] == true
    end
    for X = 0, DimX - 1 do
        for Y = 0, DimY - 1 do
            for Z = 0, DimZ - 1 do
                local Key = X .. "," .. Y .. "," .. Z
                if Grid[Key] and not Visited[Key] then
                    local MaxZ = Z
                    while MaxZ + 1 < DimZ and Occ(X, Y, MaxZ + 1) and not Visited[X .. "," .. Y .. "," .. (MaxZ + 1)] do
                        MaxZ = MaxZ + 1
                    end
                    local MaxY = Y
                    local Ok = true
                    while Ok and MaxY + 1 < DimY do
                        for ZZ = Z, MaxZ do
                            local K = X .. "," .. (MaxY + 1) .. "," .. ZZ
                            if not Grid[K] or Visited[K] then Ok = false break end
                        end
                        if Ok then MaxY = MaxY + 1 end
                    end
                    local MaxX = X
                    Ok = true
                    while Ok and MaxX + 1 < DimX do
                        for YY = Y, MaxY do
                            for ZZ = Z, MaxZ do
                                local K = (MaxX + 1) .. "," .. YY .. "," .. ZZ
                                if not Grid[K] or Visited[K] then Ok = false break end
                            end
                            if not Ok then break end
                        end
                        if Ok then MaxX = MaxX + 1 end
                    end
                    for XX = X, MaxX do
                        for YY = Y, MaxY do
                            for ZZ = Z, MaxZ do
                                Visited[XX .. "," .. YY .. "," .. ZZ] = true
                            end
                        end
                    end
                    Boxes[#Boxes + 1] = {X0 = X, Y0 = Y, Z0 = Z, X1 = MaxX, Y1 = MaxY, Z1 = MaxZ}
                end
            end
        end
    end
    return Boxes
end

function CSG:Union()
    local Parts = CollectSelectedParts()
    if #Parts < 2 then
        local Gui = rawget(_G, "Gui")
        if Gui and Gui.Console then Gui.Console:Print("[CSG] Select at least 2 parts to union") end
        if rawget(_G, "Output") and Output.Warn then Output:Warn("[CSG] Select at least 2 parts to union") end
        return nil
    end

    local Snapshots = {}
    local Parent = rawget(Parts[1], "_Parent") or Parts[1].Parent
    local Cr, Cg, Cb = SnapshotPart_Color(Parts[1])
    local BoxesIn = {}
    local MinX, MinY, MinZ = 1e12, 1e12, 1e12
    local MaxX, MaxY, MaxZ = -1e12, -1e12, -1e12

    local PreOrigin = {0, 0, 0}
    do
        local TmpBoxes = {}
        for I = 1, #Parts do ExpandToBoxes(Parts[I], TmpBoxes) end
        local MnX, MnY, MnZ = 1e12, 1e12, 1e12
        local MxX, MxY, MxZ = -1e12, -1e12, -1e12
        for I = 1, #TmpBoxes do
            local B = TmpBoxes[I]
            local Hx, Hy, Hz = B[4] * 0.5, B[5] * 0.5, B[6] * 0.5
            MnX = math.min(MnX, B[1] - Hx)
            MnY = math.min(MnY, B[2] - Hy)
            MnZ = math.min(MnZ, B[3] - Hz)
            MxX = math.max(MxX, B[1] + Hx)
            MxY = math.max(MxY, B[2] + Hy)
            MxZ = math.max(MxZ, B[3] + Hz)
        end
        PreOrigin = {(MnX + MxX) * 0.5, (MnY + MxY) * 0.5, (MnZ + MxZ) * 0.5}
    end
    for I = 1, #Parts do
        Snapshots[#Snapshots + 1] = SnapshotPart(Parts[I], PreOrigin)
        ExpandToBoxes(Parts[I], BoxesIn)
        if not Parent then
            Parent = rawget(Parts[I], "_Parent") or Parts[I].Parent
        end
    end

    for I = 1, #BoxesIn do
        local B = BoxesIn[I]
        local Hx, Hy, Hz = B[4] * 0.5, B[5] * 0.5, B[6] * 0.5
        MinX = math.min(MinX, B[1] - Hx)
        MinY = math.min(MinY, B[2] - Hy)
        MinZ = math.min(MinZ, B[3] - Hz)
        MaxX = math.max(MaxX, B[1] + Hx)
        MaxY = math.max(MaxY, B[2] + Hy)
        MaxZ = math.max(MaxZ, B[3] + Hz)
    end

    local Cell = VoxelSize
    local Span = (MaxX - MinX) * (MaxY - MinY) * (MaxZ - MinZ)
    if Span / (Cell * Cell * Cell) > 300000 then
        Cell = math.max(VoxelSize, (Span / 200000) ^ (1 / 3))
    end

    local Origin = {MinX, MinY, MinZ}
    local DimX = math.max(1, math.ceil((MaxX - MinX) / Cell - 1e-9))
    local DimY = math.max(1, math.ceil((MaxY - MinY) / Cell - 1e-9))
    local DimZ = math.max(1, math.ceil((MaxZ - MinZ) / Cell - 1e-9))

    local Grid = {}
    for I = 1, #BoxesIn do
        local B = BoxesIn[I]
        FillBoxVoxels(Grid, Origin, Cell, B[1], B[2], B[3], B[4], B[5], B[6])
    end

    local Mesh = GreedyMesh(Grid, DimX, DimY, DimZ)
    if #Mesh == 0 then
        local Gui = rawget(_G, "Gui")
        if Gui and Gui.Console then Gui.Console:Print("[CSG] Union produced empty geometry") end
        return nil
    end

    local Cx = (MinX + MaxX) * 0.5
    local Cy = (MinY + MaxY) * 0.5
    local Cz = (MinZ + MaxZ) * 0.5
    local Solids = {}
    for I = 1, #Mesh do
        local B = Mesh[I]
        local X0 = Origin[1] + B.X0 * Cell
        local Y0 = Origin[2] + B.Y0 * Cell
        local Z0 = Origin[3] + B.Z0 * Cell
        local X1 = Origin[1] + (B.X1 + 1) * Cell
        local Y1 = Origin[2] + (B.Y1 + 1) * Cell
        local Z1 = Origin[3] + (B.Z1 + 1) * Cell
        local Wx = (X0 + X1) * 0.5
        local Wy = (Y0 + Y1) * 0.5
        local Wz = (Z0 + Z1) * 0.5
        Solids[#Solids + 1] = {
            Position = {Wx - Cx, Wy - Cy, Wz - Cz},
            Size = {math.max(0.05, X1 - X0), math.max(0.05, Y1 - Y0), math.max(0.05, Z1 - Z0)},
        }
    end

    local Union = Instance.new("UnionOperation", Parent or rawget(_G, "Workspace"))
    Union.Name = "Union"
    Union.Position = Vector3.new(Cx, Cy, Cz)
    Union.Size = Vector3.new(math.max(0.05, MaxX - MinX), math.max(0.05, MaxY - MinY), math.max(0.05, MaxZ - MinZ))
    Union.Orientation = Vector3.new(0, 0, 0)
    Union.Anchored = true
    Union.CanCollide = true
    Union.Color = Color.Float(Cr, Cg, Cb, 1)
    Union.SolidPieces = Solids
    Union:SetAttribute("IsUnion", true)
    Union:SetAttribute("CSGOperands", Snapshots)

    for I = 1, #Parts do
        Parts[I].Parent = nil
        if Parts[I].Destroy then Parts[I]:Destroy() end
    end

    local Explorer = package.loaded["Services.Explorer"] or rawget(_G, "Explorer")
    if Explorer then
        Explorer.SelectedSet = {[Union] = true}
        Explorer.Selected = Union
        if Explorer.OnSelect then Explorer.OnSelect(Explorer.Selected, Explorer.SelectedSet) end
        if Explorer.Refresh then Explorer:Refresh() end
    end
    local Visuals = package.loaded["Services.Visuals"] or rawget(_G, "Visuals")
    if Visuals and Visuals.Invalidate then Visuals.Invalidate() end

    local Msg = string.format("[CSG] UnionOperation with %d solid pieces", #Solids)
    local Gui = rawget(_G, "Gui")
    if Gui and Gui.Console then Gui.Console:Print(Msg) end
    if rawget(_G, "Output") and Output.Print then Output:Print(Msg) end
    return Union
end

function CSG:Separate()
    local Explorer = package.loaded["Services.Explorer"] or rawget(_G, "Explorer")
    local Node = Explorer and Explorer.Selected
    if not Node then
        local Gui = rawget(_G, "Gui")
        if Gui and Gui.Console then Gui.Console:Print("[CSG] Select a UnionOperation to separate") end
        return nil
    end

    if not (Node.IsA and Node:IsA("UnionOperation")) and not Node:GetAttribute("IsUnion") then
        local Gui = rawget(_G, "Gui")
        if Gui and Gui.Console then Gui.Console:Print("[CSG] Selection is not a UnionOperation") end
        return nil
    end

    local Operands = Node:GetAttribute("CSGOperands")
    if type(Operands) ~= "table" or #Operands == 0 then
        local Gui = rawget(_G, "Gui")
        if Gui and Gui.Console then Gui.Console:Print("[CSG] No stored operands to separate") end
        return nil
    end

    local Parent = rawget(Node, "_Parent") or Node.Parent or rawget(_G, "Workspace")
    local U = ToArr(Node.Position)
    local Ori = ToArr(Node.Orientation)
    local Ox, Oy, Oz = math.rad(Ori[1] or 0), math.rad(Ori[2] or 0), math.rad(Ori[3] or 0)
    local Cx, Sx_ = math.cos(Ox), math.sin(Ox)
    local Cy, Sy_ = math.cos(Oy), math.sin(Oy)
    local Cz, Sz_ = math.cos(Oz), math.sin(Oz)
    local function RotLocal(Lx, Ly, Lz)
        local X1 = Lx * Cz - Ly * Sz_
        local Y1 = Lx * Sz_ + Ly * Cz
        local Z1 = Lz
        local X2 = X1 * Cy + Z1 * Sy_
        local Y2 = Y1
        local Z2 = -X1 * Sy_ + Z1 * Cy
        local X3 = X2
        local Y3 = Y2 * Cx - Z2 * Sx_
        local Z3 = Y2 * Sx_ + Z2 * Cx
        return X3, Y3, Z3
    end

    local function PlaceOperand(Data)
        local R = RestoreOperand(Data, Parent)
        local List = {}
        if type(R) == "table" and R[1] then
            for J = 1, #R do List[#List + 1] = R[J] end
        elseif R then
            List[1] = R
        end
        for J = 1, #List do
            local Part = List[J]
            local LP = ToArr(Part.Position)
            local Rx, Ry, Rz = RotLocal(LP[1], LP[2], LP[3])
            Part.Position = Vector3.new(U[1] + Rx, U[2] + Ry, U[3] + Rz)
            local LO = ToArr(Part.Orientation)
            Part.Orientation = Vector3.new((LO[1] or 0) + (Ori[1] or 0), (LO[2] or 0) + (Ori[2] or 0), (LO[3] or 0) + (Ori[3] or 0))
        end
        return List
    end

    local Restored = {}
    for I = 1, #Operands do
        local List = PlaceOperand(Operands[I])
        for J = 1, #List do Restored[#Restored + 1] = List[J] end
    end

    Node.Parent = nil
    if Node.Destroy then Node:Destroy() end

    if Explorer then
        Explorer.SelectedSet = {}
        for I = 1, #Restored do
            Explorer.SelectedSet[Restored[I]] = true
        end
        Explorer.Selected = Restored[1]
        if Explorer.OnSelect then Explorer.OnSelect(Explorer.Selected, Explorer.SelectedSet) end
        if Explorer.Refresh then Explorer:Refresh() end
    end
    local Visuals = package.loaded["Services.Visuals"] or rawget(_G, "Visuals")
    if Visuals and Visuals.Invalidate then Visuals.Invalidate() end

    local Msg = "[CSG] Separated into " .. #Restored .. " parts"
    local Gui = rawget(_G, "Gui")
    if Gui and Gui.Console then Gui.Console:Print(Msg) end
    if rawget(_G, "Output") and Output.Print then Output:Print(Msg) end
    return Restored
end

_G.CSG = CSG
return CSG