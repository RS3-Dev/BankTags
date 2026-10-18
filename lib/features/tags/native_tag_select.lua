-- Assign clicked native items to a tag and highlight its existing members

local StorageKeys = require("lib/features/storage_keys")
local BankInterface = require("lib/core/bank_interface")
local BankItemIdentity = require("lib/bank/bank_item_identity")
local NativeUi = require("lib/ui/native_ui")
local BankControls = require("lib/ui/bank_controls")
local debugLog = require("lib/core/debug_log").Write
local Theme = require("lib/ui/theme")

local NativeTagSelect = {}

local PULSE_EVENT = StorageKeys.PLUGIN_REF .. "_item_selection_pulse"
local DEFERRED_ADD_EVENT = StorageKeys.PLUGIN_REF .. "_item_selection_add"
local PULSE_PERIOD = 100
local TAGGED_OUTLINE_WIDTH = 2
local TAGGED_SHADOW_RGBA = 0xF2C66DFF
-- The select-mode panel covers the bank's right column (inventory, equipment,
-- and presets): 213px wide, 12px in from the window's right edge, 44px down.
-- Measuring from the right edge keeps it on the column in a resized bank
local PANEL_RIGHT_INSET = 12
local PANEL_Y = 44
local PANEL_WIDTH = 213
local PANEL_INSET = 12
local PANEL_FRAME = Theme.FRAME
local HEADING_COLOUR = Theme.HEADING_TEXT
local HEADING_LINE_COLOUR = Theme.HEADING_LINE
local TEXT_COLOUR = Theme.TEXT
local MUTED_COLOUR = Theme.MUTED_TEXT
local DONE_BUTTON_HEIGHT = 28

-- Collect copy-aware bank entries when the native item layer is available
local function bankItems()
    local layer = BankInterface.Find(BankInterface.ITEMS)
    if layer == nil then return {} end
    return BankItemIdentity.Collect(layer)
end

-- Create a click-through text line in the select-mode panel
local function panelText(parent, content, y, height, colour, maxLines)
    local text = ui.Text.new(parent)
    text:SetPos(PANEL_INSET, y)
    text:SetSize(-PANEL_INSET * 2, height, 1.0, 0)
    text.content = content
    text.font = id.Font.MUSEO_SANS_11PT_REGULAR
    text.rgba = colour
    text.isShadowed = true
    text.maxLines = maxLines or 1
    text.alignVertical = ui.AlignMode.CENTRE
    text.clickthrough = true
    return text
end

-- Create a filled click-through rectangle in the select-mode panel
local function panelRectangle(parent, x, y, width, height, colour, widthScale)
    local value = ui.Rectangle.new(parent)
    value:SetPos(x, y)
    value:SetSize(width, height, widthScale or 0, 0)
    value.fill = true
    value.rgba = colour
    value.clickthrough = true
    return value
end

-- Cover the bank's right column with the select-mode status and a Done button
-- The flashing tag row alone was too easy to miss
function NativeTagSelect:ShowItemSelectionPanel()
    self:DestroyItemSelectionPanel()
    local parent = self.components and self.components.all or nil
    local tag = self.itemSelectionTag
    if parent == nil or tag == nil then return false end
    local content = self.components.content
    local height = tonumber(content and content.height) or 594

    local panel = ui.Layer.new(parent)
    panel:SetPos(-(PANEL_WIDTH + PANEL_RIGHT_INSET), PANEL_Y, 1.0, 0)
    panel:SetSize(PANEL_WIDTH, height)
    -- Block the inventory and equipment beneath while selection is active
    panel.clickthrough = false
    local background = ui.Sprite.new(panel)
    background:SetSize(0, 0, 1.0, 1.0)
    background.spriteID = NativeUi.SPRITES.PANEL_BACKGROUND
    background.isTiling = true
    background.clickthrough = true
    panelRectangle(panel, 0, 0, 0, 1, PANEL_FRAME, 1.0)
    panelRectangle(panel, 0, height - 1, 0, 1, PANEL_FRAME, 1.0)
    panelRectangle(panel, 0, 0, 1, height, PANEL_FRAME)
    panelRectangle(panel, PANEL_WIDTH - 1, 0, 1, height, PANEL_FRAME)

    panelText(panel, "Select mode", PANEL_INSET, 22, HEADING_COLOUR)
    panelRectangle(panel, PANEL_INSET, PANEL_INSET + 22,
        -PANEL_INSET * 2, 1, HEADING_LINE_COLOUR, 1.0)

    local nameLeft = PANEL_INSET
    local objectID = self.store:GetTagSprite(tag)
    if objectID ~= nil then
        local icon = ui.Sprite.new(panel)
        icon:SetPos(PANEL_INSET, 46)
        icon:SetSize(32, 32)
        icon:SetAssociatedObject(objectID)
        icon.associatedObjectQuantityMode = ui.ObjectQuantityDisplayMode.NEVER
        icon.clickthrough = true
        nameLeft = PANEL_INSET + 40
    end
    local name = panelText(panel, self:DisplayTagName(tag), 46, 32, TEXT_COLOUR)
    name:SetPos(nameLeft, 46)
    name:SetSize(-nameLeft - PANEL_INSET, 32, 1.0, 0)

    panelText(panel, "Click items in your bank to add them to this tag.",
        92, 40, MUTED_COLOUR, 3)
    panelText(panel, "Items already in this tag have a white outline.",
        138, 40, MUTED_COLOUR, 3)
    -- Track the panel before the button so a failed button cannot strand it
    self.itemSelectionPanel = { root = panel }

    local created, done = pcall(BankControls.button, panel, "Done", function()
        self:StopItemSelection(true)
    end, {
        x = PANEL_INSET,
        y = height - PANEL_INSET - DONE_BUTTON_HEIGHT,
        width = PANEL_WIDTH - PANEL_INSET * 2,
        height = DONE_BUTTON_HEIGHT,
    })
    if created then
        self.itemSelectionPanel.done = done
    else
        debugLog("Bank Utilities could not create the select-mode Done button: ", done)
    end
    panel:MoveToFront()
    return true
end

-- Native bank rebuilds can redraw the right column above the panel
function NativeTagSelect:RaiseItemSelectionPanel()
    local panel = self.itemSelectionPanel
    if panel ~= nil then panel.root:MoveToFront() end
end

-- Remove the select-mode panel and uncover the bank's right column
function NativeTagSelect:DestroyItemSelectionPanel()
    local panel = self.itemSelectionPanel
    self.itemSelectionPanel = nil
    if panel == nil then return end
    if panel.done ~= nil then pcall(function() panel.done:Destroy() end) end
    pcall(function() panel.root:Destroy() end)
end

-- End the active tag-row pulse and restore its full opacity
function NativeTagSelect:StopItemSelectionPulse()
    Event.Logic.Unsubscribe(PULSE_EVENT)
    self.itemSelectionPulseTicks = 0
    for _, row in ipairs(self.list and self.list.rows or {}) do
        if row.entry ~= nil and row.entry.id == self.itemSelectionTag then
            if row.background ~= nil then row.background.alpha = 1 end
            for _, edge in ipairs(row.bankUtilitiesSelectionFrame or {}) do
                edge.alpha = 1
            end
        end
    end
end

-- Animate the selected tag row while item-selection mode remains active
function NativeTagSelect:UpdateItemSelectionPulse()
    if self.itemSelectionTag == nil or not self.active or not self.expanded
        or self.list == nil then
        self:StopItemSelectionPulse()
        return false
    end

    self.itemSelectionPulseTicks = (self.itemSelectionPulseTicks or 0) + 1
    local phase = (self.itemSelectionPulseTicks % PULSE_PERIOD) / PULSE_PERIOD
    local wave = 0.5 - 0.5 * math.cos(phase * math.pi * 2)
    local backgroundAlpha = 0.62 + wave * 0.38
    local borderAlpha = 0.4 + wave * 0.6
    for _, row in ipairs(self.list.rows or {}) do
        if row.entry ~= nil and row.entry.id == self.itemSelectionTag then
            if row.background ~= nil then row.background.alpha = backgroundAlpha end
            for _, edge in ipairs(row.bankUtilitiesSelectionFrame or {}) do
                edge.alpha = borderAlpha
            end
        end
    end
    return true
end

-- Start the tag-row pulse only for the current item-selection session
function NativeTagSelect:StartItemSelectionPulse()
    self:StopItemSelectionPulse()
    self.itemSelectionPulseTicks = 0
    Event.Logic.Subscribe(PULSE_EVENT, function()
        self:UpdateItemSelectionPulse()
    end)
    self:UpdateItemSelectionPulse()
end

-- Restore original native outlines and shadows when selection mode changes
function NativeTagSelect:RestoreItemSelectionVisuals()
    for _, visual in ipairs(self.itemSelectionVisuals or {}) do
        pcall(function()
            visual.component.outlineWidth = visual.outlineWidth
            visual.component.shadowRGBA = visual.shadowRGBA
        end)
    end
    self.itemSelectionVisuals = {}
end

-- Highlight current tag members while remembering every item's original appearance
function NativeTagSelect:RefreshItemSelectionVisuals()
    self:RestoreItemSelectionVisuals()
    local tag = self.itemSelectionTag
    if tag == nil or not self.active or not self.expanded then return false end

    local visuals = {}
    for _, item in ipairs(bankItems()) do
        local value = item.component
        local visual = {
            component = value,
            outlineWidth = tonumber(value.outlineWidth) or 0,
            shadowRGBA = tonumber(value.shadowRGBA) or 0,
        }
        visuals[#visuals + 1] = visual
        if self.store:HasTag(tag, item.layoutKey) then
            value.outlineWidth = math.max(
                visual.outlineWidth,
                TAGGED_OUTLINE_WIDTH
            )
            value.shadowRGBA = TAGGED_SHADOW_RGBA
        end
    end
    self.itemSelectionVisuals = visuals
    self:RaiseItemSelectionPanel()
    return true
end

-- Check whether item-selection mode is active for the requested tag
function NativeTagSelect:IsSelectingItemsForTag(tag)
    if tag == nil then return self.itemSelectionTag ~= nil end
    return self.itemSelectionTag == tag
end

-- Return the tag currently receiving native item selections
function NativeTagSelect:ItemSelectionTag()
    return self.itemSelectionTag
end

-- Cancel pending additions, stop the pulse, and restore native item appearance
function NativeTagSelect:StopItemSelection(refresh)
    local previous = self.itemSelectionTag
    Event.Logic.Unsubscribe(DEFERRED_ADD_EVENT)
    self.pendingItemSelections = {}
    self:StopItemSelectionPulse()
    self:RestoreItemSelectionVisuals()
    self:DestroyItemSelectionPanel()
    self.itemSelectionTag = nil
    if previous ~= nil then
        if refresh ~= false then self:RefreshTags() end
        debugLog("Bank Utilities stopped selecting items for tag ", previous)
    end
    return previous ~= nil
end

-- Leave filtered views and begin assigning native items to an ordinary tag
function NativeTagSelect:SetItemSelectionTag(tag)
    if tag == nil then return self:StopItemSelection(true) end
    if self.cleanupCategories:IsGenerated(tag) then return false end
    if self:IsPresetViewOpen() then
        debugLog("Bank Utilities item selection is unavailable while the preset selector is open")
        self:ShowPresetWarning()
        self:RefreshTags()
        return false
    end

    if self.itemSelectionTag ~= nil then self:StopItemSelection(false) end
    if self.selectedTag ~= nil then self:SetSelectedTag(nil) end
    self.itemSelectionTag = tag
    self:ShowItemSelectionPanel()
    self:UpdateLayoutControls()
    self:RefreshTags()
    self:StartItemSelectionPulse()
    debugLog("Bank Utilities selecting bank items for tag ", tag)
    return true
end

-- Start selection for a tag or stop it when that tag is already active
function NativeTagSelect:ToggleItemSelectionTag(tag)
    if self:IsSelectingItemsForTag(tag) then
        return self:StopItemSelection(true)
    end
    return self:SetItemSelectionTag(tag)
end

-- Queue native item selections until the menu action has finished on the next tick
function NativeTagSelect:AddItemToSelection(objectID, categoryID, dynamicID)
    local tag = self.itemSelectionTag
    objectID = math.tointeger(tonumber(objectID))
    if tag == nil or objectID == nil or not self.active or not self.expanded then
        return false
    end

    self.pendingItemSelections = self.pendingItemSelections or {}
    self.pendingItemSelections[#self.pendingItemSelections + 1] = {
        tag = tag,
        objectID = objectID,
        categoryID = categoryID,
        dynamicID = dynamicID,
    }
    Event.Logic.Unsubscribe(DEFERRED_ADD_EVENT)
    Event.Logic.Subscribe(DEFERRED_ADD_EVENT, function()
        Event.Logic.Unsubscribe(DEFERRED_ADD_EVENT)
        local pending = self.pendingItemSelections or {}
        self.pendingItemSelections = {}
        for _, selection in ipairs(pending) do
            if self.itemSelectionTag == selection.tag
                and self.active and self.expanded then
                self:CommitItemToSelection(selection)
            end
        end
    end)
    return true
end

-- Resolve the selected copy and save its tag membership before refreshing the sidebar
function NativeTagSelect:CommitItemToSelection(selection)
    local tag = selection and selection.tag or nil
    local objectID = selection and math.tointeger(tonumber(selection.objectID)) or nil
    if tag == nil or objectID == nil then return false end

    local itemKey = self:ResolveItemIdentity(objectID, selection.categoryID, selection.dynamicID)
    local saved, reason, added = self.store:AddTag(tag, objectID, itemKey)
    if not saved then
        debugLog("Bank Utilities could not add tag ", tag, ": ", tostring(reason))
        return false
    end
    if added then
        self:RefreshTags()
        debugLog("Bank Utilities added tag ", tag,
            " to object ", objectID, " in item-selection mode")
    end
    return true
end

-- Attach this module's methods to the owner that holds their shared state
function NativeTagSelect.install(target)
    for name, method in pairs(NativeTagSelect) do
        if name ~= "install" then target[name] = method end
    end
end

return NativeTagSelect
