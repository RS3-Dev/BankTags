package.path = "./?.lua;./?/init.lua;" .. package.path

-- Name items on a shown tag page that have no bank stack, and every item in the layout editor
-- Bank Core's stacks keep their own tooltips; Bank Tags covers only the slots Core leaves empty
-- FAKE HOST: stand-in components, pointer, hover, and tooltips, not the game client

local Harness = require("tools/test_support/tags_harness")
local Geometry = require("banktags/ui/geometry")
local h = Harness.new("item_names")
local host = h.bankHost
-- Two whips, a shark, and an egg placeholder
host:SetItems({ { 4151, 1, "Abyssal whip" }, { 4151, 1, "Abyssal whip" }, { 385, 20, "Shark" },
    { 1944, 0, "Egg" } })
host.names[536] = "Dragon bones"
host.itemLayer.interfaceID = 517
h:LoadCore()
h:LoadTags()
local app = h:App()
local session, layout = h:OpenBank()
h:Tick(2)

local key = require("banktags/tags/item_identity").LayoutKey
local function item(objectID, copy, source)
    return { kind = "item", objectID = objectID, layoutKey = key(objectID, copy),
        sourceLayoutKey = source ~= nil and key(objectID, source) or nil }
end
assert(app.store:CreateTag("melee") and app.store:CreateTag("food"))
-- A stack, a source copy, a ghost, a placeholder, a copy of a doubled stack, and an unnamed item;
-- then a label and the shark, which is the object's only stack
app.store.data.tags.melee.rows = {
    { kind = "row", slots = { item(4151, 1), item(4151, 3, 1), item(536, 1), item(1944, 1),
        item(4151, 4), item(777, 1) } },
    { kind = "label", text = "Food" },
    { kind = "row", slots = { item(385, 2) } },
}
app.store.data.tags.food.rows = { { kind = "row", slots = { item(536, 1) } } }
assert(app.store:Save())
app:Changed()

local names = app.pageNames
-- Return the page's hover areas by their cell position
local function targetsAt()
    local positions = {}
    for _, target in ipairs(names.targets) do
        assert(not target.destroyed)
        positions[target.x .. "," .. target.y] = target
    end
    return positions
end
local function count(values)
    local total = 0
    for _ in pairs(values) do total = total + 1 end
    return total
end

-- The tag page ------------------------------------------------------------------------

assert(app:ShowTag("melee"))
h:Tick(2)
assert(layout.pageState.view.key == "tag:melee" and names.ctx ~= nil)
-- The ghost, the placeholder, and the doubled stack's extra copy get a hover area;
-- the unnamed item gets none, and stacks Core leases keep theirs
local targets = targetsAt()
assert(count(targets) == 3, tostring(count(targets)))

-- Each area sits on the cell of a slot Core draws with no native item, as Core lays it out
local empty, held = {}, 0
for _, entry in ipairs(layout.nativeLease.renderedEntries) do
    if entry.placeholder or (entry.component == nil and entry.interactionComponent == nil) then
        if entry.objectID ~= 777 then empty[(entry.x - 2) .. "," .. (entry.y - 4)] = entry.objectID end
    else
        held = held + 1
        assert(targets[(entry.x - 2) .. "," .. (entry.y - 4)] == nil, "a held stack is covered")
    end
end
assert(held == 3 and count(empty) == 3)
for position, target in pairs(targets) do
    assert(empty[position] ~= nil, "no empty slot at " .. position)
    assert(target.width == 40 and target.height == 40 and target.clickthrough == false)
end
-- The shark sits under the label, which Core draws shorter than a row
local shark = nil
for _, slot in ipairs(layout.pageState.view.slots) do
    if slot.objectID == 385 then shark = slot end
end
assert(shark.y == 4 + 44 + 34, tostring(shark.y))

-- Over an empty slot the hover area is in front; over a stack, Core's input target is
-- Find the frontmost clickable component at a screen point in the bank window's tree
local function hitAt(x, y)
    local root = names.ctx.parent
    while root.parent ~= nil do root = root.parent end
    local all = host.all
    host.all = root
    local hit = host:HitTest(x - root.x, y - root.y)
    host.all = all
    return hit
end
local parentLeft, parentTop = Geometry.absolutePosition(names.ctx.parent)
local ghost = targets[(8 + 2 * 44 - 2) .. "," .. 0]
assert(ghost ~= nil)
assert(hitAt(parentLeft + ghost.x + 20, parentTop + ghost.y + 20) == ghost)
local stackHit = hitAt(parentLeft + 8 + 20, parentTop + 4 + 16)
assert(stackHit ~= nil and stackHit.parent ~= names.ctx.parent)
-- The wheel still scrolls the page over a hover area
assert(ghost.hooks.wheel ~= nil)

-- Hovering shows only the item's name, beside its cell in Core's overlay
local tooltip = names.tooltip
assert(tooltip.parent == names.ctx.parent and not tooltip.shown)
ghost.hooks.mouseover()
assert(tooltip.shown and tooltip.text == "Dragon bones")
assert(tooltip.target.x == ghost.x and tooltip.target.y == ghost.y)
local context = names.ctx.parent.tooltipContext
assert(context.parent == names.ctx.overlay)
local overlayLeft, overlayTop = Geometry.absolutePosition(names.ctx.overlay)
local x, y = context.position(tooltip.target)
assert(x == parentLeft + ghost.x - overlayLeft and y == parentTop + ghost.y - overlayTop)
targets[(8 + 3 * 44 - 2) .. "," .. 0].hooks.mouseover()
assert(tooltip.shown and tooltip.text == "Egg")
targets[(8 + 4 * 44 - 2) .. "," .. 0].hooks.mouseover()
assert(tooltip.text == "Abyssal whip")
-- Leaving hides it
targets[(8 + 4 * 44 - 2) .. "," .. 0].hooks.mouseleave()
assert(not tooltip.shown)

-- Scrolling moves the item, so a shown name hides; the scrolled position counts
-- This page is too short to scroll, so the test moves Core's offset between ticks
local watch = "banktags_page_item_names"
ghost.hooks.mouseover()
h:Tick()
assert(tooltip.shown and host.callbacks[watch] ~= nil)
layout.listEngine.scrollY = 20
host.callbacks[watch]()
assert(not tooltip.shown and host.callbacks[watch] == nil)
ghost.hooks.mouseover()
x, y = context.position(tooltip.target)
assert(y == parentTop + ghost.y - overlayTop - 20)
layout.listEngine.scrollY = 0
host.callbacks[watch]()
assert(not tooltip.shown)

-- An inventory change refreshes the areas: a deposited ghost gets a stack and its area goes
host:Rebuild(function(specs)
    specs[#specs + 1] = { 536, 5 }
    host.names[536] = "Dragon bones"
    return specs
end)
layout:HandleInventoryUpdate()
h:Tick(3)
targets = targetsAt()
assert(count(targets) == 2 and targets[(8 + 2 * 44 - 2) .. ",0"] == nil, tostring(count(targets)))
assert(ghost.destroyed)
host:Rebuild(function(specs)
    specs[#specs] = nil
    return specs
end)
layout:HandleInventoryUpdate()
h:Tick(3)
assert(count(targetsAt()) == 3)

-- An edit to the shown tag keeps the mount and follows the new rows
local mounted = names.ctx
app.store.data.tags.melee.rows[1].slots[3] = { kind = "blank" }
assert(app.store:Save())
app:Changed()
h:Tick(2)
assert(names.ctx == mounted and count(targetsAt()) == 2)

-- Another tag mounts fresh areas; the old ones and their tooltip go
local oldTooltip = tooltip
oldTooltip.shown = true
names.shownScroll = 0
assert(app:ShowTag("food"))
h:Tick(2)
assert(oldTooltip.destroyed and names.ctx ~= mounted and names.tooltip ~= oldTooltip)
assert(count(targetsAt()) == 1)
names.targets[1].hooks.mouseover()
assert(names.tooltip.shown and names.tooltip.text == "Dragon bones")

-- Leaving the page unmounts everything, the scroll watch included
tooltip = names.tooltip
assert(app:ToggleTag("food"))
h:Tick(2)
assert(names.ctx == nil and #names.targets == 0 and tooltip.destroyed)
assert(host.callbacks.banktags_page_item_names == nil)

-- Closing the bank unmounts a shown page too
assert(app:ShowTag("food"))
h:Tick(2)
assert(#names.targets == 1)
local closed = names.targets[1]
names.targets[1].hooks.mouseover()
layout:Restore()
host:UnmountBankWindow()
h:Tick(2)
assert(names.ctx == nil and closed.destroyed and host.callbacks.banktags_page_item_names == nil)

-- The layout editor ------------------------------------------------------------------

session, layout = h:OpenBank()
h:Tick(12)
app.store.data.tags.melee.unsorted = { item(385, 1) }
assert(app.store:Save())
app:Changed()
app.windows:OpenLayoutEditor("melee")
local editor = app.windows.layoutEditor
local editorSize = h:TagsModule("banktags/windows/layout_editor_parts").size
editor.window.tooltipContext = { position = function()
    return Geometry.absolutePosition(editor.content)
end }
local nameTooltip = editor.nameTooltip
assert(nameTooltip.parent == editor.content and editor.nameAnchor.clickthrough == true)

-- Point at a pane's cell, at an offset inside it
local function pointAt(paneName, column, row, dx, dy)
    local pane = editor.panes[paneName]
    local left, top = Geometry.absolutePosition(editor.content)
    host.mouse = { x = left + pane.x + editorSize.GRID_LEFT + column * 44 + (dx or 20),
        y = top + pane.y + 4 + row * 44 + (dy or 20) - pane.view.scrollY }
end
local sorted, unsorted = editor.panes.sorted, editor.panes.unsorted

-- Nothing shows until the pointer is over a surface
pointAt("sorted", 3, 0)
h:Tick()
assert(not nameTooltip.shown)
sorted.surface.hooks.mouseover()
h:Tick()
assert(nameTooltip.shown and nameTooltip.text == "Egg", tostring(nameTooltip.text))
local anchor = editor.nameAnchor
assert(anchor.x == sorted.x + editorSize.GRID_LEFT + 3 * 44 and anchor.y == sorted.y + 4)
assert(anchor.width == 40 and anchor.height == 40)
-- Every item has a name, held stacks included, with no quantity
pointAt("sorted", 0, 0)
h:Tick()
assert(nameTooltip.text == "Abyssal whip" and anchor.x == sorted.x + editorSize.GRID_LEFT)
-- The gap between cells, an empty cell, and an unnamed item show nothing
pointAt("sorted", 0, 0, 42, 20)
h:Tick()
assert(not nameTooltip.shown)
pointAt("sorted", 4, 0)
h:Tick()
assert(nameTooltip.shown and nameTooltip.text == "Abyssal whip")
pointAt("sorted", 2, 0)
h:Tick()
assert(not nameTooltip.shown, "the slot is blank")
pointAt("sorted", 5, 0)
h:Tick()
assert(not nameTooltip.shown, "the client has no name for item 777")
-- Leaving the surface hides it
pointAt("sorted", 0, 0)
h:Tick()
assert(nameTooltip.shown)
sorted.surface.hooks.mouseleave()
assert(not nameTooltip.shown)
h:Tick()
assert(not nameTooltip.shown)

-- Unsorted names its items too
unsorted.surface.hooks.mouseover()
pointAt("unsorted", 0, 0)
h:Tick()
assert(nameTooltip.shown and nameTooltip.text == "Shark")
assert(anchor.x == unsorted.x + editorSize.GRID_LEFT and anchor.y == unsorted.y + 4)

-- A press that starts a drag hides the name until the drop
sorted.surface.hooks.mouseover()
pointAt("sorted", 0, 0)
h:Tick()
assert(nameTooltip.shown)
sorted.surface.hooks.click(nil, editorSize.GRID_LEFT + 20, 24)
assert(editor.drag ~= nil)
h:Tick()
assert(not nameTooltip.shown)
sorted.surface.hooks.release()
assert(editor.drag == nil)
h:Tick()
assert(nameTooltip.shown and nameTooltip.text == "Abyssal whip")

-- A hidden tab names nothing, even if its surface heard no leave
editor.tabs:GetTab(2).hit.hooks.click()
unsorted.surface.hooks.mouseover()
pointAt("unsorted", 0, 0)
h:Tick()
assert(not nameTooltip.shown)

-- Search results name the item at its icon
editor:RunSearch("whip")
assert(#editor.searchResults >= 1)
editor.searchDragSurface.hooks.mouseover()
local left, top = Geometry.absolutePosition(editor.content)
host.mouse = { x = left + editorSize.RIGHT_X + 4 + 100, y = top + editorSize.PANEL_TOP + editorSize.SEARCH_LIST_TOP + 10 }
h:Tick()
assert(nameTooltip.shown and nameTooltip.text == "Abyssal whip", tostring(nameTooltip.text))
assert(anchor.x == editorSize.RIGHT_X + 4 + 7 and anchor.width == 24)
assert(anchor.y == editorSize.PANEL_TOP + editorSize.SEARCH_LIST_TOP + 4)
-- Below the last result there is nothing to name
host.mouse.y = host.mouse.y + 32 * #editor.searchResults
h:Tick()
assert(not nameTooltip.shown)

-- Closing the editor destroys the tooltip
host.mouse.y = top + editorSize.PANEL_TOP + editorSize.SEARCH_LIST_TOP + 10
h:Tick()
assert(nameTooltip.shown)
editor.window:Close()
h:Tick()
assert(nameTooltip.destroyed and editor.nameTooltip == nil and app.windows.layoutEditor == nil)

print("item_names_test: ok")
