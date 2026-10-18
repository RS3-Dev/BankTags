package.path = "./?.lua;./?/init.lua;" .. package.path

-- Drive Bank Tags' own menus beside Bank Core's guard with each plugin hearing the menu
-- first, under each place a host has put a plugin's entry: at the end as documented, just
-- above Cancel, or just below the native default. Under every combination select mode,
-- started from a shown tag, leaves it and tags consecutive native clicks without
-- withdrawing; Remove takes the exact slot's copy on a stack, a borrowed slot, and a ghost;
-- rows keep Cancel the left click; an entry the host does not report leaves Cancel the
-- left click; a native item without a known copy pauses select mode instead of
-- withdrawing; and an entry offered or chosen before the bank view changed writes nothing.
-- Also covers select mode started while the native tab reads All Items before Bank Core
-- recorded it, followed by a native tab and back. This exercises the path behind a
-- reported tab-switch error, whose exact message is unknown; it does not confirm a fix
-- FAKE HOST: stand-in loader, components, and menus, not the game client

local Harness = require("tools/test_support/tags_harness")
local Geometry = require("banktags/ui/geometry")
local h = Harness.new("menu_orders")
local host = h.bankHost
host:SetItems({ { 4151, 1, "Abyssal whip" }, { 4151, 1, "Abyssal whip" }, { 385, 20, "Shark" } })
host.itemLayer.interfaceID = 517
h:LoadCore()
h:LoadTags()
local app = h:App()
local session, layout = h:OpenBank()
h:Tick(2)
assert(h.menuSubscriptions.banktags_menu ~= nil and h.menuSubscriptions.bankcore_menu ~= nil)

local key = require("banktags/tags/item_identity").LayoutKey
local presetOpen = false
layout.IsPresetViewOpen = function() return presetOpen end

-- Point at a content position in the bank's item area
local function pointAt(x, y)
    local left, top = Geometry.absolutePosition(host.viewport)
    host.mouse = { x = left + x + 5, y = top + y + 5 }
end
-- Point at a tag row in the Tags tab
local function pointAtRow(tag)
    local row = app.tab:RowFor(tag)
    app.tab.controls.list.list.scrollY = row.root.y
    h:PointAt(row.root, 20, 10 - row.root.y)
end
-- Give the melee tag a stack, a borrowed slot naming copy 3 from copy 1, copy 2, and a
-- ghost, as an earlier session saved them
local function resetTags()
    for _, tag in ipairs({ "melee", "ranged" }) do
        if app.store.data.tags[tag] ~= nil then assert(app.store:DeleteTag(tag)) end
        assert(app.store:CreateTag(tag))
    end
    local function item(objectID, copy, source)
        return { kind = "item", objectID = objectID, layoutKey = key(objectID, copy),
            sourceLayoutKey = source ~= nil and key(objectID, source) or nil }
    end
    app.store.data.tags.melee.rows = { { kind = "row", slots = {
        item(4151, 1), item(4151, 3, 1), item(4151, 2), item(999, 1) } } }
    assert(app.store:Save())
    app:Changed()
    h:Tick(2)
end
-- Report the menu's left click, which must not be a native withdraw
local function leftClick(menu)
    return Harness.LeftClick(menu)
end

for _, order in ipairs({ "core_first", "tags_first" }) do
    for _, placement in ipairs({ "documented", "above_cancel", "below_default" }) do
        local where = " (" .. order .. ", " .. placement .. ")"
        h.menuOrder, h.placement = order, placement
        resetTags()

        -- Rows: Cancel stays the left click, the entries follow it in order, and a chosen
        -- entry runs on the next tick
        pointAtRow("ranged")
        local menu = h:ContentMenu()
        local labels = Harness.Labels(menu)
        assert(labels[1] == "Select <col=f2c66d>Ranged</col>" and labels[#labels] == "Cancel",
            table.concat(labels, "|") .. where)
        assert(leftClick(menu) == "Cancel")
        -- An entry the host does not report cannot be placed, so Cancel is the left click
        assert(leftClick(h:ContentMenu(true)) == "Cancel", where)

        -- Remove from the shown tag over a stack, a borrowed slot, and a ghost, each the
        -- slot's own copy; Withdraw stays a leased stack's left click
        assert(app:ShowTag("melee"))
        h:Tick(2)
        pointAt(52, 4)
        h:Tick()
        assert(layout.nativeLease:HasInteractionLease(), where)
        menu = h:MenuFor(host.items[1])
        assert(leftClick(menu) == "Withdraw-1", table.concat(Harness.Labels(menu), "|") .. where)
        Harness.Choose(menu, "Remove from <col=f2c66d>Melee</col>")
        h:Tick(2)
        assert(not app.store:HasTag("melee", key(4151, 3)) and app.store:HasTag("melee", key(4151, 1)), where)
        pointAt(96, 4)
        h:Tick()
        Harness.Choose(h:MenuFor(host.items[2]), "Remove from <col=f2c66d>Melee</col>")
        h:Tick(2)
        assert(not app.store:HasTag("melee", key(4151, 2)) and app.store:HasTag("melee", key(4151, 1)), where)
        pointAt(140, 4)
        h:Tick()
        menu = h:ContentMenu()
        assert(leftClick(menu) == "Cancel", table.concat(Harness.Labels(menu), "|") .. where)
        Harness.Choose(menu, "Remove from <col=f2c66d>Melee</col>")
        h:Tick(2)
        assert(not app.store:HasTag("melee", key(999, 1)), where)

        -- A Remove offered, or chosen, before the bank view changed writes nothing
        pointAt(8, 4)
        h:Tick()
        menu = h:MenuFor(host.items[1])
        host:Rebuild()
        layout:HandleInventoryUpdate()
        Harness.Choose(menu, "Remove from <col=f2c66d>Melee</col>")
        h:Tick(4)
        assert(app.store:HasTag("melee", key(4151, 1)), "stale after rebuild" .. where)
        pointAt(8, 4)
        h:Tick()
        menu = h:MenuFor(host.items[1])
        Harness.Choose(menu, "Remove from <col=f2c66d>Melee</col>")
        assert(app.handle:LeavePage() and app:ShowTag("melee"))
        h:Tick(2)
        assert(app.store:HasTag("melee", key(4151, 1)), "stale after reopening" .. where)

        -- Select mode from the shown tag leaves it; consecutive left clicks tag and never withdraw
        pointAtRow("ranged")
        Harness.Choose(h:ContentMenu(), "Select items <col=f2c66d>Ranged</col>")
        h:Tick(2)
        assert(app.select:Tag() == "ranged" and app.shownTag == nil and layout.selectedTag == nil, where)
        for slot = 1, 3 do
            menu = h:MenuFor(host.items[slot])
            assert(leftClick(menu) == "Add to Ranged <col=f2c66d>Item</col>",
                table.concat(Harness.Labels(menu), "|") .. where)
            h:Tick(2)
        end
        assert(app.store:HasTag("ranged", key(4151, 1)) and app.store:HasTag("ranged", key(4151, 2))
            and app.store:HasTag("ranged", key(385, 1)), where)
        -- An entry the host does not report leaves Cancel the left click
        assert(leftClick(h:MenuFor(host.items[1], true)) == "Cancel", where)
        -- In the preset view no copy is known, so select mode pauses on Cancel
        presetOpen = true
        assert(leftClick(h:MenuFor(host.items[1])) == "Cancel", where)
        presetOpen = false
        -- An Add chosen before the bank rebuilt writes nothing
        assert(app.store:RemoveTag("ranged", key(4151, 1)))
        menu = h:MenuFor(host.items[1])
        leftClick(menu)
        host:Rebuild()
        layout:HandleInventoryUpdate()
        h:Tick(2)
        assert(not app.store:HasTag("ranged", key(4151, 1)), "stale add" .. where)
        -- Done returns the left click to the bank
        Harness.Find(h:TabParent(), "Done").hooks.pressed()
        h:Tick(2)
        assert(app.select:Tag() == nil and leftClick(h:MenuFor(host.items[1])) == "Withdraw-1", where)
    end
end

-- Select mode started while the native tab reads All Items before Core recorded it, then
-- a native tab and back
h.menuOrder, h.placement = "core_first", "above_cancel"
resetTags()
layout.nativeViewAll = false
local detect = layout.DetectNativeViewAll
layout.DetectNativeViewAll = function() return true end
assert(app.select:Toggle("ranged") and layout.nativeViewAll)
h:Tick(2)
assert(app.select:Tag() == "ranged" and leftClick(h:MenuFor(host.items[3])) == "Add to Ranged <col=f2c66d>Item</col>")
h:Tick(2)
assert(app.store:HasTag("ranged", key(385, 1)))
layout.DetectNativeViewAll = function() return false end
layout:SetNativeViewAll(false)
-- Before Bank Tags hears the change, a native click is paused rather than a withdraw
assert(leftClick(h:MenuFor(host.items[1])) == "Cancel")
h:Tick(2)
assert(app.select:Tag() == nil and app.status == 'Select "All Items" before choosing items for a tag.')
assert(leftClick(h:MenuFor(host.items[1])) == "Withdraw-1")
layout.DetectNativeViewAll = function() return true end
layout:SetNativeViewAll(true)
h:Tick(2)
assert(app.select:Toggle("ranged"))
h:Tick(2)
assert(leftClick(h:MenuFor(host.items[2])) == "Add to Ranged <col=f2c66d>Item</col>")
h:Tick(2)
assert(app.store:HasTag("ranged", key(4151, 2)) and app.select:Stop())
layout.DetectNativeViewAll = detect

-- Disconnecting drops the menu subscription
app:Disconnect()
assert(h.menuSubscriptions.banktags_menu == nil)

print("menu_orders_test: ok")
