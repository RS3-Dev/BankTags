-- Compose Bank Tags and connect it to Bank Core's public API

local Config = require("banktags/core/config")
local DebugLog = require("banktags/core/debug_log")
local ImportAPI = require("banktags/imports/import_api")
local ItemIdentity = require("banktags/tags/item_identity")
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

local TAB_ID = "tags"
local NEEDS_ALL_ITEMS = 'Select "All Items" before adding items to tags.'

-- Find a running Bank Core API, trying the one passed in before the global copy
local function findBank()
    -- Loop by index since either one may be missing
    local candidates = { bankcore, rawget(_G, Config.CORE_API_KEY) }
    for index = 1, 2 do
        local candidate = candidates[index]
        if type(candidate) == "table" and type(candidate.RegisterExtension) == "function"
            and type(candidate.GetState) == "function" and candidate.GetState().running then
            return candidate
        end
    end
    return nil
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
        -- Bank Core's API and this plugin's owner handle
        bank = nil,
        handle = nil,
        -- What Bank Core last reported
        state = nil,
        shownTag = nil,
        bankItems = nil,
        pageRegistered = false,
        -- A notice the Tags tab shows
        status = nil,
        -- Preferences shown while their settings section is open
        settingsSection = nil,
        retired = false,
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
    -- Explain a tag too large for Bank Core to show
    app.noticeMount = { mount = function(ctx) app:DrawNotice(ctx) end }
    -- Bank Tags' section of Bank Core's settings window
    app.settingsMount = {
        mount = function(ctx) app:MountSettings(ctx.parent) end,
        unmount = function() app:DestroySettings() end,
    }
    if store.loadError ~= nil then app.status = store.loadError end
    return app
end

-- Connect to Bank Core if it runs
function App:Start()
    if self.shutDown or self.started then return end
    self.started = true
    self:Connect()
end

-- Report whether this plugin's owner is registered with a running Bank Core
function App:IsConnected()
    return self.handle ~= nil and self.handle:GetState().live == true
end

-- Register the tab, listener, and settings with Bank Core
function App:Connect()
    if self.shutDown then return false, "stopped" end
    if self:IsConnected() then return true end
    -- A newer load owns the ID now, so leave it
    if self.handle ~= nil and self.bank.GetState().running then
        self.handle, self.bank, self.retired = nil, nil, true
        self:Disconnect()
    end
    if self.retired then return false, "replaced" end
    self:Disconnect()
    local api = findBank()
    if api == nil then return false, "unavailable" end
    local handle, reason = api.RegisterExtension(Config.PLUGIN_REF, Config.OWNER_LABEL)
    if handle == nil then
        debugLog("Bank Tags could not register with Bank Core: ", tostring(reason))
        return false, reason
    end
    self.bank, self.handle = api, handle
    local ok, failure = handle:RegisterTab(TAB_ID, {
        label = "Tags", icon = "LIST_LAYOUT", tooltip = "Bank tags", mount = self.tab.callbacks,
    })
    if ok then
        ok, failure = handle:SetListener({
            onState = function(state) self:OnState(state) end,
            onPage = function(pageID, key) self:OnPage(pageID, key) end,
            onBankItems = function() self:OnBankItems() end,
            onBankClose = function()
                self.tutorial:Stop(false)
                self.windows:CloseBankWindows()
            end,
        })
    end
    if ok then ok, failure = handle:SetSettings({ mount = self.settingsMount }) end
    if not ok then
        debugLog("Bank Tags could not register its tab: ", tostring(failure))
        self:Disconnect()
        return false, failure
    end
    self.menus:Start()
    debugLog("Bank Tags connected to Bank Core")
    return true
end

-- Drop the owner handle and everything that needs Bank Core
function App:Disconnect()
    self.tutorial:Stop(false)
    self.windows:CloseBankWindows()
    self.menus:Stop()
    self.select:Forget()
    local handle = self.handle
    self.handle, self.bank = nil, nil
    self.state, self.shownTag, self.bankItems, self.pageRegistered = nil, nil, nil, false
    if handle ~= nil then pcall(function() handle:Dispose() end) end
end

-- Follow Bank Core's state; bank windows close on onBankClose
function App:OnState(state)
    self.state = state
    self.tutorial:Offer(state)
    self.select:Follow(state)
    self.windows:BankStateChanged(state)
end

-- Remember which tag Bank Core shows, if any
function App:OnPage(pageID, key)
    self.shownTag = pageID == TagPage.PAGE_ID and TagPage.TagFromKey(key) or nil
    self.tab:Refresh()
end

-- Read bank items, keeping the last good copy while loading
function App:OnBankItems()
    if self.handle == nil then return end
    local snapshot = self.handle:GetBankItems()
    if snapshot == nil then return end
    self.bankItems = snapshot
    self.windows:BankItemsChanged()
end

-- Return the bank's items as last read, or an empty list
function App:BankItems()
    return self.bankItems ~= nil and self.bankItems.items or {}
end

-- Show a short notice in the Tags tab, or clear it with nil
function App:ShowStatus(text)
    if self.status == text then return end
    self.status = text
    self.tab:Refresh()
end

-- Give Bank Core the page for a tag, registering the page the first time
function App:PutPage(tag)
    local page, notice = TagPage.Build(self.store, tag, self.noticeMount)
    if page == nil then return false, notice end
    self.notice = notice
    local ok, reason, detail
    if self.pageRegistered then
        ok, reason, detail = self.handle:UpdatePage(TagPage.PAGE_ID, page)
    else
        ok, reason, detail = self.handle:RegisterPage(TagPage.PAGE_ID, page)
        self.pageRegistered = ok == true
    end
    if not ok then debugLog("Bank Core refused the page for ", tag, ": ", tostring(reason), " ", tostring(detail)) end
    return ok, reason
end

-- Show a tag, only from the bank's All Items view
function App:ShowTag(tag)
    if self.handle == nil or self.store.data.tags[tag] == nil then return false end
    local ok, reason = self:PutPage(tag)
    if not ok then
        self:ShowStatus("This tag could not be shown (" .. tostring(reason) .. ").")
        return false
    end
    local ctx = self.tab.ctx
    local opened
    if ctx ~= nil then
        opened, reason = ctx:OpenPage(TagPage.PAGE_ID)
    else
        opened, reason = self.handle:OpenPage(TagPage.PAGE_ID)
    end
    if opened then self.shownTag = tag end
    self.tab:Refresh()
    return opened, reason
end

-- Show a tag, or return to the bank's own view when that tag is already shown
function App:ToggleTag(tag)
    if self.shownTag == tag and self.handle ~= nil then
        local left = self.handle:LeavePage()
        if left then self.shownTag = nil end
        self.tab:Refresh()
        return left
    end
    return self:ShowTag(tag)
end

-- Refresh everything that shows the store
function App:Changed()
    self.tab:Refresh()
    self.windows:StoreChanged()
    local tag = self.shownTag
    if tag ~= nil and self.handle ~= nil then
        if self.store.data.tags[tag] ~= nil then
            self:PutPage(tag)
        else
            self.handle:LeavePage()
        end
    end
    if self.select:Tag() ~= nil and self.store.data.tags[self.select:Tag()] == nil then
        self.select:Stop()
    else
        self.select:Refresh()
    end
end

-- Follow a renamed tag before showing the change
function App:Renamed(oldTag, newTag)
    self.select:Rename(oldTag, newTag)
    self.windows:TagRenamed(oldTag, newTag)
    if self.shownTag == oldTag and self.handle ~= nil then
        self.shownTag = newTag
        self:PutPage(newTag)
    end
    self:Changed()
end

-- Add one bank copy of an item to a tag
function App:AddItemToTag(tag, objectID, copy)
    if copy == nil then
        self:ShowStatus(NEEDS_ALL_ITEMS)
        return false
    end
    local saved, reason, added = self.store:AddTag(tag, objectID, ItemIdentity.LayoutKey(objectID, copy))
    if not saved then
        self:ShowStatus(tostring(reason))
        return false
    end
    self:ShowStatus(nil)
    if added then self:Changed() end
    return true
end

-- Remove one copy from a tag
function App:RemoveFromTag(tag, layoutKey)
    local saved, reason, removed = self.store:RemoveTag(tag, layoutKey)
    if not saved then
        self:ShowStatus(tostring(reason))
        return false
    end
    if removed then self:Changed() end
    return true
end

-- Create a tag holding a dropped item, then open it for naming
function App:CreateTagWithItem(objectID, copy)
    if copy == nil then
        self:ShowStatus(NEEDS_ALL_ITEMS)
        return false
    end
    local created, tag, reason = self.store:CreatePlaceholderTag()
    if not created then
        self:ShowStatus(tostring(reason))
        return false
    end
    local tagged, tagReason = self.store:AddTag(tag, objectID, ItemIdentity.LayoutKey(objectID, copy))
    if not tagged then
        self.store:DeleteTag(tag)
        self:ShowStatus(tostring(tagReason))
        return false
    end
    self:ShowStatus(nil)
    self:Changed()
    self.windows:OpenTagSettings(tag, false)
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

-- Explain a tag page too large for Bank Core to show
function App:DrawNotice(ctx)
    local block = ctx:GetBlocks().notice
    local text = ui.Text.new(ctx.parent)
    text:SetPos(12, block.y + 8)
    text:SetSize(ctx:GetBounds().width - 24, block.height - 16)
    text.content = tostring(self.notice or "")
    text.font = id.Font.MUSEO_SANS_11PT_REGULAR
    text.rgba = 0xE7D7B0FF
    text.maxLines = 4
    text.clickthrough = true
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

-- Draw preferences in Bank Core's settings window
function App:MountSettings(parent)
    self:DestroySettings()
    self.settingsSection = SettingsSection.new(parent, {
        settings = self.settings,
        onChange = function(key, value) return self:SetSetting(key, value) end,
    })
end

-- Release the settings section's controls when Bank Core closes it
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
    cleanup("select mode", function()
        if self.handle ~= nil and self.select:Tag() ~= nil then self.handle:SetItemHighlight(nil) end
        self.select:Forget()
    end)
    cleanup("windows", function() self.windows:CloseAll() end)
    cleanup("Bank Core registration", function() self:Disconnect() end)
    cleanup("import sources", function() self.imports:Close() end)
end

return App
