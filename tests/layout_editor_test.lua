package.path = "./?.lua;./?/init.lua;" .. package.path

-- Drive the layout editor over a bank Bank Core reports: it opens at Bank Core's bounds and
-- lays rows out at Bank Core's columns, so a move it saves lands where the page draws it.
-- Its buttons copy, unsort, and remove the selected item, labels go through the prompt,
-- quantities come from Bank Core's snapshots, and it follows the bank's moves and resizes
-- and closes with the bank and with Bank Core
-- FAKE HOST: stand-in loader, components, and menus, not the game client

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
assert(app.state.columns == 13 and app.state.bounds ~= nil)

local ItemIdentity = require("banktags/tags/item_identity")
local key = ItemIdentity.LayoutKey
assert(app.store:CreateTag("melee"))
assert(app.store:CreateTag("food"))
app.store:SetLayoutPlacement(false)
assert(app.store:AddTag("melee", 4151, key(4151, 1)))
app.store:SetLayoutPlacement(true)
assert(app.store:AddTag("melee", 385, key(385, 1)))
assert(app.store:AddTag("melee", 1944, key(1944, 1)))
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
assert(editor.window.root.x == app.state.bounds.x and editor.window.root.y == app.state.bounds.y)
-- Its tag column is the shared list, with the editor's own footer
assert(editor.tagList:RowFor("melee") ~= nil and editor.tagList:RowFor("food") ~= nil)
assert(Harness.Find(editor.tagColumn, "New Tag") ~= nil)

-- Quantities come from Bank Core's snapshot; a placeholder is drawn faded
local function spriteFor(objectID)
    for _, node in ipairs(editor.centerNodes) do
        if node.associatedObjectID == objectID then return node end
    end
    return nil
end
assert(spriteFor(385).associatedObjectQuantity == 20 and spriteFor(385).alpha == 1)
assert(spriteFor(1944).alpha < 1)

-- The editor's pointer maps through its content's place on the screen
editor.window.tooltipContext = { position = function()
    return Geometry.absolutePosition(editor.content)
end }
-- Point at the centre of a grid slot, counted from zero
local function pointAtSlot(column, row)
    local left, top = Geometry.absolutePosition(editor.content)
    local x = left + editorSize.CENTER_X + editorSize.CENTER_VIEW_X + editorSize.GRID_LEFT + column * 44 + 20
    local y = top + editorSize.PANEL_TOP + editorSize.CENTER_VIEW_Y + 4 + row * 44 + 20
    host.mouse = { x = x, y = y }
    return x - left - editorSize.CENTER_X - editorSize.CENTER_VIEW_X,
        y - top - editorSize.PANEL_TOP - editorSize.CENTER_VIEW_Y
end
-- Press on a slot and release over another, as dragging an item does
local function drag(fromColumn, fromRow, toColumn, toRow)
    local surface = editor.centerDragSurface
    surface.hooks.click(nil, pointAtSlot(fromColumn, fromRow))
    pointAtSlot(toColumn, toRow)
    surface.hooks.release()
end

-- Unsorted items sit below their own heading; drag the shark into column 12 of row 1,
-- which exists only because Bank Core reports 13 columns
local slots = editor.centerSlots
assert(slots[1].layoutKey == key(4151, 1) and editor.centerUnsortedRow == 1)
drag(0, 2, 11, 0)
local row = app.store.data.tags.melee.rows[1].slots
assert(#row == 12 and row[12].layoutKey == key(385, 1), "the shark landed at row 1, column 12")
h:Tick(4)
-- Bank Core draws the page at the same columns, so the shark is on the whip's line
local whipY, sharkX, sharkY = nil, nil, nil
for _, entry in ipairs(layout:VisibleMirrorEntries()) do
    if entry.objectID == 4151 then whipY = entry.y end
    if entry.objectID == 385 then sharkX, sharkY = entry.x, entry.y end
end
assert(whipY ~= nil and sharkY == whipY and sharkX == 8 + 11 * 44, tostring(sharkX))

-- Select the whip by clicking it, then copy it: the ghost opens copy 1
drag(0, 0, 0, 0)
assert(editor.selectedLayoutKey == key(4151, 1))
Harness.Find(editor.centerPanel, "Create Copy").hooks.pressed()
assert(editor.selectedLayoutKey == key(4151, 2))
local ghost = nil
for _, slot in ipairs(app.store.data.tags.melee.rows[1].slots) do
    if slot.layoutKey == key(4151, 2) then ghost = slot end
end
assert(ghost ~= nil and ghost.sourceLayoutKey == key(4151, 1))
-- Move to Unsorted sends the selected copy below the heading, keeping it in the tag
Harness.Find(editor.centerPanel, "Move to Unsorted").hooks.pressed()
local unsorted = app.store.data.tags.melee.unsorted
assert(unsorted[#unsorted].layoutKey == key(4151, 2) and app.store:HasTag("melee", key(4151, 2)))
-- Remove takes the selected copy out of the tag
drag(0, 0, 0, 0)
Harness.Find(editor.centerPanel, "Remove").hooks.pressed()
assert(not app.store:HasTag("melee", key(4151, 1)) and app.store:HasTag("melee", key(4151, 2)))
-- With nothing selected the buttons explain instead of acting
editor.selectedLayoutKey = nil
Harness.Find(editor.centerPanel, "Remove").hooks.pressed()
assert(editor.errorBanner ~= nil)
h:Tick(260)
assert(editor.errorBanner == nil, "the error fades on the editor's own logic subscription")

-- Clicking New label asks for its text and adds the label after the layout
local labelSurface = editor.labelDragSurface
local labelLeft, labelTop = Geometry.absolutePosition(editor.content)
host.mouse = { x = labelLeft + editorSize.CENTER_X + editorSize.LABEL_BUTTON_X + 10,
    y = labelTop + editorSize.PANEL_TOP + editorSize.FOOTER_Y + 10 }
labelSurface.hooks.click(nil, 10, 10)
labelSurface.hooks.release()
local prompt = app.windows.textPrompt
assert(prompt ~= nil and editor.overlayWindow == prompt.window)
prompt.field:SetText("Weapons")
prompt.buttons[#prompt.buttons].root.hooks.click()
local rows = app.store.data.tags.melee.rows
assert(rows[#rows].kind == "label" and rows[#rows].text == "Weapons")

-- Searching without RuneQL finds the bank's items by name and says it is limited
editor.itemSearch.root.hooks.contentchanged(nil, "change", "")
assert(string.find(editor.searchHint.content, "Without RuneQL", 1, true) ~= nil)
editor.itemSearch.root.hooks.contentchanged(nil, "change", "shark")
assert(#editor.searchResults == 1 and editor.searchResults[1].objectId == 385)

-- Choosing another tag in the editor's list opens that tag
editor.tagList.list:Click("food")
assert(editor.selectedTag == "food" and #editor.centerSlots == 0)

-- Moving the bank moves the editor once Bank Core reports the new bounds
local window = host.window
window.host:SetPos(window.host.x + 30, 80)
h:Tick(12)
assert(app.state.bounds.y == 80 and editor.window.root.y == 80)
assert(app.windows.layoutEditor == editor)
-- Resizing the bank's item area reopens the editor at the new columns on the same tag
host.itemLayer.width = 448
h:Tick(12)
assert(app.state.columns == 10)
local reopened = app.windows.layoutEditor
assert(reopened ~= nil and reopened ~= editor and reopened.selectedTag == "food")
assert(editorSize.CENTER_COLUMNS == 10)

-- Closing the bank closes the editor; Import/Share stays open
app.windows:OpenImportShare()
local importShare = app.windows.importShare
layout:Restore()
host:UnmountBankWindow()
h:Tick(2)
assert(app.windows.layoutEditor == nil and app.windows.importShare == importShare)

-- Tag settings choose a sprite through the picker, which searches the bank without RuneQL
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
assert(app:ShowTag("food"))
h:Tick(2)
app.windows:OpenTagDeleteConfirm("food")
app.windows.tagDeleteConfirm.deleteButton.root.hooks.click()
h:Tick(2)
assert(app.store.data.tags.food == nil and app.shownTag == nil and layout.selectedTag == nil)

-- The editor's close button closes it, and Bank Core going closes it too
assert(app:ShowTag("melee"))
h:Tick(2)
app.windows:OpenLayoutEditor("melee")
editor = app.windows.layoutEditor
editor.columnButtons[3].root.hooks.pressed()
assert(app.windows.layoutEditor == nil and editor.window == nil)
app.windows:OpenLayoutEditor("melee")
assert(app.windows.layoutEditor ~= nil)
h.host:Unload("bankcore")
assert(app.windows.layoutEditor == nil and app.windows.importShare == importShare)
for name in pairs(host.callbacks) do
    assert(not string.find(name, "banktags_layout_editor", 1, true), "the editor left " .. name)
end

print("layout_editor_test: ok")
