-- Render Bank Tags' preferences in the host's plugin content panel, with Import/Share and a
-- notice when Bank Core is missing

local Settings = require("banktags/core/settings")

local PluginPanel = {}
PluginPanel.__index = PluginPanel

local MAX_WIDTH = 280
local CONTENT_HEIGHT = 340
local TEXT = 0xD7C9ADFF
local GOLD = 0xF2C66DFF

-- Add a compact panel label without creating a separate input target
local function label(parent, value, x, y, width, height, colour)
    local text = prettyui.Text.new(parent, {
        text = value, x = x, y = y, width = width, height = height,
        font = id.Font.MUSEO_SANS_11PT_REGULAR,
        colour = colour or TEXT, maxLines = 1,
    })
    text.clickthrough = true
    return text
end

-- Draw a dark group header with a gold title
local function header(parent, value, x, y, width)
    local background = ui.Rectangle.new(parent)
    background:SetPos(x, y)
    background:SetSize(width, 28)
    background.fill = true
    background.rgba = 0x2A231BFF
    background.clickthrough = true
    label(parent, value, x + 10, y, width - 20, 28, GOLD)
end

-- Mount the preferences, the Import/Share button, and the debug toggle. options: settings,
-- notice, onChange(key, value), and onOpenImport()
function PluginPanel.new(parent, options)
    local self = setmetatable({
        options = options, settings = Settings.copy(options.settings),
        controls = {}, destroyed = false, notice = options.notice,
    }, PluginPanel)
    self.view = prettyui.SimpleView.new(parent, {
        width = parent.width, height = parent.height,
        contentHeight = CONTENT_HEIGHT, scrollable = true, scrollStep = 32,
    })
    local content = self.view.content
    local contentWidth = tonumber(content.width) or 0
    if contentWidth <= 0 then contentWidth = math.max(1, (parent.width or 300) - 18) end
    local width = math.min(MAX_WIDTH, math.max(1, contentWidth - 24))
    local x = math.max(12, math.floor((contentWidth - width) / 2))
    header(content, "Bank Tags", x, 12, width)
    self:AddToggle(content, "showTagSprites", "Show tag sprites", x + 10, 50,
        width - 20, "Display the selected item icon beside each tag")
    label(content, "New tagged items", x, 90, width, 20, GOLD)
    self.placement = prettyui.ComboBox.new(content, {
        x = x, y = 114, width = width, height = 30,
        font = id.Font.MUSEO_SANS_11PT_REGULAR,
        entries = {
            { id = "preserve", label = "Preserve layout (tag only)", order = 1 },
            { id = "fill", label = "Fill first empty slot", order = 2 },
        },
        selectedID = self.settings.preserveTagLayout and "preserve" or "fill",
        onChange = function(_, selected) self:Change("preserveTagLayout", selected == "preserve") end,
    })
    self.importButton = prettyui.SimpleButton.new(content, "Import / Share tags", function()
        if not self.destroyed then options.onOpenImport() end
    end, { x = x, y = 158, width = width, height = 30 })
    self:AddToggle(content, "enableDebug", "Enable debug logging", x + 10, 204, width - 20,
        "Write Bank Tags diagnostics to the client log")
    self.status = prettyui.Text.new(content, {
        text = "", x = x, y = 244, width = width, height = 60,
        font = id.Font.MUSEO_SANS_11PT_REGULAR,
        colour = 0xE57373FF, maxLines = 3,
    })
    self:ShowResult(true)
    return self
end

-- Show a save failure, or the notice, or nothing after a success
function PluginPanel:ShowResult(saved, reason, fallback)
    if saved then
        self.status.content = self.notice or ""
        self.status.hidden = self.notice == nil
        return
    end
    self.status.content = tostring(reason or fallback)
    self.status.hidden = false
end

-- Say why tags are missing from the bank, such as Bank Core not running, or clear it
function PluginPanel:ShowNotice(text)
    if self.destroyed then return end
    self.notice = text
    self:ShowResult(true)
end

-- Add one checkbox for a boolean preference
function PluginPanel:AddToggle(parent, key, text, x, y, width, tooltip)
    local control = prettyui.CheckboxButton.new(parent, {
        { text = text, value = key, tooltip = tooltip },
    }, {
        x = x, y = y, width = width, colour = TEXT, selectionCursor = false,
        selectedValues = self.settings[key] and { key } or {},
        onChange = function(value) self:Change(key, value:IsSelected(key)) end,
    })
    for _, item in ipairs(control.items or {}) do item.label.font = id.Font.MUSEO_SANS_11PT_REGULAR end
    self.controls[key] = control
end

-- Save a change at once and restore the control if the host refuses it
function PluginPanel:Change(key, enabled)
    if self.destroyed then return false end
    local saved, reason = self.options.onChange(key, enabled)
    if saved then
        self.settings[key] = enabled
    elseif key == "preserveTagLayout" then
        self.placement:Select(self.settings[key] and "preserve" or "fill", false)
    else
        self.controls[key]:SetSelected(key, self.settings[key], false)
    end
    self:ShowResult(saved, reason, "Could not save the setting.")
    return saved, reason
end

-- Release the controls before the host replaces the panel or the plugin unloads
function PluginPanel:Destroy()
    if self.destroyed then return end
    self.destroyed = true
    for _, control in pairs(self.controls) do pcall(function() control:Destroy() end) end
    for _, control in ipairs({ self.placement, self.importButton, self.status, self.view }) do
        pcall(function() control:Destroy() end)
    end
    self.controls = {}
end

return PluginPanel
