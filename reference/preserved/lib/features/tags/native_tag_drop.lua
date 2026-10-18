-- Assign native bank drops to sidebar tags after the native drag event completes

local StorageKeys = require("lib/features/storage_keys")
local BankInterface = require("lib/core/bank_interface")
local BankItemIdentity = require("lib/bank/bank_item_identity")
local debugLog = require("lib/core/debug_log").Write
local Geometry = require("lib/ui/geometry")
local absolutePosition = Geometry.absolutePosition
local interfaceMousePosition = Geometry.interfaceMousePosition

local NativeTagDrop = {}

local BANK_ITEMS_STATIC_ID = BankInterface.ITEMS
local DROP_HOOK = StorageKeys.PLUGIN_REF .. "_native_tag_drop"
local DEFERRED_EVENT = StorageKeys.PLUGIN_REF .. "_tag_drop_deferred"
local NEW_TAG_TARGET = "__bankutils_new_tag__"
local GROUP_ENTRY_PREFIX = "__bankutils_group:"
local FOLDER_ENTRY_PREFIX = "__bankutils_folder:"

-- Find a native bank component by its interface slot
local component = BankInterface.Find

-- Recognize section and folder headers that cannot receive item drops
local function isGroupEntry(entry)
    local entryID = tostring(type(entry) == "table" and entry.id or entry or "")
    return string.sub(entryID, 1, #GROUP_ENTRY_PREFIX) == GROUP_ENTRY_PREFIX
        or string.sub(entryID, 1, #FOLDER_ENTRY_PREFIX) == FOLDER_ENTRY_PREFIX
end

-- Check a component's screen bounds while accounting for sidebar scrolling
local function contains(value, x, y, scrollY)
    if value == nil or x == nil or y == nil or value.hidden == true then
        return false
    end
    local left, top = absolutePosition(value)
    top = top - (tonumber(scrollY) or 0)
    local width = tonumber(value.width) or 0
    local height = tonumber(value.height) or 0
    return x >= left and x < left + width and y >= top and y < top + height
end

-- Remove the named drop hook or replace it with a no-op on older host wrappers
local function unbindItem(item)
    local removed, result = pcall(function()
        return item:Unsubscribe(ui.Hook.ONDRAGCOMPLETE, DROP_HOOK)
    end)
    if removed and result ~= false then return end

    -- Older client builds do not expose Unsubscribe on every component
    -- wrapper. A named subscription replaces the old callback, so install a
    -- no-op handler to release the closure over the current layout instance
    pcall(function()
        item:Subscribe(ui.Hook.ONDRAGCOMPLETE, DROP_HOOK,
            function() return true end)
    end)
end

-- Find a tag row or New Tag button beneath a native bank drop
function NativeTagDrop:NativeTagDropTarget()
    if not self.active or not self.expanded or self:IsCleanupMode()
        or self:IsExtensionTabMode() or self.list == nil then return nil end
    local x, y = interfaceMousePosition()
    if x == nil then return nil end

    local button = self.newTagButton and self.newTagButton.root or nil
    if contains(button, x, y) then return NEW_TAG_TARGET end

    local viewport = self.list.viewport
    if not contains(viewport, x, y) then return nil end
    for _, row in ipairs(self.list.rows or {}) do
        if not isGroupEntry(row.entry)
            and row.entry.enabled ~= false
            and contains(row.root, x, y, self.list.scrollY) then
            return row.entry.id
        end
    end
    return nil
end

-- Capture drop identity and save its tag assignment after native drag handling finishes
function NativeTagDrop:ObserveNativeTagDrop(item, boundObjectID)
    local target = self:NativeTagDropTarget()
    local objectID = boundObjectID or BankItemIdentity.ObjectID(item)
    if target == nil or objectID == nil then return false end

    self.pendingNativeTagDrop = {
        objectID = objectID,
        itemKey = self:ResolveItemIdentity(objectID, item.categoryID, item.dynamicID),
        target = target,
    }

    Event.Logic.Unsubscribe(DEFERRED_EVENT)
    Event.Logic.Subscribe(DEFERRED_EVENT, function()
        Event.Logic.Unsubscribe(DEFERRED_EVENT)
        local pending = self.pendingNativeTagDrop
        self.pendingNativeTagDrop = nil
        if pending == nil or not self.active or not self.expanded then return end

        if pending.target == NEW_TAG_TARGET then
            self:CreatePlaceholderTag(pending.objectID, false, pending.itemKey)
            return
        end

        local saved, reason, added = self.store:AddTag(pending.target, pending.objectID, pending.itemKey)
        if not saved then
            debugLog("Bank Utilities could not add tag ", pending.target,
                ": ", tostring(reason))
            return
        end
        if added then
            self:RefreshTags()
            if self.selectedTag ~= nil then self:ReapplySelectedTag(true) end
            debugLog("Bank Utilities added tag ", pending.target,
                " to object ", pending.objectID)
        end
    end)
    return true
end

-- Replace old wrapper hooks before binding the current bank item's drop callbacks
function NativeTagDrop:BindNativeTagDrops()
    if not self.active then return false end
    local itemLayer = component(BANK_ITEMS_STATIC_ID)
    if itemLayer == nil then return false end

    -- Component wrappers are not stable across inventory rebuilds. Remove the
    -- preceding generation before subscribing the current one; otherwise an
    -- old wrapper can unsubscribe the newly installed named hook afterward
    for _, item in ipairs(self.nativeTagDropItems or {}) do unbindItem(item) end

    local current = {}
    itemLayer:IterateDynamicComponents(function(item)
        local objectID = BankItemIdentity.ObjectID(item)
        if objectID ~= nil then
            unbindItem(item)
            local ok = pcall(function()
                item:Subscribe(ui.Hook.ONDRAGCOMPLETE, DROP_HOOK,
                    function(_, _, _, _)
                        -- The hook's first value is not stable across client
                        -- builds. Keep the exact component that was bound
                        self:ObserveNativeTagDrop(item, objectID)
                        return true
                    end)
            end)
            if ok then current[#current + 1] = item end
        end
        return false
    end)
    self.nativeTagDropItems = current
    return true
end

-- Cancel pending drops and remove hooks from recorded and current native wrappers
function NativeTagDrop:UnbindNativeTagDrops()
    Event.Logic.Unsubscribe(DEFERRED_EVENT)
    self.pendingNativeTagDrop = nil
    for _, item in ipairs(self.nativeTagDropItems or {}) do unbindItem(item) end

    -- Also clear live components in case the bank rebuilt its dynamic wrappers
    -- without delivering an inventory update before teardown
    local itemLayer = component(BANK_ITEMS_STATIC_ID)
    if itemLayer ~= nil then
        pcall(function()
            itemLayer:IterateDynamicComponents(function(item)
                if BankItemIdentity.ObjectID(item) ~= nil then unbindItem(item) end
                return false
            end)
        end)
    end
    self.nativeTagDropItems = {}
end

-- Attach this module's methods to the owner that holds their shared state
function NativeTagDrop.install(target)
    for name, method in pairs(NativeTagDrop) do
        if name ~= "install" then target[name] = method end
    end
end

return NativeTagDrop
