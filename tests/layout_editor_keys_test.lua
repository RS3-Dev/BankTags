package.path = "./?.lua;./?/init.lua;" .. package.path

-- Press Delete, Ctrl+C, Ctrl+V, Ctrl+Z, Ctrl+Y, and the arrows in the layout editor over a bank Bank Core reports
-- Key events use the documented payload and modifier values captured from the live client
-- FAKE HOST: stand-in key events, keyboard, menus, and focus, not the game client

local Harness = require("tools/test_support/tags_harness")
local Geometry = require("banktags/ui/geometry")
local Json = require("banktags/core/json")
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
local store = app.store
assert(store:CreateTag("melee"))
assert(store:CreateTag("food"))
assert(store:AddTag("melee", 4151, WHIP))
assert(store:AddTag("melee", 385, SHARK))
app:Changed()
h:Tick(2)
local editorSize = h:TagsModule("banktags/windows/layout_editor_parts").size
local editor, changes
-- Open the editor on a tag, counting its change notices
local function openEditor(tag)
    app.windows:OpenLayoutEditor(tag or "melee")
    editor = app.windows.layoutEditor
    changes = 0
    local onChanged = editor.onChanged
    editor.onChanged = function()
        changes = changes + 1
        onChanged()
    end
    editor.window.tooltipContext = { position = function()
        return Geometry.absolutePosition(editor.content)
    end }
end
openEditor()

-- Find the editor's listener for a key or focus event
local function listener(event)
    for name, action in pairs(h.keySubscriptions[event]) do
        if string.find(name, "layout_editor_keys", 1, true) then return action end
    end
    return nil
end
-- GameKey, SystemKey, and ModifierKey values from the client docs
local GAME = { DELETE = 101, BACKSPACE = 85, C = 66, V = 67, Z = 64, Y = 37, A = 48, CONTROL = 82,
    LEFT = 96, RIGHT = 97, UP = 98, DOWN = 99 }
local SYSTEM = { [101] = 46, [85] = 8, [66] = 67, [67] = 86, [64] = 90, [37] = 89, [48] = 65, [82] = 17,
    [96] = 37, [97] = 39, [98] = 38, [99] = 40 }
local NONE, SHIFT, CONTROL, ALT = 0, 1, 4, 2
-- Send one KeyDown as the client does, optionally as the OS's held-key repeat
local function press(gameKey, modifiers, isRepeat)
    listener("KeyDown")({ isRepeat = isRepeat == true, gameKey = gameKey, systemKey = SYSTEM[gameKey],
        modifiers = modifiers, timestamp = 1000 })
end
-- Press a key with Ctrl held, as a user does: Ctrl first, then the key, both with Ctrl's bit
local function controlKey(gameKey)
    press(GAME.CONTROL, CONTROL)
    press(gameKey, CONTROL)
end
local function undo() controlKey(GAME.Z) end
local function redo() controlKey(GAME.Y) end

-- Point at a pane's grid cell through its scroll
local function pointAt(paneName, column, row)
    local left, top = Geometry.absolutePosition(editor.content)
    local pane = editor.panes[paneName]
    local x, y = editorSize.GRID_LEFT + column * 44 + 20, 4 + row * 44 + 20 - pane.view.scrollY
    host.mouse = { x = left + pane.x + x, y = top + pane.y + y }
    return x, y
end
-- Press and release on a pane's grid cell, which selects its item or the empty cell
local function clickSlot(paneName, column, row)
    local pane = editor.panes[paneName]
    pane.surface.hooks.click(nil, pointAt(paneName, column, row))
    pane.surface.hooks.release()
end
-- Count the tag's whip copies
local function whipCopies()
    local count = 0
    for copy = 1, 20 do
        if store:HasTag("melee", key(4151, copy)) then count = count + 1 end
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
-- Find a copy saved in the tag's rows or Unsorted
local function findSlot(layoutKey)
    local melee = store.data.tags.melee
    for _, entry in ipairs(melee.rows) do
        for index, slot in ipairs(entry.slots or {}) do
            if slot.layoutKey == layoutKey then return slot, index end
        end
    end
    for _, slot in ipairs(melee.unsorted) do
        if slot.layoutKey == layoutKey then return slot end
    end
    return nil
end
local function saved() return Json.encode(store.data) end

-- Shortcuts listen only while the editor is open
assert(listener("KeyDown") ~= nil and listener("WindowFocusChanged") ~= nil and listener("KeyUp") == nil)
-- The buttons name their keys
assert(editor.copyButton.tooltipText == "Copy the selected item or group (Ctrl+C)")
assert(editor.pasteButton.tooltipText == "Click an empty cell, then paste the copied items there (Ctrl+V)")
assert(editor.removeButton.tooltipText == "Remove the selected item (Delete). Ctrl+Z undoes and Ctrl+Y redoes;"
    .. " arrow keys move the selection when turned on in Bank settings")

-- Before any press on the grid, keys do nothing
editor.selectedLayoutKey = WHIP
controlKey(GAME.C)
press(GAME.DELETE, NONE)
assert(whipCopies() == 1 and store:HasTag("melee", WHIP) and changes == 0 and editor.clipboard == nil)

-- Ctrl+C copies the selection to the editor's clipboard, saving nothing and adding no undo step
selectWhip()
local before = saved()
controlKey(GAME.C)
assert(saved() == before and changes == 0 and editor.history == nil)
assert(#editor.clipboard.items == 1 and editor.clipboard.tag == "melee" and editor.errorBanner ~= nil)
editor:HideError()
-- Ctrl+V needs an empty cell picked first
controlKey(GAME.V)
assert(saved() == before and editor.errorBanner ~= nil)
editor:HideError()
-- Clicking an empty sorted cell outlines it as the paste cell and clears the item selection
clickSlot("sorted", 2, 1)
assert(editor.pasteCell == 13 and editor.selectedLayoutKey == nil and outlines() == 1)
-- Ctrl+V adds a new copy of the same bank stack there, selects it, and keeps the clipboard
controlKey(GAME.V)
local copy, position = findSlot(key(4151, 2))
assert(copy ~= nil and copy.sourceLayoutKey == WHIP and position == 3 and editor.panes.sorted.slots[13] ~= nil)
assert(editor.selectedLayoutKey == key(4151, 2) and editor.pasteCell == nil and changes == 1 and outlines() == 1)
assert(#editor.clipboard.items == 1)
-- The clipboard pastes again at another empty cell
clickSlot("sorted", 0, 0)
controlKey(GAME.V)
assert(whipCopies() == 3 and editor.panes.sorted.slots[1].layoutKey == key(4151, 3) and changes == 2)
-- Unsorted cells are never paste cells
clickSlot("unsorted", 3, 3)
assert(editor.pasteCell == nil and editor.selectedLayoutKey == nil and outlines() == 0)

-- A group copies with its offsets from its top-left item and pastes all or nothing
host.shiftDown = true
clickSlot("sorted", 0, 0)
clickSlot("sorted", 2, 1)
host.shiftDown = false
assert(editor:GroupCount() == 2)
controlKey(GAME.C)
assert(#editor.clipboard.items == 2 and changes == 2)
editor:HideError()
-- The shark sits where the second copy would land, so nothing is pasted
assert(store:MoveLayoutItem("melee", SHARK, 2 * 10 + 4, 10))
app:Changed()
clickSlot("sorted", 1, 1)
assert(editor.pasteCell == 12)
before = saved()
controlKey(GAME.V)
assert(saved() == before and editor.errorBanner ~= nil and changes == 2 and editor.pasteCell == 12)
editor:HideError()
-- Past the grid's right edge nothing is pasted either
clickSlot("sorted", 9, 3)
controlKey(GAME.V)
assert(saved() == before and editor.errorBanner ~= nil)
editor:HideError()
-- Into open cells the group lands with its shape and stays selected
clickSlot("sorted", 0, 3)
controlKey(GAME.V)
assert(editor.panes.sorted.slots[31].layoutKey == key(4151, 4))
assert(editor.panes.sorted.slots[43].layoutKey == key(4151, 5) and findSlot(key(4151, 5)).sourceLayoutKey == WHIP)
assert(editor:GroupCount() == 2 and editor.groupKeys[key(4151, 4)] and changes == 3)

-- Ctrl+Z and Ctrl+Y work with nothing selected, once per press
clickSlot("unsorted", 3, 3)
assert(editor.selectedLayoutKey == nil)
undo()
assert(whipCopies() == 3 and changes == 4)
redo()
assert(whipCopies() == 5 and changes == 5)
-- The OS's repeats of a held key do nothing; a new press acts without waiting for a release
press(GAME.Z, CONTROL, true)
press(GAME.Z, CONTROL, true)
assert(whipCopies() == 5)
press(GAME.Z, CONTROL)
assert(whipCopies() == 3 and changes == 6)
-- The shark's outside move ended the steps before it, so there is nothing older to undo
press(GAME.Z, CONTROL)
assert(whipCopies() == 3 and changes == 6)
-- Ctrl held on the keyboard counts even when the event leaves its bit out
host.controlDown = true
press(GAME.Y, NONE)
host.controlDown = false
assert(whipCopies() == 5 and changes == 7)
-- Bits beyond Shift, Ctrl, and Alt are ignored
press(GAME.Z, CONTROL | 16)
assert(whipCopies() == 3 and changes == 8)
press(GAME.Y, CONTROL | 16)
assert(whipCopies() == 5 and changes == 9)
-- Ctrl with Shift or Alt, AltGr (Ctrl and Alt), and plain Z do not undo
before = saved()
for _, modifiers in ipairs({ CONTROL | SHIFT, CONTROL | ALT, NONE, SHIFT }) do press(GAME.Z, modifiers) end
host.altDown = true
press(GAME.Z, CONTROL)
host.altDown = false
host.shiftDown = true
press(GAME.Z, CONTROL)
host.shiftDown = false
assert(saved() == before and changes == 9)

-- Delete removes the selected copy once; Backspace and modified Delete do not
clickSlot("sorted", 0, 0)
local selected = editor.selectedLayoutKey
assert(selected == key(4151, 3))
press(GAME.BACKSPACE, NONE)
press(GAME.DELETE, SHIFT)
press(GAME.DELETE, CONTROL)
assert(store:HasTag("melee", selected))
press(GAME.DELETE, NONE)
press(GAME.DELETE, NONE, true)
assert(not store:HasTag("melee", selected) and editor.selectedLayoutKey == nil and changes == 10)
-- With nothing selected, Delete and Ctrl+C do nothing and say nothing
press(GAME.DELETE, NONE)
controlKey(GAME.C)
assert(changes == 10 and editor.errorBanner == nil and #editor.clipboard.items == 2)
undo()
assert(store:HasTag("melee", selected) and changes == 11)

-- Arrow keys move the selection only once turned on in Bank settings
assert(app.settings.arrowKeyMovement == false)
clickSlot("sorted", 0, 0)
local history = editor.history
local historyIndex = history.index
before = saved()
for _, arrow in ipairs({ GAME.RIGHT, GAME.DOWN, GAME.LEFT, GAME.UP }) do press(arrow, NONE) end
assert(saved() == before and changes == 11 and editor.errorBanner == nil)
-- Turning it on applies at once and changes neither the layout nor the undo steps
assert(app:SetSetting("arrowKeyMovement", true))
assert(saved() == before and editor.history == history and history.index == historyIndex)
assert(#editor.clipboard.items == 2 and editor.selectedLayoutKey == key(4151, 3))
press(GAME.RIGHT, NONE)
assert(editor.panes.sorted.slots[2].layoutKey == key(4151, 3) and changes == 12)
-- Modified arrows still do nothing
before = saved()
for _, modifiers in ipairs({ SHIFT, CONTROL, ALT }) do press(GAME.LEFT, modifiers) end
assert(saved() == before)
-- Turning it off stops them again, still keeping the layout and its steps
historyIndex = editor.history.index
assert(app:SetSetting("arrowKeyMovement", false))
press(GAME.LEFT, NONE)
assert(saved() == before and editor.history.index == historyIndex and changes == 12)
undo()
assert(editor.panes.sorted.slots[1].layoutKey == key(4151, 3) and changes == 13)

-- An open menu blocks the keys; the grid's own row menu leaves them working
clickSlot("sorted", 0, 0)
h.input.menuOpen = true
before = saved()
redo()
h.input.menuOpen = false
assert(saved() == before)
pointAt("sorted", 4, 0)
Harness.Open(h:ContentMenu())
assert(editor.keysOnGrid)
redo()
assert(saved() ~= before and changes == 14)
-- Any other menu may lead to a text field, so it takes the keys until the grid is pressed
local left, top = Geometry.absolutePosition(editor.content)
host.mouse = { x = left + editorSize.RAIL_X + 10, y = top + editorSize.PANEL_TOP + 20 }
Harness.Open(h:ContentMenu())
assert(not editor.keysOnGrid)
before = saved()
undo()
assert(saved() == before)

-- The search field, the Search tab, a keybind field, windows over the editor, focus, drags, and a hidden editor block them
clickSlot("sorted", 0, 0)
editor.itemSearch.root.hooks.click(nil, 4, 4)
undo()
assert(saved() == before)
clickSlot("sorted", 0, 0)
editor.tabs:GetTab(2).hit.hooks.click()
undo()
assert(saved() == before and not editor.keysOnGrid)
editor.tabs:GetTab(1).hit.hooks.click()
clickSlot("sorted", 0, 0)
h.input.capturing = true
undo()
h.input.capturing = false
assert(saved() == before)
assert(editor:PromptNewLabel(0) and #editor.overlayWindows == 1)
undo()
controlKey(GAME.V)
assert(saved() == before)
app.windows:Close("textPrompt")
app.windows:OpenTagSettings("melee", false)
undo()
assert(saved() == before)
app.windows:Close("tagSettingsEditor")
listener("WindowFocusChanged")({ hasFocus = false })
listener("WindowFocusChanged")({ hasFocus = true })
undo()
assert(saved() == before, "the grid needs a press after focus returns")
selectWhip()
local surface = editor.panes.unsorted.surface
surface.hooks.click(nil, editorSize.GRID_LEFT + 20, 4 + 20)
assert(editor.drag ~= nil)
press(GAME.DELETE, NONE)
undo()
assert(saved() == before)
surface.hooks.release()
editor.window.root.hidden = true
undo()
editor.window.root.hidden = false
assert(saved() == before)
-- After all that a grid press arms them again
clickSlot("sorted", 9, 5)
undo()
assert(saved() ~= before)

-- An item removed elsewhere is not removed or copied
selectWhip()
local stale = editor.selectedLayoutKey
local clipboard = editor.clipboard
assert(store:RemoveTag("melee", stale))
app:Changed()
local changesBefore = changes
press(GAME.DELETE, NONE)
controlKey(GAME.C)
assert(changes == changesBefore and editor.errorBanner == nil and editor.clipboard == clipboard)

-- Debug logging names each chord and shortcut key, and what blocked it; plain typing is not logged
local logged = {}
h.host.globals.log = function(...) logged[#logged + 1] = table.concat({ ... }) end
press(GAME.A, NONE)
undo()
assert(#logged == 0, "nothing is logged while debug logging is off")
assert(app:SetSetting("enableDebug", true))
clickSlot("sorted", 9, 5)
press(GAME.A, NONE)
assert(#logged == 0, "plain typing is not logged")
undo()
assert(#logged == 2, #logged)
assert(string.find(logged[1], "CONTROL gameKey 82 systemKey 17 modifiers 4 held 4 shortcut nil", 1, true), logged[1])
assert(string.find(logged[2], "Z gameKey 64 systemKey 90 modifiers 4 held 4 shortcut undo blocked by nothing", 1,
    true), logged[2])
editor.itemSearch.root.hooks.click(nil, 4, 4)
press(GAME.V, CONTROL)
assert(string.find(logged[3], "shortcut paste blocked by no grid press", 1, true), logged[3])
assert(app:SetSetting("enableDebug", false))
h.host.globals.log = function() end

-- Renaming the open tag keeps the clipboard; choosing another tag clears it and the selection
assert(store:UpdateTag("melee", "melee2"))
app:Renamed("melee", "melee2")
assert(editor.clipboard.tag == "melee2")
assert(store:UpdateTag("melee2", "melee"))
app:Renamed("melee2", "melee")
for _, button in ipairs(editor.tagRail.buttons) do
    if button.tagID == "food" then button.root.hooks.pressed() end
end
assert(editor.selectedTag == "food" and editor.selectedLayoutKey == nil and editor.clipboard == nil)
editor:SelectTag("melee")
clickSlot("sorted", 0, 0)
assert(editor.selectedLayoutKey ~= nil)
controlKey(GAME.C)
assert(editor.clipboard ~= nil)
-- Deleting the open tag moves to another and drops the selection and clipboard
assert(store:DeleteTag("melee"))
app:Changed()
assert(editor.selectedTag ~= "melee" and editor.selectedLayoutKey == nil and editor.clipboard == nil)
press(GAME.DELETE, NONE)
controlKey(GAME.V)
editor:HideError()

-- Reopening keeps one listener; closing and unloading remove it
openEditor("food")
local first = editor
assert(listener("KeyDown") ~= nil and first.clipboard == nil)
openEditor("food")
assert(first.window == nil and listener("KeyDown") ~= nil)
app.windows.layoutEditor.window:Close()
assert(app.windows.layoutEditor == nil)
for _, event in ipairs({ "KeyDown", "WindowFocusChanged" }) do
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
