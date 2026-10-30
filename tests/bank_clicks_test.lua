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

assert(app.store:CreateTag("melee"))
assert(app.store:CreateTag("ranged"))
assert(app.store:AddTag("melee", 4151))
assert(app.store:AddTag("ranged", 385))
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
assert(app:ShownTag() == "melee" and layout.shownPage.title == "Melee")
-- The shown tag again returns to the bank's own view
clickRow("melee")
assert(app:ShownTag() == nil and layout.shownPage == nil)
-- Another tag replaces the shown one, and choosing it again leaves it
clickRow("melee")
clickRow("ranged")
assert(app:ShownTag() == "ranged" and layout.shownPage.title == "Ranged")
clickRow("ranged")
assert(app:ShownTag() == nil and layout.shownPage == nil)

-- A native tab leaves the shown tag; All Items lets it open again
clickRow("melee")
layout:SetNativeViewAll(false)
h:Tick(2)
assert(app:ShownTag() == nil and layout.shownPage == nil)
layout:SetNativeViewAll(true)
h:Tick(2)
clickRow("melee")
assert(app:ShownTag() == "melee")

-- Another extension's column unmounts the Tags tab and leaves the shown tag alone
assert(session.publicAPI.Register({ id = "other", name = "Other", icon = "STAR",
    column = { mount = function() end } }))
h:Tick(2)
layout:SetSidebarMode("__bankutils_ext_tab:other")
h:Tick(2)
assert(app:ShownTag() == "melee" and app.tab.controls == nil)
layout:SetSidebarMode("__bankutils_ext_tab:banktags")
h:Tick(2)
assert(app.tab.controls ~= nil and app:ShownTag() == "melee")

-- Select mode from the shown tag leaves it and picks with plain left clicks
local row = app.tab:RowFor("ranged")
app.tab.controls.list.list.scrollY = row.root.y
h:PointAt(row.root, 20, 10 - row.root.y)
Harness.Choose(h:ContentMenu(), "Select items <col=f2c66d>Ranged</col>")
h:Tick(2)
assert(app.select:Tag() == "ranged")
assert(app:ShownTag() == nil and layout.shownPage == nil)
-- Consecutive left clicks on native items add a slot each and withdraw nothing
local function pickItem(slot, name)
    local default = Harness.LeftClick(h:MenuFor(host.items[slot]))
    assert(default == "Add to Ranged <col=f2c66d>" .. name .. "</col>", tostring(default))
    h:Tick(2)
end
pickItem(1, "Abyssal whip")
pickItem(2, "Abyssal whip")
assert(h:Saved("ranged") == "385 4151 4151", h:Saved("ranged"))
-- After the bank rebuilds its items, clicks keep tagging
host:Rebuild()
layout:HandleInventoryUpdate()
h:Tick(2)
assert(app.select:Tag() == "ranged")
pickItem(3, "Shark")
assert(h:Saved("ranged") == "385 4151 4151 385" and app.status == nil)
-- Done ends it; a left click on an item is the bank's own again
Harness.Find(h:TabParent(), "Done").hooks.pressed()
h:Tick(2)
assert(app.select:Tag() == nil)
assert(Harness.LeftClick(h:MenuFor(host.items[1])) == "Withdraw-1")

print("bank_clicks_test: ok")
