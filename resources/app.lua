-- Compose Bank Tags and connect it to Bank Core's public API

local Config = require("resources/core/config")
local DebugLog = require("resources/core/debug_log")
local NativeItems = require("resources/tags/native_items")
local SelectMode = require("resources/sidebar/select_mode")
local Settings = require("resources/core/settings")
local SettingsSection = require("resources/windows/settings_section")
local TagMenus = require("resources/sidebar/tag_menus")
local TagPage = require("resources/tags/tag_page")
local TagStore = require("resources/tags/tag_store")
local TagTab = require("resources/sidebar/tag_tab")
local Windows = require("resources/windows/windows")
local Tutorial = require("resources/windows/tutorial")
local debugLog = DebugLog.Write

local App = {}
App.__index = App

-- Explain why Bank Core cannot show a tag
local OPEN_REFUSALS = {
    not_all_items = 'Select "All Items" to view this tag.',
    preset_open = 'Close the preset selector to view this tag.',
    search_active = "Clear the bank search to view this tag.",
    filter_active = "Clear the bank filter to view this tag.",
    bank_closed = "Open your bank to view this tag.",
    busy = "The bank is still updating. Try again.",
}
-- Bank Tags' preferences draw on its own Plugin Hub settings page
local SETTINGS_EVENT = Config.PLUGIN_REF .. "_settings"

-- Find the native state blocking tag pages
local function bankStateBlocker(state)
    if state == nil then return "stale" end
    if not state.bankOpen then return "bank_closed" end
    if state.presetOpen then return "preset_open" end
    if state.searchActive then return "search_active" end
    if state.filterActive then return "filter_active" end
    if not state.viewAll then return "not_all_items" end
    return nil
end

-- Find Bank Core's available public API
local function findBank()
    local api = bankcore or rawget(_G, Config.CORE_API_KEY)
    return type(api) == "table" and type(api.Register) == "function" and api or nil
end

-- Build the plugin's store, windows, and sidebar
function App.new()
    local settings = Settings.load()
    DebugLog.SetEnabled(settings.enableDebug)
    local store = TagStore.new()
    store:SetLayoutPlacement(settings.preserveTagLayout)
    local app = setmetatable({
        store = store,
        settings = settings,
        -- This plugin's extension with Bank Core
        ext = nil,
        -- The last page, its revision, and its item keys
        pageTag = nil,
        revision = 0,
        pageKeys = {},
        bankItems = nil,
        -- A notice shown over the bank title
        status = nil,
        -- Preferences drawn on the Plugin Hub settings page
        settingsSection = nil,
        started = false,
        shutDown = false,
    }, App)
    app.windows = Windows.new(app)
    app.select = SelectMode.new(app)
    app.menus = TagMenus.new(app)
    app.tab = TagTab.new(app)
    app.nativeItems = NativeItems.new(app)
    app.tutorial = Tutorial.new(app)
    if store.loadError ~= nil then app.status = store.loadError end
    return app
end

-- Show preferences and connect to Bank Core
function App:Start()
    if self.shutDown or self.started then return end
    self.started = true
    Event.SettingsLayerReady.Subscribe(SETTINGS_EVENT, function(event) self:MountSettings(event.component) end)
    self:Connect()
end

-- Register with Bank Core, replacing any earlier registration
function App:Connect()
    if self.shutDown then return false, "stopped" end
    self:Disconnect()
    local api = findBank()
    if api == nil then return false, "unavailable" end
    local ext, reason, detail = api.Register({
        id = Config.PLUGIN_REF,
        name = Config.OWNER_LABEL,
        icon = "LIST_LAYOUT",
        column = self.tab.callbacks,
        onClose = function() self.tab:Refresh() end,
        onBankItems = function() self:OnBankItems() end,
        onBankStateChanged = function(state) self:OnBankStateChanged(state) end,
        -- Stop bank tools when the bank closes
        onBankClose = function()
            self.nativeItems:Stop()
            self.tutorial:Stop(false)
            self.select:Stop()
            self.windows:CloseBankWindows()
        end,
    })
    if ext == nil then
        debugLog("Bank Tags could not register with Bank Core: ", tostring(reason), " ", tostring(detail))
        return false, reason
    end
    self.ext = ext
    self:OnBankStateChanged(ext:GetBankState())
    self.nativeItems:Start()
    self.menus:Start()
    debugLog("Bank Tags connected to Bank Core")
    return true
end

-- Drop the extension and everything that needs Bank Core
function App:Disconnect()
    self.nativeItems:Stop()
    self.tutorial:Stop(false)
    self.windows:CloseBankWindows()
    self.menus:Stop()
    self.select:Forget()
    local ext = self.ext
    self.ext, self.pageTag, self.pageKeys, self.bankItems = nil, nil, {}, nil
    if ext ~= nil then pcall(function() ext:Dispose() end) end
end

-- Return the tag the bank shows now, or nil
function App:ShownTag()
    return self.ext ~= nil and self.ext:IsOpen() and self.pageTag or nil
end

-- Close tag pages when native controls restrict the bank
function App:OnBankStateChanged(state)
    local blocked = bankStateBlocker(state)
    if blocked ~= nil and self.ext:IsOpen() then
        self.ext:Close()
        self.tab:Refresh()
    end
    return blocked
end

-- Refresh bank items when a new list is available
function App:OnBankItems()
    if self.ext == nil then return end
    self.nativeItems:Start()
    local items = self.ext:GetBankItems()
    if items ~= nil then
        self.bankItems = items
        self.windows:BankItemsChanged()
    end
    self.windows:CheckBankBounds()
    self.tutorial:Offer()
end

-- Return the last known bank items
function App:BankItems()
    return self.bankItems or {}
end

-- Show a bank banner notice, or clear it
function App:ShowStatus(text)
    if self.status == text then return end
    self.status = text
    self.tab:RefreshStatus()
end

-- Set a tag's page and retire old menu actions
function App:SetTagPage(tag)
    local page, keys = TagPage.Build(self.store, tag)
    if page == nil then return false, keys end
    local ok, reason, detail = self.ext:SetPage(page)
    if not ok then
        debugLog("Bank Core refused the page for ", tag, ": ", tostring(reason), " ", tostring(detail))
        return false, "This tag could not be shown (" .. tostring(reason) .. ")."
    end
    self.pageTag, self.pageKeys = tag, keys
    self.revision = self.revision + 1
    return true, nil
end

-- Show a tag, explaining refusals over the bank title
function App:ShowTag(tag)
    if self.ext == nil or self.store.data.tags[tag] == nil then return false end
    local blocked = self:OnBankStateChanged(self.ext:GetBankState())
    if blocked ~= nil then
        self:ShowStatus(OPEN_REFUSALS[blocked] or ("This tag could not be shown (" .. blocked .. ")."))
        return false
    end
    -- Core copies native sprite styles when opening a page
    self.nativeItems:RestoreHighlights()
    local shown, problem = self:SetTagPage(tag)
    if shown then
        local reason
        shown, reason = self.ext:Open()
        if not shown then
            problem = OPEN_REFUSALS[reason] or ("This tag could not be shown (" .. tostring(reason) .. ").")
        end
    end
    -- Select mode works over the bank's own view, so a shown tag ends it
    if shown then self.select:Stop() end
    if not shown then self.nativeItems:Refresh() end
    self:ShowStatus(problem)
    self.tab:Refresh()
    return shown
end

-- Toggle between a tag and the normal bank
function App:ToggleTag(tag)
    if self:ShownTag() == tag then
        local left = self.ext:Close()
        self.tab:Refresh()
        return left
    end
    return self:ShowTag(tag)
end

-- Refresh views affected by a saved change
function App:Changed(tag)
    -- The Tags tab shows only tag names and folders
    if tag == nil then self.tab:Refresh() end
    self.windows:StoreChanged(tag)
    local shown = self:ShownTag()
    -- Refresh the shown tag or close an unavailable page
    if shown ~= nil and (tag == nil or tag == shown) then
        local set, problem = false, nil
        if self.store.data.tags[shown] ~= nil then set, problem = self:SetTagPage(shown) end
        if not set then
            self.ext:Close()
            if problem ~= nil then self:ShowStatus(problem) end
            self.tab:Refresh()
        end
    end
    local selecting = self.select:Tag()
    if selecting ~= nil and self.store.data.tags[selecting] == nil then self.select:Stop() end
    if selecting ~= nil then self.nativeItems:Refresh() end
end

-- Follow a renamed tag before showing the change
function App:Renamed(oldTag, newTag)
    self.select:Rename(oldTag, newTag)
    self.windows:TagRenamed(oldTag, newTag)
    if self.pageTag == oldTag then self.pageTag = newTag end
    self:Changed()
end

-- Add a slot for an object to a tag
function App:AddItemToTag(tag, objectID)
    local saved, reason = self.store:AddTag(tag, objectID)
    if not saved then
        self:ShowStatus(tostring(reason))
        return false
    end
    self:ShowStatus(nil)
    self:Changed(tag)
    return true
end

-- Remove one slot from a tag
function App:RemoveFromTag(tag, layoutKey)
    local saved, reason, removed = self.store:RemoveTag(tag, layoutKey)
    if not saved then
        self:ShowStatus(tostring(reason))
        return false
    end
    if removed then self:Changed(tag) end
    return true
end

-- Collapse or expand a folder
function App:ToggleFolder(folderKey)
    local folder = self.store:GetFolder(folderKey)
    if folder == nil then return false end
    local saved, reason = self.store:SetFolderCollapsed(folderKey, not folder.collapsed)
    if not saved then
        self:ShowStatus(reason)
        return false
    end
    self:Changed()
    return true
end

-- Move a tag and expand its destination folder
function App:MoveTagToFolder(tag, folderKey)
    -- Save the move and folder expansion together
    local saved, reason = self.store:SaveTogether(function()
        local moved, problem = self.store:SetTagFolder(tag, folderKey)
        if not moved then return false, problem end
        if folderKey ~= nil then return self.store:SetFolderCollapsed(folderKey, false) end
        return true
    end)
    if not saved then
        self:ShowStatus(tostring(reason))
        return false
    end
    self:Changed()
    return true
end

-- Move a sidebar row and save its order
function App:MoveSidebarEntry(source, target, after)
    local saved, reason = self.store:MoveSidebarEntry(source, target, after)
    if not saved then
        if reason ~= nil then self:ShowStatus(tostring(reason)) end
        return false
    end
    self:Changed()
    return true
end

-- Remove a folder while keeping its tags
function App:DeleteFolder(folderKey)
    local saved, reason = self.store:DeleteFolder(folderKey)
    if not saved then
        self:ShowStatus(tostring(reason))
        return false
    end
    self:Changed()
    return true
end

-- Save one preference and apply it at once
function App:SetSetting(key, value)
    if self.shutDown then return false, "Bank Tags is not running." end
    local nextSettings = Settings.copy(self.settings)
    if type(nextSettings[key]) ~= "boolean" or type(value) ~= "boolean" then
        return false, "The setting is invalid."
    end
    nextSettings[key] = value
    if not Settings.save(nextSettings) then return false, "Could not save the setting." end
    self.settings = nextSettings
    DebugLog.SetEnabled(nextSettings.enableDebug)
    self.store:SetLayoutPlacement(nextSettings.preserveTagLayout)
    self:Changed()
    return true
end

-- Draw preferences on the Plugin Hub settings page
function App:MountSettings(parent)
    self:DestroySettings()
    self.settingsSection = SettingsSection.new(parent, {
        settings = self.settings,
        onChange = function(key, value) return self:SetSetting(key, value) end,
    })
end

-- Release the preferences' controls
function App:DestroySettings()
    if self.settingsSection ~= nil then self.settingsSection:Destroy() end
    self.settingsSection = nil
end

-- Stop Bank Tags, keeping saved tags as they are
function App:Shutdown()
    if self.shutDown then return end
    self.shutDown = true
    -- Release one part while allowing other cleanup to continue
    local function cleanup(label, action)
        local ok, message = pcall(action)
        if not ok then debugLog("Bank Tags shutdown could not clean ", label, ": ", message) end
    end
    cleanup("select mode", function() self.select:Forget() end)
    -- Release the settings listener and controls together
    cleanup("settings", function()
        Event.SettingsLayerReady.Unsubscribe(SETTINGS_EVENT)
        self:DestroySettings()
    end)
    cleanup("windows", function() self.windows:CloseAll() end)
    cleanup("Bank Core registration", function() self:Disconnect() end)
end

return App
