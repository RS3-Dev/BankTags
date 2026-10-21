package.path = "./?.lua;./?/init.lua;" .. package.path

-- Right-click the layout editor's sorted grid for its Edit row submenu: add a row, or remove an empty one
-- Only sorted rows in the layout get entries; they act once, from the opened menu, while still current
-- FAKE HOST: stand-in components, pointer, menus, and scroll views, not the game client

local Harness = require("tools/test_support/tags_harness")
local Geometry = require("banktags/ui/geometry")
local Json = require("banktags/core/json")
local h = Harness.new("layout_editor_rows")
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
local TagLayouts = h:TagsModule("banktags/tags/tag_layouts")
local editorSize = h:TagsModule("banktags/windows/layout_editor_parts").size
local store = app.store
local function item(objectID, copy, source)
    return { kind = "item", objectID = objectID, layoutKey = key(objectID, copy),
        sourceLayoutKey = source ~= nil and key(objectID, source) or nil }
end
-- Lines: 0 Weapons, 1 an axe, its copy, and a sword, 2 a helm; boots in Unsorted
local function resetGear()
    if store.data.tags.gear ~= nil then assert(store:DeleteTag("gear")) end
    assert(store:CreateTag("gear"))
    if store.data.tags.food == nil then assert(store:CreateTag("food")) end
    store.data.tags.gear.rows = {
        { kind = "label", text = "Weapons" },
        { kind = "row", slots = { item(3001, 1), item(3001, 2, 1), { kind = "blank" }, item(3002, 1) } },
        { kind = "row", slots = { item(3003, 1) } },
    }
    store.data.tags.gear.unsorted = { item(3004, 1) }
    assert(store:Save())
    app:Changed()
end
resetGear()

local editor, changes
-- Open the editor on gear, counting its change notices
local function openEditor()
    app.windows:OpenLayoutEditor("gear")
    editor = app.windows.layoutEditor
    changes = 0
    local onChanged = editor.onChanged
    editor.onChanged = function()
        changes = changes + 1
        onChanged()
    end
    editor.window.tooltipContext = { position = function()
        return Geometry.absolutePosition(editor.content)
    end }
end
openEditor()

-- Point at an editor content point
local function pointAtContent(x, y)
    local left, top = Geometry.absolutePosition(editor.content)
    host.mouse = { x = left + x, y = top + y }
end
-- Point at a pane's grid cell by its content row, as its scroll shows it
local function pointAt(paneName, column, row)
    local pane = editor.panes[paneName]
    local x, y = editorSize.GRID_LEFT + column * 44 + 20, 4 + row * 44 + 20 - pane.view.scrollY
    pointAtContent(pane.x + x, pane.y + y)
    return x, y
end
-- Describe each saved line of gear at the editor's columns
local function lines()
    local view = TagLayouts.Render(store.data.tags.gear.rows, editorSize.CENTER_COLUMNS)
    local out = {}
    for line = 0, view.lines - 1 do
        local text = "-"
        for _, label in ipairs(view.labels) do if label.row == line then text = label.text end end
        local columns = view.columns
        for cell = line * columns + 1, line * columns + columns do
            if text == "-" and view.slots[cell].kind == "item" then text = tostring(view.slots[cell].objectID) end
        end
        out[#out + 1] = text
    end
    return table.concat(out, " ")
end
local function saved() return Json.encode(store.data) end
local function shown(menu) return table.concat(Harness.DisplayedLabels(menu), "|") end
local EDIT = "Edit row <col=ffffff><gt></col>"
local ABOVE, BELOW, REMOVE = "Add row above", "Add row below", "Remove empty row"
local OFFERED = "Cancel|" .. EDIT
-- List the Edit row children of a menu, or nil without the submenu
local function children(menu)
    local submenu = Harness.Submenu(menu, EDIT)
    return submenu ~= nil and table.concat(Harness.ChildLabels(submenu), "|") or nil
end
local BOTH = ABOVE .. "|" .. BELOW .. "|Cancel"
-- Choose an Edit row child from a menu
local function choose(menu, label) Harness.ChooseChild(menu, EDIT, label) end

-- Items, blank cells, and labels in the layout offer both under Cancel, in every placement
for _, order in ipairs({ "core_first", "tags_first" }) do
    for _, placement in ipairs({ "documented", "above_cancel", "below_default" }) do
        local where = " (" .. order .. ", " .. placement .. ")"
        h.menuOrder, h.placement = order, placement
        for _, cell in ipairs({ { 0, 1 }, { 2, 1 }, { 9, 1 }, { 0, 0 }, { 5, 0 } }) do
            pointAt("sorted", cell[1], cell[2])
            local menu = h:ContentMenu()
            assert(shown(menu) == OFFERED, shown(menu) .. where)
            assert(children(menu) == BOTH and Harness.Submenu(menu, EDIT).options.title == "Edit row", where)
            assert(Harness.LeftClick(menu) == "Cancel", where)
        end
        -- The last line has nothing below it to move
        pointAt("sorted", 0, 2)
        assert(children(h:ContentMenu()) == ABOVE .. "|Cancel", where)
        -- The drop row and the empty rows past it are already empty
        for _, row in ipairs({ 3, 4, 8 }) do
            pointAt("sorted", 3, row)
            assert(shown(h:ContentMenu()) == "Cancel", "row " .. row .. where)
        end
    end
end
h.menuOrder, h.placement = "core_first", "documented"

-- Nothing else in the editor gets entries: Unsorted, Search, the rail, the tab header, the scrollbar, the gaps
local sorted = editor.panes.sorted
pointAt("unsorted", 0, 0)
assert(shown(h:ContentMenu()) == "Cancel")
editor:ShowRightTab("search")
pointAtContent(editorSize.RIGHT_X + 40, editorSize.PANEL_TOP + editorSize.SEARCH_LIST_TOP + 10)
assert(shown(h:ContentMenu()) == "Cancel")
editor:ShowRightTab("unsorted")
pointAtContent(editorSize.RAIL_X + 10, editorSize.PANEL_TOP + 20)
assert(shown(h:ContentMenu()) == "Cancel")
pointAtContent(sorted.x + 20, sorted.y - 20)
assert(shown(h:ContentMenu()) == "Cancel")
pointAtContent(sorted.x + sorted.width - 5, sorted.y + 4 + 44 + 20)
assert(shown(h:ContentMenu()) == "Cancel")
pointAtContent(sorted.x + 2, sorted.y + 4 + 44 + 20)
assert(shown(h:ContentMenu()) == "Cancel")
pointAtContent(editorSize.ACTION_X[1] + 10, editorSize.PANEL_TOP + editorSize.ACTIONS_Y + 10)
assert(shown(h:ContentMenu()) == "Cancel")
-- A window over the editor covers its grid
app.windows:OpenPageLabelPrompt({ onSave = function() return true end })
pointAt("sorted", 0, 1)
assert(shown(h:ContentMenu()) == "Cancel")
app.windows:Close("textPrompt")

-- A left click without opening the menu does nothing, and so does Cancel
local before = saved()
pointAt("sorted", 0, 1)
local menu = h:ContentMenu()
assert(Harness.LeftClick(menu) == "Cancel")
Harness.Submenu(menu, EDIT).children[1].action()
h:Tick(2)
assert(saved() == before and changes == 0)
choose(menu, "Cancel")
h:Tick(2)
assert(saved() == before and changes == 0)

-- Below a row moves only the rows after it, in one save and one notice
assert(lines() == "Weapons 3001 3003", lines())
pointAt("sorted", 2, 1)
menu = h:ContentMenu()
choose(menu, BELOW)
assert(saved() == before, "the insert waits for the next tick")
h:Tick(2)
assert(lines() == "Weapons 3001 - 3003", lines())
assert(changes == 1 and Json.encode(store.data.tags.gear.unsorted) == Json.encode({ item(3004, 1) }))
local copy = TagLayouts.Render(store.data.tags.gear.rows, 10).slots[12]
assert(copy.layoutKey == key(3001, 2) and copy.sourceLayoutKey == key(3001, 1))
-- The editor redraws at once: the helm's row is now the last one, then the drop row
assert(editor.usedRows == 4 and sorted.slots[31].layoutKey == key(3003, 1) and sorted.slots[21].kind == "blank")
-- The same menu's entries act only once
before = saved()
choose(menu, BELOW)
choose(menu, ABOVE)
h:Tick(2)
assert(saved() == before and changes == 1)

-- Above a label moves the label down; the new empty row also offers Remove empty row
pointAt("sorted", 4, 0)
choose(h:ContentMenu(), ABOVE)
h:Tick(2)
assert(lines() == "- Weapons 3001 - 3003", lines())
assert(editor.centerLabels[1].row == 1 and changes == 2)
pointAt("sorted", 4, 0)
assert(children(h:ContentMenu()) == BOTH:gsub("|Cancel", "|" .. REMOVE .. "|Cancel"))
-- Rows with an item, a label, or a blank beside an item offer no removal
for _, row in ipairs({ 1, 2 }) do
    pointAt("sorted", 2, row)
    assert(not string.find(children(h:ContentMenu()), REMOVE, 1, true), "row " .. row)
end

-- Removing an empty row moves every later row and label up, in one save and one notice
pointAt("sorted", 7, 3)
choose(h:ContentMenu(), REMOVE)
h:Tick(2)
assert(lines() == "- Weapons 3001 3003", lines())
assert(changes == 3 and editor.usedRows == 4)
assert(TagLayouts.Render(store.data.tags.gear.rows, 10).slots[22].sourceLayoutKey == key(3001, 1))
pointAt("sorted", 0, 0)
choose(h:ContentMenu(), REMOVE)
h:Tick(2)
assert(lines() == "Weapons 3001 3003", lines())
assert(changes == 4 and editor.centerLabels[1].row == 0)
-- A removal the store refuses shows why and changes nothing
pointAt("sorted", 0, 1)
before = saved()
editor:RemoveEmptyRow(1)
assert(saved() == before and editor.errorBanner ~= nil and changes == 4)
editor:HideError()

-- One line of a wrapped row goes alone, and a reserved blank keeps its line
local long = store.data.tags.gear.rows[2].slots
for position = #long + 1, 20 do long[position] = { kind = "blank" } end
long[21] = item(3002, 2, 1)
store.data.tags.gear.rows[3].slots = { { kind = "blank" }, { kind = "blank", dormant = "Old item" } }
assert(store:Save())
app:Changed()
assert(lines() == "Weapons 3001 - 3002 -", lines())
pointAt("sorted", 0, 4)
assert(children(h:ContentMenu()) == ABOVE .. "|Cancel")
pointAt("sorted", 0, 2)
choose(h:ContentMenu(), REMOVE)
h:Tick(2)
assert(lines() == "Weapons 3001 3002 -", lines())
local wrapped = store.data.tags.gear.rows[2].slots
assert(#wrapped == 11 and wrapped[11].layoutKey == key(3002, 2) and wrapped[2].layoutKey == key(3001, 2))
assert(store.data.tags.gear.rows[3].slots[2].dormant == "Old item")
-- Back to the rows the next checks start from
resetGear()
assert(store:InsertLayoutRow("gear", 2, 10) and store:InsertLayoutRow("gear", 0, 10))
app:Changed()
assert(lines() == "- Weapons 3001 - 3003", lines())

-- The row comes from the pointer, not the selected item
editor.selectedLayoutKey = key(3003, 1)
pointAt("sorted", 1, 2)
choose(h:ContentMenu(), BELOW)
h:Tick(2)
assert(lines() == "- Weapons 3001 - - 3003", lines())
assert(editor.selectedLayoutKey == key(3003, 1))

-- Scrolled rows count the scroll
resetGear()
for objectID = 1, 20 do store.data.tags.gear.rows[#store.data.tags.gear.rows + 1] =
    { kind = "row", slots = { item(4000 + objectID, 1) } } end
assert(store:Save())
app:Changed()
editor.panes.sorted.surface.hooks.wheel(nil, 3)
assert(sorted.view.scrollY > 0)
local scrolled = sorted.view.scrollY // 44 + 1
pointAt("sorted", 0, scrolled)
choose(h:ContentMenu(), ABOVE)
h:Tick(2)
local view = TagLayouts.Render(store.data.tags.gear.rows, 10)
assert(view.slots[scrolled * 10 + 1].kind == "blank" and view.slots[(scrolled + 1) * 10 + 1].kind == "item")

-- Stale menus do nothing: a save, another tag, a drag, a closed or reopened editor
local function staleAfter(change)
    resetGear()
    pointAt("sorted", 0, 1)
    menu = h:ContentMenu()
    Harness.Open(menu)
    change()
    before = saved()
    choose(menu, ABOVE)
    h:Tick(2)
    assert(saved() == before, lines())
end
staleAfter(function()
    assert(store:SetLabel("gear", 2, "Armour", 10))
    app:Changed()
end)
staleAfter(function() editor:SelectTag("food") end)
editor:SelectTag("gear")
staleAfter(function() sorted.surface.hooks.click(nil, pointAt("sorted", 0, 1)) end)
sorted.surface.hooks.release()
staleAfter(function() editor.window:Close() end)
openEditor()
staleAfter(function() openEditor() end)
-- An entry chosen just before a change does not run after it
resetGear()
pointAt("sorted", 0, 1)
menu = h:ContentMenu()
choose(menu, ABOVE)
editor.window:Close()
before = saved()
h:Tick(2)
assert(saved() == before)
openEditor()
sorted = editor.panes.sorted

-- A drag in progress gives no entries
sorted.surface.hooks.click(nil, pointAt("sorted", 0, 1))
assert(editor.drag ~= nil)
assert(shown(h:ContentMenu()) == "Cancel")
sorted.surface.hooks.release()

-- A failed save shows in the editor's banner and changes nothing
store.loadError = "The saved tags could not be read."
pointAt("sorted", 0, 1)
before = saved()
choose(h:ContentMenu(), ABOVE)
h:Tick(2)
store.loadError = nil
assert(saved() == before and editor.errorBanner ~= nil and changes == 0)

-- Closing the editor brings back the bank's own menus
editor.window:Close()
assert(app.windows.layoutEditor == nil)
assert(children(h:ContentMenu()) == nil)

print("layout_editor_rows_test: ok")
