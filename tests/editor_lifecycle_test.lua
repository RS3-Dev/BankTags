package.path = "./?.lua;./?/init.lua;" .. package.path

-- Check tag switching, shortcut focus, and editor cleanup
-- FAKE HOST: native components and PrettyUI leaf controls

local Harness = require("tools/test_support/tags_harness")
local Json = require("banktags/core/json")
local h = Harness.new("editor_lifecycle")
local host = h.bankHost
host:SetItems({ { 4151, 1, "Abyssal whip" }, { 385, 20, "Shark" } })
h:LoadCore()
h:LoadTags()
local app = h:App()
local store = app.store

assert(store:CreateTag("gear", 4151) and store:CreateTag("food") and store:CreateTag("ranged"))
assert(store:CreateFolder("Combat", "ranged"))
store:SetLayoutPlacement(false)
assert(store:AddTag("gear", 4151) and store:AddTag("gear", 385))
app:Changed()
h:OpenBank()
h:Tick(2)
local Size = h:TagsModule("banktags/windows/layout_editor_parts").size
local editor
-- Open the layout editor for a tag
local function openEditor(tag)
    app.windows:OpenLayoutEditor(tag)
    editor = assert(app.windows.layoutEditor)
end
openEditor("gear")
local rail = editor.tagTabs
-- Every tag remains in sidebar order, without its folder in the label
assert(#rail.entries == 3 and rail.entries[1].id == "gear")
local labels = {}
for _, entry in ipairs(rail.entries) do labels[entry.id] = entry.label end
assert(labels.gear == "Gear" and labels.food == "Food" and labels.ranged == "Ranged")
assert(rail:GetSelectedID() == "gear" and editor.tagTitle == nil)
assert(rail.rows[1].icon.associatedObjectID == 4151 and rail.rows[1].icon.clickthrough)
assert(rail.rows[1].root.width == 48 and rail.rows[1].root.height == 38)
assert(rail.rows[1].icon.width == 22 and rail.rows[1].icon.height == 22)
assert(rail.rows[1].icon.x == 13 and rail.rows[1].icon.y == 8)
assert(rail.left.iconSize == 16 and rail.right.iconSize == 16)
assert(rail.root.y == Size.TABS_Y and rail.root.x == Size.CENTER_X + Size.TABS_INSET)
assert(Harness.Find(editor.content, "Tags") == nil)
assert(editor.tagIcon == nil and editor.tagRail == nil)
assert(rail.rows[1].icon.associatedObjectQuantityMode == ui.ObjectQuantityDisplayMode.NEVER)
assert(rail.rows[2].icon == nil and rail.rows[2].label.content == "F")
assert(rail.rows[1].tooltipText == "Gear")
assert(rail.rows[1].background.spriteID == id.Sprite.BANK_TABS_HORIZONTAL_1)
assert(rail.rows[2].background.spriteID == id.Sprite.BANK_TABS_HORIZONTAL_0)
rail.rows[2].root.hooks.mouseover()
assert(rail.rows[2].background.spriteID == id.Sprite.BANK_TABS_HORIZONTAL_2)
rail.rows[2].root.hooks.mouseleave()
assert(rail.rows[2].background.spriteID == id.Sprite.BANK_TABS_HORIZONTAL_0)
assert(rail.root.width == Size.CENTER_WIDTH - 8)
assert(rail.rows[2].root.x - rail.rows[1].root.x == 50 and rail.rows[2].root.y == rail.rows[1].root.y)
assert(rail.left.root.hidden and rail.right.root.hidden)
assert(editor.chooser == nil and editor.tabs == nil)

-- Send a key as the client's KeyDown payload
local function key(gameKey, modifiers)
    for name, action in pairs(h.keySubscriptions.KeyDown) do
        if string.find(name, "layout_editor_keys", 1, true) then
            action({ gameKey = gameKey, systemKey = 0, modifiers = modifiers, isRepeat = false })
        end
    end
end
local DELETE, Z, V = 101, 64, 67
-- Select the first item and give the grid shortcuts
local function pressGrid()
    local pane = editor.panes.sorted
    h:PointEditor(pane.x + Size.GRID_LEFT + 20, pane.y + 24)
    h:PressEditor(pane.surface, Size.GRID_LEFT + 20, 24)
    h:ReleaseEditor()
    assert(editor.keysOnGrid and editor.selectedLayoutKey ~= nil)
end
-- Encode the current tag data for comparison
local function saved() return Json.encode(store.data) end

-- Navigation takes the keys, including clicking the selected tag again
pressGrid()
rail.rows[1].root.hooks.click()
assert(not editor.keysOnGrid)
local before = saved()
key(DELETE, 0)
key(Z, 2)
key(V, 2)
assert(saved() == before)
-- The grid has the keys again once pressed, and Delete then removes the selected item
pressGrid()
key(DELETE, 0)
assert(saved() ~= before)
assert(editor:Undo())
-- The item search's field behaves the same
pressGrid()
editor.itemSearch.root.hooks.click(editor.itemSearch.root, 4, 4)
key(DELETE, 0)
assert(not editor.keysOnGrid and saved() == before)
pressGrid()
editor.itemSearch:SetText("shark", true)
assert(not editor.keysOnGrid and saved() == before)

-- Choosing another rail button clears history and clipboard
pressGrid()
editor:CopySelected()
assert(editor.clipboard ~= nil and editor.history ~= nil)
assert(editor.tagTabs:Select("ranged", true))
assert(editor.selectedTag == "ranged" and not editor.keysOnGrid)
assert(editor.history == nil and editor.clipboard == nil and editor.tagTabs:GetSelectedID() == "ranged")
-- Selecting the shown entry again changes nothing
assert(editor.tagTabs:Select("ranged", true) and editor.selectedTag == "ranged")
-- A store change rebuilds the entries and keeps the open tag chosen
assert(store:CreateTag("archery"))
app:Changed()
assert(#editor.tagTabs.entries == 4 and editor.tagTabs:GetSelectedID() == "ranged")
assert(editor.tagTabs:Select("gear", true) and editor.selectedTag == "gear")

-- Long tag lists stay reachable with paging and wheel input
for index = 1, 24 do assert(store:CreateTag("extra " .. index)) end
assert(store:CreateTag("Élixirs"))
app:Changed()
rail = editor.tagTabs
assert(not rail.left.root.hidden and not rail.right.root.hidden)
assert(#rail.rows == rail.capacity and rail.capacity < #rail.entries)
assert(rail.rows[1].root.x >= rail.left.width + 2)
local finalTab = rail.rows[#rail.rows].root
assert(finalTab.x + finalTab.width <= rail.right.x - 2, "overflow tabs leave both arrows unobstructed")
local first, selected = rail.first, editor.selectedTag
assert(rail.root.hooks.wheel(nil, 1) == false and rail.first == first + 1)
assert(editor.selectedTag == selected)
rail.right.root.hooks.pressed()
assert(rail.first == first + 2)
assert(editor.selectedTag == selected, "scrolling the tab strip must not switch pages")
local last = rail.entries[#rail.entries].id
assert(rail:Select(last, true) and editor.selectedTag == last)
local shown
for _, row in ipairs(rail.rows) do if row.entry.id == last then shown = row end end
assert(shown ~= nil and shown.background.spriteID == id.Sprite.BANK_TABS_HORIZONTAL_1)
assert(shown.label.content == "É")
assert(rail.right.disabled and not rail.left.disabled)
assert(rail:Select("gear", true) and rail.first == 1)

-- Find editor-owned listeners still subscribed anywhere
local function listeners()
    local found = {}
    for name in pairs(host.callbacks) do
        if string.find(name, "layout_editor", 1, true) then found[#found + 1] = name end
    end
    for event, subscribers in pairs(h.keySubscriptions) do
        for name in pairs(subscribers) do
            if string.find(name, "layout_editor", 1, true) then found[#found + 1] = event .. " " .. name end
        end
    end
    for name in pairs(h.openSubscriptions) do
        if string.find(name, "layout_editor", 1, true) then found[#found + 1] = name end
    end
    return table.concat(found, ", ")
end
-- Check that closing released editor controls and tooltips
local function released(closed)
    for _, control in ipairs({ closed.copyButton, closed.pasteButton, closed.removeButton,
        closed.unsortButton, closed.newLabelButton, closed.closeButton }) do
        assert(control.tooltipText == nil and control.root == nil)
    end
    assert(closed.tagTabs.root == nil and #closed.tagTabs.rows == 0)
    assert(closed.tagTabs.left.root == nil and closed.tagTabs.right.root == nil)
    assert(closed.nameTooltip.destroyed and closed.window == nil and closed.panes == nil)
end

-- Closing during a drag ends the drag and removes its ghost and every listener
assert(listeners() ~= "")
local pane = editor.panes.sorted
h:PointEditor(pane.x + Size.GRID_LEFT + 20, pane.y + 24)
h:PressEditor(pane.surface, Size.GRID_LEFT + 20, 24)
local drag = assert(editor.drag)
local closing = editor
editor.closeButton.root.hooks.pressed()
assert(drag.ghost.destroyed and closing.drag == nil and app.windows.layoutEditor == nil)
assert(listeners() == "", listeners())
released(closing)
-- Closing again, by the window or the app, does nothing more
closing:Destroy()
app.windows:Close("layoutEditor")
before = saved()
closing:SetBankItems({ { objectID = 385, quantity = 1 } })
assert(saved() == before)

-- Reopening, as a resize does, closes the label prompt; its stale save changes neither editor nor tag
openEditor("gear")
-- A saved row edit also invalidates an open label prompt
assert(editor:PromptNewLabel(0))
local changedPrompt = assert(app.windows.textPrompt)
assert(store:InsertLayoutRow("gear", 0, editor.columns))
app:Changed("gear")
before = saved()
changedPrompt.field:SetText("Stale label")
Harness.Click(changedPrompt.window.content, "Add")
assert(saved() == before and not changedPrompt.closed)
assert(changedPrompt.status.content:find("editor changed", 1, true))
Harness.Click(changedPrompt.window.content, "Cancel")
assert(store:RemoveLayoutRow("gear", 0, editor.columns))
app:Changed("gear")
local asked
local promptLabel = editor.onPromptLabel
editor.onPromptLabel = function(options)
    asked = options
    promptLabel(options)
end
assert(editor:PromptNewLabel(0))
local prompt = assert(app.windows.textPrompt)
local stale = editor
openEditor("gear")
assert(app.windows.textPrompt == nil and prompt.closed and stale.window == nil)
before = saved()
assert(not asked.onSave("Late label"))
assert(saved() == before and editor.layout.labels[1] == nil)
-- A pending row removal closes the same way
assert(editor:InsertEmptyRow(0) and editor:InsertEmptyRow(0))
assert(editor:RemoveRow(2) and app.windows.rowRemoveConfirm ~= nil)
app.windows:CloseBankWindows()
assert(app.windows.rowRemoveConfirm == nil and app.windows.layoutEditor == nil and listeners() == "")

-- Shutting down mid-drag with a prompt open leaves no editor listener, window, or prompt
openEditor("gear")
assert(editor:PromptNewLabel(0))
pane = editor.panes.sorted
local first = nil
for index, slot in ipairs(pane.slots) do first = first or (slot.kind == "item" and index or nil) end
local itemY = 4 + (first - 1) // pane.columns * 44 + 20
h:PointEditor(pane.x + Size.GRID_LEFT + 20, pane.y + itemY)
h:PressEditor(pane.surface, Size.GRID_LEFT + 20, itemY)
drag = assert(editor.drag)
closing = editor
app:Shutdown()
assert(drag.ghost.destroyed and app.windows.layoutEditor == nil and app.windows.textPrompt == nil)
assert(listeners() == "", listeners())
released(closing)

print("editor_lifecycle_test: ok")
