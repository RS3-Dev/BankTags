-- Add bank menu actions that check their target before running

local Config = require("resources/core/config")
local MenuEntries = require("resources/ui/menu_entries")
local ObjectConfig = require("resources/core/object_config")
local Text = require("resources/core/text")
local debugLog = require("resources/core/debug_log").Write

local TagMenus = {}
TagMenus.__index = TagMenus

local MENU_EVENT = Config.PLUGIN_REF .. "_menu"
local ACTION_EVENT = Config.PLUGIN_REF .. "_menu_action"

-- Show a tag name as a menu subject
local function subject(store, tag)
    return Text.plain(Text.titleCase(store:GetTagName(tag)))
end

-- Prepare menu handling for this plugin
function TagMenus.new(app)
    -- Keep the latest row menu until it opens
    return setmetatable({ app = app, pending = {}, started = false, rowMenu = nil }, TagMenus)
end

-- Listen for bank menus while connected
function TagMenus:Start()
    if self.started then return end
    self.started = true
    -- Add this plugin's actions to each new menu
    Event.MiniMenuReady.Subscribe(MENU_EVENT, function(event)
        local menu = event and event.miniMenu
        if menu == nil then return end
        local ok, message = pcall(function() self:HandleMenu(menu) end)
        if not ok then debugLog("Bank Tags could not add its menu entries: ", message) end
    end)
    -- Opening freezes the latest menu until a choice is made
    Event.MiniMenuOpened.Subscribe(MENU_EVENT, function()
        local rowMenu = self.rowMenu
        if rowMenu == nil then return end
        rowMenu.opened = true
        debugLog("Bank Tags row menu opened for ", rowMenu.id)
    end)
end

-- Stop listening and discard queued menu actions
function TagMenus:Stop()
    if self.started then
        Event.MiniMenuReady.Unsubscribe(MENU_EVENT)
        Event.MiniMenuOpened.Unsubscribe(MENU_EVENT)
    end
    self.started = false
    self.rowMenu = nil
    Event.Logic.Unsubscribe(ACTION_EVENT)
    self.pending = {}
end

-- Report whether the layout editor covers the bank
function TagMenus:EditorOpen()
    return self.app.windows.layoutEditor ~= nil
end

-- Queue an action while its target remains valid
function TagMenus:Defer(current, action, forEditor)
    -- Recheck occlusion and the target before queued actions run
    local function live() return (forEditor or not self:EditorOpen()) and current() end
    -- Keep the action tied to its captured target
    return function()
        if not live() then return end
        -- Recheck the target before running a queued action
        self.pending[#self.pending + 1] = function()
            if live() then action() end
        end
        -- Run queued actions after native menu handling finishes
        Event.Logic.Subscribe(ACTION_EVENT, function()
            Event.Logic.Unsubscribe(ACTION_EVENT)
            local pending = self.pending
            self.pending = {}
            for _, run in ipairs(pending) do
                local ok, message = pcall(run)
                if not ok then debugLog("Bank Tags menu action failed: ", message) end
            end
        end)
    end
end

-- Build actions for the visible item or row
function TagMenus:HandleMenu(menu)
    self.rowMenu = nil
    local ext = self.app.ext
    if ext == nil then return end
    if self:EditorOpen() then
        self:AddEditorEntries(menu)
        return
    end
    local item = ext:GetMenuItem(menu)
    if item ~= nil then
        self:AddItemEntries(menu, item)
    else
        self:AddRowEntries(menu)
    end
end

-- Offer item selection or removal for the current tag
function TagMenus:AddItemEntries(menu, item)
    local app, ext = self.app, self.app.ext
    local session = app.select.session
    if session ~= nil then
        local current = function() return app.ext == ext and app.select.session == session end
        MenuEntries.AddDefault(menu, { label = app.select:Label(),
            subject = Text.plain(ObjectConfig.DisplayName(item.objectID) or "Item"),
            action = self:Defer(current, function() app.select:Picked(session, item.objectID) end) })
        return
    end
    -- Bank Core gives a slot only on Bank Tags' own page
    local tag, layoutKey = app:ShownTag(), item.slot ~= nil and app.pageKeys[item.slot] or nil
    if tag == nil or not layoutKey then return end
    local revision = app.revision
    -- Check that the menu still names the same target
    local current = function()
        return app.ext == ext and app.revision == revision and app:ShownTag() == tag
    end
    MenuEntries.AddLow(menu, { { label = "Remove from", subject = subject(app.store, tag),
        action = self:Defer(current, function() app:RemoveFromTag(tag, layoutKey) end) } })
end

-- Find the hovered row and its mounted column
function TagMenus:RowAtPointer()
    local tab = self.app.tab
    local ctx, controls = tab.ctx, tab.controls
    if ctx == nil or controls == nil then return nil end
    return controls.list:HoveredEntry(), ctx
end

-- Offer actions for the hovered tag or folder
function TagMenus:AddRowEntries(menu)
    local entry, ctx = self:RowAtPointer()
    if entry == nil then return end
    local app = self.app
    local tab = app.tab
    local list = tab.controls.list
    local clicks = list.clicks
    -- Check that the menu still names the same target
    local current = function()
        return tab.ctx == ctx and tab.controls ~= nil and tab.controls.list == list and list.clicks == clicks
    end
    if entry.kind == "tag" then
        local mounted = current
        current = function() return mounted() and app.store.data.tags[entry.tag] ~= nil end
    end
    local rowMenu = { id = tostring(entry.tag or entry.key), opened = false, used = false }
    -- Accept one explicit choice from the opened menu
    local function chosen(label, action, check)
        local deferred = self:Defer(check or current, action)
        -- Keep the action tied to its captured target
        return function()
            debugLog("Bank Tags row entry ", label, " for ", rowMenu.id, ": opened ", tostring(rowMenu.opened),
                ", used ", tostring(rowMenu.used), ", clicks ", clicks, " now ", list.clicks,
                ", shown ", tostring(app:ShownTag()))
            if not rowMenu.opened or rowMenu.used then return end
            rowMenu.used = true
            deferred()
        end
    end
    local entries = {}
    -- Wrap each row action with the same once-only menu guard
    local function offer(label, name, action)
        entries[#entries + 1] = { label = label, subject = name, action = chosen(label, action) }
    end
    if entry.kind == "folder" then
        local folderKey = entry.key
        local folder = app.store:GetFolder(folderKey)
        if folder == nil then return end
        local name = Text.plain(folder.name)
        offer(folder.collapsed and "Expand" or "Collapse", name, function() app:ToggleFolder(folderKey) end)
        offer("Rename folder", name, function() app.windows:OpenRenameFolderPrompt(folderKey) end)
        offer("Ungroup folder", name, function() app:DeleteFolder(folderKey) end)
    else
        local tag = entry.tag
        if app.store.data.tags[tag] == nil then return end
        local name = subject(app.store, tag)
        offer("Select", name, function() app:ToggleTag(tag) end)
        offer("Edit", name, function() app.windows:OpenLayoutEditor(tag) end)
        offer("Rename", name, function() app.windows:OpenTagSettings(tag, false) end)
        -- Toggle choosing bank items for this tag
        offer(app.select:Tag() == tag and "Stop selecting items" or "Select items", name, function()
            app.select:Toggle(tag)
        end)
        local folderKey = app.store:GetTagFolder(tag)
        if folderKey ~= nil then
            local folder = app.store:GetFolder(folderKey)
            -- Move the tag out of its current folder
            offer("Remove from folder", Text.plain(folder ~= nil and folder.name or folderKey), function()
                app:MoveTagToFolder(tag, nil)
            end)
        end
        offer("Remove", name, function() app.windows:OpenTagDeleteConfirm(tag) end)
    end
    if not MenuEntries.AddTop(menu, entries) then return end
    self.rowMenu = rowMenu
    if entry.kind == "tag" then self:AddFolderSubmenu(menu, entry.tag, 5, chosen, current) end
end

-- Offer item and row actions for the editor
function TagMenus:AddEditorEntries(menu)
    local windows = self.app.windows
    local editor = windows.layoutEditor
    local target = editor:RowMenuTarget()
    -- A menu opened over the grid leaves the editor's keys working
    editor.menuOnGrid = target ~= nil
    local MiniMenu = prettyui.MiniMenu
    if target == nil or MiniMenu == nil then return end
    local current = function() return windows.layoutEditor == editor and editor:RowTargetCurrent(target) end
    local rowMenu = { id = "editor row " .. target.row, opened = false, used = false }
    local children = {}
    -- Accept one explicit choice from the opened menu
    local function chosen(action)
        local deferred = self:Defer(current, action, true)
        -- Keep the action tied to its captured target
        return function()
            if not rowMenu.opened or rowMenu.used then return end
            rowMenu.used = true
            deferred()
        end
    end
    -- Keep a selected group or select the clicked item
    local function itemAction(action, useSelection)
        -- Select the clicked item before applying its action
        return chosen(function()
            if not useSelection or not editor:IsSelected(target.layoutKey) then
                editor:SelectOnly(target.layoutKey)
            end
            action(editor)
        end)
    end
    if target.pane == "bank" or target.pane == "search" then
        local function sourceObjectIDs()
            if target.pane == "bank" and editor.bankSelected ~= nil and editor.bankSelected[target.objectID] then
                return editor:SelectedBankObjectIDs()
            elseif target.pane == "search" and editor.searchSelected ~= nil and editor.searchSelected[target.objectID] then
                return editor:SelectedSearchObjectIDs()
            end
            return { target.objectID }
        end
        MenuEntries.AddTop(menu, {
            { label = "Add to Layout", action = chosen(function() editor:AddItemsToLayout(sourceObjectIDs()) end) },
            { label = "Add to Unsorted", action = chosen(function() editor:AddItemsToUnsorted(sourceObjectIDs()) end) },
        })
        self.rowMenu = rowMenu
        return
    end
    if target.pane == "unsorted" then
        MenuEntries.AddTop(menu, {
            { label = "Move to Layout", action = itemAction(editor.ArrangeSelected, true) },
            { label = "Remove from Tag", action = itemAction(editor.RemoveSelected, true) },
        })
        self.rowMenu = rowMenu
        return
    end
    -- Build row submenu entries with the same validity check
    local function offer(label, action)
        children[#children + 1] = { label = label, action = chosen(action) }
    end
    local row = target.row
    if target.usedRows == 0 then
        MenuEntries.AddTop(menu, {
            { label = "Add row", action = chosen(function() editor:InsertEmptyRow(0) end) },
        })
        -- Empty-space clicks belong to the editor, not a default mini-menu action
        MenuEntries.PromoteCancel(menu)
        self.rowMenu = rowMenu
        return
    end
    offer("Add row above", function() editor:InsertEmptyRow(row) end)
    offer("Add row below", function() editor:InsertEmptyRow(row + 1) end)
    -- A label below the last row goes at the end
    offer("Add label above", function() editor:PromptNewLabel(row) end)
    offer("Add label below", function() editor:PromptNewLabel(row + 1) end)
    offer("Remove row", function() editor:RemoveRow(row) end)
    children[#children + 1] = { label = "Cancel", action = function() end }
    if target.layoutKey ~= nil then
        MenuEntries.AddTop(menu, {
            { label = "Move to Unsorted", action = itemAction(editor.UnarrangeSelected, true) },
            { label = "Remove from Tag", action = itemAction(editor.RemoveSelected) },
        })
    end
    local position = target.layoutKey ~= nil and 2 or 1
    MiniMenu.AddSubmenu(menu, "Edit row", children, {
        title = "Edit row", position = target.layoutKey ~= nil and 2 or "top",
    })
    MenuEntries.PlaceSubmenu(menu, "Edit row <col=ffffff><gt></col>", position)
    if target.layoutKey == nil then MenuEntries.PromoteCancel(menu) end
    self.rowMenu = rowMenu
end

-- Offer folders and a new-folder action
function TagMenus:AddFolderSubmenu(menu, tag, position, chosen, isCurrent)
    local MiniMenu = prettyui.MiniMenu
    if MiniMenu == nil then
        debugLog("Bank Tags needs PrettyUI 1.2 or newer for its folder submenu")
        return
    end
    local app = self.app
    local tagFolder = app.store:GetTagFolder(tag)
    local children = {}
    for _, folder in ipairs(app.store:GetFolders()) do
        local folderKey = folder.key
        if folderKey ~= tagFolder then
            local label = Text.plain(folder.name)
            if label == "" then label = "Folder" end
            children[#children + 1] = { label = label,
                action = chosen("Move to " .. folderKey, function() app:MoveTagToFolder(tag, folderKey) end,
                    function() return isCurrent() and app.store:GetFolder(folderKey) ~= nil end) }
        end
    end
    children[#children + 1] = { label = "Create new folder",
        action = chosen("Create new folder", function() app.windows:OpenCreateFolderPrompt(tag) end) }
    children[#children + 1] = { label = "Cancel", action = function() end }
    local label = tagFolder ~= nil and "Move to folder" or "Add to folder"
    local text = MenuEntries.Text(label, subject(app.store, tag))
    MiniMenu.AddSubmenu(menu, text, children, { title = label, position = position })
    MenuEntries.PlaceSubmenu(menu, text .. " <col=ffffff><gt></col>", position)
end

return TagMenus
