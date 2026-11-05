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
-- Check sidebar footer actions and Help placement
local function checkButtons(editing)
    local controls = tab.controls
    local search = controls.list.search.root
    local help = controls.tutorialButton.root
    local share = controls.importShareButton.root
    local newTag = controls.newTagButton.root
    assert(help.y == search.y and help.x == search.x + search.width + 6)
    assert(help.height == search.height)
    assert(newTag.x == share.x + share.width + 8 and newTag.y == share.y)
    assert(newTag.height == share.height)
    if editing then
        local edit = controls.editTagButton.root
        assert(edit.x == newTag.x + newTag.width + 8 and edit.y == share.y)
        assert(edit.x + edit.width == help.x + help.width)
    else
        assert(controls.editTagButton == nil)
        assert(newTag.x + newTag.width == help.x + help.width)
    end
end
checkButtons(false)
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
local putPage = app.SetTagPage
app.SetTagPage = function(...)
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
h:ClickRow("__banktags_folder:combat")
assert(app.store:GetFolder("combat").collapsed and tagRows() == 70)
h:ClickRow("__banktags_folder:combat")
assert(not app.store:GetFolder("combat").collapsed and tagRows() == 72)

-- Folder settings reuse the tag icon picker and save only on confirmation
app.windows:OpenRenameFolderPrompt("combat")
local folderEditor = app.windows.tagSettingsEditor
assert(folderEditor.field.text == "Combat" and folderEditor.nameLabel.content == "Folder name")
folderEditor.spriteSlot.root.hooks.click()
assert(app.windows.spritePickerOwner == folderEditor)
app.windows.spritePicker.onSelect({ objectId = 385 })
assert(app.store:GetFolderSprite("combat") == nil)
folderEditor:Save("Combat")
assert(app.store:GetFolderSprite("combat") == 385)
local folderRow = tab:RowFor("__banktags_folder:combat")
local folderIcon
for _, child in ipairs(folderRow.root.children) do
    if child.associatedObjectID == 385 then folderIcon = child end
end
assert(folderIcon ~= nil and folderIcon.clickthrough and folderRow.label.x > folderIcon.x)
app.windows:Close("tagSettingsEditor")
app.windows:OpenRenameFolderPrompt("combat")
assert(app.windows.tagSettingsEditor.spriteObjectID == 385)
app.windows.tagSettingsEditor:SetSprite(4151)
app.windows:Close("tagSettingsEditor")
assert(app.store:GetFolderSprite("combat") == 385, "cancel keeps the saved folder icon")

-- Rows are reordered by dragging them, so the column has no Sort button or row arrows
for _, spriteName in ipairs({ "SWAP", "ARROW_UP", "ARROW_DOWN" }) do
    for _, control in ipairs(tab.controls.owned) do assert(control.spriteName ~= spriteName) end
    for _, row in ipairs(list.list.rows) do
        for _, child in ipairs(row.root.children) do assert(child.spriteName ~= spriteName) end
    end
end

-- Choosing a tag sets Bank Tags' page to it and opens it
h:ClickRow("melee")
h:Tick(2)
assert(app:ShownTag() == "melee" and app.ext:IsOpen())
assert(#layout.pageState:GetLayoutSections() == 1 and layout.pageState:GetLayoutSections()[1].label == "Unsorted")
checkButtons(true)
local entries = layout:BuildPageItems()
assert(#entries == 1 and entries[1].objectID == 4151)
-- Check whether the footer offers layout editing
local function hasEditButton()
    for _, control in ipairs(tab.controls.owned) do
        if control.spriteName == "PENCIL" then return true end
    end
    return false
end
assert(hasEditButton())
list = tab.controls.list
-- Another tag sets and opens the page again; the shown tag again closes it
h:ClickRow("ranged")
h:Tick(2)
assert(app:ShownTag() == "ranged" and layout.pageState:GetLayoutSections()[1].label == "Unsorted")
-- The footer stays, and its Edit opens the tag shown now, not the one shown when it was built
for _, control in ipairs(tab.controls.owned) do
    if control.spriteName == "PENCIL" then control.root.hooks.pressed() end
end
assert(app.windows.layoutEditor ~= nil and app.windows.layoutEditor.selectedTag == "ranged")
app.windows:Close("layoutEditor")
list = tab.controls.list
h:ClickRow("ranged")
h:Tick(2)
assert(app:ShownTag() == nil and layout.shownPage == nil and not hasEditButton())

-- Outside All Items the bank banner says why; showing a tag clears it
layout.nativeViewAll = false
local detect = layout.DetectNativeViewAll
layout.DetectNativeViewAll = function() return false end
list = tab.controls.list
h:ClickRow("melee")
h:Tick(2)
assert(app:ShownTag() == nil and layout.shownPage == nil and app.status == 'Select "All Items" to view this tag.')
layout.nativeViewAll, layout.DetectNativeViewAll = true, detect
-- With the preset selector open it says to close it
local presetOpen = layout.IsPresetViewOpen
layout.IsPresetViewOpen = function() return true end
list = tab.controls.list
h:ClickRow("melee")
h:Tick(2)
assert(app:ShownTag() == nil and layout.shownPage == nil and app.status == 'Close the preset selector to view this tag.')
layout.IsPresetViewOpen = presetOpen
list = tab.controls.list
h:ClickRow("melee")
h:Tick(2)
assert(app:ShownTag() == "melee" and app.status == nil)
list = tab.controls.list
h:ClickRow("melee")
h:Tick(2)
assert(app:ShownTag() == nil and layout.shownPage == nil)
-- Another extension's page replacing the tag clears the row's highlight once Bank Core says so
h:ClickRow("melee")
h:Tick(2)
assert(tab.controls.list:RowFor("melee").selectionFrame ~= nil)
local other = assert(h:Session().publicAPI.Register({ id = "other", name = "Other" }))
assert(other:SetPage({ rows = { { slots = { 385 } } } }) and other:Open())
assert(app:ShownTag() == nil)
h:Tick(2)
assert(tab.controls.list:RowFor("melee").selectionFrame == nil)
assert(other:Dispose())
h:Tick(2)

-- Scroll a sidebar row into view and hover it
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
assert(app:ShownTag() == nil)
h:Tick(2)
assert(app:ShownTag() == "melee")
assert(app.ext:Close())
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
-- Count item icons drawn on sidebar rows
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
local panel = ui.Layer.new(nil)
panel:SetSize(300, 400)
h.hostSubscriptions.SettingsLayerReady.banktags_settings({ component = panel })
app.settingsSection.controls.showTagSprites:SetSelected("showTagSprites", false, true)
assert(app.settings.showTagSprites == false and iconRows() == 0)
tab.controls.list.search.root.hooks.contentchanged(nil, "change", "combat")
assert(iconRows() == 0, "the sprite preference hides folder icons too")
app.settingsSection.controls.showTagSprites:SetSelected("showTagSprites", true, true)
assert(iconRows() == 1, "enabling sprites restores the folder icon")

print("tag_tab_test: ok")
