package.path = "./?.lua;./?/init.lua;" .. package.path
local BankGrid = require("banktags/ui/bank_grid")

-- Check optional arrow movement, undo, and redo
-- FAKE HOST: stand-in keyboard, pointer, and drags

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
-- Bank Tags' own module, so these slots' keys never repeat ones it gives out
local TagLayouts = h:TagsModule("banktags/tags/tag_layouts")
local store = app.store
-- Each object's first slot key, and the second slot of object 1
local keys, secondOne = {}, nil
-- Create a saved item slot for the test
local function item(objectID)
    local slot = TagLayouts.Item(objectID)
    keys[objectID] = keys[objectID] or slot.layoutKey
    return slot
end
-- Build a layout row from the supplied slots
local function row(...) return { kind = "row", slots = { ... } } end
-- Restore the test's original rows and Unsorted items
local function resetGear()
    for _, tag in ipairs({ "gear", "food" }) do
        if store.data.tags[tag] ~= nil then assert(store:DeleteTag(tag)) end
        assert(store:CreateTag(tag))
    end
    keys = {}
    local second = TagLayouts.Item(1)
    secondOne = second.layoutKey
    store.data.tags.gear.rows = {
        row(item(1), item(2), item(3), item(4)),
        { kind = "label", text = "Mid" },
        row(item(5), second),
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
    editor.onChanged = function(tag)
        changes = changes + 1
        onChanged(tag)
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
-- Send a key press, optionally as a held-key repeat
local function press(gameKey, modifiers, isRepeat)
    listener("KeyDown")({ gameKey = gameKey, systemKey = 0, modifiers = modifiers or NONE,
        isRepeat = isRepeat == true, timestamp = 0 })
end
-- Send a single keyboard press
local function tap(gameKey, modifiers)
    press(gameKey, modifiers)
end
-- Press the editor's Undo shortcut
local function undo() tap(Z, CONTROL_HELD) end
-- Press the editor's Redo shortcut
local function redo() tap(Y, CONTROL_HELD) end

-- Point at a pane cell through its scroll
local function pointAt(paneName, column, line)
    local left, top = Geometry.absolutePosition(editor.content)
    local pane = editor.panes[paneName]
    local x, y = pane.gridLeft + column * 44 + 20, BankGrid.RowItemY(line, pane.labels) + 20 - pane.view.scrollY
    h:PointEditor(pane.x + x, pane.y + y)
    return x, y
end
-- Press the chosen pane's grid cell
local function pressSlot(paneName, column, line)
    h:PressEditor(editor.panes[paneName].surface, pointAt(paneName, column, line))
end
-- Move the held pointer over another grid cell
local function dragOver(paneName, column, line)
    pointAt(paneName, column, line)
    editor.panes.sorted.surface.hooks.drag()
end
-- Release the current pane drag
local function releaseSlot(paneName)
    h:ReleaseEditor()
end
-- Press and release a grid cell
local function click(paneName, column, line)
    pressSlot(paneName, column, line)
    releaseSlot(paneName)
end
-- Click a grid cell while holding Shift
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
-- Describe the saved layout in reading order
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
-- Copy the gear tag's rows and Unsorted items
local function gearState()
    local record = store.data.tags.gear or store.data.tags.kit
    return Json.encode({ rows = record.rows, unsorted = record.unsorted })
end
-- Encode the current tag data for comparison
local function saved() return Json.encode(store.data) end
-- Check the items in the current group selection
local function grouped(...)
    local wanted = { ... }
    if editor:GroupCount() ~= #wanted then return false end
    for _, objectID in ipairs(wanted) do
        if not editor.groupKeys[keys[objectID]] then return false end
    end
    return true
end

-- Before the grid is pressed, arrows and Ctrl+Z do nothing
editor.selectedLayoutKey = keys[1]
tap(RIGHT)
undo()
assert(lines() == "1 2 3 4 | Mid | 5 1 / 99" and changes == 0)

-- An arrow swaps the selected item with its neighbour in one save, keeping it selected
click("sorted", 0, 0)
local before = saved()
tap(RIGHT)
assert(lines() == "2 1 3 4 | Mid | 5 1 / 99", lines())
assert(changes == 1 and editor.selectedLayoutKey == keys[1] and editor.status.content == "")
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
assert(lines() == "1 2 3 4 | Mid | 5 1 / 99" and changes == 2 and editor.status.content == "")
for _ = 1, COLUMNS - 1 do tap(RIGHT) end
assert(lines() == "2 3 4 . . . . . . 1 | Mid | 5 1 / 99" or COLUMNS ~= 10, lines())
before = saved()
tap(RIGHT)
assert(saved() == before and editor.status.content == "")
-- A label's line refuses it and says why
tap(DOWN)
assert(saved() == before and editor.status.content ~= "")
editor:ClearStatus()
for _ = 1, COLUMNS - 1 do tap(LEFT) end
assert(lines() == "1 2 3 4 | Mid | 5 1 / 99", lines())
changes = 0

-- Down past the last line adds a row; the moved slot keeps its key
click("sorted", 1, 2)
assert(editor.selectedLayoutKey == secondOne)
tap(DOWN)
assert(lines() == "1 2 3 4 | Mid | 5 | . 1 / 99", lines())
local moved = TagLayouts.Render(store.data.tags.gear.rows, COLUMNS).slots[3 * COLUMNS + 2]
assert(moved.layoutKey == secondOne and editor.selectedLayoutKey == secondOne)
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
assert(changes == 4 and editor.status.content == "")

-- Unsorted items, an empty selection, and the search field's keys do not move
click("unsorted", 0, 0)
assert(editor.selectedLayoutKey == keys[99])
before = saved()
for _, arrow in ipairs({ LEFT, RIGHT, UP, DOWN }) do tap(arrow) end
click("sorted", 7, 0)
assert(editor.selectedLayoutKey == nil)
for _, arrow in ipairs({ LEFT, RIGHT, UP, DOWN }) do tap(arrow) end
click("sorted", 0, 0)
editor.itemSearch.root.hooks.click(editor.itemSearch.root, 4, 4)
tap(RIGHT)
assert(saved() == before and changes == 4 and editor.status.content == "")

-- Fresh editor: with nothing to undo or redo, the keys do nothing
editor.window:Close()
resetGear()
openEditor()
click("sorted", 7, 0)
before = saved()
undo()
redo()
assert(saved() == before and changes == 0 and editor.status.content == "")

-- Every edit is one step; undo and redo walk back and forth through them
local states, names = { gearState() }, {}
-- Run an edit and check its undo and redo
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
assert(store:AddTag("food", 385))
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
editor:ClearStatus()
assert(gearState() == states[last - 1])
-- Saving a label's unchanged text writes a fresh copy, yet changes nothing, so redo stays
local label = assert(editor.layout.labels[1], "a label to rename")
local dataBefore, notices = store.data, changes
assert(editor:EditLabel(label.row))
assert(prompt.text == label.text and prompt.onSave(label.text))
assert(store.data ~= dataBefore, "the store saved a fresh copy")
assert(gearState() == states[last - 1] and changes == notices and editor:CanStepHistory(1))
-- A rejected label save also keeps redo, and its reason goes back to the prompt
assert(editor:EditLabel(label.row))
local refused, reason = prompt.onSave("<>")
assert(not refused and reason ~= nil and editor:CanStepHistory(1) and changes == notices)
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
assert(saved() == before and changes == count and editor.status.content ~= "")
editor:ClearStatus()
assert(not editor:InsertEmptyRow(0))
editor:ClearStatus()
store.loadError = nil
undo()
assert(gearState() == states[last - 2])
redo()
assert(gearState() == states[last - 1])

-- An outside change to the open tag ends its steps instead of overwriting it
local _, _, outside = store:AddTag("gear", 385)
-- Report whether gear still holds that outside slot
local function hasOutside()
    for _, slot in ipairs(store:GetTaggedItems("gear")) do
        if slot.layoutKey == outside then return true end
    end
    return false
end
assert(hasOutside())
app:Changed()
before = saved()
click("sorted", 9, 5)
undo()
redo()
assert(saved() == before and hasOutside())
-- Even one the editor was not told about
click("sorted", 0, 0)
tap(RIGHT)
local edited = gearState()
assert(store:RemoveTag("gear", outside))
before = saved()
undo()
assert(saved() == before and editor.status.content ~= "" and not hasOutside())
editor:ClearStatus()
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
