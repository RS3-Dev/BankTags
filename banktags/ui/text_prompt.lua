-- Collect one short name for folder and page-label actions through app callbacks

local Theme = require("banktags/ui/theme")

local TextPrompt = {}
TextPrompt.__index = TextPrompt

local WIDTH = 360
local HEIGHT = 176
local MARGIN = 16
local CONTENT_WIDTH = WIDTH - 16
local CONTROL_WIDTH = CONTENT_WIDTH - MARGIN * 2
local BUTTON_GAP = 8
local ERROR_COLOUR = Theme.ERROR_TEXT

-- Create the prompt; onSave and the optional onDelete return success and a reason
function TextPrompt.new(parent, options)
    options = options or {}
    local self = setmetatable({
        onSave = options.onSave,
        onDelete = options.onDelete,
    }, TextPrompt)

    self.window = prettyui.Window.new(parent, {
        title = options.title or "Name",
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
    self.heading = prettyui.Text.new(content, {
        text = options.heading or "NAME",
        x = MARGIN,
        y = 10,
        width = CONTROL_WIDTH,
        height = 20,
        colour = 0xF2C66DFF,
    })
    self.field = prettyui.TextField.new(content, {
        x = MARGIN,
        y = 31,
        width = CONTROL_WIDTH,
        height = 30,
        text = options.text or "",
        placeholder = options.placeholder or "",
        maxLength = options.maxLength or 40,
        onSubmit = function(_, value) self:Save(value) end,
    })
    self.status = prettyui.Text.new(content, {
        text = "",
        x = MARGIN,
        y = 70,
        width = CONTROL_WIDTH,
        height = 18,
        colour = ERROR_COLOUR,
        alignHorizontal = ui.AlignMode.CENTRE,
    })
    self.status.hidden = true

    local actions = {}
    if self.onDelete ~= nil then
        actions[#actions + 1] = { options.deleteLabel or "Delete", function() self:Delete() end }
    end
    actions[#actions + 1] = { "Cancel", function() self.window:Close() end }
    actions[#actions + 1] = {
        options.saveLabel or "Save",
        function() self:Save(self.field:GetText()) end,
    }
    local buttonWidth = math.floor(
        (CONTROL_WIDTH - BUTTON_GAP * (#actions - 1)) / #actions
    )
    self.buttons = {}
    for index, action in ipairs(actions) do
        self.buttons[index] = prettyui.SimpleButton.new(content, action[1], action[2], {
            x = MARGIN + (index - 1) * (buttonWidth + BUTTON_GAP),
            y = 96,
            width = buttonWidth,
            height = 28,
        })
    end
    return self
end

-- Display a rejected save or delete reason beneath the field
function TextPrompt:ShowError(reason, fallback)
    self.status.content = tostring(reason or fallback)
    self.status.rgba = ERROR_COLOUR
    self.status.hidden = false
end

-- Submit the entered text and close only when the callback accepts it
function TextPrompt:Save(value)
    if self.onSave == nil then return end
    local success, reason = self.onSave(tostring(value or ""))
    if success then
        self.window:Close()
    else
        self:ShowError(reason, "Could not save.")
    end
end

-- Run the delete callback and close only when it succeeds
function TextPrompt:Delete()
    if self.onDelete == nil then return end
    local success, reason = self.onDelete()
    if success then
        self.window:Close()
    else
        self:ShowError(reason, "Could not delete.")
    end
end

-- Show the existing prompt window
function TextPrompt:Show()
    self.window:Show()
end

-- Destroy prompt controls and release the callbacks
function TextPrompt:Destroy()
    local controls = {}
    for _, button in ipairs(self.buttons or {}) do controls[#controls + 1] = button end
    for _, control in ipairs({ self.field, self.heading, self.status, self.window }) do
        controls[#controls + 1] = control
    end
    for _, control in ipairs(controls) do
        pcall(function() control:Destroy() end)
    end
    self.buttons = nil
    self.field = nil
    self.heading = nil
    self.status = nil
    self.window = nil
    self.onSave = nil
    self.onDelete = nil
end

return TextPrompt
