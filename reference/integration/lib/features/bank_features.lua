-- Connect Bank Utilities' tags, cleanup, search, and saved queries to the bank core's
-- controller. The bank calls the hooks below at its lifecycle points; these features reach
-- the bank only through the handle it gives on attach, and read a few pieces of its state.
-- They never build a controller: the bank core owns the only one

local BankInterface = require("lib/core/bank_interface")
local BankItemIdentity = require("lib/bank/bank_item_identity")
local debugLog = require("lib/core/debug_log").Write
local CleanupCategories = require("lib/features/cleanup/cleanup_categories")
local CleanupPage = require("lib/features/cleanup/cleanup_page")
local BankNameSearch = require("lib/features/search/bank_name_search")
local NameSearchPage = require("lib/features/search/name_search_page")
local QueryPage = require("lib/features/runesql/query_page")
local NativeTagDrop = require("lib/features/tags/native_tag_drop")
local NativeTagSelect = require("lib/features/tags/native_tag_select")
local SidebarTabs = require("lib/features/tags/sidebar_tabs")
local TagPage = require("lib/features/tags/tag_page")
local TagSidebar = require("lib/features/tags/tag_sidebar")
local StorageKeys = require("lib/features/storage_keys")

local BankFeatures = {}
TagSidebar.install(BankFeatures)
NativeTagDrop.install(BankFeatures)
NativeTagSelect.install(BankFeatures)
BankNameSearch.install(BankFeatures)

local CLEANUP_BUILD_EVENT = StorageKeys.PLUGIN_REF .. "_cleanup_build"
local SEARCH_HOOK = "bankutils_tag_search"
local CLEANUP_BUILD_BATCH = 25
local SIDEBAR_TAGS = SidebarTabs.TAGS
local SIDEBAR_CLEANUP = SidebarTabs.CLEANUP
local SIDEBAR_RUNESQL = SidebarTabs.QUERIES

-- Read the bank's shared state through the handle and refuse to overwrite it
BankFeatures.__index = function(self, key)
    local method = BankFeatures[key]
    if method ~= nil then return method end
    local host = rawget(self, "host")
    if host ~= nil and host.STATE[key] then return host:State(key) end
    return nil
end
BankFeatures.__newindex = function(self, key, value)
    local host = rawget(self, "host")
    if host ~= nil and host.STATE[key] then
        error("Bank Utilities features cannot set the bank's " .. key, 2)
    end
    rawset(self, key, value)
end

-- Bank calls these features make, forwarded through the handle
for _, name in ipairs({
    "SetSelectedTag",
    "ReapplySelectedTag",
    "SetSidebarMode",
    "UpdateSidebarTabs",
    "IsPresetViewOpen",
    "DetectNativeViewAll",
    "ShowViewAllWarning",
    "ShowPresetWarning",
    "SelectionPage",
    "DisplayTagName",
    "IsGeneratedSelection",
    "ResolveItemIdentity",
    "CollectSearch",
    "InteractionIdentity",
    "PlaceholderAtPointer",
    "PrepareInteractionRebuild",
}) do
    BankFeatures[name] = function(self, ...)
        local host = self.host
        if host == nil then return nil end
        return host[name](host, ...)
    end
end

-- Collect copy-aware bank entries from the native item layer
local function bankItems()
    local itemLayer = BankInterface.Get(BankInterface.ITEMS)
    if itemLayer == nil then return nil end
    return BankItemIdentity.Collect(itemLayer)
end

-- Create the features over the tag store, with the editor and window callbacks
function BankFeatures.new(store, options)
    options = options or {}
    return setmetatable({
        store = store,
        queryStore = options.queryStore,
        cleanupCategories = CleanupCategories.new(store),
        settings = options.settings or {},
        onEditTag = options.onEditTag,
        onEditLayout = options.onEditLayout,
        onOpenSettings = options.onOpenSettings,
        onCreateRuneQuery = options.onCreateRuneQuery,
        onEditRuneQuery = options.onEditRuneQuery,
        host = nil,
        -- Native controls these features move, with their bounds before the move
        components = {},
        original = {},
        searchQuery = "",
        bankSearchQuery = "",
        bankSearchNameCache = {},
        preserveBankSearchQueryOnDeselect = false,
        tagTooltips = {},
        runeQueryCounts = {},
        nativeTagDropItems = {},
        itemSelectionTag = nil,
        pendingItemSelections = {},
        itemSelectionVisuals = {},
        itemSelectionPulseTicks = 0,
    }, BankFeatures)
end

-- List what these features add to the bank controller: search, query, and cleanup pages,
-- tags for every other selection, and the cleanup facade as page content
function BankFeatures:Contribution()
    return {
        pages = { NameSearchPage, QueryPage, CleanupPage },
        fallbackPage = TagPage,
        content = self.cleanupCategories,
    }
end

-- Keep the handle the bank gives these features
function BankFeatures:OnAttached(host)
    rawset(self, "host", host)
end

-- Report whether the sidebar is showing generated cleanup categories
function BankFeatures:IsCleanupMode()
    return self.sidebarMode == SIDEBAR_CLEANUP
end

-- Report whether the sidebar is showing saved RuneQL queries
function BankFeatures:IsRuneSQLMode()
    return self.sidebarMode == SIDEBAR_RUNESQL
end

-- Recognize a saved-query selection through the query store
function BankFeatures:IsRuneQuerySelection(tag)
    local selection = tag or self.selectedTag
    return self.queryStore ~= nil and self.queryStore:IsSelection(selection)
end

-- List these features' sidebar tabs: Tags, Cleanup, and Queries when enabled
function BankFeatures:SidebarTabs()
    return SidebarTabs.Available(self)
end

-- Build the tab content and hand the bank search back when its search is pressed
function BankFeatures:CreateSidebarContent(parent, height, tooltipParent)
    TagSidebar.CreateSidebarContent(self, parent, height, tooltipParent)
    self.search.root:Subscribe(ui.Hook.ONCLICK, SEARCH_HOOK, function()
        self:ReturnToNativeSearch()
        return false
    end)
end

-- Return the bank search to the native control when another tab's search is pressed
function BankFeatures:SidebarSearchPressed()
    self:ReturnToNativeSearch()
end

-- Leave the previous tab's work: selection mode, search text, and cleanup scans
function BankFeatures:OnSidebarModeChanged(mode)
    if mode ~= SIDEBAR_TAGS and self.itemSelectionTag ~= nil then
        self:StopItemSelection(false)
    end
    self.searchQuery = ""
    if self.search ~= nil then self.search:SetText("", false) end
    if mode == SIDEBAR_CLEANUP then
        self:BeginCleanupRefresh()
    else
        self:StopCleanupRefresh()
        self.cleanupCategories:CancelRefresh()
    end
end

-- Stop the logic listener that builds cleanup categories in batches
function BankFeatures:StopCleanupRefresh()
    Event.Logic.Unsubscribe(CLEANUP_BUILD_EVENT)
end

-- Build cleanup categories a small batch per tick and refresh the page when complete
function BankFeatures:BeginCleanupRefresh(categoryID)
    if not self.cleanupCategories:BeginRefresh(bankItems(), categoryID) then return false end
    self:StopCleanupRefresh()
    self:RefreshTags()
    Event.Logic.Subscribe(CLEANUP_BUILD_EVENT, function()
        if not self.active or self.list == nil or not self:IsCleanupMode() then
            self:StopCleanupRefresh()
            return
        end
        if not self.cleanupCategories:StepRefresh(CLEANUP_BUILD_BATCH) then return end
        self:StopCleanupRefresh()
        for _, category in ipairs(self.cleanupCategories:Entries()) do
            debugLog("Bank Utilities generated ", category.label,
                " at cleanup generation ", self.cleanupCategories.generation)
        end
        self:RefreshTags()
        if self:IsGeneratedSelection()
            and (categoryID == nil or self.selectedTag == categoryID) then
            self:ReapplySelectedTag(true)
        end
    end)
    return true
end

-- Open an unsaved tag draft, or create a placeholder for a dropped item
function BankFeatures:CreatePlaceholderTag(objectID, openEditor, itemKey)
    if objectID == nil and openEditor then
        if self.onEditTag == nil then return false end
        local ok, message = pcall(function()
            self.onEditTag(self.store:NextPlaceholderTagName(), true)
        end)
        if not ok then
            debugLog("Bank Utilities could not open the new tag editor: ", message)
        end
        return ok
    end
    local saved, tag, reason = self.store:CreatePlaceholderTag()
    if not saved then
        debugLog("Bank Utilities could not create a placeholder tag: ", tostring(reason))
        return false
    end

    if objectID ~= nil then
        local tagged, tagReason = self.store:AddTag(tag, objectID, itemKey)
        if not tagged then
            self.store:DeleteTag(tag)
            debugLog("Bank Utilities could not add the dragged item to ", tag,
                ": ", tostring(tagReason))
            return false
        end
    end

    self:RefreshTags()
    if openEditor and self.onEditTag ~= nil then
        local ok, message = pcall(function() self.onEditTag(tag, false) end)
        if not ok then
            debugLog("Bank Utilities could not open the new tag editor: ", message)
        end
    end
    debugLog("Bank Utilities created ", tag,
        objectID ~= nil and (" for object " .. tostring(objectID)) or "")
    return true
end

-- Clear the replacement search and return control to the native bank view
function BankFeatures:ReturnToNativeSearch()
    self:ClearBankNameSearch(true)
    if self.selectedTag ~= nil then
        self:SetSelectedTag(nil)
    end
end

-- Find the bank window and its native content column, then add the replacement search
function BankFeatures:OnBankApplied()
    self.components = {
        all = BankInterface.Get(BankInterface.WINDOW),
        content = BankInterface.Get(BankInterface.CONTENT),
    }
    self.original = {}
    self:CaptureBankNameSearchComponents()
    if self:CreateBankNameSearch() then self:HideNativeBankSearch() end
end

-- Start a cleanup scan for an open Cleanup tab and accept item drops onto tags
function BankFeatures:OnRailCreated()
    if self:IsCleanupMode() then self:BeginCleanupRefresh() end
    self:BindNativeTagDrops()
end

-- End selection mode, drops, and scans before the sidebar goes
function BankFeatures:OnRailDestroyed()
    if self.itemSelectionTag ~= nil then
        self:StopItemSelection(false)
    else
        self:StopItemSelectionPulse()
        self:RestoreItemSelectionVisuals()
    end
    self:UnbindNativeTagDrops()
    self:StopCleanupRefresh()
    self.cleanupCategories:CancelRefresh()
end

-- Keep the native search parked while the replacement search remains
function BankFeatures:OnSidebarClosed()
    if self.bankSearchLayer ~= nil then self:HideNativeBankSearch() end
end

-- Return the native search controls to their saved bounds, allowing removed controls
function BankFeatures:RestoreNativeComponents()
    for _, value in ipairs(self.components.nativeSearch or {}) do
        local original = self.original[value]
        if original ~= nil then
            pcall(function()
                value:SetPos(original.x, original.y)
                value:SetSize(original.width, original.height)
            end)
        end
    end
end

-- Remove the replacement search and forget generated categories when the bank closes
function BankFeatures:OnBankRestored()
    self:DestroyBankNameSearch()
    self:ClearBankNameSearch(false)
    self.cleanupCategories:Reset()
end

-- Rebind drops and refresh selection highlights and cleanup counts after a bank change
function BankFeatures:OnInventoryUpdate()
    self:BindNativeTagDrops()
    if self.itemSelectionTag ~= nil then
        self:RefreshItemSelectionVisuals()
    end
    if self:IsCleanupMode() then
        local items = bankItems()
        if items ~= nil then self.cleanupCategories:ObserveItems(items) end
    end
end

-- Stop waiting for prices before any page is built again
function BankFeatures:OnPageBuild()
    self:StopRuneQueryPriceWait()
end

-- Leave selection mode and the search text that the next page does not keep
function BankFeatures:OnPageChanging(tag)
    local wasNameSearch = self:IsNameSearchSelection()
    if tag ~= nil and self.itemSelectionTag ~= nil then
        self:StopItemSelection(false)
    end
    if (tag ~= nil and not self:IsNameSearchSelection(tag))
        or (tag == nil and wasNameSearch
            and self.preserveBankSearchQueryOnDeselect ~= true) then
        self:ClearBankNameSearch(true)
    end
end

-- Follow the native All Items tab: clear stray search text, or reopen a pending search
function BankFeatures:OnNativeViewAllChanged(enabled)
    if not enabled and self.selectedTag == nil
        and self:HasBankNameSearchText() then
        self:ClearBankNameSearch(true)
    end
    if enabled and self.selectedTag == nil and self:HasBankNameSearchQuery() then
        self:SetSelectedTag(BankNameSearch.SELECTION_ID)
        return true
    end
    return false
end

-- Apply saved preferences to tag placement and the replacement search
function BankFeatures:ApplySettings(settings)
    self.settings = settings
    self.store:SetLayoutPlacement(settings.preserveTagLayout)
    self:ApplyBankNameSearchSetting()
end

return BankFeatures
