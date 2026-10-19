-- Draw Bank Tags' preferences in Bank Core's settings window

local Settings = require("banktags/core/settings")

local SettingsSection = {}
SettingsSection.__index = SettingsSection

local MAX_WIDTH = 280
local TEXT = 0xD7C9ADFF
local GOLD = 0xF2C66DFF

-- Add a label that takes no input
local function label(parent, value, x, y, width, height, colour)
    local text = prettyui.Text.new(parent, {
        text = value, x = x, y = y, width = width, height = height,
        font = id.Font.MUSEO_SANS_11PT_REGULAR,
        colour = colour or TEXT, maxLines = 1,
    })
    text.clickthrough = true
    return text
end

-- Mount the preferences in the section's parent
function SettingsSection.new(parent, options)
    local self = setmetatable({
        options = options, settings = Settings.copy(options.settings),
        controls = {}, parts = {}, destroyed = false,
    }, SettingsSection)
    local parentWidth = tonumber(parent.width) or 300
    local width = math.min(MAX_WIDTH, math.max(1, parentWidth - 24))
    local x = math.max(12, math.floor((parentWidth - width) / 2))
    local background = ui.Rectangle.new(parent)
    background:SetPos(x, 12)
    background:SetSize(width, 28)
    background.fill = true
    background.rgba = 0x2A231BFF
    background.clickthrough = true
    self.parts[#self.parts + 1] = background
    self.parts[#self.parts + 1] = label(parent, "Bank Tags", x + 10, 12, width - 20, 28, GOLD)
    self:AddToggle(parent, "showTagSprites", "Show tag sprites", x + 10, 50,
        width - 20, "Display the selected item icon beside each tag")
    self.parts[#self.parts + 1] = label(parent, "New tagged items", x, 90, width, 20, GOLD)
    self.placement = prettyui.ComboBox.new(parent, {
        x = x, y = 114, width = width, height = 30,
        font = id.Font.MUSEO_SANS_11PT_REGULAR,
        entries = {
            { id = "preserve", label = "Preserve layout (tag only)", order = 1 },
            { id = "fill", label = "Fill first empty slot", order = 2 },
        },
        selectedID = self.settings.preserveTagLayout and "preserve" or "fill",
        onChange = function(_, selected) self:Change("preserveTagLayout", selected == "preserve") end,
    })
    self:AddToggle(parent, "enableDebug", "Enable debug logging", x + 10, 158, width - 20,
        "Write Bank Tags diagnostics to the client log")
    self.status = prettyui.Text.new(parent, {
        text = "", x = x, y = 198, width = width, height = 60,
        font = id.Font.MUSEO_SANS_11PT_REGULAR,
        colour = 0xE57373FF, maxLines = 3,
    })
    self.status.hidden = true
    return self
end

-- Add one checkbox for a boolean preference
function SettingsSection:AddToggle(parent, key, text, x, y, width, tooltip)
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

-- Save a change at once, restoring the control if refused
function SettingsSection:Change(key, enabled)
    if self.destroyed then return false end
    local saved, reason = self.options.onChange(key, enabled)
    if saved then
        self.settings[key] = enabled
    elseif key == "preserveTagLayout" then
        self.placement:Select(self.settings[key] and "preserve" or "fill", false)
    else
        self.controls[key]:SetSelected(key, self.settings[key], false)
    end
    self.status.content = saved and "" or tostring(reason or "Could not save the setting.")
    self.status.hidden = saved == true
    return saved, reason
end

-- Release the section controls
function SettingsSection:Destroy()
    if self.destroyed then return end
    self.destroyed = true
    for _, control in pairs(self.controls) do pcall(function() control:Destroy() end) end
    for _, control in ipairs(self.parts) do pcall(function() control:Destroy() end) end
    for _, control in ipairs({ self.placement, self.status }) do
        pcall(function() control:Destroy() end)
    end
    self.controls, self.parts = {}, {}
end

return SettingsSection
