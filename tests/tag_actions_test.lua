package.path = "./?.lua;./?/init.lua;" .. package.path

-- Drive Bank Tags' item menus, select mode, and bank items
-- FAKE HOST: stand-in loader, components, and menus, not the game client

local Harness = require("tools/test_support/tags_harness")
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

local TagLayouts = h:TagsModule("banktags/tags/tag_layouts")
-- Save a tag's rows directly, as a past session would
local melee = { TagLayouts.Item(4151), { kind = "blank" }, TagLayouts.Item(4151), TagLayouts.Item(4151) }
assert(app.store:CreateTag("melee"))
assert(app.store:CreateTag("ranged"))
app.store.data.tags.melee.rows = { { kind = "label", text = "Weapons" }, { kind = "row", slots = melee } }
app.store.data.tags.melee.unsorted = { TagLayouts.Item(999) }
assert(app.store:Save())
app:Changed()

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

-- The page lists object IDs: whip twice for its two stacks, a third whip as a ghost, then Unsorted
assert(app:ShowTag("melee"))
h:Tick(2)
assert(app:ShownTag() == "melee")
local sections = layout.pageState:GetLayoutSections()
assert(#sections == 2 and sections[1].label == "Weapons" and sections[2].label == "Unsorted")
assert(#app.pageKeys == 5 and app.pageKeys[2] == false and app.pageKeys[4] == melee[4].layoutKey)

-- A ghost removes its own slot; Cancel stays its left click
h:PointAtSlot(4)
local menu = h:SlotMenu()
assert(menu.entries[menu.entryCount].verbText == "Cancel")
Harness.Choose(menu, "Remove from <col=f2c66d>Melee</col>")
assert(h:Saved("melee") == "4151 0 4151 4151 999")
h:Tick(2)
-- Saving trims the row's trailing blank
assert(h:Saved("melee") == "4151 0 4151 999", h:Saved("melee"))

-- A stack removes the slot it was clicked in, counting the blank before it
h:PointAtSlot(3)
assert(layout.itemHover:HasHoveredBankStack())
menu = h:SlotMenu()
Harness.Choose(menu, "Remove from <col=f2c66d>Melee</col>")
h:Tick(2)
assert(h:Saved("melee") == "4151 999", h:Saved("melee"))

-- Unsorted slots count after the rows
h:PointAtSlot(2)
menu = h:SlotMenu()
Harness.Choose(menu, "Remove from <col=f2c66d>Melee</col>")
h:Tick(2)
assert(h:Saved("melee") == "4151", h:Saved("melee"))

-- An entry offered before the page was set again is dropped
h:PointAtSlot(1)
menu = h:SlotMenu()
assert(app:ShowTag("melee"))
Harness.Choose(menu, "Remove from <col=f2c66d>Melee</col>")
h:Tick(2)
assert(h:Saved("melee") == "4151", "the stale entry did not run")
-- So is one offered before another tag was shown
h:PointAtSlot(1)
menu = h:SlotMenu()
assert(app:ShowTag("ranged"))
Harness.Choose(menu, "Remove from <col=f2c66d>Melee</col>")
h:Tick(2)
assert(h:Saved("melee") == "4151", "the stale entry did not run")
-- While the shown tag's new page waits to be drawn, a menu names no slot, so Remove from is not offered
assert(app:ShowTag("melee"))
h:Tick(2)
h:PointAtSlot(1)
assert(app:AddItemToTag("melee", 385))
assert(tagEntries(h:SlotMenu()) == 0)
h:Tick(2)
h:PointAtSlot(1)
assert(tagEntries(h:SlotMenu()) == 1)
assert(app.ext:Close())
h:Tick(2)

-- Outside select mode, native items carry no Bank Tags entries
menu = h:MenuFor(host.items[3])
assert(tagEntries(menu) == 0)

-- An oversized tag is not shown; the bank banner says why
assert(app.store:CreateTag("huge"))
local huge = {}
for index = 1, 10001 do huge[index] = { kind = "blank" } end
app.store.data.tags.huge.rows = { { kind = "row", slots = huge } }
assert(not app:ShowTag("huge") and app:ShownTag() == nil and layout.shownPage == nil)
assert(string.find(app.status, "10002", 1, true) and Harness.Find(app.tab.ctx.overlay, app.status) ~= nil)
app.store.data.tags.huge = nil
app.store.data.order[#app.store.data.order] = nil
app:ShowStatus(nil)

-- Select mode -------------------------------------------------------------------------

-- Select items starts select mode and shows the panel
pointAtRow("ranged")
menu = h:ContentMenu()
Harness.Choose(menu, "Select items <col=f2c66d>Ranged</col>")
h:Tick()
assert(app.select:Tag() == "ranged" and app.status == nil)
assert(Harness.Find(h:TabParent(), "Select mode") ~= nil)
-- The selected row pulses on its own logic subscription
h:Tick(30)
local row = app.tab:RowFor("ranged")
assert(row.background.alpha ~= nil and row.background.alpha < 1)

-- Clicking an item adds its object
menu = h:MenuFor(host.items[1])
local pickLabel = menu.entries[menu.entryCount].verbText
assert(pickLabel == "Add to Ranged <col=f2c66d>Abyssal whip</col>", pickLabel)
Harness.Choose(menu, pickLabel)
h:Tick(2)
assert(h:Saved("ranged") == "4151")
-- Clicking the same object again adds a second slot, for its second stack
Harness.Choose(h:MenuFor(host.items[2]), pickLabel)
h:Tick(2)
assert(h:Saved("ranged") == "4151 4151")

-- Outside All Items it still adds objects
layout.nativeViewAll = false
local detect = layout.DetectNativeViewAll
layout.DetectNativeViewAll = function() return false end
layout:SetNativeViewAll(false)
h:Tick(2)
assert(app.select:Tag() == "ranged" and app.status == nil)
menu = h:MenuFor(host.items[3])
Harness.Choose(menu, menu.entries[menu.entryCount].verbText)
h:Tick(2)
assert(h:Saved("ranged") == "4151 4151 385", h:Saved("ranged"))
layout.nativeViewAll, layout.DetectNativeViewAll = true, detect

-- Done ends it and restores the column
Harness.Find(h:TabParent(), "Done").hooks.pressed()
h:Tick(2)
assert(app.select:Tag() == nil)
assert(Harness.Find(h:TabParent(), "Select mode") == nil)

-- Opening a tag ends select mode quietly
assert(app.select:Toggle("ranged"))
h:ClickRow("melee")
h:Tick(2)
assert(app.select:Tag() == nil and app:ShownTag() == "melee" and app.status == nil)
-- Starting select mode while a tag is shown leaves the tag first
assert(app.select:Toggle("ranged"))
h:Tick(2)
assert(app:ShownTag() == nil and layout.shownPage == nil and app.select:Tag() == "ranged")
-- Deleting the tag being filled ends select mode
assert(app.store:DeleteTag("ranged"))
app:Changed()
h:Tick(2)
assert(app.select:Tag() == nil)
-- Renaming it keeps the session under the new name
assert(app.select:Toggle("melee"))
local renamed = app.windows
renamed:OpenTagSettings("melee", false)
renamed.tagSettingsEditor.field:SetText("Fighting")
renamed.tagSettingsEditor.saveButton.root.hooks.click()
h:Tick(2)
assert(app.select:Tag() == "fighting" and app.select:Label() == "Add to Fighting")
assert(app.select:Stop())
h:Tick(2)

-- Bank items ---------------------------------------------------------------------------

-- Bank items are object IDs and quantities, read when Bank Core says they changed
local items = app:BankItems()
assert(#items == 4 and items[1].objectID == 4151 and items[4].quantity == 0 and items[1].copy == nil)
host:Rebuild(function(specs) specs[3][2] = 99 end)
layout:HandleInventoryUpdate()
for _ = 1, 4 do h:Tick() end
local shark = nil
for _, entry in ipairs(app:BankItems()) do
    if entry.objectID == 385 then shark = entry end
end
assert(shark.quantity == 99)

-- Losing the bank inventory ends select mode while the window is still mounted
assert(app.select:Toggle("fighting"))
h:Tick(2)
h:Fire("InventoryRemoved", { inv = { id = 95 } })
h:Tick(2)
assert(app.select:Tag() == nil, "select mode outlived the bank closing")
-- Reopening the bank starts without it
host:UnmountBankWindow()
session, layout = h:OpenBank()
h:Tick(2)
assert(app.select:Tag() == nil)

-- Save folder filing and expansion together
assert(app.store:CreateTag("folder source"))
assert(app.store:CreateFolder("Saved folder", "fighting"))
assert(app.store:SetFolderCollapsed("saved folder", true))
app:Changed()
local chunks = h:TagsModule("banktags/core/chunked_string_store")
local write = chunks.Write
local saves, failSave = 0, true
chunks.Write = function(...)
    saves = saves + 1
    if failSave then return false, { stage = "manifest", reason = "disk full" } end
    return write(...)
end
assert(not app:MoveTagToFolder("folder source", "saved folder"))
assert(app.store:GetTagFolder("folder source") == nil)
assert(app.store:GetFolder("saved folder").collapsed and saves == 1)
assert(app.status:find("disk full", 1, true))
failSave = false
saves = 0
assert(app:MoveTagToFolder("folder source", "saved folder"))
assert(saves == 1 and app.store:GetTagFolder("folder source") == "saved folder")
assert(not app.store:GetFolder("saved folder").collapsed)
failSave = true
app:ShowStatus(nil)
h:ClickRow("__banktags_folder:saved folder")
assert(not app.store:GetFolder("saved folder").collapsed)
assert(app.status:find("disk full", 1, true))
chunks.Write = write

print("tag_actions_test: ok")
