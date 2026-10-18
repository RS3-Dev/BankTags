package.path = "./?.lua;./?/init.lua;" .. package.path

-- Click through the Tags tab and the bank the way the live client delivers clicks: a left
-- click on a tag row reaches the row and also runs the menu's default, and a plugin's
-- menu entries land just above Cancel rather than where the API documents. Choosing a
-- shown tag again leaves it; another tag replaces it; a native tab or another extension's
-- tab leaves it. Select mode started from a shown tag tags several native items in a row
-- with plain left clicks and withdraws none, across a bank rebuild, and stops on Done
-- FAKE HOST: stand-in loader, components, and menus, not the game client

local Harness = require("tools/test_support/tags_harness")
local h = Harness.new("bank_clicks")
local host = h.bankHost
host:SetItems({ { 4151, 1, "Abyssal whip" }, { 4151, 1, "Abyssal whip" }, { 385, 20, "Shark" } })
host.itemLayer.interfaceID = 517
h:LoadCore()
h:LoadTags()
local app = h:App()
local session, layout = h:OpenBank()
h:Tick(2)

local key = require("banktags/tags/item_identity").LayoutKey
assert(app.store:CreateTag("melee"))
assert(app.store:CreateTag("ranged"))
assert(app.store:AddTag("melee", 4151, key(4151, 1)))
assert(app.store:AddTag("ranged", 385, key(385, 1)))
app:Changed()

-- Left-click a tag row: the row hears the click and the host runs the menu's default
local function clickRow(tag)
    local row = app.tab:RowFor(tag)
    app.tab.controls.list.list.scrollY = row.root.y
    h:PointAt(row.root, 20, 10 - row.root.y)
    local default = Harness.LeftClick(h:ContentMenu())
    app.tab.controls.list.list:Click(tag)
    h:Tick(2)
    -- No row entry is the left click, so no window opens behind the player's back
    assert(default == "Cancel", tostring(default))
    assert(app.windows.folderChooser == nil and app.windows.tagDeleteConfirm == nil
        and app.windows.tagSettingsEditor == nil)
end

clickRow("melee")
assert(app.shownTag == "melee" and layout.pageState.view.key == "tag:melee")
-- The shown tag again returns to the bank's own view
clickRow("melee")
assert(app.shownTag == nil and layout.selectedTag == nil)
-- Another tag replaces the shown one, and choosing it again leaves it
clickRow("melee")
clickRow("ranged")
assert(app.shownTag == "ranged" and layout.pageState.view.key == "tag:ranged")
clickRow("ranged")
assert(app.shownTag == nil and layout.selectedTag == nil)

-- A native tab leaves the shown tag; All Items lets it open again
clickRow("melee")
layout:SetNativeViewAll(false)
h:Tick(2)
assert(app.shownTag == nil and layout.selectedTag == nil)
layout:SetNativeViewAll(true)
h:Tick(2)
clickRow("melee")
assert(app.shownTag == "melee")

-- Another extension's tab leaves the shown tag and unmounts the Tags tab; coming back
-- mounts it again
local other = assert(session.publicAPI.RegisterExtension("other", "Other"))
assert(other:RegisterTab("notes", { label = "Notes", icon = "STAR", rows = {} }))
h:Tick(2)
layout:SetSidebarMode("__bankutils_ext_tab:other/notes")
h:Tick(2)
assert(app.shownTag == nil and layout.selectedTag == nil and app.tab.controls == nil)
layout:SetSidebarMode("__bankutils_ext_tab:banktags/tags")
h:Tick(2)
assert(app.tab.controls ~= nil)
clickRow("melee")
assert(app.shownTag == "melee")

-- Select mode from the shown tag leaves it and picks with plain left clicks
local row = app.tab:RowFor("ranged")
app.tab.controls.list.list.scrollY = row.root.y
h:PointAt(row.root, 20, 10 - row.root.y)
Harness.Choose(h:ContentMenu(), "Select items <col=f2c66d>Ranged</col>")
h:Tick(2)
assert(app.select:Tag() == "ranged" and app.handle:GetState().highlighted)
assert(app.shownTag == nil and layout.selectedTag == nil)
-- Consecutive left clicks on native items add each copy and withdraw nothing
local function pickItem(slot)
    local default = Harness.LeftClick(h:MenuFor(host.items[slot]))
    assert(default == "Add to Ranged <col=f2c66d>Item</col>", tostring(default))
    h:Tick(2)
end
pickItem(1)
pickItem(2)
assert(app.store:HasTag("ranged", key(4151, 1)) and app.store:HasTag("ranged", key(4151, 2)))
-- After the bank rebuilds its items, clicks keep tagging
host:Rebuild()
layout:HandleInventoryUpdate()
h:Tick(2)
assert(app.select:Tag() == "ranged")
pickItem(3)
assert(app.store:HasTag("ranged", key(385, 1)) and app.status == nil)
-- Done ends it; a left click on an item is the bank's own again
Harness.Find(h:TabParent(), "Done").hooks.pressed()
h:Tick(2)
assert(app.select:Tag() == nil and not app.handle:GetState().highlighted)
assert(Harness.LeftClick(h:MenuFor(host.items[1])) == "Withdraw-1")

print("bank_clicks_test: ok")
