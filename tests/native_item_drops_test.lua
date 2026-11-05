package.path = "./?.lua;./?/init.lua;" .. package.path

-- Check native bank item drops onto visible tag rows
-- FAKE HOST: real drag hover still needs client checks
local Harness = require("tools/test_support/tags_harness")
local h = Harness.new("native_item_drops")
local host = h.bankHost

-- Model named native hooks so Core and another plugin keep their own listeners
local setItems = host.SetItems
-- Replace items while recording their named native hooks
function host:SetItems(specs)
    setItems(self, specs)
    for _, item in ipairs(self.items) do
        local listeners = {}
        -- Keep native and named listeners for one item
        function item:Subscribe(hook, name, action)
            if action == nil then action, name = name, "default" end
            listeners[hook] = listeners[hook] or {}
            listeners[hook][name] = action
            self.hooks[hook] = function(...)
                local names = {}
                for key in pairs(listeners[hook]) do names[#names + 1] = key end
                table.sort(names)
                for _, key in ipairs(names) do
                    if listeners[hook][key](...) == false then return false end
                end
                return true
            end
        end
        -- Remove only the named item listener
        function item:Unsubscribe(hook, name)
            local actions = listeners[hook]
            if actions == nil then return end
            actions[name or "default"] = nil
            if next(actions) == nil then self.hooks[hook] = nil end
        end
    end
end
host:SetItems({ { 4151, 1, "Abyssal whip" }, { 385, 20, "Shark" } })
host.itemLayer.interfaceID = 517
h:LoadCore()
h:LoadTags()
local app = h:App()
local _, layout = h:OpenBank()
h:Tick(2)
for _, tag in ipairs({ "melee", "food", "ranged" }) do assert(app.store:CreateTag(tag)) end
assert(app.store:CreateFolder("Combat", "melee"))
app:Changed()
-- Mark the visible tag row as hovered
local function pointAtTag(tag)
    local row = assert(app.tab:RowFor(tag), tag)
    local list = app.tab.controls.list.list
    list.scrollY = row.root.y
    h:PointAt(row.root, 20, 10 - list.scrollY)
end
-- Drag a native item onto a sidebar row
local function drop(slot, target)
    pointAtTag(target)
    local readMouse = Mouse.GetPosition
    Mouse.GetPosition = function() error("Bank-item drop targets must not read raw mouse coordinates") end
    -- The hook's source and destination arguments are deliberately unrelated wrappers
    assert(host.items[slot].hooks.dragcomplete({}, {}, -9999, -9999))
    Mouse.GetPosition = readMouse
end

-- Assignment happens after native drag handling; moving the pointer cannot retarget it
drop(1, "melee")
assert(h:Saved("melee") == "")
pointAtTag("food")
h:Tick()
assert(h:Saved("melee") == "4151" and h:Saved("food") == "")
drop(1, "melee")
h:Tick()
assert(h:Saved("melee") == "4151 4151", "a second drop adds the next stack slot")

-- Stock quantities do not change, and selecting highlights a dropped member immediately
assert(app.select:Start("food"))
drop(2, "food")
h:Tick()
assert(h:Saved("food") == "385" and host.items[2].shadowRGBA == 0xF2C66DFF)
assert(host.items[1].associatedObjectQuantity == 1 and host.items[2].associatedObjectQuantity == 20)
app.select:Stop()

-- Native hover wins when Windows/game scaling makes raw coordinates point elsewhere
for _, gameScale in ipairs({ 100, 150 }) do
    h.host.globals.game = { options = { InterfaceScale = { setting = gameScale } } }
    pointAtTag("food")
    local misleadingMouse = host.mouse
    pointAtTag("ranged")
    host.mouse = misleadingMouse
    host.items[1].hooks.dragcomplete()
    h:Tick()
end
assert(h:Saved("ranged") == "4151 4151")

-- Folder headers and a client-cleared hover outside the viewport are not targets
pointAtTag("__banktags_folder:combat")
host.items[2].hooks.dragcomplete()
h:Tick()
assert(h:Saved("melee") == "4151 4151")
local list = app.tab.controls.list.list
local row = app.tab:RowFor("ranged")
pointAtTag("ranged")
list.scrollY = row.root.y + row.root.height + 20
row.root.isMouseOver = false
host.items[2].hooks.dragcomplete()
h:Tick()
assert(h:Saved("ranged") == "4151 4151")

-- A stale hover on a hidden or disabled row cannot receive a drop
for _, property in ipairs({ "visibleGlobal", "enabled" }) do
    pointAtTag("ranged")
    local row = app.tab:RowFor("ranged")
    local component = property == "enabled" and row.entry or row.root
    local previous = component[property]
    component[property] = false
    host.items[2].hooks.dragcomplete()
    h:Tick()
    assert(h:Saved("ranged") == "4151 4151")
    component[property] = previous
end

-- Rebuilt wrappers bind without a Core callback; the previous callback becomes inert
local staleDrop = host.items[1].hooks.dragcomplete
host:Rebuild()
h:Tick(10)
pointAtTag("food")
staleDrop()
h:Tick()
assert(h:Saved("food") == "385")
drop(1, "food")
h:Tick()
assert(h:Saved("food") == "385 4151")

-- Native handling can replace a source's identity before the completed drag is heard
local source = host.items[1]
source.hooks.drag(source, 0, 0)
source.associatedObjectID = 385
drop(1, "ranged")
h:Tick()
assert(h:Saved("ranged") == "4151 4151 4151")
source.associatedObjectID = 4151

-- A source reused for a new item is identified when that drag starts
source.associatedObjectID = 385
source.hooks.drag(source, 0, 0)
drop(1, "ranged")
h:Tick()
assert(h:Saved("ranged") == "4151 4151 4151 385")
source.associatedObjectID = 4151

-- A real stack beneath Core's shown page keeps both plugins' named drop hooks
h.host.globals.game = { options = { InterfaceScale = { setting = 100 } } }
assert(app:ShowTag("melee"))
h:Tick(2)
h:PointAtSlot(1)
local held = assert(layout.itemHover.hoveredBankStack)
pointAtTag("melee")
assert(held.item.hooks.dragcomplete(held.item, {}, 0, 0))
h:Tick(2)
assert(h:Saved("melee") == "4151 4151 4151")
assert(app:ShownTag() == "melee")
assert(app.ext:Close())
h:Tick(2)

-- A rejected save reports the error and keeps the tag's previous membership
local chunks = h:TagsModule("banktags/core/chunked_string_store")
local write = chunks.Write
chunks.Write = function() return false, { stage = "manifest", reason = "disk full" } end
drop(2, "food")
h:Tick()
assert(h:Saved("food") == "385 4151" and app.status ~= nil)
chunks.Write = write
app:ShowStatus(nil)

-- A vanished target, replaced column, editor, or bank close cancels queued assignment
drop(1, "ranged")
assert(app.store:DeleteTag("ranged"))
app:Changed()
h:Tick()
assert(app.store.data.tags.ranged == nil)
drop(1, "food")
app.tab:Build()
h:Tick()
assert(h:Saved("food") == "385 4151")
drop(1, "food")
app.windows:OpenLayoutEditor("food")
h:Tick()
assert(h:Saved("food") == "385 4151")
drop(1, "food")
h:Tick()
assert(h:Saved("food") == "385 4151")
app.windows:Close("layoutEditor")

-- Removing Bank Tags' hooks preserves other native drag listeners
local heard = 0
source:Subscribe(ui.Hook.ONDRAGCOMPLETE, "another_plugin", function() heard = heard + 1; return true end)
drop(1, "food")
assert(heard == 1)
h:CloseBank()
assert(h:Saved("food") == "385 4151")
assert(not app.nativeItems.running)
source.hooks.dragcomplete()
assert(heard == 2)

print("native_item_drops_test: ok")
