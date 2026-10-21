-- Ask before a removal that the app saves only once confirmed

local Theme = require("banktags/ui/theme")

local ConfirmWindow = {}
ConfirmWindow.__index = ConfirmWindow

local WIDTH = 340
local HEIGHT = 164
local MARGIN = 16
local CONTENT_WIDTH = WIDTH - 16
local CONTROL_WIDTH = CONTENT_WIDTH - MARGIN * 2
local BUTTON_GAP = 16
local BUTTON_WIDTH = 130
local BUTTON_X = math.floor((CONTENT_WIDTH - (BUTTON_WIDTH * 2 + BUTTON_GAP)) / 2)

local TEXT = Theme.TEXT
local ERROR = Theme.ERROR_TEXT

-- Create the confirmation dialog
function ConfirmWindow.new(parent, options)
    local self = setmetatable({
        onConfirm = options.onConfirm,
    }, ConfirmWindow)

    self.window = prettyui.Window.new(parent, {
        title = options.title,
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
    })

    local content = self.window.content
    self.message = prettyui.Text.new(content, {
        text = options.message,
        x = MARGIN,
        y = 18,
        width = CONTROL_WIDTH,
        height = 52,
        maxLines = 4,
        colour = TEXT,
        alignHorizontal = ui.AlignMode.CENTRE,
    })

    self.cancelButton = prettyui.SimpleButton.new(content, "Cancel", function()
        self.window:Close()
    end, {
        x = BUTTON_X,
        y = 84,
        width = BUTTON_WIDTH,
        height = 28,
    })

    self.confirmButton = prettyui.SimpleButton.new(content, options.confirmLabel, function()
        if self.onConfirm == nil then return end
        local success, reason = self.onConfirm()
        if success then
            self.window:Close()
        else
            self.message.content = tostring(reason or options.failureText)
            self.message.rgba = ERROR
        end
    end, {
        x = BUTTON_X + BUTTON_WIDTH + BUTTON_GAP,
        y = 84,
        width = BUTTON_WIDTH,
        height = 28,
    })

    return self
end

-- Show the dialog window
function ConfirmWindow:Show()
    self.window:Show()
end

-- Destroy the dialog controls and window
function ConfirmWindow:Destroy()
    for _, control in ipairs({
        self.confirmButton,
        self.cancelButton,
        self.message,
        self.window,
    }) do
        if control ~= nil then pcall(function() control:Destroy() end) end
    end
    self.confirmButton = nil
    self.cancelButton = nil
    self.message = nil
    self.window = nil
    self.onConfirm = nil
end

return ConfirmWindow
