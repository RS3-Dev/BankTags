package.path = "./?.lua;./?/init.lua;" .. package.path

-- Press Delete and Ctrl+C in the layout editor over a bank Bank Core reports
-- FAKE HOST: stand-in key events, menus, and focus, not the game client

local Harness = require("tools/test_support/tags_harness")
local Geometry = require("banktags/ui/geometry")
local h = Harness.new("layout_editor_keys")
local host = h.bankHost
host:SetItems({ { 4151, 1, "Abyssal whip" }, { 385, 20, "Shark" }, { 1944, 0, "Egg" } })
host.itemLayer.interfaceID = 517
h:LoadCore()
h:LoadTags()
local app = h:App()
h:OpenBank()
h:Tick(12)

local ItemIdentity = require("banktags/tags/item_identity")
local key = ItemIdentity.LayoutKey
local WHIP, SHARK = key(4151, 1), key(385, 1)
assert(app.store:CreateTag("melee"))
assert(app.store:CreateTag("food"))
assert(app.store:AddTag("melee", 4151, WHIP))
assert(app.store:AddTag("melee", 385, SHARK))
app:Changed()
h:Tick(2)
app.windows:OpenLayoutEditor("melee")
local editor = app.windows.layoutEditor
local editorSize = h:TagsModule("banktags/windows/layout_editor_parts").size
local changes = 0
local onChanged = editor.onChanged
editor.onChanged = function()
    changes = changes + 1
    onChanged()
end

-- Find the editor's listener for a key or focus event
local function listener(event)
    for name, action in pairs(h.keySubscriptions[event]) do
        if string.find(name, "layout_editor_keys", 1, true) then return action end
    end
    return nil
end
local DELETE, BACKSPACE, C, CONTROL = 101, 85, 67, 82
local NONE, SHIFT_HELD, CONTROL_HELD = 0, 1, 2
-- Send a key press, optionally as the OS's held-key repeat
local function press(gameKey, modifiers, isRepeat)
    listener("KeyDown")({ gameKey = gameKey, modifiers = modifiers, isRepeat = isRepeat == true })
end
local function release(gameKey)
    listener("KeyUp")({ gameKey = gameKey, modifiers = NONE })
end
-- Tap a key, pressing and releasing it
local function tap(gameKey, modifiers)
    press(gameKey, modifiers)
    release(gameKey)
end
-- Tap Ctrl+C as a user does, holding Ctrl around C
local function copyKeys()
    press(CONTROL, CONTROL_HELD)
    tap(C, CONTROL_HELD)
    release(CONTROL)
end

-- Press and release on a pane's grid slot, which selects its item
-- The tag starts with its items in Unsorted
editor.window.tooltipContext = { position = function()
    return Geometry.absolutePosition(editor.content)
end }
local function clickSlot(paneName, column, row)
    local left, top = Geometry.absolutePosition(editor.content)
    local pane = editor.panes[paneName]
    local x, y = editorSize.GRID_LEFT + column * 44 + 20, 4 + row * 44 + 20
    host.mouse = { x = left + pane.x + x, y = top + pane.y + y }
    pane.surface.hooks.click(nil, x, y)
    pane.surface.hooks.release()
end
-- Count the tag's whip copies
local function whipCopies()
    local count = 0
    for copy = 1, 9 do
        if app.store:HasTag("melee", key(4151, copy)) then count = count + 1 end
    end
    return count
end
local function selectWhip()
    clickSlot("unsorted", 0, 0)
    assert(editor.selectedLayoutKey == WHIP)
end
-- Count the gold outlines drawn on either grid
local function outlines()
    local count = 0
    for _, node in ipairs(editor.centerNodes) do
        if node.fill == false then count = count + 1 end
    end
    return count
end

-- The editor listens only while it is open
assert(listener("KeyDown") ~= nil and listener("KeyUp") ~= nil and listener("WindowFocusChanged") ~= nil)
-- The buttons name their keys
assert(editor.duplicateButton.tooltipText == "Copy the selected item (Ctrl+C)")
assert(editor.removeButton.tooltipText == "Remove the selected item (Delete)")

-- Before any press on the grid, keys do nothing
editor.selectedLayoutKey = WHIP
copyKeys()
tap(DELETE, NONE)
assert(whipCopies() == 1 and app.store:HasTag("melee", WHIP) and changes == 0)

-- Ctrl+C adds one copy through Create Copy and selects it
selectWhip()
copyKeys()
assert(whipCopies() == 2 and editor.selectedLayoutKey == key(4151, 2) and changes == 1)
local copy = nil
local melee = app.store.data.tags.melee
for _, entries in ipairs({ melee.rows[1].slots, melee.unsorted }) do
    for _, entry in ipairs(entries) do
        if entry.layoutKey == key(4151, 2) then copy = entry end
    end
end
assert(copy ~= nil and copy.sourceLayoutKey == WHIP, "the copy is a ghost of the whip")
-- The copy of an Unsorted item lands in the sorted grid, outlined alone
assert(editor.panes.sorted.slots[1].layoutKey == key(4151, 2) and outlines() == 1)
-- Ctrl+C and Delete act on a sorted selection too
clickSlot("sorted", 0, 0)
copyKeys()
assert(whipCopies() == 3 and editor.selectedLayoutKey == key(4151, 3) and outlines() == 1)
tap(DELETE, NONE)
assert(whipCopies() == 2 and not app.store:HasTag("melee", key(4151, 3)) and changes == 3)
-- Clicking an empty cell clears the selection
clickSlot("sorted", 0, 0)
clickSlot("unsorted", 3, 3)
assert(editor.selectedLayoutKey == nil and outlines() == 0)
clickSlot("sorted", 0, 0)
assert(editor.selectedLayoutKey == key(4151, 2))
changes = 1

-- Holding C copies once, through OS repeats and a second press report
press(CONTROL, CONTROL_HELD)
press(C, CONTROL_HELD)
press(C, CONTROL_HELD, true)
press(C, CONTROL_HELD, true)
press(C, CONTROL_HELD)
assert(whipCopies() == 3 and changes == 2, "a held C made one copy")
-- Releasing C and pressing it again copies again
release(C)
press(C, CONTROL_HELD)
release(C)
release(CONTROL)
assert(whipCopies() == 4 and editor.selectedLayoutKey == key(4151, 4) and changes == 3)

-- C alone, Shift+C, and Ctrl+Shift+C do not copy
tap(C, NONE)
tap(C, SHIFT_HELD)
tap(C, CONTROL_HELD + SHIFT_HELD)
assert(whipCopies() == 4)

-- Backspace and modified Delete do not remove
tap(BACKSPACE, NONE)
tap(DELETE, SHIFT_HELD)
tap(DELETE, CONTROL_HELD)
assert(whipCopies() == 4 and editor.selectedLayoutKey == key(4151, 4))

-- Delete removes only the selected copy through Remove
tap(DELETE, NONE)
assert(not app.store:HasTag("melee", key(4151, 4)) and whipCopies() == 3)
assert(app.store:HasTag("melee", WHIP) and app.store:HasTag("melee", SHARK))
assert(editor.selectedLayoutKey == nil and changes == 4)
-- With nothing selected, keys do nothing and show no error
tap(DELETE, NONE)
copyKeys()
assert(whipCopies() == 3 and changes == 4 and editor.errorBanner == nil)

-- Holding Delete removes one item, then works again after release
editor.selectedLayoutKey = key(4151, 2)
press(DELETE, NONE)
assert(not app.store:HasTag("melee", key(4151, 2)) and whipCopies() == 2)
editor.selectedLayoutKey = key(4151, 3)
press(DELETE, NONE, true)
press(DELETE, NONE)
assert(app.store:HasTag("melee", key(4151, 3)))
release(DELETE)
tap(DELETE, NONE)
assert(not app.store:HasTag("melee", key(4151, 3)) and whipCopies() == 1)
selectWhip()
local before = whipCopies()

-- Showing Search drops a selection in the hidden Unsorted grid and disarms the keys
selectWhip()
editor.tabs:GetTab(2).hit.hooks.click()
assert(editor.selectedLayoutKey == nil and outlines() == 0 and not editor.keysOnGrid)
-- Clicking the search field gives it the keys, so Ctrl+C stays text copy
clickSlot("sorted", 0, 0)
assert(editor.keysOnGrid)
editor.selectedLayoutKey = WHIP
editor.itemSearch.root.hooks.click(nil, 4, 4)
copyKeys()
tap(DELETE, NONE)
assert(whipCopies() == before and app.store:HasTag("melee", WHIP))
editor.tabs:GetTab(1).hit.hooks.click()
selectWhip()
-- An open menu, or one opened since the grid press, blocks the keys
selectWhip()
h.input.menuOpen = true
tap(DELETE, NONE)
h.input.menuOpen = false
assert(app.store:HasTag("melee", WHIP))
for name, opened in pairs(h.openSubscriptions) do
    if string.find(name, "layout_editor_keys", 1, true) then opened({}) end
end
tap(DELETE, NONE)
assert(app.store:HasTag("melee", WHIP))

-- A keybind field listening for keys blocks them
selectWhip()
h.input.capturing = true
tap(DELETE, NONE)
h.input.capturing = false
assert(app.store:HasTag("melee", WHIP))

-- The label prompt over the editor blocks them
selectWhip()
assert(editor:PromptNewLabel(0) and #editor.overlayWindows == 1)
tap(DELETE, NONE)
copyKeys()
assert(app.store:HasTag("melee", WHIP) and whipCopies() == before)
app.windows:Close("textPrompt")
assert(#editor.overlayWindows == 0)

-- Tag settings, with a field of its own, opens in front of the editor
selectWhip()
app.windows:OpenTagSettings("melee", false)
assert(app.windows.tagSettingsEditor ~= nil and editor.overlayWindows[1] == app.windows.tagSettingsEditor.window)
selectWhip()
tap(DELETE, NONE)
assert(app.store:HasTag("melee", WHIP), "tag settings over the editor blocks them")
-- Its sprite picker joins it in front of the editor
app.windows.tagSettingsEditor.spriteSlot.root.hooks.click()
assert(editor.overlayWindows[2] == app.windows.spritePicker.window)
app.windows:Close("tagSettingsEditor")
assert(#editor.overlayWindows == 0 and app.windows.spritePicker == nil)

-- The game losing focus clears held keys and blocks them
selectWhip()
copyKeys()
press(DELETE, NONE)
assert(whipCopies() == before)
listener("WindowFocusChanged")({ hasFocus = false })
listener("WindowFocusChanged")({ hasFocus = true })
assert(next(editor.heldKeys) == nil)
editor.selectedLayoutKey = WHIP
tap(DELETE, NONE)
assert(app.store:HasTag("melee", WHIP), "the grid needs a press after focus returns")
-- After a grid press, repeats of a key held through the change do nothing
selectWhip()
copyKeys()
press(DELETE, NONE, true)
assert(whipCopies() == before + 1)
-- A new press works without the missed release
press(DELETE, NONE)
release(DELETE)
assert(whipCopies() == before and app.store:HasTag("melee", WHIP))

-- A drag in progress blocks them
selectWhip()
local surface = editor.panes.unsorted.surface
surface.hooks.click(nil, editorSize.GRID_LEFT + 20, 4 + 20)
assert(editor.drag ~= nil)
tap(DELETE, NONE)
assert(app.store:HasTag("melee", WHIP))
surface.hooks.release()

-- A hidden editor ignores them
selectWhip()
editor.window.root.hidden = true
tap(DELETE, NONE)
editor.window.root.hidden = false
assert(app.store:HasTag("melee", WHIP))

-- An item removed elsewhere is not removed or copied
selectWhip()
copyKeys()
local stale = editor.selectedLayoutKey
assert(app.store:RemoveTag("melee", stale))
app:Changed()
assert(editor.selectedLayoutKey == stale)
local changesBefore = changes
tap(DELETE, NONE)
copyKeys()
assert(changes == changesBefore and editor.errorBanner == nil and whipCopies() == before)

-- Choosing another tag clears the selection, so keys do nothing
selectWhip()
for _, button in ipairs(editor.tagRail.buttons) do
    if button.tagID == "food" then button.root.hooks.pressed() end
end
assert(editor.selectedTag == "food" and editor.selectedLayoutKey == nil)
tap(DELETE, NONE)
assert(app.store:HasTag("melee", WHIP))
-- Deleting the open tag moves to another and drops the selection
editor:SelectTag("melee")
selectWhip()
assert(app.store:DeleteTag("melee"))
app:Changed()
assert(editor.selectedTag ~= "melee" and editor.selectedLayoutKey == nil)
tap(DELETE, NONE)
copyKeys()
assert(editor.errorBanner == nil)

-- Reopening keeps one listener; closing and unloading remove it
app.windows:OpenLayoutEditor("food")
assert(app.windows.layoutEditor ~= editor and listener("KeyDown") ~= nil)
assert(editor.window == nil)
-- The title bar's close button closes it
app.windows.layoutEditor.window:Close()
assert(app.windows.layoutEditor == nil)
for _, event in ipairs({ "KeyDown", "KeyUp", "WindowFocusChanged" }) do
    assert(listener(event) == nil, "closing left " .. event)
end
for name in pairs(h.openSubscriptions) do
    assert(not string.find(name, "layout_editor_keys", 1, true), "closing left MiniMenuOpened")
end
app.windows:OpenLayoutEditor("food")
assert(listener("KeyDown") ~= nil)
h.host:Unload("bankcore")
assert(app.windows.layoutEditor == nil and listener("KeyDown") == nil)

print("layout_editor_keys_test: ok")
