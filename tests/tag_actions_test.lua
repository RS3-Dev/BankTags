package.path = "./?.lua;./?/init.lua;" .. package.path

-- Drive Bank Tags' item menus, drops, select mode, and bank snapshots
-- FAKE HOST: stand-in loader, components, and menus, not the game client

local Harness = require("tools/test_support/tags_harness")
local Geometry = require("banktags/ui/geometry")
local h = Harness.new("tag_actions")
local host = h.bankHost
host:SetItems({ { 4151, 1, "Abyssal whip" }, { 4151, 1, "Abyssal whip" }, { 385, 20, "Shark" },
    { 1944, 0, "Egg" } })
host.itemLayer.interfaceID = 517
for _, item in ipairs(host.items) do item.outlineWidth, item.shadowRGBA = 0, 0 end
h:LoadCore()
h:LoadTags()
local app = h:App()
local session, layout = h:OpenBank()
h:Tick(2)

local ItemIdentity = require("banktags/tags/item_identity")
local key = ItemIdentity.LayoutKey
-- Save a tag's rows directly, as a past session would
local function item(objectID, copy, source)
    return { kind = "item", objectID = objectID, layoutKey = key(objectID, copy),
        sourceLayoutKey = source ~= nil and key(objectID, source) or nil }
end
assert(app.store:CreateTag("melee"))
assert(app.store:CreateTag("ranged"))
app.store.data.tags.melee.rows = { { kind = "row", slots = {
    item(4151, 1), item(4151, 3, 1), item(4151, 2), item(999, 1) } } }
assert(app.store:Save())
app:Changed()

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
-- Count Bank Tags' entries in a menu
local function tagEntries(menu)
    local count = 0
    for _, entry in ipairs(menu.entries) do
        local text = entry.verbText
        if string.find(text, "Remove from", 1, true) or string.find(text, "Add to", 1, true) then
            count = count + 1
        end
    end
    return count
end

-- Item menus over the shown tag ----------------------------------------------------

assert(app:ShowTag("melee"))
h:Tick(2)
assert(layout.pageState.view.key == "tag:melee")

-- A ghost removes its own copy, not the stack beneath
pointAt(52, 4)
h:Tick()
assert(layout.nativeLease:HasInteractionLease())
local menu = h:MenuFor(host.items[1])
Harness.Choose(menu, "Remove from <col=f2c66d>Melee</col>")
assert(app.store:HasTag("melee", key(4151, 3)))
h:Tick(2)
assert(not app.store:HasTag("melee", key(4151, 3)) and app.store:HasTag("melee", key(4151, 1)))
-- The page shows the ghost's slot as blank
local rows = app.store.data.tags.melee.rows[1].slots
assert(rows[2].kind == "blank" and rows[3].layoutKey == key(4151, 2))

-- A stack removes its own copy
pointAt(96, 4)
h:Tick()
menu = h:MenuFor(host.items[2])
Harness.Choose(menu, "Remove from <col=f2c66d>Melee</col>")
h:Tick(2)
assert(not app.store:HasTag("melee", key(4151, 2)) and app.store:HasTag("melee", key(4151, 1)))

-- A slot with no stack answers too; Cancel stays its left click
pointAt(140, 4)
h:Tick()
menu = h:ContentMenu()
assert(menu.entries[menu.entryCount].verbText == "Cancel")
Harness.Choose(menu, "Remove from <col=f2c66d>Melee</col>")
h:Tick(2)
assert(not app.store:HasTag("melee", key(999, 1)))

-- An entry offered before the shown tag changed is dropped
pointAt(8, 4)
h:Tick()
menu = h:MenuFor(host.items[1])
assert(app:ShowTag("ranged"))
Harness.Choose(menu, "Remove from <col=f2c66d>Melee</col>")
h:Tick(2)
assert(app.store:HasTag("melee", key(4151, 1)), "the stale entry did not run")
assert(app.handle:LeavePage())
h:Tick(2)

-- Outside select mode, native items carry no Bank Tags entries
menu = h:MenuFor(host.items[3])
assert(tagEntries(menu) == 0)

-- Drops -------------------------------------------------------------------------------

-- A native item dropped on a tag row joins that tag as the copy it is
assert(host.items[2].hooks.dragcomplete ~= nil)
pointAtRow("ranged")
local dropRow = app.tab:RowFor("ranged").root
host.mouse = { x = -1000, y = -1000 }
host.items[2].hooks.dragcomplete(host.items[2], dropRow)
h:Tick(2)
assert(app.store:HasTag("ranged", key(4151, 2)) and not app.store:HasTag("ranged", key(4151, 1)))

-- A drop on New Tag creates a tag holding the item and opens it for naming
local newTag = Harness.Find(h:TabParent(), "New Tag")
local left, top = Geometry.absolutePosition(newTag)
h:PointAt(newTag, 10, 10)
host.items[3].hooks.dragcomplete()
h:Tick(2)
assert(app.store:HasTag("placeholder 1", key(385, 1)))
assert(app.windows.tagSettingsEditor ~= nil and app.windows.tagSettingsEditor.originalTag == "placeholder 1")
app.windows:Close("tagSettingsEditor")

-- Browsing a numbered tab is not an error, so the tab shows no warning
layout.nativeViewAll = false
local detect = layout.DetectNativeViewAll
layout.DetectNativeViewAll = function() return false end
h:Session().extensionPages:Notify()
h:Tick(2)
assert(app.status == nil, tostring(app.status))
layout:SetNativeViewAll(false)
h:Tick(2)
assert(app.status == nil, tostring(app.status))
-- Numbered tabs carry no copy, so a drop tags copy 1
assert(app.store:CreateTag("tabbed"))
app:Changed()
pointAtRow("tabbed")
host.items[2].hooks.dragcomplete()
h:Tick(2)
assert(app.store:HasTag("tabbed", key(4151, 1)) and not app.store:HasTag("tabbed", key(4151, 2)))
assert(app.status == nil)
-- New Tag takes a numbered tab's drop the same way
newTag = Harness.Find(h:TabParent(), "New Tag")
left, top = Geometry.absolutePosition(newTag)
h:PointAt(newTag, 10, 10)
host.items[3].hooks.dragcomplete()
h:Tick(2)
assert(app.store:HasTag("placeholder 2", key(385, 1)))
app.windows:Close("tagSettingsEditor")
-- A drop queued before another numbered tab is chosen is refused
pointAtRow("tabbed")
host.items[3].hooks.dragcomplete()
layout:SetNativeViewAll(false)
h:Tick(2)
assert(not app.store:HasTag("tabbed", key(385, 1)))
-- A drop queued before the bank closes is refused
host.items[3].hooks.dragcomplete()
local dropHook = host.items[3].hooks.dragcomplete
session:CloseBank()
h:Tick(2)
assert(not app.store:HasTag("tabbed", key(385, 1)))
session, layout = h:OpenBank()
h:Tick(2)
dropHook()
h:Tick(2)
assert(not app.store:HasTag("tabbed", key(385, 1)))
assert(app.store:DeleteTag("tabbed") and app.store:DeleteTag("placeholder 2"))
app:Changed()
-- Only a drop may leave a copy unnumbered
assert(not app:AddItemToTag("ranged", 4151, nil) and not app.store:HasTag("ranged", key(4151, 1)))
layout.nativeViewAll, layout.DetectNativeViewAll = true, detect
app:ShowStatus(nil)
h:Session().extensionPages:Notify()
h:Tick(2)
assert(app.status == nil)

-- Select mode -------------------------------------------------------------------------

-- Select items starts select mode, outlining members and showing the panel
pointAtRow("ranged")
menu = h:ContentMenu()
Harness.Choose(menu, "Select items <col=f2c66d>Ranged</col>")
h:Tick()
assert(app.select:Tag() == "ranged" and app.handle:GetState().highlighted and app.status == nil)
assert((host.items[2].outlineWidth or 0) > 0 and (host.items[1].outlineWidth or 0) == 0)
assert(Harness.Find(h:TabParent(), "Select mode") ~= nil)
assert(Harness.Find(h:TabParent(), "Items already in this tag have a gold outline.") ~= nil)
-- The selected row pulses on its own logic subscription
h:Tick(30)
local row = app.tab:RowFor("ranged")
assert(row.background.alpha ~= nil and row.background.alpha < 1)

-- Clicking an item adds that copy and outlines it
menu = h:MenuFor(host.items[1])
local pickLabel = menu.entries[menu.entryCount].verbText
assert(pickLabel == "Add to Ranged <col=f2c66d>Item</col>", pickLabel)
Harness.Choose(menu, pickLabel)
h:Tick(2)
assert(app.store:HasTag("ranged", key(4151, 1)) and (host.items[1].outlineWidth or 0) > 0)

-- Done ends it, restoring outlines and the column
Harness.Find(h:TabParent(), "Done").hooks.pressed()
h:Tick(2)
assert(app.select:Tag() == nil and not app.handle:GetState().highlighted)
assert((host.items[1].outlineWidth or 0) == 0 and Harness.Find(h:TabParent(), "Select mode") == nil)

-- Opening a tag ends select mode quietly
assert(app.select:Toggle("ranged"))
app.tab.controls.list.list:Click("melee")
h:Tick(2)
assert(app.select:Tag() == nil and app.shownTag == "melee" and app.status == nil)
-- Starting select mode while a tag is shown leaves the tag first
assert(app.select:Toggle("ranged"))
h:Tick(2)
assert(app.shownTag == nil and layout.selectedTag == nil and app.select:Tag() == "ranged")
-- A native tab ends it and the tab says why
layout.DetectNativeViewAll = function() return false end
layout:SetNativeViewAll(false)
h:Tick(2)
assert(app.select:Tag() == nil and app.status == 'Select "All Items" before choosing items for a tag.')
-- It cannot start outside All Items
assert(not app.select:Toggle("ranged") and not app.handle:GetState().highlighted)
layout.nativeViewAll, layout.DetectNativeViewAll = true, detect
-- Deleting the tag being filled ends select mode
app:ShowStatus(nil)
assert(app.select:Toggle("ranged"))
assert(app.store:DeleteTag("ranged"))
app:Changed()
h:Tick(2)
assert(app.select:Tag() == nil and not app.handle:GetState().highlighted)
-- Renaming it keeps the session under the new name
assert(app.select:Toggle("melee"))
local renamed = app.windows
renamed:OpenTagSettings("melee", false)
renamed.tagSettingsEditor.field:SetText("Fighting")
renamed.tagSettingsEditor.saveButton.root.hooks.click()
h:Tick(2)
assert(app.select:Tag() == "fighting" and app.select:Label() == "Add to Fighting")
assert(app.handle:GetState().highlighted and app.select:Stop())
h:Tick(2)

-- Bank snapshots ---------------------------------------------------------------------

-- The editor and search keep the last good snapshot while Core rereads
assert(app.bankItems ~= nil)
local before = app.bankItems.generation
assert(app:ShowTag("fighting"))
h:Tick(2)
pointAt(8, 4)
h:Tick()
assert(layout.nativeLease:HasInteractionLease())
host:Rebuild(function(specs) specs[3][2] = 99 end)
layout:HandleInventoryUpdate()
h:Tick(2)
assert(select(2, app.handle:GetBankItems()) == "building")
assert(app.bankItems.generation == before)
-- Once the pointer leaves and Core reads the bank, the fresh items arrive
host.mouse = { x = -500, y = -500 }
for _ = 1, 4 do h:Tick() end
assert(app.bankItems.generation ~= before)
local shark = nil
for _, entry in ipairs(app.bankItems.items) do
    if entry.objectID == 385 then shark = entry end
end
assert(shark.quantity == 99)

print("tag_actions_test: ok")
