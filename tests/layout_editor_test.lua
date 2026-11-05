package.path = "./?.lua;./?/init.lua;" .. package.path
local BankGrid = require("banktags/ui/bank_grid")

-- Check that saved editor moves appear on the bank page
-- FAKE HOST: stand-in components, loader, and menus

local Harness = require("tools/test_support/tags_harness")
local Geometry = require("banktags/ui/geometry")
local h = Harness.new("layout_editor")
local host = h.bankHost
host:SetItems({ { 4151, 1, "Abyssal whip" }, { 4151, 1, "Abyssal whip" }, { 385, 20, "Shark" },
    { 1944, 0, "Egg" } })
host.itemLayer.interfaceID = 517
-- A bank three columns wider than the default
host.itemLayer.width = 448 + 3 * 44
h:LoadCore()
h:LoadTags()
local app = h:App()
local session, layout = h:OpenBank()
h:Tick(12)
local bounds = app.windows:BankBounds()
assert(bounds.columns == 13)

assert(app.store:CreateTag("melee", 4151))
assert(app.store:CreateTag("food"))
assert(app.store:CreateFolder("Combat", "melee"))
app.store:SetLayoutPlacement(false)
local _, _, WHIP = app.store:AddTag("melee", 4151)
app.store:SetLayoutPlacement(true)
local _, _, SHARK = app.store:AddTag("melee", 385)
assert(WHIP ~= nil and SHARK ~= nil and app.store:AddTag("melee", 1944))
app:Changed()
assert(app:ShowTag("melee"))
h:Tick(2)

-- The pencil in the Tags tab opens the editor for the shown tag, over the bank
local pencil = nil
for _, control in ipairs(app.tab.controls.owned) do
    if control.spriteName == "PENCIL" then pencil = control end
end
pencil.root.hooks.pressed()
local editor = app.windows.layoutEditor
assert(editor ~= nil and editor.selectedTag == "melee")
local editorSize = h:TagsModule("banktags/windows/layout_editor_parts").size
assert(editorSize.CENTER_COLUMNS == 13)
assert(editor.window.root.x == bounds.x and editor.window.root.y == bounds.y)
-- Tag buttons retain sidebar order and use icons or initials
local rail = editor.tagTabs
-- List the labels on the editor's tag tabs
local function railLabels()
    local labels = {}
    for _, entry in ipairs(rail.entries) do labels[#labels + 1] = entry.label end
    return table.concat(labels, ",")
end
-- Read the selected tag tab
local function chosen() return rail:GetSelectedID() end
-- Choose the named entry from an opened menu
local function choose(label)
    for _, entry in ipairs(rail.entries) do
        if entry.label == label then return assert(rail:Select(entry.id, true)) end
    end
    error("no rail entry " .. label)
end
assert(rail.entries[1].label == "Melee" and rail.entries[2].label == "Food" and chosen() == "melee")
assert(rail.rows[1].icon.associatedObjectID == 4151 and rail.rows[1].icon.clickthrough)
assert(rail.rows[2].icon == nil and rail.rows[2].label.content == "F")
assert(rail.rows[1].background.spriteID == id.Sprite.BANK_TABS_HORIZONTAL_1)
assert(rail.rows[2].background.spriteID == id.Sprite.BANK_TABS_HORIZONTAL_0)
assert(editor.tagTitle == nil and editor.tagIcon == nil)
assert(editor.status.content == "" and editor.status.parent == editor.content)
assert(editor.status.x >= editor.newLabelButton.x + editor.newLabelButton.width)
assert(editor.status.x + editor.status.width <= editor.closeButton.x)
assert(Harness.Find(editor.content, "Rename") == nil and editor.chooser == nil and editor.tabs == nil)
assert(Harness.Find(editor.content, "Exit edit mode") == nil and editor.exitButton == nil)
assert(Harness.Find(editor.content, "New Tag") == nil)
assert(editor.unsortedPanel.x < editor.centerPanel.x and editor.centerPanel.x < editor.searchPanel.x)
assert(rail.root.x >= editor.centerPanel.x and rail.root.y < editor.panes.sorted.y)
assert(editor.panes.sorted.y == editor.panes.unsorted.y)
assert(not editor.searchDragSurface.hidden and not editor.panes.unsorted.surface.hidden)
assert(Harness.Find(editor.content, "Saved automatically") == nil)

-- Find the drawn sprite for an item
local function spriteFor(objectID)
    for _, pane in pairs(editor.panes) do
        for _, sprite in pairs(pane.sprites) do
            if sprite.associatedObjectID == objectID then return sprite end
        end
    end
    return nil
end
assert(spriteFor(385).associatedObjectQuantity == 20 and spriteFor(385).alpha == 1)
assert(spriteFor(1944).alpha < 1)

-- The editor's pointer maps through its content's place on the screen
editor.window.tooltipContext = { position = function()
    return Geometry.absolutePosition(editor.content)
end }
-- Point at the centre of a pane's grid cell
local function pointAtSlot(paneName, column, row)
    local left, top = Geometry.absolutePosition(editor.content)
    local pane = editor.panes[paneName]
    local x, y = pane.gridLeft + column * 44 + 20, BankGrid.RowItemY(row, pane.labels) + 20 - pane.view.scrollY
    h:PointEditor(pane.x + x, pane.y + y)
    return x, y
end
-- Drag between the chosen grid cells
local function drag(fromPane, fromColumn, fromRow, toPane, toColumn, toRow)
    local surface = editor.panes[fromPane].surface
    h:PressEditor(surface, pointAtSlot(fromPane, fromColumn, fromRow))
    pointAtSlot(toPane, toColumn, toRow)
    h:ReleaseEditor()
end

-- Layout fills the center and Unsorted stays visible on the right; the shark leads it
local sorted, unsorted = editor.panes.sorted, editor.panes.unsorted
assert(sorted.slots[1].layoutKey == WHIP and unsorted.slots[1].layoutKey == SHARK)
-- Drag the shark into column 12, which only 13 columns allow
drag("unsorted", 0, 0, "sorted", 11, 0)
local row = app.store.data.tags.melee.rows[1].slots
assert(#row == 12 and row[12].layoutKey == SHARK, "the shark landed at row 1, column 12")
h:Tick(4)
-- Bank Core draws the page at the same columns
local whipY, sharkX, sharkY = nil, nil, nil
for _, entry in ipairs(layout:BuildPageItems()) do
    if entry.objectID == 4151 then whipY = entry.y end
    if entry.objectID == 385 then sharkX, sharkY = entry.x, entry.y end
end
assert(whipY ~= nil and sharkY == whipY and sharkX == 8 + 11 * 44, tostring(sharkX))

-- Select the whip, copy it, and paste it into an empty cell as another whip slot
drag("sorted", 0, 0, "sorted", 0, 0)
assert(editor.selectedLayoutKey == WHIP)
Harness.Find(editor.content, "Copy").hooks.pressed()
drag("sorted", 5, 0, "sorted", 5, 0)
assert(editor.pasteCell == 6 and editor.selectedLayoutKey == nil)
Harness.Find(editor.content, "Paste").hooks.pressed()
local pasted = editor.selectedLayoutKey
assert(pasted ~= nil and pasted ~= WHIP and editor.pasteCell == nil)
local row1 = app.store.data.tags.melee.rows[1].slots
assert(row1[6].layoutKey == pasted and row1[6].objectID == 4151)
-- Move to Unsorted keeps the selected slot in the tag
Harness.Find(editor.content, "Move to Unsorted").hooks.pressed()
local unsorted = app.store.data.tags.melee.unsorted
assert(unsorted[#unsorted].layoutKey == pasted and h:Saved("melee") == "4151 0 0 0 0 0 0 0 0 0 0 385 1944 4151")
-- Remove takes the selected slot out of the tag
drag("sorted", 0, 0, "sorted", 0, 0)
Harness.Find(editor.content, "Remove").hooks.pressed()
assert(h:Saved("melee") == "0 0 0 0 0 0 0 0 0 0 0 385 1944 4151", h:Saved("melee"))
-- Removing an empty selection does nothing; Copy still explains its missing selection
editor.selectedLayoutKey = nil
Harness.Find(editor.content, "Remove").hooks.pressed()
assert(editor.status.content == "")
Harness.Find(editor.content, "Copy").hooks.pressed()
assert(editor.status.content == "Select a layout item first." and editor.status.rgba == 0xE57373FF)
-- The reason stays in the status line until the next action replaces or clears it
h:Tick(260)
assert(editor.status.content == "Select a layout item first.")
Harness.Find(editor.content, "Copy").hooks.pressed()
assert(editor.status.content == "Select a layout item first.")

-- New label is a plain button: with nothing selected it asks for text and adds the label after the layout
assert(editor.newLabelButton.root.hooks.click == nil and editor.labelDragSurface == nil)
editor.newLabelButton.root.hooks.pressed()
local prompt = app.windows.textPrompt
assert(prompt ~= nil and editor.overlayWindows[#editor.overlayWindows] == prompt.window)
prompt.field:SetText("Weapons")
Harness.Click(prompt.window.content, "Add")
local rows = app.store.data.tags.melee.rows
assert(rows[#rows].kind == "label" and rows[#rows].text == "Weapons")

-- An idle search stays empty; a failed search without RuneQL explains its limits
editor.itemSearch.root.hooks.contentchanged(nil, "change", "")
assert(editor.searchHint.hidden and editor.searchHint.content == "")
editor.itemSearch.root.hooks.contentchanged(nil, "change", "no matching item")
assert(string.find(editor.searchHint.content, "Without RuneQL", 1, true) ~= nil)
editor.itemSearch.root.hooks.contentchanged(nil, "change", "shark")
assert(#editor.searchResults == 1 and editor.searchResults[1].objectId == 385)

-- A saved action clears the status line
assert(editor.status.content == "")

-- Choosing another tag opens it, with no icon and a clear status line
editor:ShowError("An old reason")
choose("Food")
assert(chosen() == "food" and editor.tagTabs.rows[2].icon == nil and editor.status.content == "")
assert(editor.selectedTag == "food" and #editor.panes.sorted.slots == 0 and #editor.panes.unsorted.slots == 0)
-- Choosing the open tag again changes nothing
editor.history = { tag = "food", states = {}, index = 1 }
choose("Food")
assert(editor.selectedTag == "food" and editor.history ~= nil)
editor.history = nil
-- Renaming from the Tags tab opens tag settings in front of the editor
app.windows:OpenTagSettings("food", false)
local tagSettings = app.windows.tagSettingsEditor
assert(tagSettings ~= nil and tagSettings.field.text == "food")
assert(editor.overlayWindows[1] == tagSettings.window)
-- Renaming keeps the tag open and renames it in the rail
tagSettings.field:SetText("snacks")
tagSettings.saveButton.root.hooks.click()
assert(editor.selectedTag == "snacks" and chosen() == "snacks" and railLabels() == "Melee,Snacks")
assert(app.store:RenameFolder(app.store:GetTagFolder("melee"), "Gear") and app:Changed() == nil)
assert(railLabels() == "Melee,Snacks" and editor.selectedTag == "snacks" and chosen() == "snacks")
-- Deleting the open tag opens the first one and drops it from the rail
assert(app.store:CreateTag("spare"))
app:Changed()
choose("Spare")
assert(editor.selectedTag == "spare" and railLabels() == "Melee,Snacks,Spare")
assert(app.store:DeleteTag("spare"))
app:Changed()
assert(editor.selectedTag == "melee" and chosen() == "melee" and railLabels() == "Melee,Snacks")
-- Every tag of many stays reachable, each by its own entry
for index = 1, 30 do assert(app.store:CreateTag("extra " .. index)) end
app:Changed()
assert(#rail.entries == 32 and chosen() == "melee")
choose("Extra 30")
assert(editor.selectedTag == "extra 30" and chosen() == "extra 30")
for index = 1, 30 do assert(app.store:DeleteTag("extra " .. index)) end
app:Changed()
assert(railLabels() == "Melee,Snacks" and editor.selectedTag == "melee" and chosen() == "melee")
choose("Snacks")

-- Moving the bank, with no item change, moves the open editor within a few ticks
local window = host.window
local items = app.bankItems
window.host:SetPos(window.host.x + 30, 80)
h:Tick(12)
assert(app.bankItems == items, "the bank's items did not change")
assert(app.windows:BankBounds().y == 80 and editor.window.root.y == 80)
assert(app.windows.layoutEditor == editor)
-- Resizing the item area reopens the editor at the new columns, once Core rewraps and the editor checks
host.itemLayer.width = 448
h:Tick(22)
assert(app.windows:BankBounds().columns == 10)
local reopened = app.windows.layoutEditor
assert(reopened ~= nil and reopened ~= editor and reopened.selectedTag == "snacks")
assert(editorSize.CENTER_COLUMNS == 10)

-- Closing the bank closes the editor and its tag settings; Import/Share stays open
-- The host removes the inventory while the window is still mounted
app.windows:OpenImportShare()
local importShare = app.windows.importShare
app.windows:OpenTagSettings("melee", false)
assert(app.windows.tagSettingsEditor ~= nil)
h:CloseBank()
assert(app.windows.layoutEditor == nil and app.windows.tagSettingsEditor == nil)
assert(app.windows.importShare == importShare)

-- Leaving the game closes the editor too
session, layout = h:OpenBank()
h:Tick(12)
app.windows:OpenLayoutEditor("melee")
assert(app.windows.layoutEditor ~= nil)
h:Fire("GameStateChanged", { newState = 20 })
h:Tick()
assert(app.windows.layoutEditor == nil and app.windows.importShare == importShare)
host:UnmountBankWindow()
h:Fire("GameStateChanged", { newState = 30 })

-- Tag settings pick a sprite from the bank without RuneQL
session, layout = h:OpenBank()
h:Tick(12)
app.windows:OpenTagSettings("melee", false)
local settings = app.windows.tagSettingsEditor
settings.spriteSlot.root.hooks.click()
local picker = app.windows.spritePicker
assert(picker ~= nil and string.find(picker.status.content, "Without RuneQL", 1, true) ~= nil)
picker:RunSearch("shark")
assert(string.find(picker.status.content, "Without RuneQL", 1, true) ~= nil and picker.grid.objects[1] ~= nil)
picker.onSelect({ objectId = 385 })
assert(settings.spriteObjectID == 385)
settings.saveButton.root.hooks.click()
assert(app.store:GetTagSprite("melee") == 385)

-- Deleting a tag asks first, and leaves its page when it is shown
assert(app:ShowTag("snacks"))
h:Tick(2)
app.windows:OpenTagDeleteConfirm("snacks")
Harness.Click(app.windows.tagDeleteConfirm.window.content, "Delete")
h:Tick(2)
assert(app.store.data.tags.snacks == nil and app:ShownTag() == nil and layout.shownPage == nil)

-- The footer Close button closes the editor, as does Bank Core unloading
assert(app:ShowTag("melee"))
h:Tick(2)
app.windows:OpenLayoutEditor("melee")
editor = app.windows.layoutEditor
editor.closeButton.root.hooks.pressed()
assert(app.windows.layoutEditor == nil and editor.window == nil)
assert(editor.panes == nil and editor.onClose == nil and editor.tagTabs.root == nil)
app.windows:OpenLayoutEditor("melee")
assert(app.windows.layoutEditor ~= nil)
h.host:Unload("bankcore")
assert(app.windows.layoutEditor == nil and app.windows.importShare == importShare)
for name in pairs(host.callbacks) do
    assert(not string.find(name, "banktags_layout_editor", 1, true), "the editor left " .. name)
end

print("layout_editor_test: ok")
