package.path = "./?.lua;./?/init.lua;" .. package.path

-- Show each saved change once, only where it shows, and add search results in one save
-- FAKE HOST: stand-in loader, components, pointer, and saves, not the game client

local Harness = require("tools/test_support/tags_harness")
local Geometry = require("banktags/ui/geometry")
local h = Harness.new("store_changes")
local host = h.bankHost
host:SetItems({ { 4151, 1, "Abyssal whip" }, { 385, 20, "Shark" } })
host.itemLayer.interfaceID = 517
h:LoadCore()
h:LoadTags()
local app = h:App()
h:OpenBank()
h:Tick(12)

local key = require("banktags/tags/item_identity").LayoutKey
local store = app.store
local App = getmetatable(app)
local Size = h:TagsModule("banktags/windows/layout_editor_parts").size
local COLUMNS = Size.CENTER_COLUMNS
local function item(objectID, copy)
    return { kind = "item", objectID = objectID, layoutKey = key(objectID, copy or 1) }
end
local function row(...) return { kind = "row", slots = { ... } } end
-- Line 0 holds 1 and 2, line 1 is a label, line 2 holds 5
for _, tag in ipairs({ "gear", "food" }) do assert(store:CreateTag(tag)) end
store.data.tags.gear.rows = { row(item(1), item(2)), { kind = "label", text = "Mid" }, row(item(5)) }
assert(store:Save())
app:Changed()

-- Count every redraw and save from here on
local counts
local function reset()
    counts = { center = 0, rail = 0, tab = 0, pages = {}, select = 0, exports = 0, writes = 0 }
end
reset()
local tabRefresh = app.tab.Refresh
app.tab.Refresh = function(tab) counts.tab = counts.tab + 1; return tabRefresh(tab) end
app.PutPage = function(self, tag)
    counts.pages[#counts.pages + 1] = tag
    return App.PutPage(self, tag)
end
local Chunks = h:TagsModule("banktags/core/chunked_string_store")
local write = Chunks.Write
local failWrites = false
Chunks.Write = function(...)
    counts.writes = counts.writes + 1
    if failWrites then return false, { stage = "manifest", reason = "disk full" } end
    return write(...)
end

assert(app:ShowTag("gear"))
h:Tick(2)
app.windows:OpenImportShare()
local share = app.windows.importShare
local refreshExports = share.RefreshExports
share.RefreshExports = function(window) counts.exports = counts.exports + 1; return refreshExports(window) end
app.windows:OpenLayoutEditor("gear")
local editor = app.windows.layoutEditor
editor.RefreshCenter = function(self)
    counts.center = counts.center + 1
    return getmetatable(self).RefreshCenter(self)
end
editor.RefreshTags = function(self)
    counts.rail = counts.rail + 1
    return getmetatable(self).RefreshTags(self)
end
editor.window.tooltipContext = { position = function()
    return Geometry.absolutePosition(editor.content)
end }

-- Read the gear share code Import/Share shows
local function sharedGear()
    for _, shareRow in ipairs(share.shareRows) do
        if shareRow.tag == "gear" then return shareRow.field:GetText() end
    end
end
local function storedGear()
    for _, export in ipairs(store:TagExports()) do
        if export.tag == "gear" then return export.value end
    end
end
-- Check one editor edit of gear redrew the grids once and only what shows gear
local function editedOnce(where)
    assert(counts.center == 1, where .. ": grids redrew " .. counts.center .. " times")
    assert(counts.rail == 0 and counts.tab == 0, where .. ": the rail or Tags tab redrew")
    assert(#counts.pages == 1 and counts.pages[1] == "gear", where .. ": the shown page was not put once")
    assert(counts.exports == 1 and sharedGear() == storedGear(), where .. ": Import/Share is stale")
end

-- Point at a pane's grid slot, counted from zero, through its scroll
local function pointAt(paneName, column, line)
    local left, top = Geometry.absolutePosition(editor.content)
    local pane = editor.panes[paneName]
    local x, y = Size.GRID_LEFT + column * 44 + 20, 4 + line * 44 + 20 - pane.view.scrollY
    host.mouse = { x = left + pane.x + x, y = top + pane.y + y }
    return x, y
end
local function drag(fromColumn, fromLine, toColumn, toLine)
    editor.panes.sorted.surface.hooks.click(nil, pointAt("sorted", fromColumn, fromLine))
    pointAt("sorted", toColumn, toLine)
    editor.panes.sorted.surface.hooks.drag()
    editor.panes.sorted.surface.hooks.release()
end

-- Each editor edit redraws once, through the app ------------------------------------

reset()
drag(0, 0, 3, 0)
assert(store.data.tags.gear.rows[1].slots[4].objectID == 1)
editedOnce("drag")

reset()
assert(editor:InsertEmptyRow(1))
editedOnce("insert row")

reset()
assert(editor:Undo())
editedOnce("undo")

-- A drag that changes nothing still puts the item back, and nothing else redraws
reset()
drag(1, 0, 1, 0)
assert(counts.center == 1 and #counts.pages == 0 and counts.exports == 0 and counts.writes == 0)

-- Outside changes reach only what shows them --------------------------------------

-- Another tag's items leave the editor, page, and select mode alone
-- Select mode's outline is counted, not drawn, since the page is shown
app.select.session = { tag = "gear" }
app.select.Refresh = function() counts.select = counts.select + 1 end
reset()
assert(app:AddItemToTag("food", 385, 1))
assert(counts.center == 0 and counts.rail == 0 and counts.tab == 0 and #counts.pages == 0)
assert(counts.select == 0 and counts.exports == 1)

-- The open tag's items redraw its grids once and forget its undo steps
assert(editor.history ~= nil)
reset()
assert(app:AddItemToTag("gear", 4151, 1))
assert(counts.center == 1 and counts.rail == 0 and counts.tab == 0 and counts.select == 1)
assert(#counts.pages == 1 and editor.history == nil)
app.select.Refresh = nil
app.select:Forget()

-- A new tag shows in the Tags tab and the rail
reset()
assert(store:CreateTag("tools"))
app:Changed()
assert(counts.tab == 1 and counts.rail == 1 and counts.center == 1 and #counts.pages == 1)

-- A search result is added and placed in one save and one undo step ------------------

local before = store.data
local function unchanged(where)
    assert(store.data == before and not store:HasTag("gear", key(385, 1)), where .. ": the data changed")
    assert(editor.history == nil, where .. ": an undo step was kept")
    assert(counts.center == 0 and counts.exports == 0, where .. ": something redrew")
end

-- A label's line refuses the item, so it is not added either
reset()
assert(not editor:AddCatalogResult({ objectId = 385 }, COLUMNS + 1))
unchanged("label line")
assert(counts.writes == 0)

-- A failed save keeps the old data after one attempt
failWrites = true
reset()
assert(not editor:AddCatalogResult({ objectId = 385 }, 3))
failWrites = false
unchanged("failed save")
assert(counts.writes == 1)

reset()
assert(editor:AddCatalogResult({ objectId = 385 }, 3))
assert(counts.writes == 1 and store.data.tags.gear.rows[1].slots[3].layoutKey == key(385, 1))
assert(editor.selectedLayoutKey == key(385, 1))
editedOnce("search add")
assert(#editor.history.states == 2)

-- An item already in the tag gets a placed copy the same way
reset()
assert(editor:AddCatalogResult({ objectId = 385 }, 5))
assert(counts.writes == 1 and store.data.tags.gear.rows[1].slots[5].layoutKey == key(385, 2))

reset()
assert(editor:Undo() and editor:Undo())
assert(not store:HasTag("gear", key(385, 1)) and not store:HasTag("gear", key(385, 2)))
assert(counts.writes == 2 and counts.center == 2)

-- An edit that errors keeps the old data and lets later saves write
before = store.data
local ok = pcall(store.SaveTogether, store, function()
    assert(store:AddTag("food", 4151, key(4151, 1)))
    error("broken edit")
end)
assert(not ok and store.data == before and not store.holdSave)

-- A dropped item makes its tag in one save, or no tag at all
reset()
assert(app:CreateTagWithItem(385, 1))
assert(counts.writes == 1 and store:HasTag("placeholder 1", key(385, 1)))
app.windows:Close("tagSettingsEditor")
failWrites = true
reset()
assert(not app:CreateTagWithItem(385, 1))
failWrites = false
assert(counts.writes == 1 and store.data.tags["placeholder 2"] == nil)

-- A renamed shown tag is put once, under its new name
reset()
local saved, name = store:UpdateTag("gear", "kit")
assert(saved and name == "kit")
app:Renamed("gear", "kit")
assert(#counts.pages == 1 and counts.pages[1] == "kit" and app.shownTag == "kit")
assert(editor.selectedTag == "kit" and counts.center == 1)

print("store changes test passed")
