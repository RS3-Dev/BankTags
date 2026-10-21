package.path = "./?.lua;./?/init.lua;" .. package.path

-- Move sorted items with the arrow keys, once turned on, and undo or redo layout edits with Ctrl+Z and Ctrl+Y
-- FAKE HOST: stand-in key events, keyboard, pointer, and drags, not the game client

local Harness = require("tools/test_support/tags_harness")
local Geometry = require("banktags/ui/geometry")
local h = Harness.new("layout_editor_history")
local host = h.bankHost
host:SetItems({ { 4151, 1, "Abyssal whip" }, { 385, 20, "Shark" } })
host.itemLayer.interfaceID = 517
h:LoadCore()
h:LoadTags()
local app = h:App()
h:OpenBank()
h:Tick(12)

local Json = require("banktags/core/json")
local TagLayouts = require("banktags/tags/tag_layouts")
local key = require("banktags/tags/item_identity").LayoutKey
local store = app.store
local function item(objectID, copy, source)
    return { kind = "item", objectID = objectID, layoutKey = key(objectID, copy or 1),
        sourceLayoutKey = source ~= nil and key(objectID, source) or nil }
end
local function row(...) return { kind = "row", slots = { ... } } end
-- Line 0 holds 1 2 3 4, line 1 is a label, line 2 holds 5 and a copy of 1; 99 is unsorted
local function resetGear()
    for _, tag in ipairs({ "gear", "food" }) do
        if store.data.tags[tag] ~= nil then assert(store:DeleteTag(tag)) end
        assert(store:CreateTag(tag))
    end
    store.data.tags.gear.rows = {
        row(item(1), item(2), item(3), item(4)),
        { kind = "label", text = "Mid" },
        row(item(5), item(1, 2, 1)),
    }
    store.data.tags.gear.unsorted = { item(99) }
    assert(store:Save())
    app:Changed()
end
resetGear()

local Size = h:TagsModule("banktags/windows/layout_editor_parts").size
local COLUMNS = Size.CENTER_COLUMNS
assert(COLUMNS >= 8)
local editor, changes
-- Open the editor on gear, counting its change notices
local function openEditor()
    app.windows:OpenLayoutEditor("gear")
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
-- Arrow-key movement is off until the player turns it on
assert(app:SetSetting("arrowKeyMovement", true))

-- Find the editor's listener for a key event
local function listener(event)
    for name, action in pairs(h.keySubscriptions[event]) do
        if string.find(name, "layout_editor_keys", 1, true) then return action end
    end
    return nil
end
-- GameKey values from the client docs
local LEFT, RIGHT, UP, DOWN, Z, Y, C, V, DELETE = 96, 97, 98, 99, 64, 37, 66, 67, 101
local NONE, SHIFT_HELD, CONTROL_HELD, CONTROL_SHIFT = 0, 1, 2, 3
-- Send a key press as the client's KeyDown payload, optionally as the OS's held-key repeat
local function press(gameKey, modifiers, isRepeat)
    listener("KeyDown")({ gameKey = gameKey, systemKey = 0, modifiers = modifiers or NONE,
        isRepeat = isRepeat == true, timestamp = 0 })
end
-- The editor acts on presses alone, so a tap is one press
local function tap(gameKey, modifiers)
    press(gameKey, modifiers)
end
local function undo() tap(Z, CONTROL_HELD) end
local function redo() tap(Y, CONTROL_HELD) end

-- Point at a pane's grid slot, counted from zero, through its scroll
local function pointAt(paneName, column, line)
    local left, top = Geometry.absolutePosition(editor.content)
    local pane = editor.panes[paneName]
    local x, y = Size.GRID_LEFT + column * 44 + 20, 4 + line * 44 + 20 - pane.view.scrollY
    host.mouse = { x = left + pane.x + x, y = top + pane.y + y }
    return x, y
end
local function pressSlot(paneName, column, line)
    editor.panes[paneName].surface.hooks.click(nil, pointAt(paneName, column, line))
end
local function dragOver(paneName, column, line)
    pointAt(paneName, column, line)
    editor.panes.sorted.surface.hooks.drag()
end
local function releaseSlot(paneName)
    editor.panes[paneName or "sorted"].surface.hooks.release()
end
local function click(paneName, column, line)
    pressSlot(paneName, column, line)
    releaseSlot(paneName)
end
local function shiftClick(paneName, column, line)
    host.shiftDown = true
    click(paneName, column, line)
    host.shiftDown = false
end
-- Drag from one pane slot to another
local function drag(fromPane, fromColumn, fromLine, toPane, toColumn, toLine)
    pressSlot(fromPane, fromColumn, fromLine)
    dragOver(toPane, toColumn, toLine)
    releaseSlot(fromPane)
end
-- Describe the gear tag's lines as the editor lays them out, and its Unsorted items
local function lines()
    local view = TagLayouts.Render(store.data.tags.gear.rows, COLUMNS)
    local out = {}
    for line = 0, view.lines - 1 do
        local label = nil
        for _, entry in ipairs(view.labels) do if entry.row == line then label = entry.text end end
        local cells = {}
        for cell = line * COLUMNS + 1, line * COLUMNS + COLUMNS do
            local slot = view.slots[cell]
            cells[#cells + 1] = slot.kind == "item" and tostring(slot.objectID) or "."
        end
        local text = label or table.concat(cells, " "):gsub("[ .]+$", "")
        out[#out + 1] = text == "" and "-" or text
    end
    local unsorted = {}
    for _, slot in ipairs(store.data.tags.gear.unsorted) do unsorted[#unsorted + 1] = tostring(slot.objectID) end
    return table.concat(out, " | ") .. " / " .. table.concat(unsorted, " ")
end
-- The part of gear the editor changes: its rows and Unsorted items
local function gearState()
    local record = store.data.tags.gear or store.data.tags.kit
    return Json.encode({ rows = record.rows, unsorted = record.unsorted })
end
local function saved() return Json.encode(store.data) end
local function grouped(...)
    local wanted = { ... }
    if editor:GroupCount() ~= #wanted then return false end
    for _, objectID in ipairs(wanted) do
        if not editor.groupKeys[key(objectID, 1)] then return false end
    end
    return true
end

-- Before the grid is pressed, arrows and Ctrl+Z do nothing
editor.selectedLayoutKey = key(1, 1)
tap(RIGHT)
undo()
assert(lines() == "1 2 3 4 | Mid | 5 1 / 99" and changes == 0)

-- An arrow swaps the selected item with its neighbour in one save, keeping it selected
click("sorted", 0, 0)
local before = saved()
tap(RIGHT)
assert(lines() == "2 1 3 4 | Mid | 5 1 / 99", lines())
assert(changes == 1 and editor.selectedLayoutKey == key(1, 1) and editor.errorBanner == nil)
-- Holding the key moves only once, through the OS's repeats
press(LEFT)
press(LEFT, NONE, true)
press(LEFT, NONE, true)
assert(lines() == "1 2 3 4 | Mid | 5 1 / 99" and changes == 2)
-- Shift, Ctrl, and Ctrl+Shift arrows do nothing
for _, modifiers in ipairs({ SHIFT_HELD, CONTROL_HELD, CONTROL_SHIFT }) do tap(RIGHT, modifiers) end
assert(changes == 2)
-- The grid's edges stop it quietly; nothing wraps to the next line
tap(LEFT)
tap(UP)
assert(lines() == "1 2 3 4 | Mid | 5 1 / 99" and changes == 2 and editor.errorBanner == nil)
for _ = 1, COLUMNS - 1 do tap(RIGHT) end
assert(lines() == "2 3 4 . . . . . . 1 | Mid | 5 1 / 99" or COLUMNS ~= 10, lines())
before = saved()
tap(RIGHT)
assert(saved() == before and editor.errorBanner == nil)
-- A label's line refuses it and says why
tap(DOWN)
assert(saved() == before and editor.errorBanner ~= nil)
editor:HideError()
for _ = 1, COLUMNS - 1 do tap(LEFT) end
assert(lines() == "1 2 3 4 | Mid | 5 1 / 99", lines())
changes = 0

-- Down past the last line adds a row; a copy keeps the item it opens
click("sorted", 1, 2)
assert(editor.selectedLayoutKey == key(1, 2))
tap(DOWN)
assert(lines() == "1 2 3 4 | Mid | 5 | . 1 / 99", lines())
local copy = TagLayouts.Render(store.data.tags.gear.rows, COLUMNS).slots[3 * COLUMNS + 2]
assert(copy.layoutKey == key(1, 2) and copy.sourceLayoutKey == key(1, 1))
tap(UP)
assert(lines() == "1 2 3 4 | Mid | 5 1 / 99" and changes == 2)

-- A group moves together, keeping its offsets, and stays selected
click("sorted", 1, 0)
shiftClick("sorted", 2, 0)
assert(grouped(2, 3))
tap(RIGHT)
assert(lines() == "1 4 2 3 | Mid | 5 1 / 99", lines())
assert(grouped(2, 3) and changes == 3)
tap(LEFT)
assert(lines() == "1 2 3 4 | Mid | 5 1 / 99" and grouped(2, 3) and changes == 4)
-- Any member past an edge stops the group quietly
tap(UP)
assert(changes == 4 and editor.errorBanner == nil)

-- Unsorted items, an empty selection, and the search field's keys do not move
click("unsorted", 0, 0)
assert(editor.selectedLayoutKey == key(99, 1))
before = saved()
for _, arrow in ipairs({ LEFT, RIGHT, UP, DOWN }) do tap(arrow) end
click("sorted", 7, 0)
assert(editor.selectedLayoutKey == nil)
for _, arrow in ipairs({ LEFT, RIGHT, UP, DOWN }) do tap(arrow) end
click("sorted", 0, 0)
editor:ShowRightTab("search")
tap(RIGHT)
editor:ShowRightTab("unsorted")
assert(saved() == before and changes == 4 and editor.errorBanner == nil)

-- Fresh editor: with nothing to undo or redo, the keys do nothing
editor.window:Close()
resetGear()
openEditor()
click("sorted", 7, 0)
before = saved()
undo()
redo()
assert(saved() == before and changes == 0 and editor.errorBanner == nil)

-- Every edit is one step; undo and redo walk back and forth through them
local states, names = { gearState() }, {}
local function step(name, action)
    local count = changes
    action()
    assert(gearState() ~= states[#states], name .. " changed nothing: " .. lines())
    assert(changes == count + 1, name .. " notified " .. (changes - count) .. " times")
    states[#states + 1] = gearState()
    names[#names + 1] = name
end
local prompt
editor.onPromptLabel = function(options) prompt = options end
step("arrow", function()
    click("sorted", 0, 0)
    tap(RIGHT)
end)
step("drag", function() drag("sorted", 1, 0, "sorted", 5, 0) end)
step("drag to Unsorted", function() drag("sorted", 2, 0, "unsorted", 3, 0) end)
step("drag from Unsorted", function() drag("unsorted", 0, 0, "sorted", 6, 2) end)
step("group drag", function()
    click("sorted", 0, 2)
    shiftClick("sorted", 1, 2)
    drag("sorted", 0, 2, "sorted", 2, 3)
end)
step("Ctrl+V", function()
    click("sorted", 3, 0)
    tap(C, CONTROL_HELD)
    click("sorted", 0, 6)
    tap(V, CONTROL_HELD)
end)
step("Delete", function()
    click("sorted", 3, 0)
    tap(DELETE)
end)
step("Move to Unsorted", function()
    click("sorted", 5, 0)
    editor.unsortButton.root.hooks.pressed()
end)
step("search add", function() assert(editor:AddCatalogResult({ objectId = 385 }, 8)) end)
step("new label", function()
    assert(editor:PromptNewLabel(0))
    assert(prompt.onSave("Top"))
end)
step("rename label", function()
    assert(editor:EditLabel(0))
    assert(prompt.onSave("Head"))
end)
step("move label", function() drag("sorted", 0, 0, "sorted", 0, 3) end)
step("delete label", function()
    assert(editor:EditLabel(2))
    assert(prompt.onDelete())
end)
step("insert row", function() assert(editor:InsertEmptyRow(1)) end)
step("remove row", function() assert(editor:RemoveRow(1)) end)
local last = #states
assert(#names == 15)

-- Other tags, folders, the tag's icon, and settings are never undone
assert(store:AddTag("food", 385, key(385, 1)))
assert(store:CreateFolder("Kit", "gear"))
local _, iconName = store:UpdateTag("gear", "gear", 4151)
assert(iconName == "gear")
app:Changed()
local others = Json.encode({ food = store.data.tags.food, folders = store.data.folders,
    order = store.data.order, icon = store.data.tags.gear.icon })
click("sorted", 9, 5)
for index = last - 1, 1, -1 do
    local count = changes
    undo()
    assert(gearState() == states[index], "undo " .. names[index] .. ": " .. lines())
    assert(changes == count + 1)
end
before = saved()
undo()
assert(saved() == before, "nothing is left to undo")
for index = 2, last do
    redo()
    assert(gearState() == states[index], "redo " .. names[index - 1] .. ": " .. lines())
end
before = saved()
redo()
assert(saved() == before, "nothing is left to redo")
assert(Json.encode({ food = store.data.tags.food, folders = store.data.folders,
    order = store.data.order, icon = store.data.tags.gear.icon }) == others)

-- A no-op edit keeps the redo steps; a real edit drops them
undo()
assert(gearState() == states[last - 1])
drag("sorted", 9, 5, "sorted", 9, 5)
editor:InsertEmptyRow(40)
editor:HideError()
assert(gearState() == states[last - 1])
redo()
assert(gearState() == states[last])
undo()
assert(editor:InsertEmptyRow(0))
local fresh = gearState()
assert(fresh ~= states[last - 1])
redo()
assert(gearState() == fresh)
undo()
assert(gearState() == states[last - 1])

-- A failed save keeps the step and shows why; a failed edit adds none
local count
store.loadError = "The saved tags could not be read."
before = saved()
count = changes
undo()
assert(saved() == before and changes == count and editor.errorBanner ~= nil)
editor:HideError()
assert(not editor:InsertEmptyRow(0))
editor:HideError()
store.loadError = nil
undo()
assert(gearState() == states[last - 2])
redo()
assert(gearState() == states[last - 1])

-- An outside change to the open tag ends its steps instead of overwriting it
assert(store:AddTag("gear", 385, key(385, 9)))
app:Changed()
before = saved()
click("sorted", 9, 5)
undo()
redo()
assert(saved() == before and store:HasTag("gear", key(385, 9)))
-- Even one the editor was not told about
click("sorted", 0, 0)
tap(RIGHT)
local edited = gearState()
assert(store:RemoveTag("gear", key(385, 9)))
before = saved()
undo()
assert(saved() == before and editor.errorBanner ~= nil and not store:HasTag("gear", key(385, 9)))
editor:HideError()
assert(gearState() ~= edited)
app:Changed()

-- Renaming the open tag keeps its steps; changing tag or closing the editor ends them
click("sorted", 1, 0)
local count = changes
tap(LEFT)
assert(changes == count + 1)
local renamedFrom = gearState()
assert(store:UpdateTag("gear", "kit"))
app:Renamed("gear", "kit")
assert(editor.selectedTag == "kit")
click("sorted", 9, 5)
undo()
assert(gearState() ~= renamedFrom)
redo()
assert(gearState() == renamedFrom)
assert(store:UpdateTag("kit", "gear"))
app:Renamed("kit", "gear")
click("sorted", 0, 0)
tap(RIGHT)
editor:SelectTag("food")
editor:SelectTag("gear")
before = saved()
click("sorted", 9, 5)
undo()
assert(saved() == before)
click("sorted", 1, 0)
count = changes
tap(LEFT)
assert(changes == count + 1 and editor.history ~= nil)
editor.window:Close()
assert(editor.history == nil)
openEditor()
before = saved()
click("sorted", 9, 5)
undo()
assert(saved() == before and changes == 0)

-- At most fifty steps are kept
click("sorted", 0, 0)
for index = 1, 55 do tap(index % 2 == 1 and RIGHT or LEFT) end
assert(changes == 55)
local undone = 0
for _ = 1, 60 do
    local count = changes
    undo()
    if changes > count then undone = undone + 1 end
end
assert(undone == 50, undone)

print("layout_editor_history_test: ok")
