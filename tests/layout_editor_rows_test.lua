package.path = "./?.lua;./?/init.lua;" .. package.path
local BankGrid = require("banktags/ui/bank_grid")

-- Right-click the layout editor's sorted grid for its Edit row submenu: add a row, or remove one
-- Removing a row with items, reserved slots, or a label asks first in a confirmation window
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

local TagLayouts = h:TagsModule("banktags/tags/tag_layouts")
local editorSize = h:TagsModule("banktags/windows/layout_editor_parts").size
local store = app.store
local item = TagLayouts.Item
-- The slot keys of the gear resetGear saves, by name
local keys = {}
-- Report whether gear still has a slot
local function has(layoutKey)
    for _, slot in ipairs(store:GetTaggedItems("gear")) do
        if slot.layoutKey == layoutKey then return true end
    end
    return false
end
-- Report whether Unsorted holds only the boots
local function onlyBoots()
    local unsorted = store.data.tags.gear.unsorted
    return #unsorted == 1 and unsorted[1].layoutKey == keys.boots
end
-- Lines: 0 Weapons, 1 an axe, a second axe, and a sword, 2 a helm; boots in Unsorted
local function resetGear()
    if store.data.tags.gear ~= nil then assert(store:DeleteTag("gear")) end
    assert(store:CreateTag("gear"))
    if store.data.tags.food == nil then assert(store:CreateTag("food")) end
    local axe, axe2, sword, helm, boots = item(3001), item(3001), item(3002), item(3003), item(3004)
    keys = { axe = axe.layoutKey, axe2 = axe2.layoutKey, sword = sword.layoutKey, helm = helm.layoutKey,
        boots = boots.layoutKey }
    store.data.tags.gear.rows = {
        { kind = "label", text = "Weapons" },
        { kind = "row", slots = { axe, axe2, { kind = "blank" }, sword } },
        { kind = "row", slots = { helm } },
    }
    store.data.tags.gear.unsorted = { boots }
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
    editor.onChanged = function(tag)
        changes = changes + 1
        onChanged(tag)
    end
    editor.window.tooltipContext = { position = function()
        return Geometry.absolutePosition(editor.content)
    end }
end
openEditor()

-- Point at an editor content point
local function pointAtContent(x, y)
    local left, top = Geometry.absolutePosition(editor.content)
    h:PointEditor(x, y)
end
-- Point at a pane's grid cell by its content row, as its scroll shows it
local function pointAt(paneName, column, row)
    local pane = editor.panes[paneName]
    local x, y = pane.gridLeft + column * 44 + 20, BankGrid.RowItemY(row, pane.labels) + 20 - pane.view.scrollY
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
local ABOVE, BELOW, REMOVE = "Add row above", "Add row below", "Remove row"
local LABELS = "Add label above|Add label below"
local OFFERED = EDIT .. "|Cancel"
local ITEM_OFFERED = "Move to Unsorted|" .. EDIT .. "|Remove from Tag|Cancel"
-- List the Edit row children of a menu, or nil without the submenu
local function children(menu)
    local submenu = Harness.Submenu(menu, EDIT)
    return submenu ~= nil and table.concat(Harness.ChildLabels(submenu), "|") or nil
end
local BOTH = ABOVE .. "|" .. BELOW .. "|" .. LABELS .. "|" .. REMOVE .. "|Cancel"
local LAST = ABOVE .. "|" .. LABELS .. "|" .. REMOVE .. "|Cancel"
-- Choose an Edit row child from a menu
local function choose(menu, label) Harness.ChooseChild(menu, EDIT, label) end

-- Items offer actions around Edit row; blanks and labels offer only row editing
for _, order in ipairs({ "core_first", "tags_first" }) do
    for _, placement in ipairs({ "documented", "above_cancel", "below_default" }) do
        local where = " (" .. order .. ", " .. placement .. ")"
        h.menuOrder, h.placement = order, placement
        for _, cell in ipairs({ { 0, 1 }, { 2, 1 }, { 9, 1 }, { 0, 0 }, { 5, 0 } }) do
            pointAt("sorted", cell[1], cell[2])
            local menu = h:ContentMenu()
            local onItem = cell[1] == 0 and cell[2] == 1
            assert(shown(menu) == (onItem and ITEM_OFFERED or OFFERED), shown(menu) .. where)
            assert(children(menu) == BOTH and Harness.Submenu(menu, EDIT).options.title == "Edit row", where)
            assert(Harness.LeftClick(menu) == (onItem and "Move to Unsorted" or EDIT), where)
        end
        -- The last line has nothing below it to move
        pointAt("sorted", 0, 2)
        assert(children(h:ContentMenu()) == LAST, where)
        -- The drop row and the empty rows past it are already empty
        for _, row in ipairs({ 3, 4, 8 }) do
            pointAt("sorted", 3, row)
            assert(shown(h:ContentMenu()) == "Cancel", "row " .. row .. where)
        end
    end
end
h.menuOrder, h.placement = "core_first", "documented"

-- Unsorted items offer item actions without row editing; other surfaces stay empty.
local sorted = editor.panes.sorted
pointAt("unsorted", 0, 0)
assert(shown(h:ContentMenu()) == "Move to Layout|Remove from Tag|Cancel")
pointAtContent(editorSize.SEARCH_X + 40, editorSize.PANEL_TOP + editorSize.SEARCH_LIST_TOP + 10)
assert(shown(h:ContentMenu()) == "Cancel")
pointAtContent(editorSize.CENTER_X + 10, editorSize.PANEL_TOP + 20)
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
assert(Harness.LeftClick(menu) == "Move to Unsorted")
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
assert(changes == 1 and onlyBoots())
assert(TagLayouts.Render(store.data.tags.gear.rows, 10).slots[12].layoutKey == keys.axe2)
-- The editor redraws at once: the helm's row is now the last one, then the drop row
assert(editor.layout.lines == 4 and sorted.slots[31].layoutKey == keys.helm and sorted.slots[21].kind == "blank")
-- The same menu's entries act only once
before = saved()
choose(menu, BELOW)
choose(menu, ABOVE)
h:Tick(2)
assert(saved() == before and changes == 1)

-- Above a label moves the label down; every row in the layout offers Remove row
pointAt("sorted", 4, 0)
choose(h:ContentMenu(), ABOVE)
h:Tick(2)
assert(lines() == "- Weapons 3001 - 3003", lines())
assert(editor.layout.labels[1].row == 1 and changes == 2)
for _, row in ipairs({ 0, 1, 2, 3 }) do
    pointAt("sorted", 2, row)
    assert(children(h:ContentMenu()) == BOTH, "row " .. row)
end

-- Removing an empty row asks nothing and moves every later row and label up, in one save and one notice
pointAt("sorted", 7, 3)
choose(h:ContentMenu(), REMOVE)
h:Tick(2)
assert(app.windows.rowRemoveConfirm == nil)
assert(lines() == "- Weapons 3001 3003", lines())
assert(changes == 3 and editor.layout.lines == 4)
assert(TagLayouts.Render(store.data.tags.gear.rows, 10).slots[22].layoutKey == keys.axe2)
pointAt("sorted", 0, 0)
choose(h:ContentMenu(), REMOVE)
h:Tick(2)
assert(lines() == "Weapons 3001 3003", lines())
assert(changes == 4 and editor.layout.labels[1].row == 0)
-- A line past the layout has nothing to remove
before = saved()
assert(not editor:RemoveRow(5) and saved() == before and changes == 4)

-- A row holding items asks first, naming what leaves the tag; Cancel changes nothing
local function confirm() return app.windows.rowRemoveConfirm end
local function askToRemove(column, row)
    pointAt("sorted", column, row)
    choose(h:ContentMenu(), REMOVE)
    h:Tick(2)
    return assert(confirm())
end
askToRemove(2, 1)
assert(saved() == before and changes == 4 and not confirm().window.root.hidden)
local message = confirm().message.content
assert(string.find(message, "its 3 items from", 1, true) and string.find(message, "your bank keeps every item", 1, true),
    message)
assert(editor.overlayWindows[#editor.overlayWindows] == confirm().window, "the confirmation stays over the editor")
assert(editor:KeysBlocker() ~= nil, "the confirmation takes the editor's keys")
Harness.Click(confirm().window.content, "Cancel")
assert(confirm().closed and saved() == before and changes == 4)
-- Confirming removes the whole line in one save and one undo step; Unsorted and the other rows stay
Harness.Click(askToRemove(2, 1).window.content, "Remove")
assert(lines() == "Weapons 3003", lines())
assert(changes == 5 and confirm().closed)
for _, gone in ipairs({ keys.axe, keys.axe2, keys.sword }) do assert(not has(gone)) end
assert(has(keys.helm) and onlyBoots())
-- Undo puts back every item and blank; redo removes them again
assert(editor:Undo() and saved() == before and changes == 6)
assert(editor:Redo() and lines() == "Weapons 3003")
assert(editor:Undo() and saved() == before)
-- A label's line asks first and removes only the label
askToRemove(5, 0)
assert(string.find(confirm().message.content, "the label <col=ffcb05>\"Weapons\"", 1, true), confirm().message.content)
Harness.Click(confirm().window.content, "Remove")
assert(lines() == "3001 3003", lines())
assert(has(keys.axe2) and editor.layout.labels[1] == nil)
assert(editor:Undo() and saved() == before)

-- A confirmation goes stale after any save or another tag, and then removes nothing
local function staleConfirm(change)
    local window = askToRemove(2, 1)
    change()
    before = saved()
    Harness.Click(window.window.content, "Remove")
    assert(saved() == before and string.find(window.message.content, "layout changed", 1, true), window.message.content)
    assert(not window.window.root.hidden)
    Harness.Click(window.window.content, "Cancel")
end
staleConfirm(function()
    assert(store:SetLabel("gear", 0, "Arms", 10))
    app:Changed()
end)
staleConfirm(function() assert(store:CreateTag("snacks")) end)
staleConfirm(function() editor:SelectTag("food") end)
editor:SelectTag("gear")
-- Closing the editor closes its confirmation
askToRemove(2, 1)
editor.window:Close()
assert(app.windows.rowRemoveConfirm == nil)
openEditor()
sorted = editor.panes.sorted
-- A failed save keeps the window open with the reason, and changes nothing
askToRemove(2, 1)
store.loadError = "The saved tags could not be read."
before = saved()
Harness.Click(confirm().window.content, "Remove")
store.loadError = nil
assert(saved() == before and changes == 0 and editor.history == nil)
assert(not confirm().window.root.hidden and confirm().message.content == "The saved tags could not be read.")
Harness.Click(confirm().window.content, "Cancel")
editor:ClearStatus()
assert(lines() == "Arms 3001 3003", lines())
assert(store:SetLabel("gear", 0, "Weapons", 10))
app:Changed()

-- One line of a wrapped row goes alone, and a reserved blank keeps its line
local long = store.data.tags.gear.rows[2].slots
for position = #long + 1, 20 do long[position] = { kind = "blank" } end
long[21] = item(3002)
local sword2 = long[21].layoutKey
store.data.tags.gear.rows[3].slots = { { kind = "blank" }, { kind = "blank", dormant = "Old item" } }
assert(store:Save())
app:Changed()
assert(lines() == "Weapons 3001 - 3002 -", lines())
pointAt("sorted", 0, 4)
assert(children(h:ContentMenu()) == LAST)
pointAt("sorted", 0, 2)
choose(h:ContentMenu(), REMOVE)
h:Tick(2)
assert(lines() == "Weapons 3001 3002 -", lines())
local wrapped = store.data.tags.gear.rows[2].slots
assert(#wrapped == 11 and wrapped[11].layoutKey == sword2 and wrapped[2].layoutKey == keys.axe2)
assert(store.data.tags.gear.rows[3].slots[2].dormant == "Old item")
-- A reserved slot counts as content, so its line asks first
askToRemove(0, 3)
assert(string.find(confirm().message.content, "its 1 reserved slot from", 1, true), confirm().message.content)
Harness.Click(confirm().window.content, "Cancel")
-- Removing a wrapped row's item line takes only that line's items
Harness.Click(askToRemove(0, 2).window.content, "Remove")
assert(lines() == "Weapons 3001 -", lines())
assert(#store.data.tags.gear.rows[2].slots == 4 and not has(sword2))
assert(store.data.tags.gear.rows[3].slots[2].dormant == "Old item")
-- Back to the rows the next checks start from
resetGear()
assert(store:InsertLayoutRow("gear", 2, 10) and store:InsertLayoutRow("gear", 0, 10))
app:Changed()
assert(lines() == "- Weapons 3001 - 3003", lines())

-- The row comes from the pointer, not the selected item
editor.selectedLayoutKey = keys.helm
pointAt("sorted", 1, 2)
choose(h:ContentMenu(), BELOW)
h:Tick(2)
assert(lines() == "- Weapons 3001 - - 3003", lines())
assert(editor.selectedLayoutKey == keys.helm)

-- Scrolled rows count the scroll
resetGear()
for objectID = 1, 20 do store.data.tags.gear.rows[#store.data.tags.gear.rows + 1] =
    { kind = "row", slots = { item(4000 + objectID) } } end
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

-- Add label above or below asks for text and puts the label at that row, in one undo step
-- Labels drawn on the grid stay draggable, and New label adds at the selection or the end
resetGear()
local function labelRows()
    local found = {}
    for _, label in ipairs(TagLayouts.Render(store.data.tags.gear.rows, 10).labels) do
        found[#found + 1] = label.text .. "@" .. label.row
    end
    return table.concat(found, " ")
end
-- Type text into the open label prompt and add it
local function addLabel(text)
    local prompt = assert(app.windows.textPrompt)
    local over = false
    for _, window in ipairs(editor.overlayWindows) do over = over or window == prompt.window end
    assert(over, "the prompt opens in front of the editor")
    prompt.field:SetText(text)
    Harness.Click(prompt.window.content, "Add")
    assert(prompt.closed)
end
assert(labelRows() == "Weapons@0")
pointAt("sorted", 3, 1)
choose(h:ContentMenu(), "Add label below")
assert(app.windows.textPrompt == nil, "the prompt waits for the next tick")
h:Tick(2)
addLabel("Armour")
assert(labelRows() == "Weapons@0 Armour@2" and lines() == "Weapons 3001 Armour 3003", lines())
before = saved()
pointAt("sorted", 6, 1)
choose(h:ContentMenu(), "Add label above")
h:Tick(2)
addLabel("Axes")
assert(labelRows() == "Weapons@0 Axes@1 Armour@3")
assert(editor:Undo() and saved() == before)
-- The last row's Add label below goes at the layout's end
pointAt("sorted", 0, 3)
choose(h:ContentMenu(), "Add label below")
h:Tick(2)
addLabel("Spare")
assert(labelRows() == "Weapons@0 Armour@2 Spare@4", labelRows())
-- New label goes above the selected item's row, then above the outlined paste cell
editor:SelectOnly(keys.helm)
editor.newLabelButton.root.hooks.pressed()
addLabel("Helms")
assert(labelRows() == "Weapons@0 Armour@2 Helms@3 Spare@5")
editor:SelectOnly(nil)
editor.pasteCell = 13
editor.newLabelButton.root.hooks.pressed()
addLabel("Picks")
assert(labelRows() == "Weapons@0 Picks@1 Armour@3 Helms@4 Spare@6")
-- A prompt left open after another tag opens saves nothing to either tag
before = saved()
editor:SelectOnly(nil)
editor.newLabelButton.root.hooks.pressed()
local stalePrompt = app.windows.textPrompt
editor:SelectTag("food")
stalePrompt.field:SetText("Stale")
Harness.Click(stalePrompt.window.content, "Add")
assert(saved() == before and not stalePrompt.closed)
Harness.Click(stalePrompt.window.content, "Cancel")
editor:SelectTag("gear")

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
staleAfter(function() h:PressEditor(sorted.surface, pointAt("sorted", 0, 1)) end)
h:ReleaseEditor()
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
h:PressEditor(sorted.surface, pointAt("sorted", 0, 1))
assert(editor.drag ~= nil)
assert(shown(h:ContentMenu()) == "Cancel")
h:ReleaseEditor()

-- A failed save shows in the editor's banner and changes nothing
store.loadError = "The saved tags could not be read."
pointAt("sorted", 0, 1)
before = saved()
choose(h:ContentMenu(), ABOVE)
h:Tick(2)
store.loadError = nil
assert(saved() == before and editor.status.content ~= "" and changes == 0)

-- Closing the editor brings back the bank's own menus
editor.window:Close()
assert(app.windows.layoutEditor == nil)
assert(children(h:ContentMenu()) == nil)

-- Item actions use the clicked slot, not a different selection or group
resetGear()
openEditor()
editor:SelectItems({ keys.axe, keys.sword })
pointAt("sorted", 1, 1)
menu = h:ContentMenu()
assert(shown(menu) == ITEM_OFFERED)
before = saved()
Harness.LeftClick(menu)
h:Tick(2)
assert(saved() == before, "a plain left click never runs the menu action")
Harness.Choose(menu, "Move to Unsorted")
h:Tick(2)
assert(changes == 1 and has(keys.axe2))
assert(store.data.tags.gear.unsorted[2].layoutKey == keys.axe2)
assert(has(keys.axe) and has(keys.sword))
Harness.Choose(menu, "Remove from Tag")
h:Tick(2)
assert(changes == 1, "the same menu only acts once")
assert(editor:Undo())
assert(saved() == before, "moving to Unsorted is undoable")

editor:SelectOnly(keys.axe)
pointAt("sorted", 3, 1)
menu = h:ContentMenu()
Harness.Choose(menu, "Remove from Tag")
h:Tick(2)
assert(not has(keys.sword) and has(keys.axe))
assert(#host.items == 4, "removing a tag never removes bank items")
assert(editor:Undo() and has(keys.sword))

-- Another edit after building an item menu invalidates its actions
pointAt("sorted", 0, 1)
menu = h:ContentMenu()
assert(store:AddTag("gear", 3005))
before = saved()
Harness.Choose(menu, "Remove from Tag")
h:Tick(2)
assert(saved() == before)
editor.window:Close()

print("layout_editor_rows_test: ok")
