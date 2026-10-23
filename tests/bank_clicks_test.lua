package.path = "./?.lua;./?/init.lua;" .. package.path

-- Click tag rows and bank items the way the live client delivers clicks
-- Covers showing and leaving tags and select mode's plain left clicks
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

-- Left-click a tag row, which also runs the menu's default
local function clickRow(tag)
    local row = app.tab:RowFor(tag)
    app.tab.controls.list.list.scrollY = row.root.y
    h:PointAt(row.root, 20, 10 - row.root.y)
    local default = Harness.LeftClick(h:ContentMenu())
    h:ClickRow(tag)
    h:Tick(2)
    -- Select is the left click, which the row answers once; no window opens unasked
    assert(string.sub(tostring(default), 1, 7) == "Select ", tostring(default))
    assert(app.windows.textPrompt == nil and app.windows.tagDeleteConfirm == nil
        and app.windows.tagSettingsEditor == nil)
end

clickRow("melee")
assert(app.shownTag == "melee" and layout.pageState.view.key == "tag:melee")
-- The shown tag again returns to the bank's own view
clickRow("melee")
assert(app.shownTag == nil and layout.selection == nil)
-- Another tag replaces the shown one, and choosing it again leaves it
clickRow("melee")
clickRow("ranged")
assert(app.shownTag == "ranged" and layout.pageState.view.key == "tag:ranged")
clickRow("ranged")
assert(app.shownTag == nil and layout.selection == nil)

-- A native tab leaves the shown tag; All Items lets it open again
clickRow("melee")
layout:SetNativeViewAll(false)
h:Tick(2)
assert(app.shownTag == nil and layout.selection == nil)
layout:SetNativeViewAll(true)
h:Tick(2)
clickRow("melee")
assert(app.shownTag == "melee")

-- Another extension's tab leaves the shown tag and unmounts the Tags tab
local other = assert(session.publicAPI.RegisterExtension("other", "Other"))
assert(other:RegisterTab("notes", { label = "Notes", icon = "STAR", mount = { mount = function() end } }))
h:Tick(2)
layout:SetSidebarMode("__bankutils_ext_tab:other/notes")
h:Tick(2)
assert(app.shownTag == nil and layout.selection == nil and app.tab.controls == nil)
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
assert(app.shownTag == nil and layout.selection == nil)
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
