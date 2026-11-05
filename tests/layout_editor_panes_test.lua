package.path = "./?.lua;./?/init.lua;" .. package.path
local BankGrid = require("banktags/ui/bank_grid")

-- Check independent Search, Layout, and Unsorted panes
-- FAKE HOST: stand-in components, pointer, and scrolling

local Harness = require("tools/test_support/tags_harness")
local Geometry = require("banktags/ui/geometry")
local Json = require("banktags/core/json")
local h = Harness.new("layout_editor_panes")
local host = h.bankHost
host:SetItems({ { 3001, 1, "Rune axe" }, { 3002, 1, "Rune sword" }, { 3003, 1, "Rune helm" },
    { 3004, 1, "Rune boots" } })
host.itemLayer.interfaceID = 517
h:LoadCore()
h:LoadTags()
local app = h:App()
h:OpenBank()
h:Tick(12)

local store = app.store
-- Find the saved key for an item
local function key(objectID)
    for _, slot in ipairs(store:GetTaggedItems("gear")) do
        if slot.objectID == objectID then return slot.layoutKey end
    end
    return nil
end
-- Sorted: a label, then 195 items wrapping onto twenty rows, with one blank
-- Unsorted: 135 items, packed into four-column rows
assert(store:CreateTag("gear") and store:CreateTag("food"))
store:SetLayoutPlacement(false)
for objectID = 1001, 1195 do assert(store:AddTag("gear", objectID)) end
assert(store:InsertLabel("gear", 0, "Weapons", 10))
assert(store:RemoveTag("gear", key(1045)))
store:SetLayoutPlacement(true)
for objectID = 2001, 2135 do assert(store:AddTag("gear", objectID)) end
app:Changed()
h:Tick(2)
app.windows:OpenLayoutEditor("gear")
local editor = app.windows.layoutEditor
local editorSize = h:TagsModule("banktags/windows/layout_editor_parts").size
local editorTheme = h:TagsModule("banktags/ui/theme")
local changes = 0
local onChanged = editor.onChanged
editor.onChanged = function(tag)
    changes = changes + 1
    onChanged(tag)
end
editor.window.tooltipContext = { position = function()
    return Geometry.absolutePosition(editor.content)
end }
-- Each save replaces the data, so read the tag fresh
local function gear() return store.data.tags.gear end
local sorted, unsorted = editor.panes.sorted, editor.panes.unsorted

-- Point at a pane cell through its scroll
local function pointAt(paneName, column, row)
    local pane = editor.panes[paneName]
    local x, y = pane.gridLeft + column * 44 + 20, BankGrid.RowItemY(row, pane.labels) + 20 - pane.view.scrollY
    assert(column < pane.columns, "column " .. column .. " is past " .. paneName)
    assert(y >= 0 and y < pane.height, "row " .. row .. " is scrolled out of " .. paneName)
    local left, top = Geometry.absolutePosition(editor.content)
    h:PointEditor(pane.x + x, pane.y + y)
    return x, y
end
-- Point at an editor content point outside the grids
local function pointAtContent(x, y)
    local left, top = Geometry.absolutePosition(editor.content)
    h:PointEditor(x, y)
end
-- Press the chosen grid cell
local function press(paneName, column, row)
    h:PressEditor(editor.panes[paneName].surface, pointAt(paneName, column, row))
    assert(editor.drag ~= nil or editor.selectedLayoutKey == nil)
end
-- Drag between the chosen grid cells
local function drag(fromPane, fromColumn, fromRow, toPane, toColumn, toRow)
    local surface = editor.panes[fromPane].surface
    press(fromPane, fromColumn, fromRow)
    if type(toPane) == "string" then pointAt(toPane, toColumn, toRow) else pointAtContent(toPane, toColumn) end
    h:ReleaseEditor()
end
-- Select a tag through the native rail
local function openTag(tag) assert(editor.tagTabs:Select(tag, true)) end
-- Scroll the chosen pane with the wheel
local function wheel(paneName, delta) editor.panes[paneName].surface.hooks.wheel(nil, delta) end
-- Encode the current tag data for comparison
local function saved() return Json.encode(store.data) end
-- Count the gold outlines drawn on either grid
local function outlines()
    local count = 0
    for _, pane in pairs(editor.panes) do
        for _, mark in ipairs(pane.outlines) do
            if not mark.hidden and not mark.destroyed then count = count + 1 end
        end
    end
    return count
end
-- Find an item in the Unsorted list
local function unsortedIndex(layoutKey)
    for index, slot in ipairs(gear().unsorted) do
        if slot.layoutKey == layoutKey then return index end
    end
    return nil
end
-- Count the grid cells drawn in a pane
local function cells(pane)
    local count = 0
    for _, node in ipairs(pane.cells.children) do
        if not node.destroyed and node.spriteID ~= nil and node.associatedObjectID == nil then
            count = count + 1
        end
    end
    return count
end

-- Rail, Search, Layout, and Unsorted reuse the existing bank footprint
assert(editor.unsortedPanel.x < editor.centerPanel.x and editor.centerPanel.x < editor.searchPanel.x)
assert(editor.tagTabs.root.x >= editor.centerPanel.x and sorted.columns == 10 and unsorted.columns == 5)
assert(editor.unsortedPanel.width == 252 and editor.centerPanel.width == 474 and editor.searchPanel.width == 232)
assert(editor.tabs == nil and editor.chooser == nil)
assert(sorted.x == editorSize.CENTER_X + 4 and sorted.y == editorSize.VIEW_Y)
assert(unsorted.x == editorSize.UNSORTED_X + 4 and sorted.y == unsorted.y)
assert(sorted.height == editorSize.AREA_HEIGHT - 8 and sorted.width == editorSize.CENTER_WIDTH - 8)
assert(sorted.view.root.parent == editor.centerPanel and unsorted.view.root.parent == editor.unsortedPanel)
assert(editor.itemSearch.root.parent == editor.searchPanel and editor.searchList.root.parent == editor.searchPanel)
assert(editor.searchList.root.y == editorSize.SEARCH_LIST_TOP)
assert(editor.itemSearch.root.y == 8 and editor.itemSearch.root.x == 8)
assert(editor.searchList.root.x == 8 and editor.searchList.root.width == editorSize.SEARCH_WIDTH - 16)
assert(editor.searchList.root.y == editor.itemSearch.root.y + editorSize.SEARCH_FIELD_HEIGHT + 8)
assert(editor.searchList.root.y + editor.searchList.root.height == editorSize.COLUMN_HEIGHT - 8)
assert(Harness.Find(editor.searchPanel, "Search") == nil and editor.searchHint.hidden)
assert(not editor.searchDragSurface.hidden and not unsorted.surface.hidden and not unsorted.hidden)
assert(editorSize.GRID_LEFT + 9 * 44 + 40 <= sorted.width - editorSize.SCROLLBAR_RESERVE)
assert(editorSize.GRID_LEFT + 3 * 44 + 40 <= unsorted.width - editorSize.SCROLLBAR_RESERVE)
assert(editor.tagTabs:GetSelectedID() == "gear" and editor.tagTitle == nil)
assert(editor.status.parent == editor.content and editor.status.y == editor.copyButton.y)
assert(editor.status.x >= editor.newLabelButton.x + editor.newLabelButton.width)
assert(editor.status.x + editor.status.width < editor.closeButton.x)
assert(editor.copyButton.x == editorSize.UNSORTED_X)
assert(editor.unsortButton.x == editorSize.CENTER_X + editorSize.VIEW_INSET)
assert(editor.closeButton.x + editor.closeButton.width == editorSize.WIDTH - editorSize.RIGHT_MARGIN)
assert(editor.unsortedTitle.content == "Unsorted (135)")
-- Wider banks add columns to Layout; taller banks grow every view
local Parts = h:TagsModule("banktags/windows/layout_editor_parts")
local view, searchHeight, centerWidth, trayWidth = editorSize.VIEW_HEIGHT, editorSize.SEARCH_LIST_HEIGHT,
    editorSize.CENTER_WIDTH, editorSize.UNSORTED_WIDTH
Parts.SizeToBank(13, editorSize.DEFAULT_WIDTH + 132, editorSize.DEFAULT_HEIGHT + 88)
assert(editorSize.CENTER_WIDTH == centerWidth + 132 and editorSize.UNSORTED_WIDTH == trayWidth)
assert(editorSize.VIEW_HEIGHT == view + 88 and editorSize.SEARCH_LIST_HEIGHT == searchHeight + 88)
assert(editorSize.UNSORTED_COLUMNS == 5)
Parts.SizeToBank(editor.columns, editor.bounds.width, editor.bounds.height)
assert(#sorted.slots == 210 and #unsorted.slots == 135 and editor.layout.labels[1].row == 0)
local unsortedRows = math.ceil(135 / unsorted.columns)
assert(sorted.view.content.height == BankGrid.RowItemY(22, sorted.labels) and unsorted.view.content.height == 4 + unsortedRows * 44)
assert(cells(unsorted) == unsortedRows * unsorted.columns and unsorted.slots[135].layoutKey == key(2135))
assert(unsorted.view.scrollbarVisible)
local gridWidth = (unsorted.columns - 1) * editorSize.GRID_STEP + editorSize.GRID_SLOT_SIZE
assert(unsorted.columns == 5 and gridWidth == 216 and unsorted.gridLeft + gridWidth <= unsorted.view.contentWidth,
    "all five Unsorted columns must fit before the scrollbar")
assert(math.abs(unsorted.gridLeft - (unsorted.view.contentWidth - unsorted.gridLeft - gridWidth)) <= 1)
assert(sorted.slots[55].kind == "blank" and gear().rows[2].slots[45].kind == "blank")

-- Each wheel scrolls only its own grid, clamped to that grid's content
local unsortedMost = 4 + unsortedRows * 44 - unsorted.height
wheel("unsorted", 1)
assert(unsorted.view.scrollY == 44 and sorted.view.scrollY == 0)
wheel("unsorted", 100)
assert(unsorted.view.scrollY == unsortedMost, "Unsorted stops at its last row")
wheel("unsorted", -1)
assert(unsorted.view.scrollY == unsortedMost - 44)
wheel("sorted", 3)
assert(sorted.view.scrollY == 132)
wheel("sorted", 30)
assert(sorted.view.scrollY == BankGrid.RowItemY(22, sorted.labels) - sorted.height)
wheel("sorted", -30)
wheel("sorted", 3)
assert(sorted.view.scrollY == 132 and unsorted.view.scrollY == unsortedMost - 44)

-- Drop Unsorted item 2103 into the scrolled layout
-- Use Unsorted cell (2, 25) and Layout cell (4, 5)
drag("unsorted", 102 % unsorted.columns, 102 // unsorted.columns, "sorted", 4, 5)
assert(gear().rows[2].slots[45].layoutKey == key(2103) and unsortedIndex(key(2103)) == nil)
assert(#gear().unsorted == 134 and key(2103) ~= nil and changes == 1)
assert(sorted.slots[55].layoutKey == key(2103) and editor.selectedLayoutKey == key(2103) and outlines() == 1)
-- Its neighbours, the label, and the scroll of each grid are unchanged
assert(gear().rows[1].kind == "label" and gear().rows[1].text == "Weapons")
assert(gear().rows[2].slots[44].layoutKey == key(1044) and gear().rows[2].slots[46].layoutKey == key(1046))
assert(sorted.view.scrollY == 132 and unsorted.view.scrollY == unsortedMost - 44)

-- A sorted item dropped on Unsorted leaves a blank and joins the end of Unsorted
-- Sorted row 6, column 0 is item 1051
drag("sorted", 0, 6, "unsorted", 3, 19)
assert(gear().rows[2].slots[51].kind == "blank" and unsortedIndex(key(1051)) == 135)
assert(key(1051) ~= nil and changes == 2 and editor.selectedLayoutKey == key(1051))
assert(unsorted.slots[135].layoutKey == key(1051) and outlines() == 1)
assert(sorted.view.scrollY == 132 and unsorted.view.scrollY == unsortedMost - 44)

-- Unsorted has no order to edit, so a drag within it only selects
local before = saved()
drag("unsorted", 0, 18, "unsorted", 3, 19)
assert(saved() == before and changes == 2 and editor.selectedLayoutKey == gear().unsorted[18 * unsorted.columns + 1].layoutKey)

-- Drops on headings, footer actions, or a label change nothing
drag("sorted", 1, 6, editorSize.SEARCH_X + 10, editorSize.PANEL_TOP + 10)
drag("sorted", 1, 6, editorSize.CENTER_X + 10, editorSize.PANEL_TOP + 10)
drag("sorted", 1, 6, editorSize.UNSORTED_X + 20, editorSize.PANEL_TOP + 10)
drag("unsorted", 1, 18, editorSize.UNSORTED_X + 20, editorSize.PANEL_TOP + editorSize.ACTIONS_Y + 10)
wheel("sorted", -10)
drag("unsorted", 1, 18, "sorted", 3, 0)
assert(saved() == before and changes == 2 and editor.drag == nil)
assert(sorted.view.scrollY == 0 and unsorted.view.scrollY == unsortedMost - 44)

-- A wheel turned mid-drag scrolls the grid under the pointer
press("sorted", 2, 1)
pointAt("unsorted", 2, 19)
editor.panes.sorted.surface.hooks.wheel(nil, -1)
assert(unsorted.view.scrollY == unsortedMost - 88 and sorted.view.scrollY == 0)
pointAt("sorted", 2, 2)
editor.panes.sorted.surface.hooks.wheel(nil, 1)
assert(sorted.view.scrollY == 44)
pointAtContent(editorSize.CENTER_X + 10, editorSize.PANEL_TOP + 10)
h:ReleaseEditor()
assert(saved() == before and editor.drag == nil)
wheel("sorted", -1)

-- A label stays in the sorted grid: dropped on Unsorted it does not move
press("sorted", 3, 0)
assert(editor.drag ~= nil and editor.drag.kind == "label")
pointAt("unsorted", 3, 18)
h:ReleaseEditor()
assert(saved() == before and editor.layout.labels[1].row == 0)
-- New label is a plain button with no drag surface over it
assert(editor.labelDragSurface == nil and editor.newLabelButton.root.hooks.click == nil)

-- Search is always available and leaves Unsorted's scroll and selection alone
local unsortedScroll = unsorted.view.scrollY
assert(not unsorted.hidden and not unsorted.surface.hidden and not editor.searchDragSurface.hidden)
editor.itemSearch:SetText("rune", true)
assert(#editor.searchResults == 4 and unsorted.view.scrollY == unsortedScroll)

-- A scrolled result list drags the row under the press
local resultsTop = editorSize.PANEL_TOP + editorSize.SEARCH_LIST_TOP
-- Begin dragging a visible search result
local function pressResult(listY)
    pointAtContent(editorSize.SEARCH_X + editorSize.SEARCH_INSET + 16, resultsTop + listY)
    h:PressEditor(editor.searchDragSurface, 16, listY)
end
-- Scroll the sorted grid to its drop row first
wheel("sorted", 30)
assert(sorted.view.scrollY == BankGrid.RowItemY(22, sorted.labels) - sorted.height)
editor.searchList.scrollY = 64
pressResult(10)
assert(editor.drag.kind == "search" and editor.drag.result == editor.searchResults[3])
assert(editor.drag.ghost.x == editorSize.SEARCH_X + editorSize.SEARCH_INSET + 16 - 18 and editor.drag.ghost.y == resultsTop + 10 - 16)
local third = editor.searchResults[3].objectId
-- Dropped on the scrolled sorted grid's drop row, it lands in that cell
pointAt("sorted", 2, 21)
h:ReleaseEditor()
local placed = sorted.slots[21 * 10 + 3]
assert(placed.objectID == third and changes == 3)
assert(editor.selectedLayoutKey == placed.layoutKey and outlines() == 1)
-- The sorted grid grows a new drop row and keeps its scroll
assert(sorted.view.content.height == BankGrid.RowItemY(23, sorted.labels) and sorted.view.scrollY == BankGrid.RowItemY(22, sorted.labels) - sorted.height)
-- Search results add only into Layout, not into Unsorted
before = saved()
pressResult(10)
pointAtContent(editorSize.UNSORTED_X + 40, editorSize.PANEL_TOP + editorSize.TAB_HEADER + 100)
h:ReleaseEditor()
assert(saved() == before and editor.drag == nil)
-- A sorted item dropped on the Search list stays where it was
wheel("sorted", -30)
drag("sorted", 1, 6, editorSize.SEARCH_X + 40, resultsTop + 20)
assert(saved() == before and gear().rows[2].slots[52].layoutKey == key(1052))
-- Move to Unsorted works while Search remains available
press("sorted", 1, 6)
h:ReleaseEditor()
editor.unsortButton.root.hooks.pressed()
assert(unsortedIndex(key(1052)) == #gear().unsorted and gear().rows[2].slots[52].kind == "blank" and changes == 4)

-- Explicit cancellation releases capture without hiding either source
press("sorted", 2, 1)
local ghost = editor.drag.ghost
editor:CancelDrag()
assert(editor.drag == nil and ghost.destroyed and editor.surfaceClips[sorted.surface].x == sorted.x)
assert(unsorted.view.scrollY == unsortedScroll and not unsorted.hidden and not editor.searchDragSurface.hidden)
pressResult(10)
ghost = editor.drag.ghost
editor:CancelDrag()
assert(editor.drag == nil and ghost.destroyed)
local searchClip = editor.surfaceClips[editor.searchDragSurface]
assert(searchClip.x == editorSize.SEARCH_X + editorSize.SEARCH_INSET and searchClip.y == resultsTop)
assert(editor.itemSearch.text == "rune" and editor.searchList.scrollY == 64)

-- A dragged label shades its drop row; dropped inside the wrapped row it starts, it stays put
press("sorted", 3, 0)
pointAt("sorted", 0, 7)
sorted.surface.hooks.hold(sorted.surface, sorted.x + editorSize.GRID_LEFT + 20, sorted.y + BankGrid.RowItemY(7, sorted.labels) + 20)
assert(editor.drag.kind == "label" and not editor.drag.highlight.hidden)
assert(editor.drag.highlight.y == BankGrid.RowItemY(7, sorted.labels))
local moves = changes
h:ReleaseEditor()
-- The store keeps a label at the start of the run of items holding that row
assert(editor.layout.labels[1].row == 0 and editor.layout.labels[1].text == "Weapons" and changes == moves)
local sortedClip = editor.surfaceClips[sorted.surface]
assert(sortedClip.x == sorted.x and sortedClip.y == sorted.y and editor.drag == nil)
-- Dropped back on its own row, it opens the prompt to rename it
press("sorted", 3, 0)
h:ReleaseEditor()
local prompt = app.windows.textPrompt
assert(prompt ~= nil and prompt.field.text == "Weapons")
prompt.field:SetText("Arms")
Harness.Click(prompt.window.content, "Save")
assert(editor.layout.labels[1].row == 0 and editor.layout.labels[1].text == "Arms" and changes == moves + 1)

-- Another tag resets both grids and cancels capture without clearing Search
wheel("unsorted", 1)
wheel("sorted", 1)
pressResult(10)
local pendingGhost = editor.drag.ghost
openTag("food")
assert(editor.drag == nil and pendingGhost.destroyed)
assert(sorted.view.scrollY == 0 and unsorted.view.scrollY == 0)
assert(editor.itemSearch.text == "rune" and not editor.searchDragSurface.hidden and not unsorted.surface.hidden)
assert(#unsorted.slots == 0 and cells(unsorted) == 0 and not unsorted.view.scrollbarVisible)
assert(editor.unsortedTitle.content == "Unsorted (0)")
wheel("unsorted", 1)
assert(unsorted.view.scrollY == 0)
-- A partial row stays compact and centered, with no excess scrolling
assert(store:AddTag("food", 3001) and store:AddTag("food", 3002))
app:Changed()
assert(#unsorted.slots == 2 and cells(unsorted) == unsorted.columns)
assert(not unsorted.view.scrollbarVisible and unsorted.view.content.height == unsorted.height)
assert(math.abs(unsorted.gridLeft - (unsorted.view.contentWidth - unsorted.gridLeft - gridWidth)) <= 1)
assert(unsorted.sprites[1].x == unsorted.gridLeft + 2)
pointAt("unsorted", 0, 0)
press("unsorted", 0, 0)
h:ReleaseEditor()
assert(editor.selectedLayoutKey == unsorted.slots[1].layoutKey)
assert(unsorted.outlines[1].x == unsorted.gridLeft)
wheel("unsorted", 10)
assert(unsorted.view.scrollY == 0)

-- Reopening releases all three scroll areas, capture surfaces, and the rail
openTag("gear")
local oldPanes, oldRail, oldSearch = editor.panes, editor.tagTabs, editor.searchList
app.windows:OpenLayoutEditor("gear")
local reopened = app.windows.layoutEditor
assert(reopened ~= editor and editor.window == nil and editor.panes == nil and oldRail.root == nil)
assert(oldSearch.destroyed and reopened.itemSearch.text == "")
for _, pane in pairs(oldPanes) do assert(pane.view.destroyed and pane.surface.destroyed) end
assert(not reopened.searchDragSurface.hidden and not reopened.panes.unsorted.surface.hidden)
assert(reopened.panes.sorted.view.scrollY == 0 and #reopened.panes.unsorted.slots == 136)
local reopenedPanes, rail, searchSurface = reopened.panes, reopened.tagTabs, reopened.searchDragSurface
reopened.window:Close()
assert(app.windows.layoutEditor == nil and reopened.panes == nil and rail.root == nil and searchSurface.destroyed)
for _, pane in pairs(reopenedPanes) do assert(pane.view.destroyed and pane.surface.destroyed) end

print("layout_editor_panes_test: ok")
