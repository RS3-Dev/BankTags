package.path = "./?.lua;./?/init.lua;" .. package.path

-- Shift-click sorted items in the layout editor and drag them as a group
-- FAKE HOST: stand-in keyboard, pointer, and drags, not the game client

local Harness = require("tools/test_support/tags_harness")
local Geometry = require("banktags/ui/geometry")
local h = Harness.new("layout_editor_group")
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
local function item(objectID) return { kind = "item", objectID = objectID, layoutKey = key(objectID, 1) } end
local function row(...) return { kind = "row", slots = { ... } } end
assert(app.store:CreateTag("gear"))
assert(app.store:CreateTag("food"))
-- Line 0 holds 1 2 3 4, line 1 is a label, line 2 holds 5; 99 is unsorted
app.store.data.tags.gear.rows = {
    row(item(1), item(2), item(3), item(4)),
    { kind = "label", text = "Mid" },
    row(item(5)),
}
app.store.data.tags.gear.unsorted = { item(99) }
assert(app.store:Save())
app:Changed()
h:Tick(2)
app.windows:OpenLayoutEditor("gear")
local editor = app.windows.layoutEditor
local Size = h:TagsModule("banktags/windows/layout_editor_parts").size
local COLUMNS = Size.CENTER_COLUMNS
assert(COLUMNS >= 8)
local changes = 0
local onChanged = editor.onChanged
editor.onChanged = function()
    changes = changes + 1
    onChanged()
end
editor.window.tooltipContext = { position = function()
    return Geometry.absolutePosition(editor.content)
end }

-- Point at a pane's grid slot, counted from zero, through its scroll
local function pointAt(paneName, column, line)
    local left, top = Geometry.absolutePosition(editor.content)
    local pane = editor.panes[paneName]
    local x, y = Size.GRID_LEFT + column * 44 + 20, 4 + line * 44 + 20 - pane.view.scrollY
    host.mouse = { x = left + pane.x + x, y = top + pane.y + y }
    return x, y
end
local function press(paneName, column, line)
    editor.panes[paneName].surface.hooks.click(nil, pointAt(paneName, column, line))
end
-- Move a held drag over another slot, as the client's drag hook does
local function dragOver(paneName, column, line)
    pointAt(paneName, column, line)
    editor.panes.sorted.surface.hooks.drag()
end
local function release(paneName)
    editor.panes[paneName or "sorted"].surface.hooks.release()
end
local function click(paneName, column, line)
    press(paneName, column, line)
    release(paneName)
end
local function shiftClick(paneName, column, line)
    host.shiftDown = true
    click(paneName, column, line)
    host.shiftDown = false
end
-- Count the gold outlines drawn on either grid
local function outlines()
    local count = 0
    for _, node in ipairs(editor.centerNodes) do
        if node.fill == false then count = count + 1 end
    end
    return count
end
-- Describe the gear tag's lines as the editor lays them out
local function lines()
    local view = TagLayouts.Render(app.store.data.tags.gear.rows, COLUMNS)
    local out = {}
    for line = 0, view.lines - 1 do
        local cells = {}
        for cell = line * COLUMNS + 1, line * COLUMNS + COLUMNS do
            local slot = view.slots[cell]
            cells[#cells + 1] = slot.kind == "item" and tostring(slot.objectID) or "."
        end
        local text = table.concat(cells, " "):gsub("[ .]+$", "")
        out[#out + 1] = text == "" and "-" or text
    end
    return table.concat(out, " | ")
end
local function grouped(...)
    local wanted = { ... }
    if editor:GroupCount() ~= #wanted then return false end
    for _, objectID in ipairs(wanted) do
        if not editor.groupKeys[key(objectID, 1)] then return false end
    end
    return true
end

-- A plain click selects one item; Shift-click adds sorted items without dragging
click("sorted", 0, 0)
assert(editor.selectedLayoutKey == key(1, 1) and editor.groupKeys == nil and outlines() == 1)
host.shiftDown = true
press("sorted", 1, 0)
assert(editor.drag == nil, "a Shift press never drags")
release()
press("sorted", 2, 0)
release()
host.shiftDown = false
assert(grouped(1, 2, 3) and editor.selectedLayoutKey == key(3, 1) and outlines() == 3)
-- Shift-click again takes an item out, and puts it back
shiftClick("sorted", 1, 0)
assert(grouped(1, 3) and outlines() == 2)
shiftClick("sorted", 1, 0)
assert(grouped(1, 2, 3) and outlines() == 3)
-- A Shift-click on an empty cell keeps the group
shiftClick("sorted", 6, 0)
assert(grouped(1, 2, 3) and changes == 0)
-- Items the group blocks say so; Copy takes the whole group
assert(editor.copyButton.tooltipText == "Copy the selected item or group (Ctrl+C)")
assert(editor.removeButton.tooltipText == "Select one item to remove it")
assert(editor.unsortButton.tooltipText == "Select one item to move it to Unsorted")

-- A plain click on a group item keeps the group and saves nothing
local before = Json.encode(app.store.data)
click("sorted", 0, 0)
assert(grouped(1, 2, 3) and editor.selectedLayoutKey == key(1, 1) and editor.drag == nil)
assert(changes == 0 and Json.encode(app.store.data) == before)

-- Dragging shows every cell it would take, gold where it fits
press("sorted", 0, 0)
assert(editor.drag.kind == "group" and #editor.drag.keys == 3)
dragOver("sorted", 1, 0)
local preview = editor.drag.preview
assert(#preview == 3 and preview[1].rgba == 0xD2A84D55 and preview[1].fill)
assert(preview[1].x == Size.GRID_LEFT + 44 and preview[3].x == Size.GRID_LEFT + 3 * 44)
-- Past the edge the cells that still fit turn red; the rest are not drawn
dragOver("sorted", COLUMNS - 2, 0)
assert(preview[1].destroyed and #editor.drag.preview == 2 and editor.drag.preview[1].rgba == 0xC0392B66)
-- Over a label there is no drop cell
dragOver("sorted", 0, 1)
assert(#editor.drag.preview == 0)
-- Three side by side move right one; only the item beyond them fills the left cell
dragOver("sorted", 1, 0)
preview = editor.drag.preview
release()
assert(lines() == "4 1 2 3 | - | 5", lines())
assert(changes == 1 and editor.drag == nil and preview[1].destroyed and preview[3].destroyed)
-- The selection follows the moved items
assert(grouped(1, 2, 3) and outlines() == 3)
for _, index in ipairs({ 2, 3, 4 }) do assert(editor:IsSelected(editor.panes.sorted.slots[index].layoutKey)) end

-- A drop that cannot fit, onto Unsorted, or off the grid changes nothing
before = Json.encode(app.store.data)
press("sorted", 1, 0)
dragOver("sorted", COLUMNS - 1, 0)
release()
assert(Json.encode(app.store.data) == before and changes == 1 and grouped(1, 2, 3))
assert(editor.errorBanner ~= nil)
editor:HideError()
press("sorted", 1, 0)
dragOver("sorted", 2, 2)
pointAt("unsorted", 0, 0)
release()
assert(Json.encode(app.store.data) == before and editor.errorBanner ~= nil and grouped(1, 2, 3))
editor:HideError()
-- Across the label line the group cannot land
press("sorted", 1, 0)
dragOver("sorted", 1, 1)
release()
assert(Json.encode(app.store.data) == before and editor.errorBanner == nil and changes == 1)

-- A failed save keeps the layout and the group, and says why
-- The store's own write failure is covered by layout_group_move_test
app.store.Commit = function() return false, "Could not save the layout." end
press("sorted", 1, 0)
dragOver("sorted", 0, 0)
release()
app.store.Commit = nil
assert(Json.encode(app.store.data) == before and editor.errorBanner ~= nil and grouped(1, 2, 3))
editor:HideError()

-- Remove and Move to Unsorted refuse a group by button and key
editor.keysOnGrid = true
for _, button in ipairs({ editor.removeButton, editor.unsortButton }) do
    button.root.hooks.pressed()
    assert(editor.errorBanner ~= nil, "a group action explains itself")
    editor:HideError()
end
for name, action in pairs(h.keySubscriptions.KeyDown) do
    if string.find(name, "layout_editor_keys", 1, true) then
        action({ gameKey = 101, modifiers = 0, isRepeat = false })
    end
end
assert(editor.errorBanner ~= nil and Json.encode(app.store.data) == before and changes == 1)
editor:HideError()
-- Copy keeps the whole group for Paste and saves nothing
editor.copyButton.root.hooks.pressed()
assert(#editor.clipboard.items == 3 and Json.encode(app.store.data) == before and grouped(1, 2, 3))
editor:HideError()
-- A new label goes above the item last grabbed
assert(editor:DefaultLabelRow() == 0)

-- A plain click on an unselected item selects only it, and a single drag still works
click("sorted", 0, 0)
assert(editor.groupKeys == nil and editor.selectedLayoutKey == key(4, 1) and outlines() == 1)
assert(editor.copyButton.tooltipText == "Copy the selected item or group (Ctrl+C)")
press("sorted", 0, 0)
assert(editor.drag.kind == "layout")
dragOver("sorted", 5, 0)
release()
assert(lines() == ". 1 2 3 . 4 | - | 5" and changes == 2, lines())

-- Shift-click on an Unsorted item is a plain click there; groups are sorted only
shiftClick("sorted", 1, 0)
shiftClick("sorted", 2, 0)
assert(grouped(4, 1, 2))
shiftClick("unsorted", 0, 0)
assert(editor.groupKeys == nil and editor.selectedLayoutKey == key(99, 1))
-- A Shift-click joins only the sorted item to the Unsorted selection
shiftClick("sorted", 1, 0)
assert(editor.groupKeys == nil and editor.selectedLayoutKey == key(1, 1) and outlines() == 1)

-- Removing group items elsewhere prunes them; one left is a plain selection
shiftClick("sorted", 2, 0)
shiftClick("sorted", 3, 0)
assert(grouped(1, 2, 3))
assert(app.store:RemoveTag("gear", key(2, 1)))
editor:StoreChanged()
assert(grouped(1, 3) and outlines() == 2)
assert(app.store:UnarrangeLayoutItem("gear", key(3, 1)))
editor:StoreChanged()
assert(editor.groupKeys == nil and editor.selectedLayoutKey == key(1, 1) and outlines() == 1)
-- Another tag clears the group
shiftClick("sorted", 5, 0)
assert(grouped(1, 4))
editor:SelectTag("food")
assert(editor.groupKeys == nil and editor.selectedLayoutKey == nil)
editor:SelectTag("gear")
assert(editor.groupKeys == nil and outlines() == 0)

-- In a scrolled grid the drop lands under the pointer
local tall = {}
for index = 1, 12 do tall[index] = row() end
tall[13] = row(item(21), item(22))
tall[14] = row({ kind = "blank" }, item(23))
app.store.data.tags.gear.rows, app.store.data.tags.gear.unsorted = tall, {}
assert(app.store:Save())
editor:StoreChanged()
editor.panes.sorted.view:SetScrollPosition(3 * 44)
assert(editor.panes.sorted.view.scrollY == 3 * 44)
click("sorted", 0, 12)
shiftClick("sorted", 1, 13)
assert(grouped(21, 23))
press("sorted", 0, 12)
dragOver("sorted", 3, 10)
assert(#editor.drag.preview == 2 and editor.drag.preview[1].y == 4 + 10 * 44)
release()
local view = TagLayouts.Render(app.store.data.tags.gear.rows, COLUMNS)
assert(view.slots[10 * COLUMNS + 4].layoutKey == key(21, 1) and view.slots[11 * COLUMNS + 5].layoutKey == key(23, 1))
assert(view.slots[12 * COLUMNS + 2].layoutKey == key(22, 1) and grouped(21, 23))

-- Closing mid-drag removes the preview with the editor
press("sorted", 3, 10)
dragOver("sorted", 4, 10)
preview = editor.drag.preview
assert(#preview == 2)
editor.window:Close()
assert(preview[1].destroyed and preview[2].destroyed and app.windows.layoutEditor == nil)

print("layout_editor_group_test: ok")
