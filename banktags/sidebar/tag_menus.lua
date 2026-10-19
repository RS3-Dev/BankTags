-- Add Bank Tags' entries to bank menus
-- Chosen entries run next tick, only while their target still holds

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
    return setmetatable({ app = app, pending = {}, started = false }, TagMenus)
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
end

-- Stop answering menus and drop chosen entries that have not run
function TagMenus:Stop()
    if self.started then Event.MiniMenuReady.Unsubscribe(MENU_EVENT) end
    self.started = false
    Event.Logic.Unsubscribe(ACTION_EVENT)
    self.pending = {}
end

-- Defer an action to the next tick while current() holds
function TagMenus:Defer(current, action)
    return function()
        if not current() then return end
        self.pending[#self.pending + 1] = function()
            if current() then action() end
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
function TagMenus:HandleMenu(menu)
    local handle = self.app.handle
    if handle == nil then return end
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

-- Add actions for the tag or folder row under the pointer
function TagMenus:AddRowEntries(menu)
    local entry, ctx = self:RowAtPointer()
    if entry == nil then return end
    local app = self.app
    local tab = app.tab
    local current = function() return tab.ctx == ctx and type(ctx:GetBounds()) == "table" end
    if entry.kind == "tag" then
        local mounted = current
        current = function() return mounted() and app.store.data.tags[entry.tag] ~= nil end
    end
    local entries = {}
    local function offer(label, name, action)
        entries[#entries + 1] = { label = label, subject = name, action = self:Defer(current, action) }
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
        offer("Select", name, function() app:ShowTag(tag) end)
        offer("Edit", name, function() app.windows:OpenTagSettings(tag, false) end)
        offer(app.select:Tag() == tag and "Stop selecting items" or "Select items", name, function()
            app.select:Toggle(tag)
        end)
        offer("Remove", name, function() app.windows:OpenTagDeleteConfirm(tag) end)
        local folderKey = app.store:GetTagFolder(tag)
        if folderKey ~= nil then
            local folder = app.store:GetFolder(folderKey)
            offer("Remove from folder", Text.plain(folder ~= nil and folder.name or folderKey), function()
                app:MoveTagToFolder(tag, nil)
            end)
        end
        offer("Move to folder...", name, function() app.windows:OpenFolderChooser(tag) end)
    end
    MenuEntries.AddLow(menu, entries)
end

return TagMenus
