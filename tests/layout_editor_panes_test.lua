package.path = "./?.lua;./?/init.lua;" .. package.path

-- Move items between the layout editor's sorted grid and its Unsorted grid
-- Each grid scrolls on its own; drops count the scroll of both
-- FAKE HOST: stand-in components, pointer, and scroll views, not the game client

local Harness = require("tools/test_support/tags_harness")
local Geometry = require("banktags/ui/geometry")
local Json = require("banktags/core/json")
local h = Harness.new("layout_editor_panes")
local host = h.bankHost
host:SetItems({ { 3001, 1, "Rune axe" } })
host.itemLayer.interfaceID = 517
h:LoadCore()
h:LoadTags()
local app = h:App()
h:OpenBank()
h:Tick(12)

local key = require("banktags/tags/item_identity").LayoutKey
local store = app.store
-- Sorted: a label, then 95 items wrapping onto ten rows, with one blank
-- Unsorted: 45 items, five rows
assert(store:CreateTag("gear") and store:CreateTag("food"))
store:SetLayoutPlacement(false)
for objectID = 1001, 1095 do assert(store:AddTag("gear", objectID)) end
assert(store:InsertLabel("gear", 0, "Weapons", 10))
assert(store:RemoveTag("gear", key(1045)))
store:SetLayoutPlacement(true)
for objectID = 2001, 2045 do assert(store:AddTag("gear", objectID)) end
app:Changed()
h:Tick(2)
app.windows:OpenLayoutEditor("gear")
local editor = app.windows.layoutEditor
local editorSize = h:TagsModule("banktags/windows/layout_editor_parts").size
local changes = 0
local onChanged = editor.onChanged
editor.onChanged = function()
    changes = changes + 1
    onChanged()
end
editor.window.tooltipContext = { position = function()
    return Geometry.absolutePosition(editor.content)
end }
-- Each save replaces the data, so read the tag fresh
local function gear() return store.data.tags.gear end
local sorted, unsorted = editor.panes.sorted, editor.panes.unsorted

-- Point at a pane's grid slot by its content row, as its scroll shows it
local function pointAt(paneName, column, row)
    local pane = editor.panes[paneName]
    local x, y = editorSize.GRID_LEFT + column * 44 + 20, 4 + row * 44 + 20 - pane.view.scrollY
    assert(y >= 0 and y < pane.height, "row " .. row .. " is scrolled out of " .. paneName)
    local left, top = Geometry.absolutePosition(editor.content)
    host.mouse = { x = left + editorSize.CENTER_X + editorSize.CENTER_VIEW_X + x,
        y = top + editorSize.PANEL_TOP + pane.y + y }
    return x, y
end
-- Point at an editor content point outside the grids
local function pointAtContent(x, y)
    local left, top = Geometry.absolutePosition(editor.content)
    host.mouse = { x = left + x, y = top + y }
end
-- Press on a slot; finish over a slot, or over a content point
local function press(paneName, column, row)
    editor.panes[paneName].surface.hooks.click(nil, pointAt(paneName, column, row))
    assert(editor.drag ~= nil or editor.selectedLayoutKey == nil)
end
local function drag(fromPane, fromColumn, fromRow, toPane, toColumn, toRow)
    local surface = editor.panes[fromPane].surface
    press(fromPane, fromColumn, fromRow)
    if type(toPane) == "string" then pointAt(toPane, toColumn, toRow) else pointAtContent(toPane, toColumn) end
    surface.hooks.release()
end
local function wheel(paneName, delta) editor.panes[paneName].surface.hooks.wheel(nil, delta) end
local function saved() return Json.encode(store.data) end
-- Count the gold outlines drawn on either grid
local function outlines()
    local count = 0
    for _, node in ipairs(editor.centerNodes) do
        if node.fill == false then count = count + 1 end
    end
    return count
end
local function unsortedIndex(layoutKey)
    for index, slot in ipairs(gear().unsorted) do
        if slot.layoutKey == layoutKey then return index end
    end
    return nil
end

-- Unsorted shows four rows below its heading; sorted takes the rest
assert(unsorted.height == 4 + 4 * 44 and unsorted.view.height == unsorted.height)
assert(sorted.y + sorted.height + editorSize.PANE_GAP + editorSize.UNSORTED_HEADING_HEIGHT == unsorted.y)
assert(unsorted.y + unsorted.height == editorSize.CENTER_SURFACE_HEIGHT - 4)
assert(Harness.Find(editor.centerPanel, "Unsorted") ~= nil)
-- A taller bank grows only the sorted grid, at the same columns
do
    local Parts = h:TagsModule("banktags/windows/layout_editor_parts")
    local before = { sorted = editorSize.SORTED_VIEW_HEIGHT, unsorted = editorSize.UNSORTED_VIEW_HEIGHT }
    Parts.SizeToBank(editorSize.CENTER_COLUMNS, editor.bounds.width, editorSize.HEIGHT + 88)
    assert(editorSize.SORTED_VIEW_HEIGHT == before.sorted + 88)
    assert(editorSize.UNSORTED_VIEW_HEIGHT == before.unsorted)
    Parts.SizeToBank(editor.columns, editor.bounds.width, editor.bounds.height)
end
-- The label, the ten item rows, and an empty drop row; Unsorted packs five rows
assert(#sorted.slots == 110 and #unsorted.slots == 45 and editor.centerLabels[1].row == 0)
assert(sorted.view.content.height == 4 + 12 * 44 and unsorted.view.content.height == 4 + 5 * 44)
assert(sorted.slots[55].kind == "blank" and gear().rows[2].slots[45].kind == "blank")

-- Each wheel scrolls only its own grid, clamped to that grid's content
wheel("unsorted", 1)
assert(unsorted.view.scrollY == 44 and sorted.view.scrollY == 0)
wheel("unsorted", 5)
assert(unsorted.view.scrollY == 44, "Unsorted stops at its last row")
wheel("sorted", 3)
assert(sorted.view.scrollY == 132 and unsorted.view.scrollY == 44)
wheel("sorted", 10)
assert(sorted.view.scrollY == 4 + 12 * 44 - sorted.height)
wheel("sorted", -10)
wheel("sorted", 3)
assert(sorted.view.scrollY == 132)

-- With both scrolled, an Unsorted item drops into the exact sorted cell
-- Unsorted row 4, column 2 is item 2043; sorted row 5, column 4 is the blank
drag("unsorted", 2, 4, "sorted", 4, 5)
assert(gear().rows[2].slots[45].layoutKey == key(2043) and unsortedIndex(key(2043)) == nil)
assert(#gear().unsorted == 44 and store:HasTag("gear", key(2043)) and changes == 1)
assert(sorted.slots[55].layoutKey == key(2043) and editor.selectedLayoutKey == key(2043) and outlines() == 1)
-- Its neighbours, the label, and the scroll of each grid are unchanged
assert(gear().rows[1].kind == "label" and gear().rows[1].text == "Weapons")
assert(gear().rows[2].slots[44].layoutKey == key(1044) and gear().rows[2].slots[46].layoutKey == key(1046))
assert(sorted.view.scrollY == 132 and unsorted.view.scrollY == 44)

-- A sorted item dropped on Unsorted leaves a blank and joins the end of Unsorted
-- Sorted row 6, column 0 is item 1051
drag("sorted", 0, 6, "unsorted", 3, 2)
assert(gear().rows[2].slots[51].kind == "blank" and unsortedIndex(key(1051)) == 45)
assert(store:HasTag("gear", key(1051)) and changes == 2 and editor.selectedLayoutKey == key(1051))
assert(sorted.view.scrollY == 132 and unsorted.view.scrollY == 44)

-- Unsorted has no order to edit, so a drag within it only selects
local before = saved()
drag("unsorted", 0, 1, "unsorted", 5, 3)
assert(saved() == before and changes == 2 and editor.selectedLayoutKey == gear().unsorted[11].layoutKey)

-- Drops outside both grids, on the Unsorted heading, or on a label change nothing
drag("sorted", 1, 6, editorSize.COLUMN_X + 10, editorSize.PANEL_TOP + 10)
drag("unsorted", 1, 1, editorSize.CENTER_X + 40, editorSize.PANEL_TOP + editorSize.UNSORTED_HEADING_Y + 10)
wheel("sorted", -10)
drag("unsorted", 1, 1, "sorted", 3, 0)
assert(saved() == before and changes == 2 and editor.drag == nil)
assert(sorted.view.scrollY == 0 and unsorted.view.scrollY == 44)

-- A wheel turned mid-drag scrolls the grid under the pointer
press("sorted", 2, 1)
pointAt("unsorted", 2, 2)
editor.panes.sorted.surface.hooks.wheel(nil, -1)
assert(unsorted.view.scrollY == 0 and sorted.view.scrollY == 0)
pointAt("sorted", 2, 2)
editor.panes.sorted.surface.hooks.wheel(nil, 1)
assert(sorted.view.scrollY == 44)
pointAtContent(editorSize.COLUMN_X + 10, editorSize.PANEL_TOP + 10)
editor.panes.sorted.surface.hooks.release()
assert(saved() == before and editor.drag == nil)
wheel("sorted", -1)

-- A label stays in the sorted grid: dropped on Unsorted it does not move
press("sorted", 3, 0)
assert(editor.drag ~= nil and editor.drag.kind == "label")
pointAt("unsorted", 3, 1)
editor.panes.sorted.surface.hooks.release()
assert(saved() == before and editor.centerLabels[1].row == 0)
-- New label released over Unsorted asks for nothing
local left, top = Geometry.absolutePosition(editor.content)
host.mouse = { x = left + editorSize.CENTER_X + editorSize.LABEL_BUTTON_X + 10,
    y = top + editorSize.PANEL_TOP + editorSize.FOOTER_Y + 10 }
editor.labelDragSurface.hooks.click(nil, 10, 10)
pointAt("unsorted", 3, 1)
editor.labelDragSurface.hooks.release()
assert(app.windows.textPrompt == nil and saved() == before)

-- A search result dropped on Unsorted joins it; again, as a copy, still in Unsorted
editor.itemSearch.root.hooks.contentchanged(nil, "change", "rune axe")
assert(#editor.searchResults == 1 and editor.searchResults[1].objectId == 3001)
local function dragResult(toPane, column, row)
    local searchLeft, searchTop = Geometry.absolutePosition(editor.content)
    host.mouse = { x = searchLeft + editorSize.RIGHT_X + 20, y = searchTop + editorSize.PANEL_TOP + editorSize.SEARCH_LIST_TOP + 10 }
    editor.searchDragSurface.hooks.click(nil, 12, 10)
    pointAt(toPane, column, row)
    editor.searchDragSurface.hooks.release()
end
dragResult("unsorted", 0, 0)
assert(gear().unsorted[#gear().unsorted].layoutKey == key(3001, 1) and changes == 3)
dragResult("unsorted", 4, 2)
assert(gear().unsorted[#gear().unsorted].layoutKey == key(3001, 2) and changes == 4)
assert(gear().unsorted[#gear().unsorted].sourceLayoutKey == key(3001, 1))
assert(gear().rows[2].slots[51].kind == "blank", "the copy left no item in the sorted rows")
-- Dropped on a sorted cell, it lands there: here the empty row after the layout
wheel("sorted", 10)
dragResult("sorted", 2, 11)
assert(gear().rows[3].slots[3].layoutKey == key(3001, 3) and gear().rows[3].slots[1].kind == "blank")
assert(gear().rows[2].slots[51].kind == "blank" and changes == 5)
assert(editor.selectedLayoutKey == key(3001, 3) and outlines() == 1)
-- The sorted grid grows a new drop row and keeps its scroll
assert(sorted.view.content.height == 4 + 13 * 44 and sorted.view.scrollY == 4 + 12 * 44 - sorted.height)

-- Another tag starts both grids at the top; its empty Unsorted still shows four rows
wheel("unsorted", 1)
assert(sorted.view.scrollY > 0 and unsorted.view.scrollY == 44)
editor.tagList.list:Click("food")
assert(sorted.view.scrollY == 0 and unsorted.view.scrollY == 0)
assert(#unsorted.slots == 0 and unsorted.view.content.height == unsorted.height)
local cells = 0
for _, node in ipairs(unsorted.view.content.children) do
    if not node.destroyed and node.spriteID ~= nil then cells = cells + 1 end
end
assert(cells == 4 * editorSize.CENTER_COLUMNS)
-- A drop on that empty Unsorted adds the result there
dragResult("unsorted", 0, 0)
assert(store.data.tags.food.unsorted[1].layoutKey == key(3001, 1) and #store.data.tags.food.rows == 0)

-- Reopening builds fresh grids at the top; closing destroys both
editor.tagList.list:Click("gear")
app.windows:OpenLayoutEditor("gear")
local reopened = app.windows.layoutEditor
assert(reopened ~= editor and editor.window == nil and editor.panes == nil)
assert(reopened.panes.sorted.view.scrollY == 0 and #reopened.panes.unsorted.slots == 47)
local reopenedPanes = reopened.panes
reopened.columnButtons[3].root.hooks.pressed()
assert(app.windows.layoutEditor == nil and reopened.panes == nil)
for _, pane in pairs(reopenedPanes) do
    assert(pane.view.destroyed and pane.surface.destroyed)
end

print("layout_editor_panes_test: ok")
