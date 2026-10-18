-- Add Bank Utilities' right-click entries: tag, folder, and saved-query rows, Add to the
-- tag in select mode, and Remove from the shown tag. The bank's menu router asks for
-- these; removal reads the item beneath the pointer as object ID and layout key only

local StorageKeys = require("lib/features/storage_keys")
local DebugLog = require("lib/core/debug_log")
local NativeItemMenuGuard = require("lib/bank/native_item_menu_guard")
local MenuEntries = require("lib/ui/menu_entries")
local debugLog = DebugLog.Write

local TagMenu = {}
TagMenu.__index = TagMenu

local TAG_REMOVE_EVENT = StorageKeys.PLUGIN_REF .. "_tag_remove"
local TAG_REMOVE_REFRESH_EVENT = StorageKeys.PLUGIN_REF .. "_tag_remove_refresh"
local TAG_NAME_COLOUR = MenuEntries.NAME_COLOUR

local moveCancelToEnd = MenuEntries.MoveCancelToEnd
local moveEntryToIndex = MenuEntries.MoveToIndex
local menuEntryIndex = MenuEntries.IndexOf
local addTagAction = MenuEntries.AddNamedAction
local guarded = MenuEntries.Guarded

-- Check whether the viewed page lets players remove its items
local function removesFromPage(features, tag)
    local page = features:SelectionPage(tag)
    return page ~= nil and page.isMembershipEditable == true
end

-- Return PrettyUI's submenu API when the installed version provides it
local function submenuApi()
    local miniMenu = type(prettyui) == "table" and prettyui.MiniMenu or nil
    if type(miniMenu) == "table" and type(miniMenu.AddSubmenu) == "function" then
        return miniMenu
    end
    return nil
end

-- Create the menu entries for one Bank Utilities app
function TagMenu.new(app, options)
    return setmetatable({
        app = app,
        options = options,
        pendingTagRemoval = nil,
        pendingTagRemovalRefresh = nil,
        removalWorkerActive = false,
    }, TagMenu)
end

-- Cancel pending membership removal
function TagMenu:CancelPendingTagRemoval()
    Event.Logic.Unsubscribe(TAG_REMOVE_EVENT)
    Event.Logic.Unsubscribe(TAG_REMOVE_REFRESH_EVENT)
    self.pendingTagRemoval = nil
    self.pendingTagRemovalRefresh = nil
    self.removalWorkerActive = false
end

-- Process removal worker phases
function TagMenu:ProcessTagRemoval()
    if self.pendingTagRemoval ~= nil then
        self:CommitPendingTagRemoval()
        return
    end

    local app = self.app
    local refreshTag = self.pendingTagRemovalRefresh
    self.pendingTagRemovalRefresh = nil
    Event.Logic.Unsubscribe(TAG_REMOVE_EVENT)
    self.removalWorkerActive = false
    if refreshTag == nil or not app.inGame then return end
    if app.features.selectedTag == refreshTag then
        app.features:ReapplySelectedTag(true)
        debugLog("Bank Utilities rebuilt tag ", refreshTag,
            " after native interaction release")
    end
end

-- Start the removal worker
function TagMenu:StartRemovalWorker()
    if self.removalWorkerActive then return end
    self.removalWorkerActive = true
    Event.Logic.Subscribe(TAG_REMOVE_EVENT, function()
        self:ProcessTagRemoval()
    end)
end

-- Refresh a removed item next tick
function TagMenu:ScheduleTagRemovalRefresh(tag)
    self.pendingTagRemovalRefresh = tag
    self:StartRemovalWorker()
end

-- Save pending membership removal
function TagMenu:CommitPendingTagRemoval()
    local app = self.app
    local pending = self.pendingTagRemoval
    self.pendingTagRemoval = nil
    if pending == nil or not app.inGame then
        self:CancelPendingTagRemoval()
        return false
    end

    local saved, reason, removed = app.store:RemoveTag(pending.tag, pending.itemKey)
    if not saved then
        self:CancelPendingTagRemoval()
        debugLog("Bank Utilities could not remove object ", pending.objectID,
            " from tag ", pending.tag, ": ", tostring(reason))
        return false
    end
    if removed then
        app.features:PrepareInteractionRebuild()
        app.features:RefreshTags()
        if app.features.selectedTag == pending.tag then
            self:ScheduleTagRemovalRefresh(pending.tag)
        else
            self:CancelPendingTagRemoval()
        end
        debugLog("Bank Utilities removed object ", pending.objectID,
            " from tag ", pending.tag)
    else
        self:CancelPendingTagRemoval()
    end
    return true
end

-- Queue membership removal next tick
function TagMenu:QueueTagRemoval(pending)
    self:CancelPendingTagRemoval()
    self.pendingTagRemoval = pending
    self:StartRemovalWorker()
    return true
end

-- Add the Remove from <tag> action just above Cancel
function TagMenu:AddRemovalEntry(menu, viewedTag, objectID, itemKey)
    local displayTag = self.app.features:DisplayTagName(viewedTag)
    local removalLabel = "Remove from <col=" .. TAG_NAME_COLOUR .. ">"
        .. displayTag .. "</col>"
    moveCancelToEnd(menu)
    menu:Add(removalLabel, function()
        self:QueueTagRemoval({
            objectID = objectID,
            tag = viewedTag,
            itemKey = itemKey,
        })
    end)
    local removalIndex = menuEntryIndex(
        menu,
        removalLabel,
        self.options.normalizeMenuText
    )
    if not moveEntryToIndex(menu, removalIndex, 2) then
        debugLog("Bank Utilities could not position the Remove from ", displayTag,
            " mini-menu entry; entry count=", tostring(menu.entryCount))
    end
end

-- Offer removal on a placeholder for an item the bank does not hold
-- Cancel stays the default so a left click on the placeholder stays harmless
function TagMenu:AddPlaceholderMenuEntries(menu)
    local features = self.app.features
    local viewedTag = features.selectedTag
    if menu == nil or features:ItemSelectionTag() ~= nil
        or not removesFromPage(features, viewedTag) then return end
    local entry = features:PlaceholderAtPointer()
    local objectID = entry ~= nil and math.tointeger(tonumber(entry.objectID)) or nil
    if objectID == nil then return end
    self:AddRemovalEntry(menu, viewedTag, objectID, entry.layoutKey)
    NativeItemMenuGuard.PromoteCancel(menu)
end

-- Add Remove from the shown tag, or Add to the tag in select mode, for a bank item
function TagMenu:AddItemMenuEntries(menu, item)
    local features = self.app.features
    local selectionTag = features:ItemSelectionTag()
    local categoryID = item.categoryID
    local dynamicID = item.dynamicID

    if selectionTag == nil then
        local viewedTag = features.selectedTag
        if not removesFromPage(features, viewedTag) then return end
        local itemKey = features:InteractionIdentity(item.id, categoryID, dynamicID)
            or features:ResolveItemIdentity(item.id, categoryID, dynamicID)
        self:AddRemovalEntry(menu, viewedTag, item.id, itemKey)
        return
    end

    moveCancelToEnd(menu)
    local displayTag = features:DisplayTagName(selectionTag)
    local selectionLabel = "Add to <col=" .. TAG_NAME_COLOUR .. ">"
        .. displayTag .. "</col>"
    menu:Add(
        selectionLabel,
        function(itemID)
            local ok, message = pcall(function()
                features:AddItemToSelection(itemID, categoryID, dynamicID)
            end)
            if not ok then
                debugLog("Bank Utilities could not add the selected item: ", message)
            end
        end,
        item.id
    )
    local selectionIndex = menuEntryIndex(
        menu,
        selectionLabel,
        self.options.normalizeMenuText
    )
    if not moveEntryToIndex(menu, selectionIndex, menu.entryCount) then
        debugLog("Bank Utilities could not promote the Add to ", displayTag,
            " mini-menu entry; entry count=", tostring(menu.entryCount))
    end
end

-- Add the folder submenu listing other folders, Create New Folder, and Cancel
function TagMenu:AddFolderSubmenu(menu, tag, currentFolder, displayTag)
    local app = self.app
    local miniMenu = submenuApi()
    if miniMenu == nil then
        -- PrettyUI before 1.2.0 has no submenus, so offer folder creation directly
        addTagAction(menu, "Add to new folder", guarded("create a folder", function()
            app.windows:OpenCreateFolderPrompt(tag)
        end), displayTag)
        return
    end
    local children = {}
    for _, folder in ipairs(app.store:GetFolders()) do
        if folder.key ~= currentFolder then
            children[#children + 1] = {
                label = folder.name,
                action = guarded("move the tag", function()
                    app:MoveTagToFolder(tag, folder.key)
                end),
            }
        end
    end
    children[#children + 1] = {
        label = "Create New Folder",
        action = guarded("create a folder", function()
            app.windows:OpenCreateFolderPrompt(tag)
        end),
    }
    children[#children + 1] = { label = "Cancel", action = function() end }
    local label = currentFolder ~= nil and "Move To Folder" or "Add To Folder"
    local ok, entry = pcall(miniMenu.AddSubmenu, menu, label, children, {
        title = label,
        position = "bottom",
    })
    if not ok then
        debugLog("BankUtils could not add the folder submenu: ", entry)
        return
    end
    -- PrettyUI's bottom placement does not account for a relocated Cancel, so
    -- park the parent at the lowest-priority index; the caller then moves
    -- Cancel below it, leaving the submenu directly above Cancel
    local wanted = self.options.normalizeMenuText(label)
    for index, candidate in ipairs(menu.entries or {}) do
        local text = self.options.normalizeMenuText(
            candidate.overrideText or candidate.fullText or candidate.verbText
        )
        if candidate == entry or string.sub(text, 1, #wanted) == wanted then
            moveEntryToIndex(menu, index, 1)
            return
        end
    end
    debugLog("BankUtils could not position the folder submenu; entry count=",
        tostring(menu.entryCount))
end

-- Add folder header actions
function TagMenu:AddFolderListEntries(menu, folderKey)
    local app = self.app
    local folder = app.store:GetFolder(folderKey)
    if folder == nil then return false end
    addTagAction(menu, folder.collapsed and "Expand" or "Collapse", guarded(
        "toggle the folder", function() app.features:ToggleFolder(folderKey) end
    ), folder.name)
    addTagAction(menu, "Rename folder", guarded("rename the folder", function()
        app.windows:OpenRenameFolderPrompt(folderKey)
    end), folder.name)
    addTagAction(menu, "Ungroup folder", guarded("ungroup the folder", function()
        app:DeleteFolder(folderKey)
    end), folder.name)
    moveCancelToEnd(menu)
    return true
end

-- Let an open layout editor answer the menu first
function TagMenu:AddWindowMenuEntries(event)
    local editor = self.app.windows and self.app.windows.layoutEditor or nil
    if editor ~= nil and editor:AddMenuEntries(event) then return true end
    return false
end

-- Add actions for the saved query, folder, or tag row beneath the pointer
function TagMenu:AddSidebarMenuEntries(menu)
    local app = self.app
    local features = app.features
    local querySelection = features:HoveredRuneQuery()
    if querySelection ~= nil then
        local record = app.queryStore:GetBySelection(querySelection)
        if record == nil then return false end
        addTagAction(menu, "Delete", function()
            local ok, message = pcall(function()
                app:DeleteRuneQuery(querySelection)
            end)
            if not ok then
                debugLog("BankUtils could not delete RuneQL query: ", message)
            end
        end, record.name)
        addTagAction(menu, "Convert to tag", function()
            local ok, message = pcall(function()
                app:ConvertRuneQueryToTag(querySelection)
            end)
            if not ok then
                debugLog("BankUtils could not convert RuneQL query: ", message)
            end
        end, record.name)
        moveCancelToEnd(menu)
        return true
    end

    local folderKey = features:HoveredFolder()
    if folderKey ~= nil then return self:AddFolderListEntries(menu, folderKey) end

    local tag = features:HoveredTag()
    if tag == nil then return false end
    local displayTag = features:DisplayTagName(tag)
    local currentFolder = app.store:GetTagFolder(tag)
    addTagAction(menu, "Select", function()
        features:SetSelectedTag(tag)
    end, displayTag)
    addTagAction(menu, "Edit", function()
        local ok, message = pcall(function() app.windows:OpenTagSettings(tag) end)
        if not ok then debugLog("Bank Utilities could not edit tag: ", message) end
    end, displayTag)
    local selectingItems = features:IsSelectingItemsForTag(tag)
    addTagAction(menu, selectingItems and "Stop selecting items" or "Select items",
        function()
            features:ToggleItemSelectionTag(tag)
        end,
        displayTag
    )
    addTagAction(menu, "Remove", function()
        local ok, message = pcall(function() app.windows:OpenTagDeleteConfirm(tag) end)
        if not ok then debugLog("Bank Utilities could not remove tag: ", message) end
    end, displayTag)
    if currentFolder ~= nil then
        local folder = app.store:GetFolder(currentFolder)
        addTagAction(menu, "Remove from folder", guarded("ungroup the tag", function()
            app:MoveTagToFolder(tag, nil)
        end), folder and folder.name or currentFolder)
    end
    self:AddFolderSubmenu(menu, tag, currentFolder, displayTag)
    -- Move Cancel last so it stays below the submenu; Swap keeps the submenu link
    moveCancelToEnd(menu)
    return true
end

return TagMenu
