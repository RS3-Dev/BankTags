package.path = "./?.lua;./?/init.lua;" .. package.path
local BankGrid = require("banktags/ui/bank_grid")

-- Native press coordinates must place drag ghosts consistently across rows and scroll.
local Harness = require("tools/test_support/tags_harness")
local h = Harness.new("editor_pointer")
h.bankHost:SetItems({ { 385, 20, "Shark" }, { 1944, 1, "Egg" } })
h:LoadCore()
h:LoadTags()
h.tags.env.Mouse = { GetPosition = function() error("editor must use native hook coordinates") end }
local app = h:App()
local item = h:TagsModule("banktags/tags/tag_layouts").Item
assert(app.store:CreateTag("gear"))
local slots = {}
for _ = 1, 40 do slots[#slots + 1] = item(385) end
app.store.data.tags.gear.rows = { { kind = "label", text = "Food" }, { kind = "row", slots = slots } }
assert(app.store:Save())
h:OpenBank()
h:Tick(2)
app.windows:OpenLayoutEditor("gear")
local editor = app.windows.layoutEditor
local pane = editor.panes.sorted
assert(editor.dragCapture == nil, "a held press must not depend on a second hover target")
editor.content.xyGlobal = { x = 700, y = 400 }
-- The pointer conversion must not rely on PrettyUI's private tooltip context.
editor.window.tooltipContext = { position = function() return -1000, -1000 end }

local function point(surface, x, y, scale)
    local clip = editor.surfaceClips[surface]
    surface.xyGlobal = { x = 700 + clip.x + surface.x, y = 400 + clip.y + surface.y }
    h.bankHost.mouse = { x = (700 + clip.x + x) * scale, y = (400 + clip.y + y) * scale }
end

for _, row in ipairs({ 1, 3 }) do
    for _, scroll in ipairs({ 0, 44 }) do
        pane.view:SetScrollPosition(scroll)
        local x, y = 24, BankGrid.RowItemY(row, pane.labels) + 20 - pane.view.scrollY
        local index = editor:SlotIndexAt(pane, x, y)
        local key = pane.slots[index].layoutKey
        point(pane.surface, x, y, 1.25)
        local clip = editor.surfaceClips[pane.surface]
        assert(clip.x + pane.surface.x == 0 and clip.y + pane.surface.y == 0)
        local eventX, eventY = pane.x + x, pane.y + y
        pane.surface.hooks.click(pane.surface, eventX, eventY)
        assert(editor.drag.layoutKey == key)
        assert(editor.drag.sourceSurface == pane.surface and editor.pointerSurface == pane.surface)
        assert(editor.drag.ghost.hidden, "a press alone must not flash a ghost")
        -- The next queued event was computed before the click expanded the clip
        assert(clip.x + pane.surface.x == 0 and clip.y + pane.surface.y == 0)
        pane.surface.hooks.hold(pane.surface, eventX, eventY)
        assert(editor.drag.ghost.hidden, "a queued point must not manufacture motion")
        assert(editor.drag.ghost.x == pane.x + x - 18 and editor.drag.ghost.y == pane.y + y - 16,
            "a native press must start at the clicked row")
        h.bankHost.mouse = { x = (700 + pane.x + x + 44) * 1.25, y = (400 + pane.y + y) * 1.25 }
        -- Only the pressed surface delivers motion; no other layer receives hover
        pane.surface.hooks.hold(pane.surface, pane.x + x + 44, pane.y + y)
        assert(not editor.drag.ghost.hidden)
        assert(editor.drag.ghost.x == pane.x + x + 44 - 18)
        assert(editor.drag.ghost.y == pane.y + y - 16)
        editor:CancelDrag()
        assert(clip.x == pane.x and clip.y == pane.y)
        assert(clip.x + pane.surface.x == 0 and clip.y + pane.surface.y == 0)
    end
end

-- A group uses the same native grab point as a single item.
pane.view:SetScrollPosition(0)
editor:SelectOnly(nil)
editor:ToggleGroupItem(pane.slots[21].layoutKey)
editor:ToggleGroupItem(pane.slots[22].layoutKey)
point(pane.surface, 24, 112, 1.25)
h:PressEditor(pane.surface, 24, 112)
assert(editor.drag.kind == "group")
assert(editor.drag.ghost.x == pane.x + 24 - 18 and editor.drag.ghost.y == pane.y + 112 - 16)
editor:CancelDrag()

-- Search's surface is a viewport overlay: its click is already unscrolled.
editor:RunSearch("Shark")
local result = editor.searchResults[1]
editor.searchResults = { result, result, result, result }
editor.searchList.scrollY = 64
point(editor.searchDragSurface, 30, 12, 1.25)
h:PressEditor(editor.searchDragSurface, 30, 12)
local drag = editor.drag
assert(drag.result == editor.searchResults[3])
local size = h:TagsModule("banktags/windows/layout_editor_parts").size
local searchX, searchY = size.SEARCH_X + size.SEARCH_INSET + 30, size.PANEL_TOP + size.SEARCH_LIST_TOP + 12
assert(drag.ghost.x == searchX - 18 and drag.ghost.y == searchY - 16)
editor:CancelDrag()

-- Native click coordinates are sufficient even if the global pointer is unavailable.
h.bankHost.mouse = nil
h:PressEditor(editor.searchDragSurface, 30, 12)
assert(editor.drag ~= nil and editor.drag.ghost.y == searchY - 16)
editor:CancelDrag()

-- An existing label's grab follows the same native point on its row
h:PressEditor(pane.surface, 30, 12)
assert(editor.drag.kind == "label" and editor.drag.fromRow == 0)
assert(editor.drag.ghost.x == pane.x + 30 - size.LABEL_GHOST_WIDTH // 2)
assert(editor.drag.ghost.y == pane.y + 12 - size.LABEL_GHOST_HEIGHT // 2)
-- Its drop row comes from the pressed surface, with no global pointer
pane.surface.hooks.hold(pane.surface, pane.x + 30, pane.y + BankGrid.RowItemY(2, pane.labels) + 10)
assert(not editor.drag.highlight.hidden and editor.drag.highlight.y == BankGrid.RowItemY(2, pane.labels))
-- Releasing outside the sorted grid cancels without moving the label
local labelsBefore = require("banktags/core/json").encode(app.store.data)
pane.surface.hooks.release(pane.surface, size.UNSORTED_X + 40, size.VIEW_Y + 40)
assert(editor.drag == nil and require("banktags/core/json").encode(app.store.data) == labelsBefore)

-- A completed drag drops at the latest owned native point, never at its reported end point
local grabbed = pane.slots[21].layoutKey
h:PressEditor(pane.surface, 24, 112)
pane.surface.hooks.hold(pane.surface, pane.x + 24 + 44, pane.y + 112)
pane.surface.hooks.dragcomplete(pane.surface, editor.searchDragSurface, -500, -500)
assert(editor.drag == nil and app.store.data.tags.gear.rows[2].slots[12].layoutKey == grabbed)
-- Another surface's completion does not end this surface's drag
h:PressEditor(pane.surface, 24, 112)
editor.panes.unsorted.surface.hooks.dragcomplete(editor.panes.unsorted.surface, nil, 0, 0)
editor.panes.unsorted.surface.hooks.release(editor.panes.unsorted.surface, 0, 0)
assert(editor.drag ~= nil and editor.drag.sourceSurface == pane.surface)
editor:CancelDrag()
-- A completed drag after leaving the capture must not save at the last hovered cell.
h:PressEditor(pane.surface, 24, 112)
assert(editor.drag ~= nil)
local before = require("banktags/core/json").encode(app.store.data)
pane.surface.hooks.mouseleave()
pane.surface.hooks.dragcomplete(nil, nil, 999999, 999999)
assert(editor.drag == nil and require("banktags/core/json").encode(app.store.data) == before)
app:Shutdown()
print("editor_pointer_test: ok")
