-- Host the optional debug console window

local DebugConsole = {}
DebugConsole.__index = DebugConsole

local WIDTH = 520
local HEIGHT = 360

-- Create the optional debug console window and attach its close callback
function DebugConsole.new(parent, options)
    options = options or {}
    local self = setmetatable({}, DebugConsole)
    self.window = prettyui.Window.new(parent, {
        title = "Bank Utilities Debug Console",
        x = -math.floor(WIDTH / 2),
        y = -math.floor(HEIGHT / 2),
        xAnchor = 0.5,
        yAnchor = 0.5,
        width = WIDTH,
        height = HEIGHT,
        minWidth = WIDTH,
        maxWidth = WIDTH,
        minHeight = HEIGHT,
        maxHeight = HEIGHT,
        scrollable = false,
        destroyOnClose = true,
        onClose = options.onClose,
    })
    return self
end

-- Show the existing editor window
function DebugConsole:Show()
    self.window:Show()
end

-- Destroy the debug window and release its reference
function DebugConsole:Destroy()
    if self.window ~= nil then pcall(function() self.window:Destroy() end) end
    self.window = nil
end

return DebugConsole
