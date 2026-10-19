-- Confirm a tag deletion before the app saves it

local Theme = require("banktags/ui/theme")

local TagDeleteConfirm = {}
TagDeleteConfirm.__index = TagDeleteConfirm

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

-- Create the deletion confirmation dialog
function TagDeleteConfirm.new(parent, options)
    local self = setmetatable({
        tag = options.tag,
        onDelete = options.onDelete,
    }, TagDeleteConfirm)

    self.window = prettyui.Window.new(parent, {
        title = "Delete Bank Tag",
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
        text = "Delete <col=ffcb05>\"" .. tostring(self.tag)
            .. "\"</col> from every tagged item?<br><br>Do you wish to continue?",
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

    self.deleteButton = prettyui.SimpleButton.new(content, "Delete", function()
        if self.onDelete == nil then return end
        local success, reason = self.onDelete()
        if success then
            self.window:Close()
        else
            self.message.content = tostring(reason or "Could not delete the tag.")
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
function TagDeleteConfirm:Show()
    self.window:Show()
end

-- Destroy the dialog controls and window
function TagDeleteConfirm:Destroy()
    for _, control in ipairs({
        self.deleteButton,
        self.cancelButton,
        self.message,
        self.window,
    }) do
        if control ~= nil then pcall(function() control:Destroy() end) end
    end
    self.deleteButton = nil
    self.cancelButton = nil
    self.message = nil
    self.window = nil
    self.onDelete = nil
end

return TagDeleteConfirm
