-- Own native bank-item highlights and drops without a Bank Core item API

local Config = require("banktags/core/config")

local NativeItems = {}
NativeItems.__index = NativeItems

local BANK_INTERFACE = 517
local ITEM_LAYER = 201
local ITEM_HOOK = Config.PLUGIN_REF .. "_native_item"
local WATCH_EVENT = Config.PLUGIN_REF .. "_native_items"
local DROP_EVENT = Config.PLUGIN_REF .. "_native_drop"
-- Native tabs can rebuild wrappers without changing inventory contents
local CHECK_TICKS = 10
local OUTLINE_WIDTH = 2
local SHADOW_RGBA = 0xF2C66DFF

-- The bank's components can disappear while the client rebuilds its interface
local function itemLayer()
    local ok, layer = pcall(function()
        if ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__BANK_WINDOW) == nil then return nil end
        return ui.Interfaces:GetComponent(BANK_INTERFACE, ITEM_LAYER)
    end)
    return ok and layer or nil
end

-- Keep hooks and original item looks together for one running plugin
function NativeItems.new(app)
    return setmetatable({ app = app, items = {}, visuals = {}, pending = {}, ticks = 0 }, NativeItems)
end

-- Restore only the sprite properties changed by select mode
function NativeItems:RestoreHighlights()
    for _, visual in ipairs(self.visuals) do
        pcall(function()
            visual.component.outlineWidth = visual.outlineWidth
            visual.component.shadowRGBA = visual.shadowRGBA
        end)
    end
    self.visuals = {}
end

-- Outline as many stacks as the tag lists, stocked stacks before placeholders
function NativeItems:RefreshHighlights()
    self:RestoreHighlights()
    local tag = self.app.select:Tag()
    if tag == nil then return end
    local counts, stacks = {}, {}
    for _, slot in ipairs(self.app.store:GetTaggedItems(tag)) do
        if slot.objectID ~= nil then counts[slot.objectID] = (counts[slot.objectID] or 0) + 1 end
    end
    for _, entry in ipairs(self.items) do stacks[#stacks + 1] = entry end
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

-- Remove this plugin's hooks before binding a replacement generation of wrappers
function NativeItems:ClearItems()
    self:RestoreHighlights()
    for _, entry in ipairs(self.items) do
        pcall(function()
            entry.component:Unsubscribe(ui.Hook.ONDRAG, ITEM_HOOK)
            entry.component:Unsubscribe(ui.Hook.ONDRAGCOMPLETE, ITEM_HOOK)
        end)
    end
    self.items = {}
end

-- Capture the source and visible target now; save after native drag handling finishes
function NativeItems:Drop(entry)
    local app = self.app
    local objectID = entry.dragObjectID or entry.objectID
    entry.dragObjectID = nil
    if app.windows.layoutEditor ~= nil or objectID < 0 then return true end
    local tag = app.tab:ItemDropTarget()
    if tag == nil then return true end
    self.pending[#self.pending + 1] = { objectID = objectID, tag = tag,
        controls = app.tab.controls, ext = app.ext }
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
            entry.component:Subscribe(ui.Hook.ONDRAG, ITEM_HOOK, function()
                if self.items == items then entry.dragObjectID = entry.component.associatedObjectID end
                return true
            end)
            entry.component:Subscribe(ui.Hook.ONDRAGCOMPLETE, ITEM_HOOK, function()
                -- The host can change the source sprite before delivering this hook
                if self.items ~= items then return true end
                return self:Drop(entry)
            end)
        end
    end
    self:RefreshHighlights()
end

-- Follow the client's native items even when Core has no inventory update to report
function NativeItems:Start()
    self:Refresh()
    if self.running then return end
    self.running = true
    Event.Logic.Subscribe(WATCH_EVENT, function()
        self.ticks = self.ticks + 1
        if self.ticks % CHECK_TICKS == 0 then self:Refresh() end
    end)
end

-- Cancel queued drops and release native wrappers on bank close or plugin disconnect
function NativeItems:Stop()
    Event.Logic.Unsubscribe(WATCH_EVENT)
    Event.Logic.Unsubscribe(DROP_EVENT)
    self.pending, self.ticks, self.running = {}, 0, false
    self:ClearItems()
end

return NativeItems
