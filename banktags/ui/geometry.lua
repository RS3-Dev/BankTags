-- Measure component positions and the pointer in interface coordinates

local Geometry = {}

local MAX_PARENT_DEPTH = 32
local POINTER_HOOK = "banktags_pointer_scale"
local pointerScale, pointerInterfaceScale

-- Read the game's current interface scale
local function interfaceScale()
    local option = game and game.options and game.options.InterfaceScale
    local percent = option and tonumber(option.setting) or 100
    return percent > 0 and percent / 100 or 1
end

-- Measure display scaling from native hover coordinates
function Geometry.calibratePointer(component, x, y)
    if type(x) ~= "number" or type(y) ~= "number" then return false end
    local raw, origin = Mouse.GetPosition(), component.xyGlobal
    if raw == nil or origin == nil then return false end
    local expectedX, expectedY = origin.x + x, origin.y + y
    if math.abs(expectedX) < 32 or math.abs(expectedY) < 32 then return false end
    local scaleX, scaleY = raw.x / expectedX, raw.y / expectedY
    if scaleX < 0.5 or scaleX > 4 or scaleY < 0.5 or scaleY > 4
        or math.abs(scaleX - scaleY) > math.max(scaleX, scaleY) * 0.1 then return false end
    pointerScale = math.abs(expectedX) >= math.abs(expectedY) and scaleX or scaleY
    pointerInterfaceScale = interfaceScale()
    return true
end

-- Keep pointer conversion aligned with native hover events
function Geometry.trackPointer(component)
    component:Subscribe(ui.Hook.ONMOUSEREPEAT, POINTER_HOOK, function(value, x, y)
        Geometry.calibratePointer(value, x, y)
        return false
    end)
end

-- Stop calibrating from a component's hover events
function Geometry.untrackPointer(component)
    component:Unsubscribe(ui.Hook.ONMOUSEREPEAT, POINTER_HOOK)
end

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
    local scale = interfaceScale()
    if pointerInterfaceScale == scale then scale = pointerScale end
    return position.x / scale, position.y / scale
end

return Geometry
