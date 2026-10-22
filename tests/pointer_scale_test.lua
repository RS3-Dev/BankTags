package.path = "./?.lua;./?/init.lua;" .. package.path

-- Compare physical mouse pixels with native interface hook coordinates
local Geometry = require("banktags/ui/geometry")
local raw
Mouse = { GetPosition = function() return raw end }
game = { options = { InterfaceScale = { setting = 100 } } }

local function point(x, y, factor)
    raw = { x = x * factor, y = y * factor }
end

local function expect(x, y)
    local actualX, actualY = Geometry.interfaceMousePosition()
    assert(math.abs(actualX - x) < 0.000001)
    assert(math.abs(actualY - y) < 0.000001)
end

local component = { xyGlobal = { x = 400, y = 200 } }
point(440, 220, 1.25)
assert(Geometry.calibratePointer(component, 40, 20))
expect(440, 220)
point(900, 650, 1.25)
expect(900, 650)

-- A mismatched event must not replace a valid calibration
raw = { x = 600, y = 900 }
assert(not Geometry.calibratePointer(component, 40, 20))
point(440, 220, 1.25)
expect(440, 220)

-- Changing game scale discards calibration until a fresh native event
game.options.InterfaceScale.setting = 150
raw = { x = 600, y = 300 }
expect(400, 200)
point(440, 220, 1.875)
assert(Geometry.calibratePointer(component, 40, 20))
expect(440, 220)

-- Moving to another display can replace the combined scale
point(440, 220, 1.5)
assert(Geometry.calibratePointer(component, 40, 20))
expect(440, 220)
raw = nil
assert(not Geometry.calibratePointer(component, 40, 20))
assert(Geometry.interfaceMousePosition() == nil)

print("pointer_scale_test: ok")

