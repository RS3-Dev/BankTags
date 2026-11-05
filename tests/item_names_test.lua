package.path = "./?.lua;./?/init.lua;" .. package.path
local BankGrid = require("banktags/ui/bank_grid")

-- Check editor item names without duplicating bank page tooltips
-- FAKE HOST: stand-in components, pointer, and tooltips

local Harness = require("tools/test_support/tags_harness")
local Geometry = require("banktags/ui/geometry")
local h = Harness.new("item_names")
h.bankHost.anchoredLayout = true
-- Exercise PrettyUI's actual automatic hover hooks and manual tooltip lifecycle
local frame = setmetatable({}, { __index = function() return 1 end })
local tooltipEnv = setmetatable({
    require = function(name)
        if name == "src/core/sprites" then return { CONTENT_FRAME = frame } end
        if name == "src/core/math" then return { clamp = function(v, a, b) return math.max(a, math.min(b, v)) end } end
        error(name)
    end,
    config = { Font = { MUSEO_SANS_15PT_REGULAR = { baseline = 15,
        GetStringWidth = function(_, text) return #text * 7 end,
        GetStringHeightAndLineCount = function() return 18, 1 end } } },
}, { __index = _G })
local Tooltip = assert(loadfile(Harness.PrettyUIRoot() .. "/src/tooltip.lua", "t", tooltipEnv))()
prettyui.Tooltip.registerContext = Tooltip.registerContext
prettyui.Tooltip.unregisterContext = Tooltip.unregisterContext
prettyui.Tooltip.bind = Tooltip.bind
prettyui.Tooltip.set = Tooltip.set
prettyui.Tooltip.unbind = Tooltip.unbind
prettyui.Tooltip.attach = function(target, parent, value)
    local tooltip = Tooltip.attach(target, parent, value)
    local show, hide, setText, destroy = tooltip.Show, tooltip.Hide, tooltip.SetText, tooltip.Destroy
    tooltip.shown, tooltip.text = false, type(value) == "table" and value.text or value
    -- Show the tooltip and record its visibility
    function tooltip:Show() show(self); self.shown = not self.root.hidden end
    -- Hide the tooltip and record its visibility
    function tooltip:Hide() hide(self); self.shown = false end
    -- Update and record the tooltip text
    function tooltip:SetText(text) setText(self, text); self.text = text end
    -- Release the tooltip and record its removal
    function tooltip:Destroy() destroy(self); self.destroyed, self.shown = true, false end
    return tooltip
end
local host = h.bankHost
-- Two whips, a shark, and an egg placeholder
host:SetItems({ { 4151, 1, "Abyssal whip" }, { 4151, 1, "Abyssal whip" }, { 385, 20, "Shark" },
    { 1944, 0, "Egg" } })
host.names[536] = "Dragon bones"
host.itemLayer.interfaceID = 517
h:LoadCore()
h:LoadTags()
h.tags.env.Mouse = { GetPosition = function() error("editor hover must use native hooks") end }
local app = h:App()
h:OpenBank()
h:Tick(12)

-- Bank Tags' own module, so these slots' keys never repeat ones it gives out
local item = h:TagsModule("banktags/tags/tag_layouts").Item
assert(app.store:CreateTag("melee"))
-- Cover repeated stacks, ghosts, placeholders, unnamed items, and both panes
app.store.data.tags.melee.rows = {
    { kind = "row", slots = { item(4151), item(4151), item(536), item(1944), item(4151), item(777) } },
    { kind = "label", text = "Food" },
    { kind = "row", slots = { item(385) } },
}
app.store.data.tags.melee.unsorted = { item(385) }
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

-- Rail names render in the editor overlay, not inside the 32px button row
local railTooltip = editor.tagTabs.rows[1].tooltip
local railContext = railTooltip.context
assert(railTooltip.parent == editor.content and railTooltip.root.parent == editor.content)
railTooltip:Show()
assert(railTooltip.width > 48)
local railX, railY = railTooltip.context.position(railTooltip.target)
assert(railX == editorSize.CENTER_X + editorSize.TABS_INSET and railY == editorSize.TABS_Y)
railTooltip:Hide()

-- Point at a pane's cell, at an offset inside it
local function pointAt(paneName, column, row, dx, dy)
    local pane = editor.panes[paneName]
    local left, top = Geometry.absolutePosition(editor.content)
    h:PointEditor(pane.x + pane.gridLeft + column * 44 + (dx or 20),
        pane.y + BankGrid.RowItemY(row, pane.labels) + (dy or 20) - pane.view.scrollY)
end
local sorted, unsorted = editor.panes.sorted, editor.panes.unsorted

-- Nothing shows until the pointer is over a surface
h:Tick()
assert(not nameTooltip.shown)
pointAt("sorted", 3, 0)
h:Tick()
assert(nameTooltip.shown and nameTooltip.text == "Egg", tostring(nameTooltip.text))
local show = nameTooltip.Show
local repeatedShows = 0
-- Count repeated tooltip displays
function nameTooltip:Show() repeatedShows = repeatedShows + 1; return show(self) end
local front = editor.window.root.front
h:Tick(20)
assert(repeatedShows == 0, "an unchanged tooltip must not be re-shown every tick")
assert(editor.window.root.front == front, "an idle editor must not reorder its native window every tick")
local anchor = editor.nameAnchor
assert(anchor.hidden, "the positioning anchor must not participate in native hover")
-- The editor drives this anchor programmatically; native hover must not hide it
for _ = 1, 5 do
    if anchor.enabled ~= false then anchor.hooks.mouseleave() end
    assert(nameTooltip.shown, "automatic anchor hover must not fight the editor's tooltip")
    h:Tick()
end
-- A leave/re-enter during native layer ordering must not hide the tooltip mid-frame
for _ = 1, 5 do
    sorted.surface.hooks.mouseleave()
    assert(nameTooltip.shown)
    sorted.surface.hooks.mouseover(sorted.surface,
        sorted.x + editorSize.GRID_LEFT + 3 * 44 + 20, sorted.y + 24)
    h:Tick()
    assert(nameTooltip.shown and nameTooltip.text == "Egg")
end
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
assert(nameTooltip.shown, "leave is settled on the next logic tick")
h:Tick()
assert(not nameTooltip.shown)

-- Unsorted names its items too
pointAt("unsorted", 0, 0)
h:Tick()
assert(nameTooltip.shown and nameTooltip.text == "Shark")
assert(anchor.x == unsorted.x + unsorted.gridLeft and anchor.y == unsorted.y + 4)

-- A press that starts a drag hides the name until the drop
pointAt("sorted", 0, 0)
h:Tick()
assert(nameTooltip.shown)
h:PressEditor(sorted.surface, editorSize.GRID_LEFT + 20, 24)
assert(editor.drag ~= nil)
h:Tick()
assert(not nameTooltip.shown)
h:ReleaseEditor()
assert(editor.drag == nil)
-- Native hover returns to the grid after release
pointAt("sorted", 0, 0)
h:Tick()
assert(nameTooltip.shown and nameTooltip.text == "Abyssal whip")

-- Hide names while a window or menu covers the editor
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

-- Unsorted stays available alongside the search list
pointAt("unsorted", 0, 0)
h:Tick()
assert(nameTooltip.shown and nameTooltip.text == "Shark")

-- Readable search labels do not get a redundant tooltip over their text
editor:RunSearch("whip")
assert(#editor.searchResults >= 1)
local left, top = Geometry.absolutePosition(editor.content)
h:PointEditor(editorSize.SEARCH_X + editorSize.SEARCH_INSET + 100, editorSize.PANEL_TOP + editorSize.SEARCH_LIST_TOP + 10)
h:Tick()
assert(not nameTooltip.shown)
-- A name that exactly fits still needs no tooltip; only a clipped name does
local label = editor.searchList.rows[1].label
local searchRow = editor.searchList.rows[1].root
local nameWidth = config.Font.MUSEO_SANS_15PT_REGULAR:GetStringWidth("Abyssal whip", false)
searchRow:SetSize(nameWidth + 44, editorSize.SEARCH_ROW_HEIGHT)
assert(label.width == nameWidth)
h:Tick()
assert(not nameTooltip.shown)
-- The native list removes 16px from the row when its scrollbar is visible
searchRow:SetSize(nameWidth + 44 - 16, editorSize.SEARCH_ROW_HEIGHT)
assert(label.width == nameWidth - 16)
h:Tick()
assert(nameTooltip.shown and nameTooltip.text == "Abyssal whip")
local shows = repeatedShows
h:Tick(10)
assert(repeatedShows == shows, "a clipped name must not re-show every tick")
searchRow:SetSize(nameWidth + 44, editorSize.SEARCH_ROW_HEIGHT)
h:Tick()
assert(not nameTooltip.shown)
-- Below the last result there is nothing to name
h:PointEditor(editorSize.SEARCH_X + editorSize.SEARCH_INSET + 100,
    editorSize.PANEL_TOP + editorSize.SEARCH_LIST_TOP + 10 + 32 * #editor.searchResults)
h:Tick()
assert(not nameTooltip.shown)

-- Closing the editor destroys the tooltip
pointAt("sorted", 0, 0)
h:Tick()
assert(nameTooltip.shown)
editor.window:Close()
h:Tick()
assert(nameTooltip.destroyed and app.windows.layoutEditor == nil)
assert(railTooltip.root == nil and not railContext.active, "closing releases the rail's overlay names")

print("item_names_test: ok")
