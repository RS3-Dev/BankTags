package.path = "./?.lua;./?/init.lua;" .. package.path

-- Show each saved change once, only where it shows, and add search results in one save
-- FAKE HOST: stand-in loader, components, pointer, and saves, not the game client

local Harness = require("tools/test_support/tags_harness")
local Geometry = require("banktags/ui/geometry")
local h = Harness.new("store_changes")
local host = h.bankHost
host:SetItems({ { 4151, 1, "Abyssal whip" }, { 385, 20, "Shark" } })
host.itemLayer.interfaceID = 517
local core = h:LoadCore()
h:LoadTags()
local app = h:App()
h:OpenBank()
h:Tick(12)

local TagLayouts = h:TagsModule("banktags/tags/tag_layouts")
local store = app.store
local App = getmetatable(app)
local Size = h:TagsModule("banktags/windows/layout_editor_parts").size
local COLUMNS = Size.CENTER_COLUMNS
local item = TagLayouts.Item
local function row(...) return { kind = "row", slots = { ... } } end
-- Count a tag's slots for an object
local function count(tag, objectID)
    local total = 0
    for _, slot in ipairs(store:GetTaggedItems(tag)) do
        if slot.objectID == objectID then total = total + 1 end
    end
    return total
end
-- Line 0 holds 1 and 2, line 1 is a label, line 2 holds 5
for _, tag in ipairs({ "gear", "food" }) do assert(store:CreateTag(tag)) end
store.data.tags.gear.rows = { row(item(1), item(2)), { kind = "label", text = "Mid" }, row(item(5)) }
assert(store:Save())
app:Changed()

-- Count every redraw and save from here on
local counts
local function reset()
    counts = { center = 0, rail = 0, tab = 0, pages = {}, exports = 0, writes = 0 }
end
reset()
local tabRefresh = app.tab.Refresh
app.tab.Refresh = function(tab) counts.tab = counts.tab + 1; return tabRefresh(tab) end
app.SetTagPage = function(self, tag)
    counts.pages[#counts.pages + 1] = tag
    return App.SetTagPage(self, tag)
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
    h:PointEditor(pane.x + x, pane.y + y)
    return x, y
end
local function drag(fromColumn, fromLine, toColumn, toLine)
    h:PressEditor(editor.panes.sorted.surface, pointAt("sorted", fromColumn, fromLine))
    pointAt("sorted", toColumn, toLine)
    editor.panes.sorted.surface.hooks.drag()
    h:ReleaseEditor()
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

-- A drag that changes nothing only selects, so neither grid nor anything else redraws
reset()
drag(1, 0, 1, 0)
assert(counts.center == 0 and #counts.pages == 0 and counts.exports == 0 and counts.writes == 0)

-- Outside changes reach only what shows them --------------------------------------

-- Another tag's items leave the editor and page alone
reset()
assert(app:AddItemToTag("food", 385))
assert(counts.center == 0 and counts.rail == 0 and counts.tab == 0 and #counts.pages == 0)
assert(counts.exports == 1)

-- The open tag's items redraw its grids once and forget its undo steps
assert(editor.history ~= nil)
reset()
assert(app:AddItemToTag("gear", 4151))
assert(counts.center == 1 and counts.rail == 0 and counts.tab == 0)
assert(#counts.pages == 1 and editor.history == nil)

-- A new tag shows in the Tags tab and the rail
reset()
assert(store:CreateTag("tools"))
app:Changed()
assert(counts.tab == 1 and counts.rail == 1 and counts.center == 1 and #counts.pages == 1)

-- A search result is added and placed in one save and one undo step ------------------

local before = store.data
local function unchanged(where)
    assert(store.data == before and count("gear", 385) == 0, where .. ": the data changed")
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
local added = store.data.tags.gear.rows[1].slots[3]
assert(counts.writes == 1 and added.objectID == 385)
assert(editor.selectedLayoutKey == added.layoutKey)
editedOnce("search add")
assert(#editor.history.states == 2)

-- An item already in the tag gets another placed slot the same way
reset()
assert(editor:AddCatalogResult({ objectId = 385 }, 5))
local again = store.data.tags.gear.rows[1].slots[5]
assert(counts.writes == 1 and again.objectID == 385 and again.layoutKey ~= added.layoutKey)

reset()
assert(editor:Undo() and editor:Undo())
assert(count("gear", 385) == 0)
assert(counts.writes == 2 and counts.center == 2)

-- An edit that errors keeps the old data and lets later saves write
before = store.data
local ok = pcall(store.SaveTogether, store, function()
    assert(store:AddTag("food", 4151))
    error("broken edit")
end)
assert(not ok and store.data == before and not store.holdSave)

-- A renamed shown tag is put once, under its new name
reset()
local saved, name = store:UpdateTag("gear", "kit")
assert(saved and name == "kit")
app:Renamed("gear", "kit")
assert(#counts.pages == 1 and counts.pages[1] == "kit" and app:ShownTag() == "kit")
assert(editor.selectedTag == "kit" and counts.center == 1)

-- A change to the shown tag never takes the bank from another plugin's page,
-- even before Bank Core says its page closed; the player's click shows the tag again
local layout = h:Session().layout
local other = assert(core.result.Register({ id = "test.other", name = "Other" }))
assert(other:SetPage({ rows = { { slots = { 385 } } } }) and other:Open())
reset()
assert(app:AddItemToTag("kit", 385))
assert(#counts.pages == 0 and other:IsOpen())
h:Tick(2)
assert(app:ShownTag() == nil and other:IsOpen())
assert(app:ShowTag("kit") and not other:IsOpen() and app:ShownTag() == "kit")
-- Once the player picks a native tab, a change to the tag shows nothing
layout:SetNativeViewAll(false)
reset()
assert(app:AddItemToTag("kit", 385))
h:Tick(2)
assert(#counts.pages == 0 and layout.shownPage == nil and app:ShownTag() == nil)
layout:SetNativeViewAll(true)
assert(other:Dispose())

print("store changes test passed")
