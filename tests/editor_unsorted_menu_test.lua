package.path = "./?.lua;./?/init.lua;" .. package.path

-- Unsorted context actions use the first available layout cell and preserve menu validity.
-- FAKE HOST: native components, context menus, and deferred callbacks, not the live client.
local Harness = require("tools/test_support/tags_harness")
local BankGrid = require("banktags/ui/bank_grid")
local Json = require("banktags/core/json")
local h = Harness.new("editor_unsorted_menu")
h.bankHost:SetItems({ { 385, 10, "Shark" }, { 4151, 1, "Abyssal whip" }, { 536, 1, "Dragon bones" } })
h:LoadCore()
h:LoadTags()
local app = h:App()
local store = app.store
local Item = h:TagsModule("banktags/tags/tag_layouts").Item
assert(store:CreateTag("gear") and store:CreateTag("food"))
local existing, source, other = Item(385), Item(385), Item(536)
store.data.tags.gear.rows = {
    { kind = "label", text = "Food" },
    { kind = "row", slots = { existing, { kind = "blank", dormant = "Old item" },
        { kind = "blank" }, Item(4151) } },
}
store.data.tags.gear.unsorted = { source, other }
assert(store:Save())
h:OpenBank()
h:Tick(2)
app.windows:OpenLayoutEditor("gear")
local editor = app.windows.layoutEditor
local columns = editor.panes.sorted.columns
local function saved() return Json.encode(store.data) end
local function record() return store.data.tags.gear end
local function shown(menu) return table.concat(Harness.DisplayedLabels(menu), "|") end
local function menuFor(layoutKey)
    local pane = editor.panes.unsorted
    local index = assert(editor.layout.unsortedIndex[layoutKey]) - 1
    h:PointEditor(pane.x + pane.gridLeft + index % pane.columns * 44 + 20,
        pane.y + BankGrid.RowItemY(index // pane.columns) + 20 - pane.view.scrollY)
    return h:ContentMenu()
end
local function choose(menu, label)
    Harness.Choose(menu, label)
    h:Tick(2)
end

for _, order in ipairs({ "core_first", "tags_first" }) do
    for _, placement in ipairs({ "documented", "above_cancel", "below_default" }) do
        h.menuOrder, h.placement = order, placement
        local menu = menuFor(source.layoutKey)
        assert(shown(menu) == "Move to Layout|Remove from Tag|Cancel", shown(menu))
        assert(#Harness.Submenus(menu) == 0, "Unsorted items must not offer row data")
    end
end
h.menuOrder, h.placement = "core_first", "documented"

-- Merely building the menu or its default action does not edit the tag.
local before = saved()
local menu = menuFor(source.layoutKey)
assert(Harness.LeftClick(menu) == "Move to Layout")
h:Tick(2)
assert(saved() == before)
-- The label row and reserved slot are skipped; the duplicate object's key stays distinct.
choose(menu, "Move to Layout")
assert(editor.layout.sortedIndex[source.layoutKey] == columns + 3)
assert(editor.layout.sortedIndex[existing.layoutKey] == columns + 1)
assert(editor.layout.unsortedIndex[source.layoutKey] == nil and #record().unsorted == 1)
assert(record().rows[2].slots[2].dormant == "Old item")
assert(editor.selectedLayoutKey == source.layoutKey)
local moved = saved()
assert(editor:Undo() and saved() == before)
assert(editor:Redo() and saved() == moved)
assert(editor:Undo() and saved() == before)

-- Remove affects the clicked item, even when a different Layout item is selected.
editor:SelectOnly(existing.layoutKey)
choose(menuFor(other.layoutKey), "Remove from Tag")
assert(editor.layout.unsortedIndex[other.layoutKey] == nil)
assert(editor.layout.unsortedIndex[source.layoutKey] ~= nil and editor.layout.sortedIndex[existing.layoutKey] ~= nil)
assert(editor:Undo() and saved() == before)

-- A failed move preserves both the source and all existing cells.
store.Commit = function() return false, "Could not save the layout." end
choose(menuFor(source.layoutKey), "Move to Layout")
store.Commit = nil
assert(saved() == before and editor.layout.unsortedIndex[source.layoutKey] ~= nil)
assert(editor.status.content ~= "")
editor:ClearStatus()

-- A menu becomes stale after a save or switching tags.
menu = menuFor(source.layoutKey)
assert(store:SetLabel("gear", 0, "Meals", columns))
app:Changed()
local changed = saved()
choose(menu, "Move to Layout")
assert(saved() == changed and editor.layout.unsortedIndex[source.layoutKey] ~= nil)
menu = menuFor(source.layoutKey)
editor:SelectTag("food")
choose(menu, "Remove from Tag")
assert(saved() == changed)
editor:SelectTag("gear")

-- Empty cells and the scrollbar never offer item actions.
local pane = editor.panes.unsorted
h:PointEditor(pane.x + pane.gridLeft + 2 * 44 + 20, pane.y + 24)
assert(shown(h:ContentMenu()) == "Cancel")
h:PointEditor(pane.x + pane.width - 5, pane.y + 24)
assert(shown(h:ContentMenu()) == "Cancel")

-- A full layout appends a row; an empty layout starts at its first cell.
local full = {}
for index = 1, columns do full[index] = Item(4151) end
record().rows = { { kind = "row", slots = full } }
assert(store:Save())
app:Changed()
choose(menuFor(source.layoutKey), "Move to Layout")
assert(editor.layout.sortedIndex[source.layoutKey] == columns + 1)
assert(#record().rows == 2 and #record().rows[1].slots == columns)
assert(editor:Undo())
record().rows = {}
assert(store:Save())
app:Changed()
choose(menuFor(source.layoutKey), "Move to Layout")
assert(editor.layout.sortedIndex[source.layoutKey] == 1 and #record().rows == 1)

-- Closing the editor invalidates an outstanding item menu.
menu = menuFor(other.layoutKey)
before = saved()
editor.window:Close()
choose(menu, "Remove from Tag")
assert(saved() == before and app.windows.layoutEditor == nil)

print("editor_unsorted_menu_test: ok")
