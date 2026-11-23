-- Configure layout editor keybinds and movement shortcuts in a modal over the editor

local Settings = require("resources/core/settings")
local Text = require("resources/core/text")
local Theme = require("resources/ui/theme")

local EditorSettingsWindow = {}
EditorSettingsWindow.__index = EditorSettingsWindow

local WIDTH = 404
local HEIGHT = 496
local MARGIN = 16
local CONTENT_WIDTH = WIDTH - 16
local INNER_WIDTH = CONTENT_WIDTH - MARGIN * 2
local LABEL_WIDTH = 160
local FIELD_X = MARGIN + LABEL_WIDTH + 8
local FIELD_WIDTH = INNER_WIDTH - LABEL_WIDTH - 8
local ROW_HEIGHT = 30
local BUTTON_WIDTH = 132
local BUTTON_HEIGHT = 28

local ACTIONS = {
    { key = "copy", label = "Copy" },
    { key = "paste", label = "Paste" },
    { key = "remove", label = "Remove" },
    { key = "removeRow", label = "Remove row / label" },
    { key = "undo", label = "Undo" },
    { key = "redo", label = "Redo" },
    { key = "moveLeft", label = "Move left", directional = true },
    { key = "moveRight", label = "Move right", directional = true },
    { key = "moveUp", label = "Move up", directional = true },
    { key = "moveDown", label = "Move down", directional = true },
}

-- Convert saved key names into GameKey IDs for KeybindField
local function namesToCodes(names)
    local codes = {}
    if type(GameKey) ~= "table" then return codes end
    for _, name in ipairs(names or {}) do
        local code = GameKey[name]
        if type(code) == "number" then codes[#codes + 1] = code end
    end
    return codes
end

-- Convert GameKey IDs from KeybindField back into saved key names
local function codesToNames(codes)
    local names = {}
    if type(GameKey) ~= "table" or type(GameKey.FromID) ~= "function" then return names end
    for _, code in ipairs(codes or {}) do
        local name = GameKey.FromID(code)
        if type(name) == "string" and name ~= "" then names[#names + 1] = name end
    end
    return names
end

-- Build a normalized signature to spot duplicate bindings
local function bindingSignature(names)
    if type(names) ~= "table" or #names == 0 then return nil end
    local sorted = {}
    for index, name in ipairs(names) do sorted[index] = name end
    table.sort(sorted)
    return table.concat(sorted, "+")
end

-- Open the editor settings modal
function EditorSettingsWindow.new(parent, options)
    local self = setmetatable({
        options = options,
        fields = {},
        labels = {},
        parts = {},
        destroyed = false,
    }, EditorSettingsWindow)

    self.window = prettyui.Window.new(parent, {
        categoryID = "auto",
        title = "Layout Editor Settings",
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
        onClose = function()
            if options.onClose ~= nil then options.onClose(self) end
        end,
    })

    local content = self.window.content
    self.parts[#self.parts + 1] = prettyui.Text.new(content, {
        text = "Editor keybinds",
        x = MARGIN, y = 8, width = INNER_WIDTH, height = 22,
        colour = Theme.HEADING_TEXT, font = id.Font.CINZEL_13PT_BOLD, maxLines = 1,
    })
    self.parts[#self.parts + 1] = prettyui.Text.new(content, {
        text = "Click a field and press 1 or 2 keys. Hover X or right-click to reset.",
        x = MARGIN, y = 30, width = INNER_WIDTH, height = 32,
        colour = Theme.MUTED_TEXT, font = id.Font.MUSEO_SANS_11PT_REGULAR, maxLines = 2,
    })

    local settings = options.settings()
    local defaults = Settings.defaultEditorKeybinds()
    local bindings = Settings.copyEditorKeybinds(settings.editorKeybinds)
    local moveEnabled = settings.arrowKeyMovement == true
    local rowTop = 66
    for index, action in ipairs(ACTIONS) do
        local y = rowTop + (index - 1) * ROW_HEIGHT
        local disabled = action.directional == true and not moveEnabled
        local label = prettyui.Text.new(content, {
            text = action.label,
            x = MARGIN, y = y, width = LABEL_WIDTH, height = 24,
            colour = disabled and Theme.MUTED_TEXT or Theme.TEXT, font = id.Font.MUSEO_SANS_11PT_REGULAR,
            alignVertical = ui.AlignMode.CENTRE, maxLines = 1,
        })
        self.parts[#self.parts + 1] = label
        self.labels[action.key] = label
        self.fields[action.key] = prettyui.KeybindField.new(content, {
            x = FIELD_X, y = y, width = FIELD_WIDTH, height = 24,
            font = id.Font.MUSEO_SANS_11PT_REGULAR,
            disabled = disabled,
            value = namesToCodes(bindings[action.key]),
            defaultValue = namesToCodes(defaults[action.key]),
            onChange = function(_, codes)
                self:SaveKeybind(action.key, codesToNames(codes))
            end,
        })
    end

    local toggleY = rowTop + #ACTIONS * ROW_HEIGHT + 6
    self.moveToggle = prettyui.CheckboxButton.new(content, {
        {
            text = "Enable directional movement keys",
            value = "arrowKeyMovement",
            tooltip = "Allow move keybinds to nudge the selected item or group in the layout grid",
        },
    }, {
        x = MARGIN, y = toggleY, width = INNER_WIDTH, colour = Theme.TEXT,
        selectionCursor = false,
        selectedValues = moveEnabled and { "arrowKeyMovement" } or {},
        onChange = function(control)
            local enabled = control:IsSelected("arrowKeyMovement")
            local saved, reason = options.onSetArrowKeyMovement(enabled)
            if not saved then
                local current = options.settings().arrowKeyMovement == true
                control:SetSelected("arrowKeyMovement", current, false)
                self:SyncMoveFields(current)
                self:ShowStatus(reason or "Could not save the setting.", Theme.ERROR_TEXT)
            else
                self:SyncMoveFields(enabled)
                self:ShowStatus(nil)
            end
        end,
    })
    for _, item in ipairs(self.moveToggle.items or {}) do
        item.label.font = id.Font.MUSEO_SANS_11PT_REGULAR
    end

    self.status = prettyui.Text.new(content, {
        text = "",
        x = MARGIN, y = toggleY + 26, width = INNER_WIDTH, height = 18,
        colour = Theme.HEADING_TEXT, font = id.Font.MUSEO_SANS_11PT_REGULAR,
        alignHorizontal = ui.AlignMode.CENTRE, maxLines = 1,
    })
    self.status.hidden = true

    local buttonY = toggleY + 48
    self.resetButton = prettyui.SimpleButton.new(content, "Reset Defaults", function()
        self:ResetDefaults()
    end, {
        x = MARGIN, y = buttonY, width = BUTTON_WIDTH, height = BUTTON_HEIGHT,
    })
    self.closeButton = prettyui.SimpleButton.new(content, "Close", function()
        if self.window ~= nil then self.window:Close() end
    end, {
        x = CONTENT_WIDTH - MARGIN - BUTTON_WIDTH, y = buttonY,
        width = BUTTON_WIDTH, height = BUTTON_HEIGHT,
    })
    return self
end

-- Enable or disable the directional movement keybind fields
function EditorSettingsWindow:SyncMoveFields(enabled)
    for _, action in ipairs(ACTIONS) do
        if action.directional then
            local field = self.fields[action.key]
            local label = self.labels[action.key]
            if field ~= nil and field.SetDisabled ~= nil then field:SetDisabled(not enabled) end
            if label ~= nil then label.rgba = enabled and Theme.TEXT or Theme.MUTED_TEXT end
        end
    end
end

-- Show a status message or hide it
function EditorSettingsWindow:ShowStatus(message, colour)
    if self.status == nil then return end
    self.status.content = Text.plain(message or "")
    self.status.rgba = colour or Theme.HEADING_TEXT
    self.status.hidden = message == nil or message == ""
end

-- Persist one rebound action and note any duplicate binding
function EditorSettingsWindow:SaveKeybind(actionKey, names)
    local saved, reason = self.options.onSetKeybind(actionKey, names)
    if not saved then
        local current = Settings.copyEditorKeybinds(self.options.settings().editorKeybinds)
        self.fields[actionKey]:SetValue(namesToCodes(current[actionKey]), false)
        self:ShowStatus(reason or "Could not save the keybind.", Theme.ERROR_TEXT)
        return
    end
    local sig = bindingSignature(names)
    if sig ~= nil then
        local current = Settings.copyEditorKeybinds(self.options.settings().editorKeybinds)
        for _, other in ipairs(ACTIONS) do
            if other.key ~= actionKey and bindingSignature(current[other.key]) == sig then
                self:ShowStatus("Also bound to " .. other.label .. ".", Theme.HEADING_TEXT)
                return
            end
        end
    end
    self:ShowStatus(nil)
end

-- Reset every keybind back to its default
function EditorSettingsWindow:ResetDefaults()
    local saved, reason = self.options.onResetKeybinds()
    if not saved then
        self:ShowStatus(reason or "Could not reset keybinds.", Theme.ERROR_TEXT)
        return
    end
    local defaults = Settings.defaultEditorKeybinds()
    for _, action in ipairs(ACTIONS) do
        self.fields[action.key]:SetValue(namesToCodes(defaults[action.key]), false)
    end
    self:ShowStatus("Keybinds reset to defaults.", Theme.HEADING_TEXT)
end

-- Show the settings modal
function EditorSettingsWindow:Show()
    if self.window ~= nil then self.window:Show() end
end

-- Destroy the settings modal and its controls
function EditorSettingsWindow:Destroy()
    if self.destroyed then return end
    self.destroyed = true
    for _, field in pairs(self.fields) do pcall(function() field:Destroy() end) end
    for _, part in ipairs(self.parts) do pcall(function() part:Destroy() end) end
    for _, control in ipairs({ self.moveToggle, self.status, self.resetButton, self.closeButton, self.window }) do
        if control ~= nil then pcall(function() control:Destroy() end) end
    end
    self.fields, self.parts, self.window = {}, {}, nil
end

return EditorSettingsWindow
