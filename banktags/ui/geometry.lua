-- Measure component positions and the pointer in interface coordinates

local Geometry = {}

local MAX_PARENT_DEPTH = 32

-- Locate a component relative to an ancestor
function Geometry.relativePosition(value, ancestor)
    local x, y, current, depth = 0, 0, value, 0
    while current ~= nil and current ~= ancestor and depth < MAX_PARENT_DEPTH do
        x = x + (tonumber(current.x) or 0)
        y = y + (tonumber(current.y) or 0)
        current = current.parent
        depth = depth + 1
    end
    if current ~= ancestor then return nil, nil end
    return x, y
end

-- Locate a component on the screen
function Geometry.absolutePosition(value)
    local x, y, current, depth = 0, 0, value, 0
    while current ~= nil and depth < MAX_PARENT_DEPTH do
        x = x + (tonumber(current.x) or 0)
        y = y + (tonumber(current.y) or 0)
        current = current.parent
        depth = depth + 1
    end
    return x, y
end

-- Convert the mouse position to interface coordinates
function Geometry.interfaceMousePosition()
    if Mouse == nil or Mouse.GetPosition == nil then return nil, nil end
    local position = Mouse.GetPosition()
    if position == nil then return nil, nil end
    local options = game and game.options
    local interfaceScale = options and options.InterfaceScale
    local percent = interfaceScale and tonumber(interfaceScale.setting) or 100
    if percent <= 0 then percent = 100 end
    local scale = percent / 100
    return position.x / scale, position.y / scale
end

return Geometry
