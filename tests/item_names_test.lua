package.path = "./?.lua;./?/init.lua;" .. package.path

-- Name every item in the layout editor's grids and search results
-- Bank Core names a shown tag page's items itself; Bank Tags adds nothing over the page
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
h:OpenBank()
h:Tick(12)

local key = require("banktags/tags/item_identity").LayoutKey
local function item(objectID, copy, source)
    return { kind = "item", objectID = objectID, layoutKey = key(objectID, copy),
        sourceLayoutKey = source ~= nil and key(objectID, source) or nil }
end
assert(app.store:CreateTag("melee"))
-- A stack, a source copy, a ghost, a placeholder, a copy of a doubled stack, and an unnamed item;
-- then a label and a shark, with another shark in Unsorted
app.store.data.tags.melee.rows = {
    { kind = "row", slots = { item(4151, 1), item(4151, 3, 1), item(536, 1), item(1944, 1),
        item(4151, 4), item(777, 1) } },
    { kind = "label", text = "Food" },
    { kind = "row", slots = { item(385, 2) } },
}
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
-- A ghost of an item the bank lacks is named too
-- The gap between cells and an unnamed item show nothing
pointAt("sorted", 0, 0, 42, 20)
h:Tick()
assert(not nameTooltip.shown)
pointAt("sorted", 4, 0)
h:Tick()
assert(nameTooltip.shown and nameTooltip.text == "Abyssal whip")
pointAt("sorted", 2, 0)
h:Tick()
assert(nameTooltip.shown and nameTooltip.text == "Dragon bones")
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

-- A window opened over the editor, an open menu, or a hidden editor names nothing,
-- even if the surface heard no leave, and the name returns once it is gone
assert(editor:PromptNewLabel(0) and #editor.overlayWindows == 1)
h:Tick()
assert(not nameTooltip.shown)
app.windows:Close("textPrompt")
h:Tick()
assert(nameTooltip.shown and nameTooltip.text == "Abyssal whip")
h.input.menuOpen = true
h:Tick()
assert(not nameTooltip.shown)
h.input.menuOpen = false
editor.window.root.hidden = true
h:Tick()
assert(not nameTooltip.shown)
editor.window.root.hidden = false
h:Tick()
assert(nameTooltip.shown)

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
