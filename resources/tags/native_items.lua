-- Own native item highlights and bank-item drops without a Bank Core item API

local Config = require("resources/core/config")

local NativeItems = {}
NativeItems.__index = NativeItems

local ITEM_LAYER = id.Component.BANK__BANK_INV
local ITEM_HOOK = Config.PLUGIN_REF .. "_native_item"
local WATCH_EVENT = Config.PLUGIN_REF .. "_native_items"
local DROP_EVENT = Config.PLUGIN_REF .. "_native_drop"
-- Native tabs can rebuild wrappers without changing inventory contents
local CHECK_TICKS = 10
local OUTLINE_WIDTH = 2
local SHADOW_RGBA = 0xF2C66DFF

-- Find the bank's current item area
local function itemLayer()
    -- Allow the bank to disappear while finding its items
    local ok, layer = pcall(function()
        if ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__BANK_WINDOW) == nil then return nil end
        return ui.Interfaces:GetComponent(ITEM_LAYER)
    end)
    return ok and layer or nil
end

-- Prepare bank item hooks and original appearance settings
function NativeItems.new(app)
    return setmetatable({ app = app, items = {}, visuals = {}, pending = {}, ticks = 0 }, NativeItems)
end

-- Restore only the sprite properties changed by select mode
function NativeItems:RestoreHighlights()
    for _, visual in ipairs(self.visuals) do
        -- Allow item controls to disappear during cleanup
        pcall(function()
            visual.component.outlineWidth = visual.outlineWidth
            visual.component.shadowRGBA = visual.shadowRGBA
        end)
    end
    self.visuals = {}
end

-- Outline selected stacks, placing stocked items first
function NativeItems:RefreshHighlights()
    self:RestoreHighlights()
    local tag = self.app.select:Tag()
    if tag == nil then return end
    local counts = {}
    for _, slot in ipairs(self.app.store:GetTaggedItems(tag)) do
        if slot.objectID ~= nil then counts[slot.objectID] = (counts[slot.objectID] or 0) + 1 end
    end
    self:HighlightItems(self.items, counts)
    if itemLayer() == nil then return end
    for _, name in ipairs({ "BANK__INVENTORY_SLOTS", "BANK__WORN_CONTENT_LAYER" }) do
        -- A panel may be absent while switching between inventory and equipment.
        local ok, layer = pcall(function() return ui.Interfaces:GetComponent(id.Component[name]) end)
        if ok and layer ~= nil then
            local items, seen = {}, {}
            -- Equipment sprites can sit inside static slot layers.
            local function collect(component)
                if seen[component] then return false end
                seen[component] = true
                local objectID = component.associatedObjectID
                if objectID ~= nil and objectID >= 0 then
                    items[#items + 1] = { component = component, objectID = objectID }
                else
                    component:IterateStaticComponents(collect)
                    component:IterateDynamicComponents(collect)
                end
                return false
            end
            collect(layer)
            self:HighlightItems(items, counts)
        end
    end
end

-- Match tag copies independently in each panel using the bank's outline styling.
function NativeItems:HighlightItems(items, taggedCounts)
    local stacks, counts = {}, {}
    for objectID, count in pairs(taggedCounts) do counts[objectID] = count end
    for _, entry in ipairs(items) do stacks[#stacks + 1] = entry end
    -- Place stocked stacks first, then follow bank order
    table.sort(stacks, function(a, b)
        local aStocked = (a.component.associatedObjectQuantity or 0) > 0
        local bStocked = (b.component.associatedObjectQuantity or 0) > 0
        if aStocked ~= bStocked then return aStocked end
        if a.component.y ~= b.component.y then return a.component.y < b.component.y end
        if a.component.x ~= b.component.x then return a.component.x < b.component.x end
        return a.component.dynamicID < b.component.dynamicID
    end)
    for _, entry in ipairs(stacks) do
        local count = counts[entry.objectID] or 0
        if count > 0 then
            counts[entry.objectID] = count - 1
            local component = entry.component
            self.visuals[#self.visuals + 1] = { component = component,
                outlineWidth = component.outlineWidth, shadowRGBA = component.shadowRGBA }
            component.outlineWidth = math.max(component.outlineWidth or 0, OUTLINE_WIDTH)
            component.shadowRGBA = SHADOW_RGBA
        end
    end
end

-- Release old item hooks and restore their appearance
function NativeItems:ClearItems()
    self:RestoreHighlights()
    for _, entry in ipairs(self.items) do
        -- Allow item controls to disappear during cleanup
        pcall(function()
            entry.component:Unsubscribe(ui.Hook.ONDRAG, ITEM_HOOK)
            entry.component:Unsubscribe(ui.Hook.ONDRAGCOMPLETE, ITEM_HOOK)
        end)
    end
    self.items = {}
end

-- Capture the drop before saving on the next tick
function NativeItems:Drop(entry)
    local app = self.app
    local objectID = entry.dragObjectID or entry.objectID
    entry.dragObjectID = nil
    if app.windows.layoutEditor ~= nil or objectID < 0 then return true end
    local tag = app.tab:ItemDropTarget()
    if tag == nil then return true end
    self.pending[#self.pending + 1] = { objectID = objectID, tag = tag,
        controls = app.tab.controls, ext = app.ext }
    -- Save pending drops after native drag handling finishes
    Event.Logic.Subscribe(DROP_EVENT, function()
        Event.Logic.Unsubscribe(DROP_EVENT)
        local pending = self.pending
        self.pending = {}
        for _, drop in ipairs(pending) do
            if drop.ext == app.ext and drop.controls == app.tab.controls
                and app.windows.layoutEditor == nil and itemLayer() ~= nil
                and app.store.data.tags[drop.tag] ~= nil then
                app:AddItemToTag(drop.tag, drop.objectID)
            end
        end
    end)
    return true
end

-- Read native wrappers directly; unchanged lists keep their existing hooks
function NativeItems:Refresh()
    local layer, items = itemLayer(), {}
    if layer ~= nil then
        -- Collect the bank's current item controls
        layer:IterateDynamicComponents(function(component)
            local objectID = component.associatedObjectID
            if objectID ~= nil and objectID >= 0 then
                items[#items + 1] = { component = component, objectID = objectID }
            end
            return false
        end)
    end
    local changed = #items ~= #self.items
    for index, entry in ipairs(items) do
        local before = self.items[index]
        if before == nil or before.component ~= entry.component or before.objectID ~= entry.objectID then
            changed = true
            break
        end
    end
    if changed then
        self:ClearItems()
        self.items = items
        for _, entry in ipairs(items) do
            -- Remember the item before native dragging changes its sprite
            entry.component:Subscribe(ui.Hook.ONDRAG, ITEM_HOOK, function()
                if self.items == items then entry.dragObjectID = entry.component.associatedObjectID end
                return true
            end)
            -- Accept completion only from the current item controls
            entry.component:Subscribe(ui.Hook.ONDRAGCOMPLETE, ITEM_HOOK, function()
                -- The host can change the source sprite before delivering this hook
                if self.items ~= items then return true end
                return self:Drop(entry)
            end)
        end
    end
    self:RefreshHighlights()
end

-- Watch bank items while the bank is open
function NativeItems:Start()
    self:Refresh()
    if self.running then return end
    self.running = true
    -- Check for replacement bank controls every few ticks
    Event.Logic.Subscribe(WATCH_EVENT, function()
        self.ticks = self.ticks + 1
        if self.ticks % CHECK_TICKS == 0 then self:Refresh() end
    end)
end

-- Cancel pending drops and release bank item hooks
function NativeItems:Stop()
    Event.Logic.Unsubscribe(WATCH_EVENT)
    Event.Logic.Unsubscribe(DROP_EVENT)
    self.pending, self.ticks, self.running = {}, 0, false
    self:ClearItems()
end

return NativeItems
