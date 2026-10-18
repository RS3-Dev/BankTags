-- Render general preferences in the host's plugin content panel

local Settings = require("lib/core/settings")

local PluginPanel = {}
PluginPanel.__index = PluginPanel

local MAX_WIDTH = 280
local CONTENT_HEIGHT = 424
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

-- Match the dark group headers used by Unified Logs' plugin panel
local function header(parent, value, x, y, width)
    local background = ui.Rectangle.new(parent)
    background:SetPos(x, y)
    background:SetSize(width, 28)
    background.fill = true
    background.rgba = 0x2A231BFF
    background.clickthrough = true
    label(parent, value, x + 10, y, width - 20, 28, GOLD)
end

-- Mount scrollable preferences, placement choices, and the existing utility windows
function PluginPanel.new(parent, options)
    local self = setmetatable({
        options = options or {}, settings = Settings.copy(options and options.settings),
        controls = {}, destroyed = false,
        -- Why the bank features are missing, kept below any save message
        notice = options and options.notice or nil,
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
    header(content, "General", x, 12, width)
    self:AddToggle(content, "autoExpandSidebar", "Open sidebar automatically", x + 10, 50,
        width - 20, "Expand the bank sidebar whenever the bank opens")
    self:AddToggle(content, "showTagSprites", "Show tag sprites", x + 10, 80,
        width - 20, "Display the selected item icon beside each tag")
    self:AddToggle(content, "enableAdvancedSearch", "Enable advanced search", x + 10, 110,
        width - 20, 'Disables native "press s to search" functionality')
    self:AddToggle(content, "enableRuneSQL", "Enable RuneQL", x + 10, 140,
        width - 20, "Show saved RuneQL queries in the bank sidebar")
    label(content, "New tagged items", x, 180, width, 20, GOLD)
    self.placement = prettyui.ComboBox.new(content, {
        x = x, y = 204, width = width, height = 30,
        font = id.Font.MUSEO_SANS_11PT_REGULAR,
        entries = {
            { id = "preserve", label = "Preserve layout (tag only)", order = 1 },
            { id = "fill", label = "Fill first empty slot", order = 2 },
        },
        selectedID = self.settings.preserveTagLayout and "preserve" or "fill",
        onChange = function(_, selected) self:Change("preserveTagLayout", selected == "preserve") end,
    })
    self.importButton = prettyui.SimpleButton.new(content, "Import / Share tags", function()
        if not self.destroyed and self.options.onOpenImport ~= nil then self.options.onOpenImport() end
    end, { x = x, y = 248, width = width, height = 30 })
    -- Launchers are moved and hidden from their right-click menu; this undoes all of it
    self.resetLaunchersButton = prettyui.SimpleButton.new(content, "Reset header launchers", function()
        self:ResetLaunchers()
    end, { x = x, y = 288, width = width, height = 30 })

    self.debugSection = prettyui.CollapseButton.new(content, "Debug", {
        x = x, y = 334, width = width, indent = 10, expanded = false,
        onToggle = function() self:LayoutDebugSection() end,
    })
    self:AddToggle(self.debugSection.content, "enableDebug", "Enable debug", 0, 6, width - 20,
        "Show the filtered bank at 50% opacity and enable diagnostic logging")
    self.debugButton = self.debugSection:AddSimpleButton("Open debug console", function()
        if not self.destroyed and self.options.onOpenDebugConsole ~= nil then
            self.options.onOpenDebugConsole()
        end
    end, { x = 0, y = 38, width = width - 20, height = 30 })
    self.status = prettyui.Text.new(content, {
        text = "", x = x, y = 410, width = width, height = 40,
        font = id.Font.MUSEO_SANS_11PT_REGULAR,
        colour = 0xE57373FF, maxLines = 2,
    })
    self.status.hidden = true
    self:ShowResult(true)
    self:LayoutDebugSection()
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

-- Say why the bank features are missing, such as Bank Core not running, or clear it
function PluginPanel:ShowNotice(text)
    if self.destroyed then return end
    self.notice = text
    self:ShowResult(true)
end

-- Keep save feedback and the scroll range directly below the collapsed or expanded section
function PluginPanel:LayoutDebugSection()
    if self.destroyed then return end
    local root = self.debugSection.root
    local statusY = root.y + root.height + 14
    self.status:SetPos(root.x, statusY)
    self.view:SetContentHeight(statusY + 56)
end

-- Add one checkbox using the same selection callback contract as Unified Logs
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

-- Persist immediately and restore the control if the host rejects the save
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

-- Show every hidden header launcher again in its default order
function PluginPanel:ResetLaunchers()
    if self.destroyed or self.options.onResetLaunchers == nil then return false end
    local saved, reason = self.options.onResetLaunchers()
    self:ShowResult(saved, reason, "Could not reset the launchers.")
    return saved, reason
end

-- Release controls before replacing the host panel or unloading the plugin
function PluginPanel:Destroy()
    if self.destroyed then return end
    self.destroyed = true
    for _, control in pairs(self.controls) do control:Destroy() end
    for _, control in ipairs({ self.placement, self.importButton, self.resetLaunchersButton,
        self.debugSection, self.status }) do
        control:Destroy()
    end
    self.view:Destroy()
    self.controls = {}
end

return PluginPanel
