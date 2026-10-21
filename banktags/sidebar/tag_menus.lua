-- Add Bank Tags' entries to bank menus
-- Chosen entries run on the next tick, and only if their target is still there
-- A Tags row handles its own left click, so its entries only act when picked from the open menu

local Config = require("banktags/core/config")
local Geometry = require("banktags/ui/geometry")
local ItemIdentity = require("banktags/tags/item_identity")
local MenuEntries = require("banktags/ui/menu_entries")
local TagPage = require("banktags/tags/tag_page")
local Text = require("banktags/core/text")
local debugLog = require("banktags/core/debug_log").Write

local TagMenus = {}
TagMenus.__index = TagMenus

local MENU_EVENT = Config.PLUGIN_REF .. "_menu"
local ACTION_EVENT = Config.PLUGIN_REF .. "_menu_action"

-- Show a tag name as a menu subject
local function subject(tag)
    return Text.plain(Text.titleCase(tag))
end

-- Create the menus for an app; nothing is subscribed until Start
function TagMenus.new(app)
    -- rowMenu is the newest Tags row menu, which is the one shown if the menu opens
    return setmetatable({ app = app, pending = {}, started = false, rowMenu = nil }, TagMenus)
end

-- Answer bank menus while Bank Tags is connected to Bank Core
function TagMenus:Start()
    if self.started then return end
    self.started = true
    Event.MiniMenuReady.Subscribe(MENU_EVENT, function(event)
        local menu = event and event.miniMenu
        if menu == nil then return end
        local ok, message = pcall(function() self:HandleMenu(menu) end)
        if not ok then debugLog("Bank Tags could not add its menu entries: ", message) end
    end)
    -- The client stops rebuilding an opened menu, so the newest row menu is the one opened
    Event.MiniMenuOpened.Subscribe(MENU_EVENT, function()
        local rowMenu = self.rowMenu
        if rowMenu == nil then return end
        rowMenu.opened = true
        debugLog("Bank Tags row menu opened for ", rowMenu.id)
    end)
end

-- Stop answering menus and drop chosen entries that have not run
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

-- Run an action next tick if current() still returns true
-- Bank entries also need the editor to stay closed; editor entries check their editor in current()
function TagMenus:Defer(current, action, forEditor)
    local function live() return (forEditor or not self:EditorOpen()) and current() end
    return function()
        if not live() then return end
        self.pending[#self.pending + 1] = function()
            if live() then action() end
        end
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

-- Check that an item's handle and bank view are still current
function TagMenus:ItemCheck(item, extra)
    local app, handle = self.app, self.app.handle
    return function()
        return app.handle == handle and handle ~= nil and item.viewID ~= nil
            and handle:GetState().viewID == item.viewID
            and (extra == nil or extra())
    end
end

-- Answer one menu: entries for the bank item beneath the pointer, or for the Tags row
-- The layout editor covers the bank, so nothing beneath it gets entries; only its own grid does
function TagMenus:HandleMenu(menu)
    self.rowMenu = nil
    local handle = self.app.handle
    if handle == nil then return end
    if self:EditorOpen() then
        self:AddEditorEntries(menu)
        return
    end
    local item = handle:GetMenuItem(menu)
    if item ~= nil then
        self:AddItemEntries(menu, item)
    else
        self:AddRowEntries(menu)
    end
end

-- Add select mode's Add to and the shown tag's Remove from
-- Without a known copy or outline, Cancel stays the left click
function TagMenus:AddItemEntries(menu, item)
    local app = self.app
    local select = app.select
    if item.view == "native" then
        local session = select.session
        if session == nil then return end
        if item.copy == nil or not select:IsShown() then
            MenuEntries.PromoteCancel(menu)
            return
        end
        local current = self:ItemCheck(item, function()
            return select.session == session and select:IsShown()
        end)
        MenuEntries.AddDefault(menu, { label = select:Label(),
            subject = Text.plain(item.name or "Item"),
            action = self:Defer(current, function() select:Picked(session, item) end) })
        return
    end
    if item.pageID ~= TagPage.PAGE_ID or item.slot == nil then return end
    local tag = TagPage.TagFromKey(item.key)
    if tag == nil then return end
    local layoutKey = ItemIdentity.LayoutKey(item.objectID, item.slot.copy)
    if not app.store:HasTag(tag, layoutKey) then return end
    local current = self:ItemCheck(item, function() return app.store:HasTag(tag, layoutKey) end)
    MenuEntries.AddLow(menu, { { label = "Remove from", subject = subject(tag),
        action = self:Defer(current, function() app:RemoveFromTag(tag, layoutKey) end) } })
end

-- Find the Tags row beneath the pointer, with the mounted context it was found in
function TagMenus:RowAtPointer()
    local tab = self.app.tab
    local ctx, controls = tab.ctx, tab.controls
    if ctx == nil or controls == nil then return nil end
    local bounds = ctx:GetBounds()
    local pointerX, pointerY = Geometry.interfaceMousePosition()
    if type(bounds) ~= "table" or pointerX == nil then return nil end
    local left, top = Geometry.absolutePosition(ctx.parent)
    local x, y = math.floor(pointerX - left), math.floor(pointerY - top)
    if x < 0 or y < 0 or x >= bounds.width or y >= bounds.height then return nil end
    return controls.list:EntryAt(x, y), ctx
end

-- Add actions for the tag or folder row under the pointer, the first shown as the left click
-- The row handles left clicks itself, no matter when the client runs this menu's default
-- An entry picked from the open menu, or its folder submenu, acts once
-- A row click, a rebuilt tab, or a removed tag makes the menu out of date
function TagMenus:AddRowEntries(menu)
    local entry, ctx = self:RowAtPointer()
    if entry == nil then return end
    local app = self.app
    local tab = app.tab
    local list = tab.controls.list
    local clicks = list.clicks
    local current = function()
        return tab.ctx == ctx and type(ctx:GetBounds()) == "table"
            and tab.controls ~= nil and tab.controls.list == list and list.clicks == clicks
    end
    if entry.kind == "tag" then
        local mounted = current
        current = function() return mounted() and app.store.data.tags[entry.tag] ~= nil end
    end
    local rowMenu = { id = tostring(entry.tag or entry.key), opened = false, used = false }
    -- Run an action once, next tick, if picked from the opened menu and still current
    local function chosen(label, action, check)
        local deferred = self:Defer(check or current, action)
        return function()
            debugLog("Bank Tags row entry ", label, " for ", rowMenu.id, ": opened ", tostring(rowMenu.opened),
                ", used ", tostring(rowMenu.used), ", clicks ", clicks, " now ", list.clicks,
                ", shown ", tostring(app.shownTag))
            if not rowMenu.opened or rowMenu.used then return end
            rowMenu.used = true
            deferred()
        end
    end
    local entries = {}
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
        local name = subject(tag)
        offer("Select", name, function() app:ToggleTag(tag) end)
        offer("Edit", name, function() app.windows:OpenLayoutEditor(tag) end)
        offer("Rename", name, function() app.windows:OpenTagSettings(tag, false) end)
        offer(app.select:Tag() == tag and "Stop selecting items" or "Select items", name, function()
            app.select:Toggle(tag)
        end)
        local folderKey = app.store:GetTagFolder(tag)
        if folderKey ~= nil then
            local folder = app.store:GetFolder(folderKey)
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

-- Add the Edit row submenu for the layout editor's sorted grid row under the pointer
-- Cancel stays the left click; a child acts once, only when picked from the opened menu
-- Another save, tag, size, drag, or a closed editor makes the menu out of date
function TagMenus:AddEditorEntries(menu)
    local windows = self.app.windows
    local editor = windows.layoutEditor
    local target = editor:RowMenuTarget()
    local MiniMenu = prettyui.MiniMenu
    if target == nil or MiniMenu == nil then return end
    local current = function() return windows.layoutEditor == editor and editor:RowTargetCurrent(target) end
    local rowMenu = { id = "editor row " .. target.row, opened = false, used = false }
    local children = {}
    local function offer(label, action)
        local deferred = self:Defer(current, action, true)
        children[#children + 1] = { label = label, action = function()
            if not rowMenu.opened or rowMenu.used then return end
            rowMenu.used = true
            deferred()
        end }
    end
    -- Rows past the layout are already empty, so they offer nothing
    local row = target.row
    if row < target.usedRows then offer("Add row above", function() editor:InsertEmptyRow(row) end) end
    if row + 1 < target.usedRows then offer("Add row below", function() editor:InsertEmptyRow(row + 1) end) end
    if target.emptyRow then offer("Remove empty row", function() editor:RemoveEmptyRow(row) end) end
    if #children == 0 then return end
    children[#children + 1] = { label = "Cancel", action = function() end }
    MiniMenu.AddSubmenu(menu, "Edit row", children, { title = "Edit row" })
    MenuEntries.PromoteCancel(menu)
    self.rowMenu = rowMenu
end

-- Add the folder submenu between selection and removal actions
-- It lists the other folders, Create new folder, and Cancel
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
    local text = MenuEntries.Text(label, subject(tag))
    MiniMenu.AddSubmenu(menu, text, children, { title = label, position = position })
    MenuEntries.PlaceSubmenu(menu, text .. " <col=ffffff><gt></col>", position)
end

return TagMenus
