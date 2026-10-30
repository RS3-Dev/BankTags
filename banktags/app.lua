-- Compose Bank Tags and connect it to Bank Core's public API

local Config = require("banktags/core/config")
local DebugLog = require("banktags/core/debug_log")
local ImportAPI = require("banktags/imports/import_api")
local SelectMode = require("banktags/sidebar/select_mode")
local Settings = require("banktags/core/settings")
local SettingsSection = require("banktags/windows/settings_section")
local TagDraft = require("banktags/imports/tag_draft")
local TagMenus = require("banktags/sidebar/tag_menus")
local TagPage = require("banktags/tags/tag_page")
local TagStore = require("banktags/tags/tag_store")
local TagTab = require("banktags/sidebar/tag_tab")
local Windows = require("banktags/windows/windows")
local Tutorial = require("banktags/windows/tutorial")
local debugLog = DebugLog.Write

local App = {}
App.__index = App

-- What the Tags tab says when Bank Core cannot show a tag now
local OPEN_REFUSALS = {
    not_all_items = 'Select "All Items" to view this tag.',
    preset_open = 'Close the preset selector to view this tag.',
    bank_closed = "Open your bank to view this tag.",
    busy = "The bank is still updating. Try again.",
}
-- Bank Tags' preferences draw on its own plugin panel
local CONTENT_EVENT = Config.PLUGIN_REF .. "_content"

-- Find Bank Core's API, trying the one passed in before the global copy
local function findBank()
    local api = bankcore or rawget(_G, Config.CORE_API_KEY)
    return type(api) == "table" and type(api.Register) == "function" and api or nil
end

-- Build the store, windows, tab, and import API before connecting to Bank Core
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
        -- The tag whose page was set last, counted by revision, with each page slot's layout key
        pageTag = nil,
        revision = 0,
        pageKeys = {},
        bankItems = nil,
        -- A notice the Tags tab shows
        status = nil,
        -- Preferences drawn on the plugin panel
        settingsSection = nil,
        started = false,
        shutDown = false,
    }, App)
    app.imports = ImportAPI.new({
        readDraft = TagDraft.Read,
        onChange = function() app.windows:RefreshImportSources() end,
    })
    app.publicAPI = app.imports.publicAPI
    app.windows = Windows.new(app)
    app.select = SelectMode.new(app)
    app.menus = TagMenus.new(app)
    app.tab = TagTab.new(app)
    app.tutorial = Tutorial.new(app)
    if store.loadError ~= nil then app.status = store.loadError end
    return app
end

-- Draw preferences on the plugin panel and connect to Bank Core if it runs
function App:Start()
    if self.shutDown or self.started then return end
    self.started = true
    Event.ContentLayerReady.Subscribe(CONTENT_EVENT, function(event) self:MountSettings(event.component) end)
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
        onBankClose = function()
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
    self.menus:Start()
    debugLog("Bank Tags connected to Bank Core")
    return true
end

-- Drop the extension and everything that needs Bank Core
function App:Disconnect()
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

-- Read bank items, keeping the last good copy while Bank Core cannot read them
function App:OnBankItems()
    if self.ext == nil then return end
    local items = self.ext:GetBankItems()
    if items ~= nil then
        self.bankItems = items
        self.windows:BankItemsChanged()
    end
    self.windows:CheckBankBounds()
    self.tutorial:Offer()
end

-- Return the bank's items as last read, or an empty list
function App:BankItems()
    return self.bankItems or {}
end

-- Show a short notice in the Tags tab, or clear it with nil
function App:ShowStatus(text)
    if self.status == text then return end
    self.status = text
    self.tab:Refresh()
end

-- Give Bank Core a tag's page, or explain why it cannot be shown
-- Each page set is a new revision, so menu entries offered over the old one are dropped
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

-- Show a tag in place of whatever the bank shows, explaining a refusal in the Tags tab
function App:ShowTag(tag)
    if self.ext == nil or self.store.data.tags[tag] == nil then return false end
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
    self:ShowStatus(problem)
    self.tab:Refresh()
    return shown
end

-- Show a tag, or return to the bank's own view when that tag is already shown
function App:ToggleTag(tag)
    if self:ShownTag() == tag then
        local left = self.ext:Close()
        self.tab:Refresh()
        return left
    end
    return self:ShowTag(tag)
end

-- Refresh what shows the store
-- A tag names the only tag whose items or layout changed; nil means anything may have
function App:Changed(tag)
    -- The Tags tab shows only tag names and folders
    if tag == nil then self.tab:Refresh() end
    self.windows:StoreChanged(tag)
    local shown = self:ShownTag()
    -- Redraw the shown tag in place, or leave it once it is gone or too large to show
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
    self.store:SetFolderCollapsed(folderKey, not folder.collapsed)
    self:Changed()
    return true
end

-- File a tag under a folder, or ungroup it when the folder key is nil
function App:MoveTagToFolder(tag, folderKey)
    local saved, reason = self.store:SetTagFolder(tag, folderKey)
    if not saved then
        self:ShowStatus(tostring(reason))
        return false
    end
    -- Expand the destination so the moved tag stays visible
    if folderKey ~= nil then self.store:SetFolderCollapsed(folderKey, false) end
    self:Changed()
    return true
end

-- Move a tag or folder in the Tags tab, saving the new order once
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

-- Draw preferences on the plugin panel
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
    -- Clean up one part, logging a failure so the others still run
    local function cleanup(label, action)
        local ok, message = pcall(action)
        if not ok then debugLog("Bank Tags shutdown could not clean ", label, ": ", message) end
    end
    cleanup("select mode", function() self.select:Forget() end)
    cleanup("settings", function()
        Event.ContentLayerReady.Unsubscribe(CONTENT_EVENT)
        self:DestroySettings()
    end)
    cleanup("windows", function() self.windows:CloseAll() end)
    cleanup("Bank Core registration", function() self:Disconnect() end)
    cleanup("import sources", function() self.imports:Close() end)
end

return App
