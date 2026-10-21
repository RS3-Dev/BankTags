package.path = "./?.lua;./?/init.lua;" .. package.path

-- Move items between the layout editor's sorted grid and the right column's tabs
-- The sorted grid fills the center; Unsorted and Search share the right column
-- Each grid scrolls on its own; drops count the scroll of both
-- FAKE HOST: stand-in components, pointer, and scroll views, not the game client

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

local key = require("banktags/tags/item_identity").LayoutKey
local store = app.store
-- Sorted: a label, then 195 items wrapping onto twenty rows, with one blank
-- Unsorted: 135 items, fifteen rows at nine columns
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
    assert(column < pane.columns, "column " .. column .. " is past " .. paneName)
    assert(y >= 0 and y < pane.height, "row " .. row .. " is scrolled out of " .. paneName)
    local left, top = Geometry.absolutePosition(editor.content)
    host.mouse = { x = left + pane.x + x, y = top + pane.y + y }
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
-- Press a tag's button in the tag rail
local function openTag(tag)
    for _, button in ipairs(editor.tagRail.buttons) do
        if button.tagID == tag then return button.root.hooks.pressed() end
    end
    error("no rail button for " .. tag)
end
local function wheel(paneName, delta) editor.panes[paneName].surface.hooks.wheel(nil, delta) end
-- Click a right tab's header, as PrettyUI's Tabs hears it
local TAB_INDEX = { unsorted = 1, search = 2 }
local function showTab(name) editor.tabs:GetTab(TAB_INDEX[name]).hit.hooks.click() end
local function page(name) return editor.tabs:GetPage(TAB_INDEX[name]) end
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
-- Count the grid cells drawn in a pane
local function cells(pane)
    local count = 0
    for _, node in ipairs(pane.view.content.children) do
        if not node.destroyed and node.spriteID ~= nil and node.associatedObjectID == nil then
            count = count + 1
        end
    end
    return count
end

-- The sorted grid fills the center at Bank Core's columns, with no Unsorted heading
-- It sits beside the tag rail, under its own Layout tab
assert(editorSize.SORTED_TOP == editorSize.TAB_PAGE_Y and editorSize.CENTER_SURFACE_HEIGHT == editorSize.AREA_HEIGHT)
assert(sorted.x == editorSize.CENTER_X + 4 and sorted.y == editorSize.PANEL_TOP + editorSize.SORTED_TOP + 4)
assert(sorted.height == editorSize.AREA_HEIGHT - 8 and sorted.width == editorSize.CENTER_SURFACE_WIDTH - 8)
-- The rail and both columns start right under the title bar
assert(editorSize.PANEL_TOP == 6 and editor.centerPanel.y == 6 and editor.rightPanel.y == 6)
local rail = editor.tagRail.root
assert(rail.x == editorSize.RAIL_X and rail.y == editorSize.PANEL_TOP and rail.height == editorSize.PANEL_HEIGHT)
assert(rail.x + rail.width + editorSize.RAIL_GAP == editorSize.CENTER_X and editorSize.CENTER_X == 48)
-- A single PrettyUI Layout tab heads the sorted grid, the open tag named beside it
local layoutTabs = editor.layoutTabs
assert(layoutTabs.root.parent == editor.centerPanel and #layoutTabs.tabs == 1 and layoutTabs:GetTab(1).text == "Layout")
assert(sorted.view.root.parent == layoutTabs:GetPage(1).content)
assert(editor.tagName.parent == editor.centerPanel and editor.tagName.x == editorSize.TAG_NAME_X)
assert(editor.tagName.y + editor.tagName.height <= editorSize.TAB_PAGE_Y)
assert(editor.tagTitle == nil and editor.editTagButton == nil and Harness.Find(editor.content, "Rename") == nil)
assert(editor.exitButton == nil and Harness.Find(editor.content, "Exit edit mode") == nil)
-- Both headers share their top, height, and width with their item area
for _, tabs in ipairs({ layoutTabs, editor.tabs }) do
    assert(tabs.root.x == 0 and tabs.root.y == editorSize.TAB_Y)
    assert(tabs.root.height == editorSize.TAB_HEADER + editorSize.AREA_HEIGHT)
end
assert(layoutTabs.root.width == editorSize.CENTER_SURFACE_WIDTH and editor.tabs.root.width == editorSize.RIGHT_WIDTH)
-- Shortcuts, the saved note, and the drag help moved into tooltips
assert(editor.footerNotes == nil and editor.actionsHelp == nil)
assert(Harness.Find(editor.content, "Saved automatically") == nil)
-- The window keeps its width; the right column takes the rest of it
assert(editorSize.WIDTH == editorSize.DEFAULT_WIDTH and editorSize.CENTER_WIDTH == editorSize.DEFAULT_CENTER_WIDTH)
assert(editorSize.RIGHT_X == editorSize.CENTER_X + editorSize.CENTER_WIDTH)
assert(editorSize.RIGHT_X + editorSize.RIGHT_WIDTH + editorSize.RIGHT_MARGIN == editorSize.WIDTH)
assert(sorted.columns == editorSize.CENTER_COLUMNS and sorted.columns == 10)
assert(Harness.Find(editor.centerPanel, "Unsorted") == nil)
assert(Harness.Find(editor.centerPanel, "Create Copy") == nil and Harness.Find(editor.rightPanel, "New label") == nil)
-- Unsorted fills the right column, at nine columns of its own
assert(unsorted.x == editorSize.RIGHT_X + 4 and unsorted.width == editorSize.RIGHT_WIDTH - 8)
assert(unsorted.y == editorSize.PANEL_TOP + editorSize.TAB_PAGE_Y + 4 and unsorted.columns == 9)
local itemWidth = unsorted.width - editorSize.SCROLLBAR_RESERVE - editorSize.GRID_LEFT
assert(9 * 44 - 4 <= itemWidth and 10 * 44 - 4 > itemWidth, "nine columns fit beside the scrollbar")
-- Sorted and Unsorted share their top, bottom, and inset
assert(sorted.y == unsorted.y and sorted.height == unsorted.height)
assert(unsorted.y + unsorted.height + 4 + editorSize.AREA_BOTTOM == editorSize.PANEL_TOP + editorSize.COLUMN_HEIGHT)
assert(editorSize.COLUMN_HEIGHT + editorSize.ACTIONS_GAP == editorSize.ACTIONS_Y)
-- The freed band under the title bar goes to the grids; the actions stay put
assert(editorSize.PANEL_TOP + editorSize.ACTIONS_Y == 578 and sorted.height == 506)
-- Each item area has one outer frame and no outline inside it
local function frames(parent)
    local edges = 0
    for _, node in ipairs(parent.children) do
        if not node.destroyed and node.rgba == editorTheme.FRAME and (node.width == 1 or node.height == 1) then
            edges = edges + 1
        end
    end
    return edges
end
assert(frames(page("unsorted").content) == 4 and frames(page("search").content) == 4)
assert(frames(layoutTabs:GetPage(1).content) == 4 and frames(editor.rightPanel) == 0)
-- One row of four equal actions spans both columns, from the rail's gap to the right edge
local actions = { editor.duplicateButton, editor.removeButton, editor.unsortButton, editor.newLabelButton }
for index, button in ipairs(actions) do
    assert(button.parent == editor.content and button.y == editorSize.PANEL_TOP + editorSize.ACTIONS_Y)
    assert(button.y + button.height == editorSize.PANEL_TOP + editorSize.PANEL_HEIGHT)
    assert(math.abs(button.width - actions[1].width) <= 3)
    if index > 1 then assert(button.x == actions[index - 1].x + actions[index - 1].width + editorSize.BUTTON_GAP) end
end
assert(actions[1].x == editorSize.CENTER_X and actions[4].x + actions[4].width == editorSize.WIDTH - editorSize.RIGHT_MARGIN)
assert(editor.unsortButton.width >= 140, "Move to Unsorted keeps the width its label fit")
assert(editor.newLabelButton.x == editorSize.LABEL_BUTTON_X and editor.newLabelButton.y == editorSize.LABEL_BUTTON_Y)
assert(editor.unsortButton.tooltipText ~= nil and string.find(editor.unsortButton.tooltipText, "Unsorted", 1, true) ~= nil)
-- The Search list ends where Unsorted does
assert(editorSize.SEARCH_LIST_TOP + editorSize.SEARCH_LIST_HEIGHT == editorSize.TAB_PAGE_Y + 4 + editorSize.UNSORTED_VIEW_HEIGHT)
-- A taller bank grows the sorted grid and both tabs, keeping the actions at the bottom
do
    local Parts = h:TagsModule("banktags/windows/layout_editor_parts")
    local before = { sorted = editorSize.SORTED_VIEW_HEIGHT, unsorted = editorSize.UNSORTED_VIEW_HEIGHT,
        search = editorSize.SEARCH_LIST_HEIGHT, actions = editorSize.ACTIONS_Y }
    Parts.SizeToBank(editorSize.CENTER_COLUMNS, editor.bounds.width, editorSize.HEIGHT + 88)
    assert(editorSize.SORTED_VIEW_HEIGHT == before.sorted + 88 and editorSize.UNSORTED_VIEW_HEIGHT == before.unsorted + 88)
    assert(editorSize.SEARCH_LIST_HEIGHT == before.search + 88 and editorSize.ACTIONS_Y == before.actions + 88)
    assert(editorSize.UNSORTED_COLUMNS == 9)
    Parts.SizeToBank(editor.columns, editor.bounds.width, editor.bounds.height)
end
-- The label, twenty item rows, and an empty drop row; Unsorted packs fifteen rows of nine
assert(#sorted.slots == 210 and #unsorted.slots == 135 and editor.centerLabels[1].row == 0)
assert(sorted.view.content.height == 4 + 22 * 44 and unsorted.view.content.height == 4 + 15 * 44)
assert(cells(unsorted) == 15 * 9 and unsorted.slots[135].layoutKey == key(2135))
assert(sorted.slots[55].kind == "blank" and gear().rows[2].slots[45].kind == "blank")

-- Unsorted shows first; Search's page and input are hidden
-- Both are PrettyUI tabs in the right column, their pages under the header
assert(editor.tabs.root.parent == editor.rightPanel and editor.tabs.root.y == editorSize.TAB_Y)
assert(editor.tabs:GetTab(1).text == "Unsorted" and editor.tabs:GetTab(2).text == "Search")
assert(editor.rightTab == "unsorted" and editor.tabs:GetActiveIndex() == 1)
assert(not page("unsorted").root.hidden and page("search").root.hidden)
assert(editor.searchDragSurface.hidden and not unsorted.surface.hidden)
assert(editor.itemSearch.root.parent == page("search").content and unsorted.view.root.parent == page("unsorted").content)
assert(editor.itemSearch.root.y == 4 and editor.searchList.root.y == editorSize.SEARCH_LIST_TOP - editorSize.TAB_PAGE_Y)
assert(editor.itemSearch.root.x == 4 and editor.searchList.root.x == 4)

-- Each wheel scrolls only its own grid, clamped to that grid's content
local unsortedMost = 4 + 15 * 44 - unsorted.height
wheel("unsorted", 1)
assert(unsorted.view.scrollY == 44 and sorted.view.scrollY == 0)
wheel("unsorted", 5)
assert(unsorted.view.scrollY == unsortedMost, "Unsorted stops at its last row")
wheel("unsorted", -1)
assert(unsorted.view.scrollY == unsortedMost - 44)
wheel("sorted", 3)
assert(sorted.view.scrollY == 132)
wheel("sorted", 30)
assert(sorted.view.scrollY == 4 + 22 * 44 - sorted.height)
wheel("sorted", -30)
wheel("sorted", 3)
assert(sorted.view.scrollY == 132 and unsorted.view.scrollY == unsortedMost - 44)

-- With both scrolled, an Unsorted item drops into the exact sorted cell
-- Unsorted row 10, column 2 is item 2093; sorted row 5, column 4 is the blank
drag("unsorted", 2, 10, "sorted", 4, 5)
assert(gear().rows[2].slots[45].layoutKey == key(2093) and unsortedIndex(key(2093)) == nil)
assert(#gear().unsorted == 134 and store:HasTag("gear", key(2093)) and changes == 1)
assert(sorted.slots[55].layoutKey == key(2093) and editor.selectedLayoutKey == key(2093) and outlines() == 1)
-- Its neighbours, the label, and the scroll of each grid are unchanged
assert(gear().rows[1].kind == "label" and gear().rows[1].text == "Weapons")
assert(gear().rows[2].slots[44].layoutKey == key(1044) and gear().rows[2].slots[46].layoutKey == key(1046))
assert(sorted.view.scrollY == 132 and unsorted.view.scrollY == unsortedMost - 44)

-- A sorted item dropped on Unsorted leaves a blank and joins the end of Unsorted
-- Sorted row 6, column 0 is item 1051
drag("sorted", 0, 6, "unsorted", 3, 4)
assert(gear().rows[2].slots[51].kind == "blank" and unsortedIndex(key(1051)) == 135)
assert(store:HasTag("gear", key(1051)) and changes == 2 and editor.selectedLayoutKey == key(1051))
assert(unsorted.slots[135].layoutKey == key(1051) and outlines() == 1)
assert(sorted.view.scrollY == 132 and unsorted.view.scrollY == unsortedMost - 44)

-- Unsorted has no order to edit, so a drag within it only selects
local before = saved()
drag("unsorted", 0, 3, "unsorted", 3, 5)
assert(saved() == before and changes == 2 and editor.selectedLayoutKey == gear().unsorted[28].layoutKey)

-- Drops on the tag rail, the top band, the tabs, the actions, or a label change nothing
drag("sorted", 1, 6, editorSize.RAIL_X + 10, editorSize.PANEL_TOP + 10)
drag("sorted", 1, 6, editorSize.CENTER_X + 10, editorSize.PANEL_TOP + 10)
drag("sorted", 1, 6, editorSize.RIGHT_X + 20, editorSize.PANEL_TOP + editorSize.TAB_Y + 10)
drag("unsorted", 1, 3, editorSize.RIGHT_X + 20, editorSize.PANEL_TOP + editorSize.ACTIONS_Y + 10)
wheel("sorted", -10)
drag("unsorted", 1, 3, "sorted", 3, 0)
assert(saved() == before and changes == 2 and editor.drag == nil)
assert(sorted.view.scrollY == 0 and unsorted.view.scrollY == unsortedMost - 44)

-- A wheel turned mid-drag scrolls the grid under the pointer
press("sorted", 2, 1)
pointAt("unsorted", 2, 4)
editor.panes.sorted.surface.hooks.wheel(nil, -1)
assert(unsorted.view.scrollY == unsortedMost - 88 and sorted.view.scrollY == 0)
pointAt("sorted", 2, 2)
editor.panes.sorted.surface.hooks.wheel(nil, 1)
assert(sorted.view.scrollY == 44)
pointAtContent(editorSize.CENTER_X + 10, editorSize.PANEL_TOP + 10)
editor.panes.sorted.surface.hooks.release()
assert(saved() == before and editor.drag == nil)
wheel("sorted", -1)

-- A label stays in the sorted grid: dropped on Unsorted it does not move
press("sorted", 3, 0)
assert(editor.drag ~= nil and editor.drag.kind == "label")
pointAt("unsorted", 3, 4)
editor.panes.sorted.surface.hooks.release()
assert(saved() == before and editor.centerLabels[1].row == 0)
-- New label ends the actions row; released over Unsorted it asks for nothing
local labelSurface = editor.labelDragSurface
assert(labelSurface.x == editorSize.LABEL_BUTTON_X and labelSurface.y == editorSize.LABEL_BUTTON_Y)
assert(labelSurface.width == editor.newLabelButton.width and labelSurface.height == editor.newLabelButton.height)
local function pointAtNewLabel()
    pointAtContent(editorSize.LABEL_BUTTON_X + 10, editorSize.LABEL_BUTTON_Y + 10)
end
pointAtNewLabel()
labelSurface.hooks.click(nil, 10, 10)
assert(editor.drag.kind == "label" and editor.drag.ghost.hidden, "a press may be a click")
pointAt("unsorted", 3, 4)
labelSurface.hooks.release()
assert(app.windows.textPrompt == nil and saved() == before)

-- Search shows its own page, keeping Unsorted's scroll for later
local unsortedScroll = unsorted.view.scrollY
showTab("search")
assert(editor.rightTab == "search" and editor.tabs:GetActiveIndex() == 2)
assert(page("unsorted").root.hidden and not page("search").root.hidden)
assert(unsorted.hidden and unsorted.surface.hidden and not editor.searchDragSurface.hidden)
-- The hidden Unsorted grid takes no press or wheel
unsorted.surface.hooks.click(nil, editorSize.GRID_LEFT + 20, 24)
wheel("unsorted", 1)
assert(editor.drag == nil and unsorted.view.scrollY == unsortedScroll)
editor.itemSearch.root.hooks.contentchanged(nil, "change", "rune")
assert(#editor.searchResults == 4)

-- A scrolled result list drags the row under the press
local resultsTop = editorSize.PANEL_TOP + editorSize.SEARCH_LIST_TOP
local function pressResult(listY)
    pointAtContent(editorSize.RIGHT_X + 20, resultsTop + listY)
    editor.searchDragSurface.hooks.click(nil, 12, listY)
end
-- Scroll the sorted grid to its drop row first
wheel("sorted", 30)
assert(sorted.view.scrollY == 4 + 22 * 44 - sorted.height)
editor.searchList.scrollY = 64
pressResult(10)
assert(editor.drag.kind == "search" and editor.drag.result == editor.searchResults[3])
assert(editor.drag.pointerX == editorSize.RIGHT_X + 20 and editor.drag.pointerY == resultsTop + 10)
local third = editor.searchResults[3].objectId
-- Dropped on the scrolled sorted grid's drop row, it lands in that cell
pointAt("sorted", 2, 21)
editor.searchDragSurface.hooks.release()
assert(sorted.slots[21 * 10 + 3].layoutKey == key(third, 1) and changes == 3)
assert(editor.selectedLayoutKey == key(third, 1) and outlines() == 1)
-- The sorted grid grows a new drop row and keeps its scroll
assert(sorted.view.content.height == 4 + 23 * 44 and sorted.view.scrollY == 4 + 22 * 44 - sorted.height)
-- Over the right column, where Unsorted is hidden, a result adds nothing
before = saved()
pressResult(10)
pointAtContent(editorSize.RIGHT_X + 40, editorSize.PANEL_TOP + editorSize.TAB_PAGE_Y + 100)
editor.searchDragSurface.hooks.release()
assert(saved() == before and editor.drag == nil)
-- A sorted item dropped on the Search list stays where it was
wheel("sorted", -30)
drag("sorted", 1, 6, editorSize.RIGHT_X + 40, resultsTop + 20)
assert(saved() == before and gear().rows[2].slots[52].layoutKey == key(1052))
-- Move to Unsorted still works on the Search tab
press("sorted", 1, 6)
editor.panes.sorted.surface.hooks.release()
editor.unsortButton.root.hooks.pressed()
assert(unsortedIndex(key(1052)) == #gear().unsorted and gear().rows[2].slots[52].kind == "blank" and changes == 4)

-- Changing tab cancels a drag, its ghost, and its stretched surface
press("sorted", 2, 1)
local ghost = editor.drag.ghost
assert(sorted.surface.x == 0)
showTab("unsorted")
assert(editor.drag == nil and ghost.destroyed and sorted.surface.x == sorted.x)
assert(unsorted.view.scrollY == unsortedScroll and not unsorted.hidden and editor.searchDragSurface.hidden)
showTab("search")
pressResult(10)
ghost = editor.drag.ghost
showTab("unsorted")
assert(editor.drag == nil and ghost.destroyed and editor.searchDragSurface.hidden)
assert(editor.searchDragSurface.x == editorSize.RIGHT_X + editorSize.VIEW_INSET and editor.searchDragSurface.y == resultsTop)
-- The hidden Search list takes no press or wheel, and keeps its text and scroll
editor.searchDragSurface.hooks.click(nil, 12, 10)
assert(editor.drag == nil and editor.searchDragSurface.hooks.wheel(nil, 1) == true)
showTab("search")
assert(editor.itemSearch.text == "rune" and editor.searchList.scrollY == 64 and #editor.searchResults == 4)
showTab("unsorted")

-- New label dragged onto a sorted row asks for its text
pointAtNewLabel()
labelSurface.hooks.click(nil, 10, 10)
pointAt("sorted", 0, 7)
labelSurface.hooks.hold()
assert(not editor.drag.ghost.hidden and not editor.drag.highlight.hidden)
labelSurface.hooks.release()
local prompt = app.windows.textPrompt
assert(prompt ~= nil and editor.overlayWindows[#editor.overlayWindows] == prompt.window)
prompt.field:SetText("Armour")
prompt.buttons[#prompt.buttons].root.hooks.click()
-- The store starts it at the run of items holding that row
assert(editor.centerLabels[2].row == 1 and editor.centerLabels[2].text == "Armour")
assert(labelSurface.x == editorSize.LABEL_BUTTON_X and labelSurface.y == editorSize.LABEL_BUTTON_Y)

-- Another tag starts both grids at the top and keeps the tab and search
wheel("unsorted", 1)
wheel("sorted", 1)
showTab("search")
openTag("food")
assert(sorted.view.scrollY == 0 and unsorted.view.scrollY == 0)
assert(editor.rightTab == "search" and editor.itemSearch.text == "rune")
showTab("unsorted")
-- Its empty Unsorted still fills the tab with cells, the last row partly shown
local unsortedRows = math.ceil((unsorted.height - 4) / 44)
assert(#unsorted.slots == 0 and unsorted.view.content.height == 4 + unsortedRows * 44)
assert(cells(unsorted) == unsortedRows * 9)

-- Reopening builds fresh grids on the Unsorted tab; closing destroys them
openTag("gear")
showTab("search")
app.windows:OpenLayoutEditor("gear")
local reopened = app.windows.layoutEditor
assert(reopened ~= editor and editor.window == nil and editor.panes == nil and editor.tabs == nil)
assert(reopened.rightTab == "unsorted" and reopened.tabs:GetActiveIndex() == 1 and reopened.itemSearch.text == "")
-- Showing a tab by name moves PrettyUI's tabs without calling back
reopened:ShowRightTab("search")
assert(reopened.rightTab == "search" and reopened.tabs:GetActiveIndex() == 2 and not reopened.searchDragSurface.hidden)
reopened:ShowRightTab("unsorted")
assert(reopened.tabs:GetActiveIndex() == 1 and reopened.searchDragSurface.hidden)
assert(reopened.panes.sorted.view.scrollY == 0 and #reopened.panes.unsorted.slots == 136)
local reopenedPanes, reopenedTabs = reopened.panes, reopened.tabs
local reopenedPages = { reopenedTabs:GetPage(1), reopenedTabs:GetPage(2) }
reopened.window:Close()
assert(app.windows.layoutEditor == nil and reopened.panes == nil and reopened.tabs == nil)
for _, pane in pairs(reopenedPanes) do
    assert(pane.view.destroyed and pane.surface.destroyed)
end
-- The tabs destroyed their own pages, once
assert(reopenedTabs.root == nil)
for _, tabPage in ipairs(reopenedPages) do assert(tabPage.root.destroyed and tabPage.content.destroyed) end

print("layout_editor_panes_test: ok")
