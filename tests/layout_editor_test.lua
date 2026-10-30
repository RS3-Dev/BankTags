package.path = "./?.lua;./?/init.lua;" .. package.path

-- Drive the layout editor over a bank Bank Core reports
-- Moves it saves show up where the page draws them
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
-- A tag rail replaces the tag column: an icon button per tag in sidebar order, named with its folder
local rail = editor.tagRail
-- Find the rail button for a tag
local function railButton(tag)
    for _, button in ipairs(rail.buttons) do
        if button.tagID == tag then return button end
    end
    return nil
end
-- List the rail's tags, then whether only the open one is gold
local function railTags()
    local tags = {}
    for _, button in ipairs(rail.buttons) do tags[#tags + 1] = button.tagID end
    return table.concat(tags, ",")
end
local function railOpen(tag)
    for _, button in ipairs(rail.buttons) do
        if button.active ~= (button.tagID == tag) then return false end
    end
    return true
end
assert(railTags() == "melee,food" and railOpen("melee"))
assert(rail.entries[1].label == "Combat / Melee" and railButton("melee").tooltipText == "Combat / Melee")
assert(rail.entries[2].label == "Food" and railButton("food").tooltipText == "Food")
-- The stored icon draws over its button; a tag without one shows its first letters
local melee = railButton("melee")
assert(melee.root.text.content == "" and Harness.Find(rail.root, "Fo") == railButton("food").root)
local railIcon = nil
for _, node in ipairs(rail.root.children) do
    if node.associatedObjectID == 4151 and not node.destroyed then railIcon = node end
end
assert(railIcon ~= nil and railIcon.clickthrough and railIcon.y > melee.y and railIcon.y < melee.y + melee.height)
-- The open tag is named beside the Layout tab; no Rename or Exit edit mode
assert(editor.tagName.content == "Combat / Melee" and Harness.Find(editor.content, "Rename") == nil and railOpen("melee"))
assert(editor.layoutTabs:GetTab(1).text == "Layout" and editor.tagName.parent == editor.centerPanel)
assert(Harness.Find(editor.content, "Exit edit mode") == nil and editor.exitButton == nil)
-- New Tag and Import/Share stay in the Tags tab, and the window's own close button closes it
assert(Harness.Find(editor.content, "New Tag") == nil)
-- The sorted grid sits beside the rail, level with Unsorted, over the item actions
assert(editor.centerPanel.x == editorSize.CENTER_X and rail.root.x + rail.root.width < editorSize.CENTER_X)
assert(editor.panes.sorted.y > editor.tagName.y + editor.tagName.height)
assert(Harness.Find(editor.content, "Saved automatically") == nil)

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
-- Point at the centre of a pane's grid slot, counted from zero
local function pointAtSlot(paneName, column, row)
    local left, top = Geometry.absolutePosition(editor.content)
    local pane = editor.panes[paneName]
    local x, y = editorSize.GRID_LEFT + column * 44 + 20, 4 + row * 44 + 20 - pane.view.scrollY
    host.mouse = { x = left + pane.x + x, y = top + pane.y + y }
    return x, y
end
-- Press on a slot and release over another, as dragging an item does
local function drag(fromPane, fromColumn, fromRow, toPane, toColumn, toRow)
    local surface = editor.panes[fromPane].surface
    surface.hooks.click(nil, pointAtSlot(fromPane, fromColumn, fromRow))
    pointAtSlot(toPane, toColumn, toRow)
    surface.hooks.release()
end

-- Sorted rows fill the center and Unsorted is the right column's first tab; the shark leads it
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
-- With nothing selected the buttons explain instead of acting
editor.selectedLayoutKey = nil
Harness.Find(editor.content, "Remove").hooks.pressed()
assert(editor.errorBanner ~= nil)
h:Tick(260)
assert(editor.errorBanner == nil, "the error fades on the editor's own logic subscription")

-- New label asks for text and adds the label after the layout
local labelSurface = editor.labelDragSurface
local labelLeft, labelTop = Geometry.absolutePosition(editor.content)
host.mouse = { x = labelLeft + editorSize.LABEL_BUTTON_X + 10,
    y = labelTop + editorSize.LABEL_BUTTON_Y + 10 }
labelSurface.hooks.click(nil, 10, 10)
labelSurface.hooks.release()
local prompt = app.windows.textPrompt
assert(prompt ~= nil and editor.overlayWindows[#editor.overlayWindows] == prompt.window)
prompt.field:SetText("Weapons")
prompt.buttons[#prompt.buttons].root.hooks.click()
local rows = app.store.data.tags.melee.rows
assert(rows[#rows].kind == "label" and rows[#rows].text == "Weapons")

-- Searching without RuneQL finds bank items and says it is limited
editor.tabs:GetTab(2).hit.hooks.click()
editor.itemSearch.root.hooks.contentchanged(nil, "change", "")
assert(string.find(editor.searchHint.content, "Without RuneQL", 1, true) ~= nil)
editor.itemSearch.root.hooks.contentchanged(nil, "change", "shark")
assert(#editor.searchResults == 1 and editor.searchResults[1].objectId == 385)

-- Pressing another tag in the rail opens that tag
railButton("food").root.hooks.pressed()
assert(railOpen("food") and editor.tagName.content == "Food")
assert(editor.selectedTag == "food" and #editor.panes.sorted.slots == 0 and #editor.panes.unsorted.slots == 0)
-- Renaming from the Tags tab opens tag settings in front of the editor
app.windows:OpenTagSettings("food", false)
local tagSettings = app.windows.tagSettingsEditor
assert(tagSettings ~= nil and tagSettings.field.text == "food")
assert(editor.overlayWindows[1] == tagSettings.window)
-- Renaming keeps the tag open and renames it in the rail
tagSettings.field:SetText("snacks")
tagSettings.saveButton.root.hooks.click()
assert(editor.selectedTag == "snacks" and railOpen("snacks") and editor.tagName.content == "Snacks")
assert(railTags() == "melee,snacks" and railButton("snacks").tooltipText == "Snacks")
assert(app.store:RenameFolder(app.store:GetTagFolder("melee"), "Gear") and app:Changed() == nil)
assert(railButton("melee").tooltipText == "Gear / Melee" and editor.selectedTag == "snacks")
-- Deleting the open tag opens the first one and drops it from the rail
assert(app.store:CreateTag("spare"))
app:Changed()
railButton("spare").root.hooks.pressed()
assert(editor.selectedTag == "spare" and railTags() == "melee,snacks,spare")
assert(app.store:DeleteTag("spare"))
app:Changed()
assert(editor.selectedTag == "melee" and railOpen("melee") and railTags() == "melee,snacks")
assert(editor.tagName.content == "Gear / Melee")
railButton("snacks").root.hooks.pressed()
-- More tags than fit page with arrows; every tag stays reachable and the open one in view
for index = 1, 30 do assert(app.store:CreateTag("extra " .. index)) end
app:Changed()
assert(rail.view.arrows and #rail.buttons < 32 and rail.upArrow.disabled and not rail.downArrow.disabled)
assert(railOpen("snacks") and railButton("snacks") ~= nil)
local seen = {}
repeat
    for _, button in ipairs(rail.buttons) do seen[button.tagID] = true end
    local paged = not rail.downArrow.disabled
    if paged then rail.downArrow.root.hooks.pressed() end
until not paged
for index = 1, 30 do assert(seen["extra " .. index], "extra " .. index .. " is reachable") end
assert(seen.melee and seen.snacks and editor.selectedTag == "snacks" and railButton("snacks") == nil)
railButton("extra 30").root.hooks.pressed()
assert(editor.selectedTag == "extra 30" and railOpen("extra 30"))
editor:SelectTag("melee")
assert(railButton("melee") ~= nil and rail.upArrow.disabled)
for index = 1, 30 do assert(app.store:DeleteTag("extra " .. index)) end
app:Changed()
assert(not rail.view.arrows and railTags() == "melee,snacks" and rail.upArrow == nil)
railButton("snacks").root.hooks.pressed()

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
app.windows.tagDeleteConfirm.confirmButton.root.hooks.click()
h:Tick(2)
assert(app.store.data.tags.snacks == nil and app:ShownTag() == nil and layout.shownPage == nil)

-- The footer Close button closes the editor, as does Bank Core unloading
assert(app:ShowTag("melee"))
h:Tick(2)
app.windows:OpenLayoutEditor("melee")
editor = app.windows.layoutEditor
editor.closeButton.root.hooks.pressed()
assert(app.windows.layoutEditor == nil and editor.window == nil)
assert(editor.panes == nil and editor.onClose == nil)
assert(editor.tabs == nil and editor.layoutTabs == nil and editor.tagName == nil)
app.windows:OpenLayoutEditor("melee")
assert(app.windows.layoutEditor ~= nil)
h.host:Unload("bankcore")
assert(app.windows.layoutEditor == nil and app.windows.importShare == importShare)
for name in pairs(host.callbacks) do
    assert(not string.find(name, "banktags_layout_editor", 1, true), "the editor left " .. name)
end

print("layout_editor_test: ok")
