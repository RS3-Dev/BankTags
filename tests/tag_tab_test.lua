package.path = "./?.lua;./?/init.lua;" .. package.path

-- Drive the Tags tab Bank Core mounts, as a player would
-- FAKE HOST: stand-in loader, components, and menus, not the game client

local Harness = require("tools/test_support/tags_harness")
local h = Harness.new("tag_tab")
h.bankHost:SetItems({ { 4151, 1, "Abyssal whip" }, { 385, 20, "Shark" }, { 1944, 3, "Egg" } })
h:LoadCore()
h:LoadTags()
local app = h:App()
local session, layout = h:OpenBank()
h:Tick(2)

-- Seventy tags, more than Bank Core's 16 tabs or 64 rows
for index = 1, 70 do assert(app.store:CreateTag(string.format("tag %02d", index))) end
assert(app.store:CreateTag("melee"))
assert(app.store:CreateTag("ranged"))
assert(app.store:AddTag("melee", 4151))
assert(app.store:AddTag("ranged", 385))
assert(app.store:CreateFolder("Combat", "melee"))
assert(app.store:SetTagFolder("ranged", "combat"))
assert(app.store:CreateFolder("Numbers", "tag 01"))
app:Changed()

local tab = app.tab
local list = tab.controls.list
-- Count the tag rows the list draws
local function tagRows()
    local count = 0
    for _, row in ipairs(list.list.rows) do
        if string.sub(row.entry.id, 1, 18) ~= "__banktags_folder:" then count = count + 1 end
    end
    return count
end
assert(tagRows() == 72, "every tag has a row: " .. tagRows())

-- Searching filters only the tab's own list and never touches the page
local pagesPut = 0
local putPage = app.PutPage
app.PutPage = function(...)
    pagesPut = pagesPut + 1
    return putPage(...)
end
list.search.root.hooks.contentchanged(nil, "change", "mel")
assert(tagRows() == 1 and list.list.rows[2].entry.id == "melee")
list.search.root.hooks.contentchanged(nil, "change", "combat")
assert(tagRows() == 2, "a folder-name match lists its members")
list.search.root.hooks.contentchanged(nil, "change", "nothing like this")
assert(list.emptyLabel.hidden == false and list.emptyLabel.content == "No matching tags.")
list.search.root.hooks.contentchanged(nil, "change", "")
assert(pagesPut == 0 and tagRows() == 72)

-- Collapsing a folder hides its members and saves the state
list.list:Click("__banktags_folder:combat")
assert(app.store:GetFolder("combat").collapsed and tagRows() == 70)
list.list:Click("__banktags_folder:combat")
assert(not app.store:GetFolder("combat").collapsed and tagRows() == 72)

-- Sorting shows arrows that move an entry one step within its own group
local sortButton = list.sortButton.root
sortButton.hooks.pressed()
assert(list.sortMode and #list.sortButtons > 0)
local before = app.store:AllTags()
for _, button in ipairs(list.sortButtons) do
    if button.spriteName == "ARROW_DOWN" and button.root.parent == list.list.rows[1].root then
        button.action()
        break
    end
end
assert(app.store:AllTags()[1] ~= before[1], "the first entry moved down")
sortButton = list.sortButton.root
sortButton.hooks.pressed()
assert(not list.sortMode)

-- Choosing a tag shows it through Bank Tags' one page, keyed by the tag
list.list:Click("melee")
h:Tick(2)
assert(app.shownTag == "melee" and layout.pageState.view.key == "tag:melee")
local state = app.handle:GetState()
assert(#state.pages == 1 and state.pages[1] == "tag" and state.openPage == "tag")
local entries = layout:VisibleMirrorEntries()
assert(#entries == 1 and entries[1].objectID == 4151)
-- The footer offers the layout editor only while a tag is shown
local function hasEditButton()
    for _, control in ipairs(tab.controls.owned) do
        if control.spriteName == "PENCIL" then return true end
    end
    return false
end
assert(hasEditButton())
list = tab.controls.list
-- Another tag updates the same page with a new key; the shown tag again leaves it
list.list:Click("ranged")
h:Tick(2)
assert(app.shownTag == "ranged" and layout.pageState.view.key == "tag:ranged")
assert(#app.handle:GetState().pages == 1)
list = tab.controls.list
list.list:Click("ranged")
h:Tick(2)
assert(app.shownTag == nil and layout.selectedTag == nil and not hasEditButton())

-- The click-through experiment opens a scrolled tag only after the real native All Items operation
local nativeAll = ui.Layer.new(h.bankHost.window.all)
nativeAll:SetPos(350, 12)
nativeAll:SetSize(44, 36)
nativeAll.alpha, nativeAll.clickthrough, nativeAll.interfaceID = 1, false, 517
nativeAll.opConfig = { numOpNames = 1, GetOpName = function(_, index)
    return index == 0 and "View all" or ""
end }
h.bankHost.window.parts[165] = nativeAll
local beforeExperimentDetect = layout.DetectNativeViewAll
layout.nativeViewAll = false
layout.DetectNativeViewAll = function() return false end
local clickedRow = tab:RowFor("melee")
list = tab.controls.list
list.list.scrollY = clickedRow.root.y
local rowLeft, rowTop = require("banktags/ui/geometry").absolutePosition(clickedRow.root)
clickedRow.root.xyGlobal = { x = rowLeft, y = rowTop - list.list.scrollY }
h:PointAt(clickedRow.root, 20, 10 - clickedRow.root.y)
clickedRow.root.hooks.mouseover()
assert(tab.ctx:IsAllItemsClickActive() and clickedRow.root.clickthrough)
local _, nativeParentY = require("banktags/ui/geometry").absolutePosition(nativeAll.parent)
assert(nativeAll.y == clickedRow.root.xyGlobal.y - nativeParentY, "native input follows the scrolled row")
local nativeEntry = { verbText = "View all", componentData = { component = nativeAll } }
local nativeMenu = h:HostMenu({ nativeEntry })
assert(Harness.LeftClick(nativeMenu) == "View all", "the click reaches native All Items")
list.list:Click("melee")
assert(app.shownTag == nil, "the plugin waits rather than opening against the old native tab")
h:Fire("MiniMenuEntrySelected", { entry = nativeEntry })
layout.DetectNativeViewAll = function() return true end
h:Tick(2)
assert(app.shownTag == "melee" and layout.pageState.view.key == "tag:melee")
assert(nativeAll.x == 350 and nativeAll.y == 12 and nativeAll.width == 44 and nativeAll.alpha == 1)
assert(app.handle:LeavePage())
h:Tick(2)
h.bankHost.window.parts[165] = nil
layout.DetectNativeViewAll = beforeExperimentDetect
nativeAll:Destroy()

-- Outside All Items the page is refused and Bank Core shows its guidance
layout.nativeViewAll = false
local detect = layout.DetectNativeViewAll
layout.DetectNativeViewAll = function() return false end
local guidance = nil
local showGuidance = layout.ShowPageGuidance
layout.ShowPageGuidance = function(_, reason) guidance = reason end
list = tab.controls.list
list.list:Click("melee")
h:Tick(2)
assert(app.shownTag == nil and layout.selectedTag == nil and guidance == "not_all_items")
layout.nativeViewAll, layout.DetectNativeViewAll, layout.ShowPageGuidance = true, detect, showGuidance

-- Scroll a row to the top of the list and point at it
local function pointAtRow(entryID)
    list = tab.controls.list
    local row = nil
    for _, candidate in ipairs(list.list.rows) do
        if candidate.entry.id == entryID then row = candidate end
    end
    list.list.scrollY = row.root.y
    h:PointAt(row.root, 20, 10 - row.root.y)
    return row
end

-- A scrolled row is found where it is drawn
local melee = pointAtRow("melee")
assert(melee.root.y > list.list.root.height, "melee starts below the visible list")

-- Right-clicking a tag row offers its actions; Select shows it on a later tick
local menu = h:ContentMenu()
-- Native row hover wins when Windows DPI makes raw mouse pixels disagree
h.bankHost.mouse = { x = -1000, y = -1000 }
menu = h:ContentMenu()
assert(Harness.Has(menu, "Select <col=f2c66d>Melee</col>"))
for _, labelText in ipairs({ "Select", "Edit", "Rename", "Select items", "Remove", "Remove from folder",
    "Move to folder" }) do
    local found = false
    for _, entry in ipairs(menu.entries) do
        if string.sub(entry.verbText, 1, #labelText) == labelText then found = true end
    end
    assert(found, labelText .. " is offered: " .. table.concat(Harness.Labels(menu), " | "))
end
Harness.Choose(menu, "Select <col=f2c66d>Melee</col>")
assert(app.shownTag == nil)
h:Tick(2)
assert(app.shownTag == "melee" and layout.pageState.view.key == "tag:melee")
assert(app.handle:LeavePage())
h:Tick(2)

-- The folder submenu files the tag under another folder; Remove from folder files it under none
local moveMelee = "Move to folder <col=f2c66d>Melee</col> <col=ffffff><gt></col>"
pointAtRow("melee")
menu = h:ContentMenu()
assert(table.concat(Harness.ChildLabels(Harness.Submenu(menu, moveMelee)), ",") == "Numbers,Create new folder,Cancel")
Harness.ChooseChild(menu, moveMelee, "Numbers")
h:Tick(1)
assert(app.store:GetTagFolder("melee") == "numbers")
pointAtRow("melee")
menu = h:ContentMenu()
Harness.Choose(menu, "Remove from folder <col=f2c66d>Numbers</col>")
h:Tick(1)
assert(app.store:GetTagFolder("melee") == nil)
assert(app.store:CreateFolder("Numbers", "melee"))
app:Changed()
-- Edit opens the layout editor; Rename opens the name and icon settings
pointAtRow("melee")
menu = h:ContentMenu()
Harness.Choose(menu, "Edit <col=f2c66d>Melee</col>")
h:Tick(1)
assert(app.windows.layoutEditor ~= nil and app.windows.layoutEditor.selectedTag == "melee")
assert(app.windows.tagSettingsEditor == nil)
app.windows:Close("layoutEditor")
pointAtRow("melee")
menu = h:ContentMenu()
Harness.Choose(menu, "Rename <col=f2c66d>Melee</col>")
h:Tick(1)
assert(app.windows.tagSettingsEditor ~= nil and app.windows.tagSettingsEditor.field.text == "melee")
assert(app.windows.layoutEditor == nil)
app.windows:Close("tagSettingsEditor")
-- Without PrettyUI's MiniMenu the row keeps its other actions
local MiniMenu = prettyui.MiniMenu
prettyui.MiniMenu = nil
pointAtRow("melee")
menu = h:ContentMenu()
assert(#Harness.Submenus(menu) == 0 and Harness.LeftClick(menu) == "Select <col=f2c66d>Melee</col>")
assert(Harness.Has(menu, "Remove from folder <col=f2c66d>Numbers</col>"))
prettyui.MiniMenu = MiniMenu

-- Folder rows offer collapse, rename, and ungroup
pointAtRow("__banktags_folder:numbers")
menu = h:ContentMenu()
assert(Harness.Has(menu, "Collapse <col=f2c66d>Numbers</col>") and Harness.Has(menu, "Ungroup folder <col=f2c66d>Numbers</col>"))
Harness.Choose(menu, "Ungroup folder <col=f2c66d>Numbers</col>")
h:Tick(1)
assert(app.store:GetFolder("numbers") == nil and app.store:GetTagFolder("melee") == nil)

-- Column space outside the rows has no menu entries
h:PointAt(h:TabParent(), 2, 3)
menu = h:ContentMenu()
assert(#menu.entries == 1)

-- New Tag opens an unsaved draft; saving it creates the tag
Harness.Find(h:TabParent(), "New Tag").hooks.pressed()
local editor = app.windows.tagSettingsEditor
assert(editor ~= nil and app.store.data.tags["placeholder 1"] == nil)
editor.field:SetText("Potions")
editor.saveButton.root.hooks.click()
assert(app.store.data.tags.potions ~= nil)
assert(tab.controls.list:RowFor("potions") ~= nil)

-- A resize rebuilds the column at Bank Core's new bounds
local mount = layout.tabMount
local oldList = tab.controls.list
mount:Resize({ x = mount.bounds.x, y = mount.bounds.y, width = mount.bounds.width,
    height = mount.bounds.height - 40 })
assert(tab.controls.list ~= oldList and tab.controls.list.list.root.height < oldList.list.root.height)

-- Closing the bank unmounts the column; reopening mounts it with the search kept
tab.controls.list.search.root.hooks.contentchanged(nil, "change", "pot")
h.bankHost:UnmountBankWindow()
layout:Restore()
assert(tab.controls == nil and tab.ctx == nil)
session, layout = h:OpenBank()
h:Tick(2)
assert(tab.controls ~= nil and tab.controls.list.search.text == "pot")

-- Bank Tags' preferences in the bank settings window apply to the tab at once
assert(app.store:CreateTag("iconic", 385))
local function iconRows()
    local count = 0
    for _, row in ipairs(tab.controls.list.list.rows) do
        for _, child in ipairs(row.root.children) do
            if child.associatedObjectID ~= nil then count = count + 1 end
        end
    end
    return count
end
tab.controls.list.search.root.hooks.contentchanged(nil, "change", "iconic")
assert(iconRows() == 1)
layout.tabRail.settingsButton.root.hooks.pressed()
assert(session.bankSettings.window.nav:Click("banktags"))
app.settingsSection.controls.showTagSprites:SetSelected("showTagSprites", false, true)
assert(app.settings.showTagSprites == false and iconRows() == 0)

print("tag_tab_test: ok")
