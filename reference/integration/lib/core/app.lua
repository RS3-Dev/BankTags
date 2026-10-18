-- Compose Bank Utilities: its tag, query, and settings stores, the tags, cleanup, search,
-- and saved-query features, windows, plugin panel, and right-click entries, attached to the
-- running bank core. App.new builds everything without attaching or subscribing; the core
-- plugin owns the only bank session, and main.lua connects this app to it

local DebugLog = require("lib/core/debug_log")
local BankFeatures = require("lib/features/bank_features")
local PluginPanel = require("lib/features/settings/plugin_panel")
local QueryStore = require("lib/features/runesql/query_store")
local Settings = require("lib/core/settings")
local StandaloneWindows = require("lib/core/standalone_windows")
local StorageKeys = require("lib/features/storage_keys")
local TagDraft = require("lib/features/extensions/tag_draft")
local TagMenu = require("lib/features/tags/tag_menu")
local TagStore = require("lib/features/tags/tag_store")
local Text = require("lib/core/text")
local debugLog = DebugLog.Write

local App = {}
App.__index = App

-- The name the bank core knows these features by; a newer load replaces an older one
local FEATURE_ID = "bankutils"
-- The trusted feature attach this app speaks
local FEATURE_VERSION = 1
local CONTENT_EVENT = StorageKeys.PLUGIN_REF .. "_content"
local NOT_CONNECTED = "Bank Core is not running. Load or reload Bank Core, then reopen this panel."
local REPLACED = "A newer Bank Utilities took over; this copy is idle."
-- An Import window opened while no core is attached lists no sources and runs no request
local NO_IMPORTS = {
    Sources = function() return {} end,
    Begin = function() return nil end,
    Cancel = function() end,
}

-- Check whether a table is a running bank core that offers the feature attach
function App.IsCore(candidate)
    if type(candidate) ~= "table" or candidate.API_VERSION ~= 1 then return false end
    local features = candidate.Features
    if type(features) ~= "table" or features.VERSION ~= FEATURE_VERSION
        or type(features.Attach) ~= "function" then
        return false
    end
    return candidate.GetState().running == true
end

-- Read the launcher choices the single-plugin build saved, for the core to adopt once
local function legacyLauncherChoices()
    local ok, saved = pcall(function()
        return PersistentDB:GetStructuredData(StorageKeys.LEGACY_HEADER_LAUNCHERS_KEY)
    end)
    if not ok or type(saved) ~= "table" then return nil end
    return { order = saved.order, hidden = saved.hidden }
end

-- Load settings and stores and build the features, windows, and menus, attached to nothing
function App.new()
    local store = TagStore.new()
    local queryStore = QueryStore.new()
    local settings = Settings.load()
    store:SetLayoutPlacement(settings.preserveTagLayout)
    DebugLog.SetEnabled(settings.enableDebug)
    local app = setmetatable({
        store = store,
        queryStore = queryStore,
        settings = settings,
        -- The bank core this app attached to, its handle, and the Import window's sources
        core = nil,
        sessionHost = nil,
        importProviders = NO_IMPORTS,
        findCore = nil,
        features = nil,
        windows = nil,
        pluginPanel = nil,
        tagMenu = nil,
        inGame = Player.IsAvailable(),
        started = false,
        retired = false,
        shutDown = false,
    }, App)
    app.features = app:NewFeatures()
    app.windows = StandaloneWindows.new(app)
    app.tagMenu = TagMenu.new(app, { normalizeMenuText = Text.normalizeMenuText })
    return app
end

-- Create the bank-side features over the stores, with the editor and window callbacks
function App:NewFeatures()
    return BankFeatures.new(self.store, {
        settings = self.settings,
        queryStore = self.queryStore,
        onEditTag = function(tag, isNew) self.windows:OpenTagSettings(tag, isNew) end,
        onEditLayout = function(tag) self.windows:OpenLayoutEditor(tag) end,
        onOpenSettings = function() self.windows:OpenBankSettings() end,
        onCreateRuneQuery = function() self.windows:OpenRuneQueryEditor(nil) end,
        onEditRuneQuery = function(selection) self.windows:OpenRuneQueryEditor(selection) end,
    })
end

-- Report whether the features are attached to a running bank core
function App:IsConnected()
    return self.sessionHost ~= nil and self.sessionHost.IsOpen()
end

-- Attach fresh features to a running bank core through its trusted feature attach. A core
-- that stopped since the last attach is replaced by the one given; a newer copy of this
-- plugin that took the attachment while the core kept running retires this copy
function App:Connect(core)
    if self.shutDown then return false, "stopped" end
    if self:IsConnected() then return true end
    if self.sessionHost ~= nil and self.sessionHost.ClosedReason() == "replaced" then
        self.retired = true
    end
    if self.retired then return false, "replaced" end
    if not App.IsCore(core) then return false, "unavailable" end
    local features = self:NewFeatures()
    local host, reason = core.Features.Attach(self, {
        featureID = FEATURE_ID,
        bank = features,
        readDraft = TagDraft.Read,
        settings = self.settings,
        launcherPreferences = legacyLauncherChoices(),
        launcherPreferencesSource = StorageKeys.LEGACY_HEADER_LAUNCHERS_KEY,
    })
    if host == nil then
        debugLog("Bank Utilities could not attach to Bank Core: ", tostring(reason))
        return false, reason
    end
    self.core = core
    self.features = features
    self.sessionHost = host
    -- The Import window reads the session's sources through the feature handle
    self.importProviders = host.imports
    if self.pluginPanel ~= nil then self.pluginPanel:ShowNotice(nil) end
    debugLog("Bank Utilities attached to Bank Core")
    return true
end

-- Attach to the core the entry point finds, when not attached already
function App:Reconnect()
    if self.findCore == nil or self:IsConnected() then return self:IsConnected() end
    return self:Connect(self.findCore())
end

-- Save one supported panel preference and apply it to the attached bank immediately
function App:SetSetting(key, enabled)
    if self.shutDown then return false, "Bank Utilities is not running." end
    if type(Settings.defaults()[key]) ~= "boolean" or type(enabled) ~= "boolean" then
        return false, "The setting is invalid."
    end
    local nextSettings = Settings.copy(self.settings)
    nextSettings[key] = enabled
    local ok, saved = pcall(Settings.save, nextSettings)
    if not ok or not saved then return false, "Could not save the setting." end
    self.settings = nextSettings
    DebugLog.SetEnabled(nextSettings.enableDebug)
    -- Without a core the saved preferences reach the bank when the features next attach
    if self:IsConnected() then
        self.sessionHost:ApplySettings(nextSettings)
    else
        self.features:ApplySettings(nextSettings)
    end
    return true
end

-- Forget the player's launcher order and hidden launchers, which the bank core keeps
function App:ResetLauncherPreferences()
    if self.shutDown then return false, "Bank Utilities is not running." end
    if not self:IsConnected() then return false, "Bank Core is not running." end
    return self.sessionHost:ResetLauncherPreferences()
end

-- Explain why the panel's bank features are missing, or nothing while attached
function App:PanelNotice()
    if self:IsConnected() then return nil end
    return self.retired and REPLACED or NOT_CONNECTED
end

-- Mount preferences on this plugin's own ContentLayerReady host, as Unified Logs does,
-- attaching to a core that started since the features were last attached
function App:CreateContentLayer(parent)
    if self.shutDown then return end
    self:Reconnect()
    self:DestroyPluginPanel()
    self.pluginPanel = PluginPanel.new(parent, {
        settings = self.settings,
        notice = self:PanelNotice(),
        onChange = function(key, enabled) return self:SetSetting(key, enabled) end,
        onOpenImport = function() self.windows:OpenBankSettings() end,
        onOpenDebugConsole = function() self.windows:OpenDebugConsole() end,
        onResetLaunchers = function() return self:ResetLauncherPreferences() end,
    })
end

-- Remove the current host-owned settings view before releasing application state
function App:DestroyPluginPanel()
    if self.pluginPanel ~= nil then self.pluginPanel:Destroy() end
    self.pluginPanel = nil
end

-- Let an open layout editor answer the bank's right-click menu first
function App:AddWindowMenuEntries(event)
    return self.tagMenu:AddWindowMenuEntries(event)
end

-- Add the tag, folder, or saved-query row actions beneath the pointer
function App:AddSidebarMenuEntries(menu)
    return self.tagMenu:AddSidebarMenuEntries(menu)
end

-- Add Remove from the shown tag, or Add to the tag in select mode, for a bank item
function App:AddItemMenuEntries(menu, item)
    self.tagMenu:AddItemMenuEntries(menu, item)
end

-- Add Remove from the shown tag for the placeholder beneath the pointer
function App:AddPlaceholderMenuEntries(menu)
    self.tagMenu:AddPlaceholderMenuEntries(menu)
end

-- Show the current import sources in an open Import/Share window
function App:RefreshImportSources()
    self.windows:RefreshImportSources()
end

-- Cancel pending removals and close plugin windows when game UI becomes unavailable
function App:OnGameSuspended()
    self.inGame = false
    self.tagMenu:CancelPendingTagRemoval()
    self.windows:CloseAll()
end

-- Allow plugin windows again once the game UI returns
function App:OnGameResumed()
    self.inGame = true
end

-- Close plugin windows when the bank closes; Import/Share stays, as the panel opens it too
function App:OnBankClosed()
    self.windows:CloseAll(true)
end

-- Release removals, editor input, and every window before the core restores the bank and
-- closes this app's handles; the panel stays and says the core is gone
function App:OnSessionShutdown()
    local function cleanup(label, action)
        local ok, message = pcall(action)
        if not ok then
            debugLog("Bank Utilities could not clean ", label, " as Bank Core stopped: ", message)
        end
    end
    self.tagMenu:CancelPendingTagRemoval()
    self.windows:StopGlobalEvents()
    cleanup("windows", function() self.windows:CloseAll() end)
    self.importProviders = NO_IMPORTS
    if self.pluginPanel ~= nil then self.pluginPanel:ShowNotice(NOT_CONNECTED) end
end

-- Rebuild every tag list that shows folder grouping
function App:RefreshFolders()
    self.features:RefreshTags()
    if self.windows.layoutEditor ~= nil then self.windows.layoutEditor:RefreshTags() end
end

-- File a tag under a folder, or ungroup it when the folder key is nil
function App:MoveTagToFolder(tag, folderKey)
    local saved, reason = self.store:SetTagFolder(tag, folderKey)
    if not saved then
        debugLog("BankUtils could not move tag ", tag, " to a folder: ", tostring(reason))
        return false
    end
    -- Expand the destination so the moved tag stays visible
    if folderKey ~= nil then self.store:SetFolderCollapsed(folderKey, false) end
    self:RefreshFolders()
    return true
end

-- Remove a folder while keeping its tags
function App:DeleteFolder(folderKey)
    local saved, reason = self.store:DeleteFolder(folderKey)
    if not saved then
        debugLog("BankUtils could not ungroup the folder: ", tostring(reason))
        return false
    end
    self:RefreshFolders()
    return true
end

-- Remove a saved query and leave its active page before refreshing the sidebar
function App:DeleteRuneQuery(selection)
    local features = self.features
    local record = self.queryStore:GetBySelection(selection)
    if record == nil then
        debugLog("BankUtils could not find the RuneQL query to delete")
        features:RefreshTags()
        return false
    end

    local querySelection = QueryStore.SelectionID(record.id)
    local deleted, reason = self.queryStore:Delete(record.id)
    if not deleted then
        debugLog("BankUtils could not delete RuneQL query ", record.name,
            ": ", tostring(reason))
        return false
    end
    if features.selectedTag == querySelection then
        features:SetSelectedTag(nil)
    end
    if self.windows:IsEditingRuneQuery(record.id) then
        self.windows:Close("runeQueryEditor")
    end
    features.runeQueryCounts[tostring(record.id)] = nil
    features:RefreshTags()
    debugLog("BankUtils deleted RuneQL query ", record.name)
    return true
end

-- Create an ordinary editable tag from the saved query's current bank matches
function App:ConvertRuneQueryToTag(selection)
    local features = self.features
    if not features.nativeViewAll and features:DetectNativeViewAll() ~= true then
        features:ShowViewAllWarning()
        debugLog("BankUtils requires the native All Items tab before converting RuneQL")
        return false
    end

    local items, record, reason = features:RuneQueryResults(selection)
    if items == nil then
        debugLog("BankUtils could not convert RuneQL query: ", tostring(reason))
        return false
    end
    if #items == 0 then
        debugLog("BankUtils did not convert RuneQL query ", record.name,
            " because it has no results in the current bank")
        return false
    end

    local saved, tag, count, saveReason = self.store:CreateTagFromItems(
        record.name,
        items
    )
    if not saved then
        debugLog("BankUtils could not convert RuneQL query ", record.name,
            ": ", tostring(saveReason))
        return false
    end

    features:SetSidebarMode("tags")
    features:SetSelectedTag(tag)
    features:RefreshTags()
    debugLog("BankUtils converted RuneQL query ", record.name,
        " to tag ", tag, " with ", tostring(count), " items")
    return true
end

-- Subscribe this plugin's own panel event and attach to the core findCore returns, if one
-- runs. Bank Utilities subscribes to no bank, menu, inventory, or game-state event
function App:Start(findCore)
    if self.shutDown or self.started then return end
    self.started = true
    self.findCore = findCore
    Event.ContentLayerReady.Subscribe(CONTENT_EVENT, function(event)
        self:CreateContentLayer(event.component)
    end)
    self:Reconnect()
end

-- Stop Bank Utilities: release its panel event, removals, panel, and windows, then detach
-- its features from the core, which keeps running with every other plugin's pages
function App:Shutdown()
    if self.shutDown then return end
    self.shutDown = true
    local function cleanup(label, action)
        local ok, message = pcall(action)
        if not ok then
            debugLog("Bank Utilities shutdown could not clean ", label, ": ", message)
        end
    end
    if self.started then Event.ContentLayerReady.Unsubscribe(CONTENT_EVENT) end
    self.tagMenu:CancelPendingTagRemoval()
    self.windows:StopGlobalEvents()
    cleanup("plugin panel", function() self:DestroyPluginPanel() end)
    cleanup("windows", function() self.windows:CloseAll() end)
    if self:IsConnected() then
        cleanup("bank features", function() self.sessionHost.Detach() end)
    end
    local features = self.features
    features.onEditTag = nil
    features.onEditLayout = nil
    features.onOpenSettings = nil
    features.onCreateRuneQuery = nil
    features.onEditRuneQuery = nil
    self.core = nil
    self.sessionHost = nil
    self.importProviders = NO_IMPORTS
    self.findCore = nil
    self.store = nil
    self.queryStore = nil
    self.settings = nil
end

return App
