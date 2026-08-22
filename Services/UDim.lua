local UDim = {}

function UDim.CanvasDimentions()
    return love.graphics.getDimensions()
end

function UDim.FromScale(Sx, Sy)
    return {Sx, 0, Sy, 0}
end

function UDim.FromOffset(Ox, Oy)
    return {0, Ox, 0, Oy}
end

function UDim.New(Sx, Ox, Sy, Oy)
    return {Sx, Ox, Sy, Oy}
end

return UDim