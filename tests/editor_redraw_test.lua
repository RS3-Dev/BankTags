package.path = "./?.lua;./?/init.lua;" .. package.path

-- Check that selection and quantity changes reuse grid controls
-- FAKE HOST: stand-in components and pointer

local Harness = require("tools/test_support/tags_harness")
local h = Harness.new("editor_redraw")
local host = h.bankHost
host:SetItems({ { 385, 200, "Shark" }, { 1944, 0, "Egg" } })
h:LoadCore()
h:LoadTags()
local app = h:App()
local Item = h:TagsModule("banktags/tags/tag_layouts").Item
local Size = h:TagsModule("banktags/windows/layout_editor_parts").size
assert(app.store:CreateTag("review"))
local slots = {}
for index = 1, 200 do slots[index] = Item(index % 2 == 0 and 1944 or 385) end
app.store.data.tags.review.rows = { { kind = "label", text = "Food" }, { kind = "row", slots = slots } }
app.store.data.tags.review.unsorted = { Item(385) }
assert(app.store:Save())
h:OpenBank()
h:Tick(2)
app.windows:OpenLayoutEditor("review")
local editor = app.windows.layoutEditor
local sorted, unsorted = editor.panes.sorted, editor.panes.unsorted

-- Count every native component created or destroyed, and every object rebinding
local stats
-- Reset the counters before the next check
local function reset() stats = { created = 0, destroyed = 0, rebound = 0 } end
reset()
-- Count new hook bindings on a component
local function watch(node)
    local destroy, bind = node.Destroy, node.SetAssociatedObject
    node.Destroy = function(self, ...)
        if not self.destroyed then stats.destroyed = stats.destroyed + 1 end
        return destroy(self, ...)
    end
    node.SetAssociatedObject = function(self, ...)
        stats.rebound = stats.rebound + 1
        return bind(self, ...)
    end
end
-- Visit a component and all its children
local function visit(node, action)
    if node.destroyed then return end
    action(node)
    for _, child in ipairs(node.children) do visit(child, action) end
end
visit(editor.window.root, watch)
for _, kind in ipairs({ "Layer", "Sprite", "Rectangle", "Text", "Button" }) do
    local new = ui[kind].new
    ui[kind].new = function(...)
        local node = new(...)
        stats.created = stats.created + 1
        watch(node)
        return node
    end
end
-- Remember the drawn cells, sprites, and heading of both grids
local function drawn()
    local nodes = {}
    for _, pane in pairs(editor.panes) do
        visit(pane.cells, function(node) nodes[node] = true end)
    end
    return nodes
end
-- Check that grid components were reused
local function same(before)
    local after, count = drawn(), 0
    for node in pairs(after) do
        if not before[node] then return false end
        count = count + 1
    end
    for node in pairs(before) do
        if not after[node] then return false end
    end
    return count > 400
end
-- Count the outlines shown on a pane
local function outlines(pane)
    local count = 0
    for _, mark in ipairs(pane.outlines) do
        if not mark.hidden then count = count + 1 end
    end
    return count
end
-- Press and release a grid cell
local function click(pane, column, line)
    local x, y = Size.GRID_LEFT + column * 44 + 20, 4 + line * 44 + 20 - pane.view.scrollY
    h:PointEditor(pane.x + x, pane.y + y)
    h:PressEditor(pane.surface, x, y)
    h:ReleaseEditor()
end

-- The label row draws a heading and no cells; each item has one sprite
assert(sorted.sprites[11] ~= nil and sorted.sprites[1] == nil and unsorted.sprites[1] ~= nil)
local before = drawn()
local whip = sorted.sprites[11]

-- A plain click changes only the outline and temporary ghost
reset()
click(sorted, 0, 1)
assert(editor.selectedLayoutKey == sorted.slots[11].layoutKey and outlines(sorted) == 1 and editor.drag == nil)
assert(stats.created == 3 and stats.destroyed == 2 and stats.rebound == 1)
assert(same(before) and sorted.sprites[11] == whip)

-- Shift-click builds a group with the same components
reset()
host.shiftDown = true
click(sorted, 1, 1)
click(sorted, 2, 1)
host.shiftDown = false
assert(editor:GroupCount() == 3 and outlines(sorted) == 3)
assert(stats.destroyed == 0 and stats.rebound == 0 and stats.created <= 2 and same(before))

-- Clearing the selection and choosing an empty paste cell hide outlines and reuse one
reset()
editor:SelectOnly(nil)
editor:ShowSelection()
assert(outlines(sorted) == 0 and stats.created == 0 and stats.destroyed == 0)
-- The drop row after the items, scrolled into view, holds empty cells
local columns = Size.CENTER_COLUMNS
local emptyLine = (200 + columns - 1) // columns + 1
sorted.view:SetScrollPosition(math.maxinteger)
click(sorted, columns - 1, emptyLine)
assert(editor.pasteCell == emptyLine * columns + columns and outlines(sorted) == 1)
assert(stats.created == 0 and stats.destroyed == 0 and stats.rebound == 0 and same(before))
-- Selecting Unsorted adds an outline without rebuilding either grid
reset()
click(unsorted, 0, 0)
assert(outlines(sorted) == 0 and outlines(unsorted) == 1 and editor.pasteCell == nil)
assert(stats.created == 3 and stats.destroyed == 2 and stats.rebound == 1 and same(before))

-- Bank quantities restyle the same sprites: stacks, placeholders, and absent items
reset()
editor:SetBankItems({ { objectID = 385, quantity = 0 }, { objectID = 385, quantity = 77 } })
assert(stats.created == 0 and stats.destroyed == 0 and stats.rebound == 0 and same(before))
-- A stocked stack beats a placeholder for the same object
assert(whip.associatedObjectQuantity == 77 and whip.alpha == 1)
-- An object missing from the bank shows as its placeholder
local egg = sorted.sprites[12]
assert(egg.associatedObjectQuantity == 0 and egg.alpha < 1 and egg.associatedObjectQuantityMode == 2)
editor:SetBankItems({ { objectID = 1944, quantity = 5 } })
assert(egg.associatedObjectQuantity == 5 and egg.alpha == 1 and whip.alpha < 1 and same(before))

-- A saved layout change rebuilds the grids it draws
reset()
assert(editor:InsertEmptyRow(1))
assert(stats.destroyed > 0 and not same(before) and sorted.sprites[11] == nil)
assert(editor:Undo() and sorted.sprites[11] ~= nil)

app:Shutdown()
print("editor_redraw_test: ok")
