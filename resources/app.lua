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
    stale = "Bank Tags lost its connection to Bank Core. Reload Bank Tags and try again.",
    no_page = "This tag has no prepared page. Select the tag again.",
    failed = "Bank Core could not draw this tag. Try again.",
}
-- Bank Tags' preferences draw on its own Plugin Hub settings page
local SETTINGS_EVENT = Config.PLUGIN_REF .. "_settings"
local CONNECTION_EVENT = Config.PLUGIN_REF .. "_core_connection"
local RESTORE_ACTION_EVENT = Config.PLUGIN_REF .. "_restore_action"
local RESTORE_INVENTORY_EVENT = Config.PLUGIN_REF .. "_restore_inventory"

-- Subscribe (handler) or unsubscribe (nil) safely when Event[name] exists
local function setEvent(name, key, handler)
    local target = type(Event) == "table" and Event[name] or nil
    if type(target) ~= "table" then return end
    local method = handler ~= nil and target.Subscribe or target.Unsubscribe
    if type(method) == "function" then method(key, handler) end
end

-- Normalize a native mini-menu verb, stripping markup and outer spaces
local function menuVerb(event)
    local verb = event and event.entry and event.entry.verbText
    return type(verb) == "string" and string.lower(verb:gsub("<[^>]->", ""):match("^%s*(.-)%s*$")) or nil
end

-- Check whether an inventory update came from the bank container
local function isBankInventoryEvent(event)
    local bankInvID = type(id) == "table" and type(id.Inv) == "table" and id.Inv.BANK or nil
    return bankInvID ~= nil and event and event.inv and event.inv.id == bankInvID
end

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
        -- Session-only page restoration state
        restoreTag = nil,
        sidebarSelected = false,
        pendingRestore = nil,
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
    local ticks = 0
    Event.Logic.Subscribe(CONNECTION_EVENT, function()
        ticks = ticks + 1
        if ticks % 50 == 0 then self:CheckConnection() end
    end)
end

-- Recover a missing or stopped registration without replacing a live one
function App:CheckConnection()
    if self.shutDown then return end
    if self.ext ~= nil then
        local state, reason = self.ext:GetBankState()
        if state ~= nil or reason ~= "stale" then return end
    end
    self:Connect()
end

-- Register with Bank Core, replacing any earlier registration
function App:Connect()
    if self.shutDown then return false, "stopped" end
    self:Disconnect()
    local api = findBank()
    if api == nil then return false, "unavailable" end
    local function tryRegister(spec)
        local ext, reason, detail = api.Register(spec)
        -- An injected export may still refer to the session Core just stopped
        if ext == nil and reason == "stopped" then
            local published = rawget(_G, Config.CORE_API_KEY)
            if type(published) == "table" and type(published.Register) == "function" and published ~= api then
                ext, reason, detail = published.Register(spec)
            end
        end
        return ext, reason, detail
    end
    local registration = {
        id = Config.PLUGIN_REF,
        name = Config.OWNER_LABEL,
        icon = "LIST_LAYOUT",
        column = self.tab.callbacks,
        onSelect = function() self:OnSidebarSelected() end,
        onDeselect = function() self:OnSidebarDeselected() end,
        onClose = function() self:OnPageClosed() end,
        onBankItems = function() self:OnBankItems() end,
        onBankStateChanged = function(state) self:OnBankStateChanged(state) end,
        onBankClose = function() self:OnBankClose() end,
    }
    local ext, reason, detail = tryRegister(registration)
    -- Fall back gracefully when connected to an older Bank Core without selection hooks
    if ext == nil and reason == "invalid" then
        registration.onSelect, registration.onDeselect = nil, nil
        ext, reason, detail = tryRegister(registration)
        if ext ~= nil then
            debugLog("Bank Core rejected sidebar selection hooks; update Bank Core to 1.1.5+ for tag restoration")
        end
    end
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
    self:CancelPendingRestore()
    self:ClearStateNotice()
    self.sidebarSelected = false
    if self.tab ~= nil and self.tab.ResetScroll ~= nil then self.tab:ResetScroll() end
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

-- Wait for All Items or bank readiness, canceling if the player does another action first
function App:StartPendingRestore(mode)
    self.pendingRestore = mode
    setEvent("MiniMenuEntrySelected", RESTORE_ACTION_EVENT, function(event)
        local verb = menuVerb(event)
        if self.pendingRestore == nil or (verb ~= "view all" and verb ~= "cancel") then
            self:CancelPendingRestore()
        end
    end)
    setEvent("InventoryUpdated", RESTORE_INVENTORY_EVENT, function(event)
        if self.pendingRestore == "not_all_items" and isBankInventoryEvent(event) then
            self:CancelPendingRestore()
        end
    end)
end

-- Stop waiting to restore the last viewed tag
function App:CancelPendingRestore()
    if self.pendingRestore == nil then return end
    self.pendingRestore = nil
    setEvent("MiniMenuEntrySelected", RESTORE_ACTION_EVENT, nil)
    setEvent("InventoryUpdated", RESTORE_INVENTORY_EVENT, nil)
end

-- Reopen the previous tag quietly, or defer/cancel when blocked
function App:TryRestore(blocked, pending)
    local mode = pending and self.pendingRestore or nil
    if pending and mode == nil then return false end
    local tag = self.restoreTag
    if self.ext == nil or not self.sidebarSelected
        or (self.settings ~= nil and self.settings.restoreLastTag == false)
        or self:ShownTag() ~= nil
        or (self.select ~= nil and self.select.Tag ~= nil and self.select:Tag() ~= nil)
        or tag == nil or self.store.data.tags[tag] == nil then
        if tag ~= nil and self.store.data.tags[tag] == nil then self.restoreTag = nil end
        if pending then self:CancelPendingRestore() end
        return false
    end
    if not pending then blocked = bankStateBlocker(self.ext:GetBankState()) end
    if blocked == nil then
        if pending then self:CancelPendingRestore() end
        local shown, reason = self:ShowTag(tag, true)
        if not shown and (reason == "not_all_items" or reason == "bank_closed" or reason == "busy") then
            self:StartPendingRestore(reason == "not_all_items" and "not_all_items" or "attaching")
        end
        return shown, reason
    end
    if blocked == "not_all_items" then
        if not pending or mode == "attaching" then self:StartPendingRestore("not_all_items") end
    elseif blocked == "bank_closed" and (not pending or mode == "attaching") then
        if not pending then self:StartPendingRestore("attaching") end
    elseif pending then
        self:CancelPendingRestore()
    end
    return false, blocked
end

-- Track sidebar selection and restore the previously open tag when available
function App:OnSidebarSelected()
    self.sidebarSelected = true
    self:CancelPendingRestore()
    self:TryRestore(nil, false)
end

-- Track sidebar deselection and cancel any deferred restore
function App:OnSidebarDeselected()
    self.sidebarSelected = false
    self:CancelPendingRestore()
    self:ClearStateNotice()
end

-- Update restoration memory after a tag page closes
function App:OnPageClosed()
    local blocked = self.ext ~= nil and bankStateBlocker(self.ext:GetBankState()) or nil
    -- Explicit return to the normal bank while selected forgets the restored tag
    if self.sidebarSelected and self:ShownTag() == nil and blocked == nil then
        self.restoreTag = nil
    end
    self.tab:Refresh()
end

-- Stop bank tools when the bank closes
function App:OnBankClose()
    self.sidebarSelected = false
    self:CancelPendingRestore()
    self:ClearStateNotice()
    if self.tab ~= nil and self.tab.ResetScroll ~= nil then self.tab:ResetScroll() end
    self.nativeItems:Stop()
    self.tutorial:Stop(false)
    self.select:Stop()
    self.windows:CloseBankWindows()
end

-- Close tag pages quietly when native controls restrict the bank
function App:OnBankStateChanged(state)
    local blocked = bankStateBlocker(state)
    if blocked == nil then self:ClearStateNotice() end
    if blocked ~= nil and self.ext ~= nil and self.ext:IsOpen() then
        local closed, reason = self.ext:Close()
        if not closed then
            self:ShowStatus(OPEN_REFUSALS[reason] or ("This tag could not be closed (" .. tostring(reason) .. ")."))
            return blocked
        end
        self.tab:Refresh()
    end
    if self.pendingRestore ~= nil then self:TryRestore(blocked, true) end
    return blocked
end

-- Track restriction notices so returning to an available bank clears them
function App:ShowStateNotice(reason)
    self.stateNotice = OPEN_REFUSALS[reason] or ("This tag could not be shown (" .. tostring(reason) .. ").")
    self:ShowStatus(self.stateNotice)
end

-- Clear any active restriction notice without touching unrelated errors
function App:ClearStateNotice()
    local notice = self.stateNotice
    self.stateNotice = nil
    if notice ~= nil and self.status == notice then self:ShowStatus(nil) end
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
    if self.pendingRestore ~= nil and self.sidebarSelected then
        self:TryRestore(bankStateBlocker(self.ext:GetBankState()), true)
    end
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

-- Show a tag, explaining refusals over the bank title unless quiet
function App:ShowTag(tag, quiet)
    if not quiet then self:CancelPendingRestore() end
    if self.ext == nil or self.store.data.tags[tag] == nil then return false end
    local blocked = quiet and bankStateBlocker(self.ext:GetBankState())
        or self:OnBankStateChanged(self.ext:GetBankState())
    if blocked ~= nil then
        if not quiet then
            self:ShowStateNotice(blocked)
            if blocked == "not_all_items" and self.ext.HighlightAllItems ~= nil then
                self.ext:HighlightAllItems()
            end
            self.tab:Refresh()
        end
        return false, blocked
    end
    -- Core copies native sprite styles when opening a page
    self.nativeItems:RestoreHighlights()
    local previousTag, previousKeys, previousRevision = self.pageTag, self.pageKeys, self.revision
    local shown, problem = self:SetTagPage(tag)
    local openReason
    if shown then
        local reason
        shown, reason = self.ext:Open()
        openReason = reason
        if not shown then
            problem = OPEN_REFUSALS[reason] or ("This tag could not be shown (" .. tostring(reason) .. ").")
            -- A refusal can leave the previous tag page displayed
            self.pageTag, self.pageKeys, self.revision = previousTag, previousKeys, previousRevision
        end
    end
    -- Select mode works over the bank's own view, so a shown tag ends it
    if shown then
        self.restoreTag = tag
        self.select:Stop()
        self:ClearStateNotice()
    end
    if not shown then self.nativeItems:Refresh() end
    if not quiet then
        if openReason == "not_all_items" or openReason == "preset_open" or openReason == "bank_closed" then
            self:ShowStateNotice(openReason)
        else
            self:ShowStatus(problem)
        end
    end
    if shown or not quiet then self.tab:Refresh() end
    return shown, openReason
end

-- Toggle between a tag and the normal bank
function App:ToggleTag(tag)
    self:CancelPendingRestore()
    if self:ShownTag() == tag then
        local left, reason = self.ext:Close()
        if left then
            self.restoreTag = nil
        else
            self:ShowStatus(OPEN_REFUSALS[reason] or ("This tag could not be closed (" .. tostring(reason) .. ")."))
        end
        self.tab:Refresh()
        return left, reason
    end
    return self:ShowTag(tag)
end

-- Refresh views affected by a saved change
function App:Changed(tag)
    if self.restoreTag ~= nil and self.store.data.tags[self.restoreTag] == nil then
        self.restoreTag = nil
        self:CancelPendingRestore()
    end
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
            if self.restoreTag == shown then self.restoreTag = nil end
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
    if self.restoreTag == oldTag then self.restoreTag = newTag end
    self:Changed()
end

-- Add a slot for an object to a tag
function App:AddItemToTag(tag, objectID)
    self:CancelPendingRestore()
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
    self:CancelPendingRestore()
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
    self:CancelPendingRestore()
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
    self:CancelPendingRestore()
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
    self:CancelPendingRestore()
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
    self:CancelPendingRestore()
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
    if key == "restoreLastTag" and not value then self:CancelPendingRestore() end
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
    Event.Logic.Unsubscribe(CONNECTION_EVENT)
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
