package.path = "./?.lua;./?/init.lua;" .. package.path

-- Saved strings, and a catalog naming only the whip and shark
local db, writes, failWrites = {}, 0, false
PersistentDB = {
    GetString = function(_, key) return db[key] end,
    SetString = function(_, key, value)
        if failWrites then return false end
        db[key], writes = value, writes + 1
        return true
    end,
}
local objects = {
    abyssal_whip = { id = 4151, configName = "abyssal_whip" },
    shark = { id = 385, configName = "shark" },
}
local byID = {}
for _, object in pairs(objects) do byID[object.id] = object end
config = { Obj = setmetatable({
    FromID = function(objectID) return byID[objectID] end,
}, { __index = function(_, name) return objects[name] end }) }

local Json = require("banktags/core/json")
local TagStore = require("banktags/tags/tag_store")
local TagData = require("banktags/tags/tag_data")
local TagLayouts = require("banktags/tags/tag_layouts")
-- Reload the store after item IDs change
local function reloadStore()
    for _, name in ipairs({ "banktags/tags/item_identity", "banktags/tags/tag_data", "banktags/tags/tag_store" }) do
        package.loaded[name] = nil
    end
    TagData = require("banktags/tags/tag_data")
    TagStore = require("banktags/tags/tag_store")
    return TagStore.new()
end

-- Report whether a tag holds the slot with a key
local function has(store, tag, layoutKey)
    for _, slot in ipairs(store:GetTaggedItems(tag)) do
        if slot.layoutKey == layoutKey then return true end
    end
    return false
end
-- Count a tag's slots for an object
local function count(store, tag, objectID)
    local total = 0
    for _, slot in ipairs(store:GetTaggedItems(tag)) do
        if slot.objectID == objectID then total = total + 1 end
    end
    return total
end
-- Read the item at a ten-column grid position
local function objectAt(store, tag, index)
    local slot = TagLayouts.Render(store.data.tags[tag].rows, 10).slots[index]
    return slot ~= nil and slot.kind == "item" and slot.objectID or nil
end

-- Membership ---------------------------------------------------------------------

local store = TagStore.new()
assert(store:CreateTag("melee", 4151))
local saved, _, whip = store:AddTag("melee", 4151)
assert(saved and has(store, "melee", whip))
assert(not has(store, "ranged", whip))
-- Adding the same item keeps a separate layout slot
local _, _, secondWhip = store:AddTag("melee", 4151)
assert(secondWhip ~= whip and count(store, "melee", 4151) == 2)
assert(not store:AddTag("missing", 4151))
assert(store:RemoveTag("melee", secondWhip) and count(store, "melee", 4151) == 1)
assert(store:AddTag("melee", 385))

-- New items go to Unsorted, or with fill placement into the layout
assert(#store.data.tags.melee.unsorted == 2 and #store.data.tags.melee.rows == 0)
store:SetLayoutPlacement(false)
local keys = {}
for objectID = 100, 102 do
    local added
    added, _, keys[objectID] = store:AddTag("melee", objectID)
    assert(added)
end
assert(objectAt(store, "melee", 1) == 100 and objectAt(store, "melee", 3) == 102)
assert(store:MoveLayoutItem("melee", whip, 4, 10))
assert(#store.data.tags.melee.unsorted == 1)

-- Removing an arranged item leaves a blank so later items keep their places
assert(store:RemoveTag("melee", keys[102]))
assert(not has(store, "melee", keys[102]))
assert(objectAt(store, "melee", 3) == nil and objectAt(store, "melee", 4) == 4151)
local removed
saved, _, removed = store:RemoveTag("melee", keys[102])
assert(saved and not removed)
-- Fill placement takes the first open slot
saved, _, keys[103] = store:AddTag("melee", 103)
assert(saved and objectAt(store, "melee", 3) == 103)
store:SetLayoutPlacement(true)
assert(store:RemoveTag("melee", keys[103]) and store:RemoveTag("melee", keys[101]))
-- A trailing blank is not kept
assert(store:MoveLayoutItem("melee", whip, 3, 10))
assert(#store.data.tags.melee.rows[1].slots == 3 and objectAt(store, "melee", 2) == nil)

-- Another slot for an object is placed like any new item; removing it leaves the first
_, _, secondWhip = store:AddTag("melee", 4151)
assert(store:MoveLayoutItem("melee", secondWhip, 4, 10))
assert(objectAt(store, "melee", 3) == 4151 and objectAt(store, "melee", 4) == 4151)
assert(store:RemoveTag("melee", secondWhip))
assert(has(store, "melee", whip) and count(store, "melee", 4151) == 1)
_, _, secondWhip = store:AddTag("melee", 4151)
assert(store:MoveLayoutItem("melee", secondWhip, 4, 10))

-- Tag names follow the limit saving enforces
assert(not store:CreateTag(string.rep("a", TagStore.MAX_TAG_NAME + 1)))
assert(store:CreateTag(string.rep("a", TagStore.MAX_TAG_NAME)))
assert(store:DeleteTag(string.rep("a", TagStore.MAX_TAG_NAME)))
assert(store:NextPlaceholderTagName() == "placeholder 1")

-- Saving and loading ------------------------------------------------------------

-- Keep saved item names across ID changes and repeated slots
local text = TagData.Encode(store.data, "melee")
assert(string.find(text, '"abyssal_whip","abyssal_whip"', 1, true))
assert(not string.find(text, "4151", 1, true) and not string.find(text, "abyssal_whip:", 1, true))
objects.abyssal_whip.id, byID[4151], byID[5000] = 5000, nil, objects.abyssal_whip
local reloaded = reloadStore()
assert(count(reloaded, "melee", 5000) == 2 and reloaded:GetTagSprite("melee") == 5000)
assert(Json.encode(reloaded:AllTags()) == Json.encode(store:AllTags()))

-- An item this client cannot name keeps its place and is written back unchanged
objects.abyssal_whip = nil
reloaded = reloadStore()
local dormant = reloaded.data.tags.melee.rows[1].slots[3]
assert(dormant.kind == "blank" and dormant.dormant == "abyssal_whip")
assert(not TagLayouts.IsOpen(dormant))
assert(reloaded:AddTag("melee", 200))
assert(string.find(TagData.Encode(reloaded.data, "melee"), '"abyssal_whip","abyssal_whip"', 1, true))

-- A failed save reports why and leaves the live data as it was
failWrites = true
local before = Json.encode(store.data)
-- Check that a failed save leaves live data unchanged
local function refused(ok, ...)
    assert(not ok, "a failed save must report failure")
    assert(select("#", ...) > 0)
    assert(Json.encode(store.data) == before, "the live data must not change")
end
refused(store:CreateTag("potions"))
refused(store:AddTag("melee", 300))
refused(store:RemoveTag("melee", keys[100]))
refused(store:UpdateTag("melee", "fighting"))
refused(store:DeleteTag("melee"))
refused(store:CreateFolder("Combat", "melee"))
refused(store:InsertLabel("melee", 0, "Weapons", 10))
refused(store:PasteLayoutItems("melee", { { objectID = 100, line = 0, column = 0 } }, 9, 10))
refused(store:MoveLayoutItem("melee", keys[100], 9, 10))
refused(store:ImportText(TagData.Encode(store.data, "melee"), { name = "copy" }))
failWrites = false

-- Folders ------------------------------------------------------------------------

db = {}
store = TagStore.new()
for _, tag in ipairs({ "food", "mining", "woodcutting" }) do assert(store:CreateTag(tag)) end
local created, folderKey = store:CreateFolder("  Gathering   Skills ", "mining")
assert(created and folderKey == "gathering skills")
assert(store:GetFolder(folderKey).name == "Gathering Skills")
assert(store:GetTagFolder("mining") == folderKey)
assert(store:SetTagFolder("woodcutting", folderKey))

-- The folder appears where its first member appears in the tag order
local tree = store:TagTree()
assert(#tree == 2 and tree[1].tag == "food" and tree[2].key == folderKey)
assert(#tree[2].tags == 2 and tree[2].tags[1] == "mining")

-- Reusing a folder name joins the existing folder
local _, sameKey = store:CreateFolder("GATHERING SKILLS", "food")
assert(sameKey == folderKey and #store:TagTree() == 1)
assert(store:SetTagFolder("food", nil))

-- Collapse state survives a reload
assert(store:SetFolderCollapsed(folderKey, true))
assert(TagStore.new():GetFolder(folderKey).collapsed == true)

-- Folder icons survive saves and share codes without changing membership
assert(store:RenameFolder(folderKey, "Gathering Skills", 385))
assert(store:GetFolderSprite(folderKey) == 385 and store:GetFolder(folderKey).icon == "shark")
assert(TagStore.new():GetFolderSprite(folderKey) == 385)
local sharedFolder = assert(TagData.Decode(TagData.Encode(store.data, "mining")))
assert(sharedFolder.folders[folderKey].icon == "shark")
local importedFolder = TagStore.new()
assert(importedFolder:ImportText(TagData.Encode(store.data, "mining")))
assert(importedFolder:GetFolderSprite(folderKey) == 385)
local folderBefore = Json.encode(store.data)
assert(not store:RenameFolder(folderKey, "Gathering Skills", -1))
assert(Json.encode(store.data) == folderBefore)
failWrites = true
assert(not store:RenameFolder(folderKey, "Gathering Skills", 4151))
assert(Json.encode(store.data) == folderBefore)
failWrites = false

-- Renaming a tag keeps its folder; renaming the folder keeps its tags in it
assert(store:UpdateTag("mining", "mining gear"))
assert(store:GetTagFolder("mining gear") == folderKey)
local renamed, renamedKey = store:RenameFolder(folderKey, "Skilling")
assert(renamed and renamedKey == "skilling" and store:GetTagFolder("mining gear") == "skilling")
assert(store:GetFolderSprite("skilling") == 385)
assert(not store:UpdateTag("mining gear", "woodcutting"))
assert(store:CreateFolder("Other", "food"))
assert(not store:RenameFolder("other", "skilling"))

-- A folder with no tags left is dropped, so its name is free again
assert(store:SetTagFolder("food", nil))
assert(store:GetFolder("other") == nil)
assert(store:DeleteFolder("skilling"))
assert(store:GetTagFolder("mining gear") == nil and #store:AllTags() == 3)

-- AllTags hands out copies
local tags = store:AllTags()
tags[1] = "mutated"
assert(store:AllTags()[1] ~= "mutated")

-- Labels and rows ----------------------------------------------------------------

store = TagStore.new()
assert(store:CreateTag("gear"))
store:SetLayoutPlacement(false)
local gear = {}
for objectID = 1, 12 do
    local added
    added, _, gear[objectID] = store:AddTag("gear", objectID)
    assert(added)
end
store:SetLayoutPlacement(true)
-- List the grid rows containing labels
local function labelRows(columns)
    local rows = {}
    for _, label in ipairs(store:GetLabels("gear", columns or 10)) do rows[#rows + 1] = label.row end
    return table.concat(rows, ",")
end
-- Twelve items in one row, split into a row of ten and a row of two
assert(store:MoveLayoutItem("gear", gear[11], 21, 10))
assert(store:MoveLayoutItem("gear", gear[12], 22, 10))
assert(#store.data.tags.gear.rows == 2 and objectAt(store, "gear", 12) == 12)

-- Label text is cleaned
assert(store:SetLabel("gear", 5, "  <col=ff0000>Odd</col> ", 10))
assert(store:GetLabel("gear", 2, 10) == "col=ff0000Odd/col")
assert(store:SetLabel("gear", 2, nil, 10) and labelRows() == "")
assert(not store:SetLabel("gear", -1, "Bad", 10))

-- A label dropped on a row of items goes above them
assert(store:InsertLabel("gear", 0, "Weapons", 10))
assert(labelRows() == "0" and objectAt(store, "gear", 1) == nil and objectAt(store, "gear", 11) == 1)

-- Labels past the layout land just below it
assert(store:InsertLabel("gear", 3, "Food", 10))
assert(store:InsertLabel("gear", math.maxinteger, "Potions", 10))
assert(labelRows() == "0,3,4")
-- In a narrower bank the full row wraps onto three lines, pushing labels down
assert(labelRows(4) == "0,5,6")

-- Items cannot drop onto labels; the layout ends after the last label
assert(not store:MoveLayoutItem("gear", gear[1], 5, 10))
local view = store:EditorLayout("gear", 10)
assert(view.lines == 5 and #view.slots == 50 and #view.labels == 3)
-- The editor's view finds each item slot by its key, on the grid or in Unsorted
for index, slot in ipairs(view.slots) do
    if slot.kind == "item" then assert(view.sortedIndex[slot.layoutKey] == index) end
end
for index, slot in ipairs(view.unsorted) do assert(view.unsortedIndex[slot.layoutKey] == index) end
assert(store:EditorLayout("missing", 10).lines == 0 and #store:EditorLayout("missing", 10).unsorted == 0)

-- Removing a label lifts everything below it
assert(store:RemoveLabel("gear", 0, 10))
assert(labelRows() == "2,3" and objectAt(store, "gear", 1) == 1)
assert(not store:RemoveLabel("gear", 0, 10))

-- Moving a label carries only the label
local moved, _, changed = store:MoveLabel("gear", 3, 0, 10)
assert(moved and changed and labelRows() == "0,3")
assert(objectAt(store, "gear", 11) == 1)
moved, _, changed = store:MoveLabel("gear", 0, 1, 10)
assert(moved and not changed)

-- Renaming and deleting a tag carries its labels
assert(store:UpdateTag("gear", "kit"))
assert(store:GetLabel("kit", 0, 10) == "Potions" and #store:GetLabels("gear", 10) == 0)
assert(store:DeleteTag("kit") and store.data.tags.kit == nil)

-- Sharing and import --------------------------------------------------------------

db = {}
local source = TagStore.new()
assert(source:CreateTag("alpha", 385))
assert(source:AddTag("alpha", 385))
assert(source:CreateFolder("Combat", "alpha"))
assert(source:SetLabel("alpha", 0, "Melee, ranged | mixed", 10))
assert(source:CreateTag("beta"))
local exports = source:TagExports()
assert(#exports == 2 and exports[1].tag == "alpha" and exports[1].length == #exports[1].value)
local shared = exports[1].value
local backup = TagData.Encode(source.data)

-- A shared tag reads back with its folder, label, and icon
local preview = assert(TagData.Decode(shared))
assert(#preview.order == 1 and preview.tags.alpha.folder == "combat")
assert(preview.folders.combat.name == "Combat" and preview.tags.alpha.icon == "shark")
assert(preview.tags.alpha.rows[1].text == "Melee, ranged | mixed")

-- Bad text is refused
for _, bad in ipairs({ "", "not json", Json.encode({ format = "other" }),
    TagData.Encode(TagData.Empty()) }) do
    local result, reason = TagData.Decode(bad)
    assert(result == nil and reason ~= nil)
end

db = {}
local target = TagStore.new()
assert(target:CreateTag("existing"))
assert(target:CreateFolder("Mine", "existing"))
-- A backup brings every tag and folder, placed first
local imported, summary = target:ImportText(backup)
assert(imported and summary.tags == 2)
assert(Json.encode(target:AllTags()) == Json.encode({ "alpha", "beta", "existing" }))
assert(target:GetTagFolder("alpha") == "combat" and count(target, "alpha", 385) == 1)

-- A tag with the same name is replaced
assert(target:AddTag("alpha", 4151))
assert(target:ImportText(shared))
assert(count(target, "alpha", 4151) == 0 and count(target, "alpha", 385) == 1)

-- One shared tag can take a new name, icon, and folder
assert(target:ImportText(shared, { name = "Renamed", spriteObjectID = 4151, folderKey = "mine" }))
assert(target:GetTagSprite("renamed") == 4151 and target:GetTagFolder("renamed") == "mine")
local mine = target:TagTree()
for _, node in ipairs(mine) do
    if node.kind == "folder" and node.key == "mine" then assert(node.tags[2] == "renamed") end
end
assert(target:ImportText(shared, { name = "loose", folderKey = false }))
assert(target:GetTagFolder("loose") == nil)
assert(target:ImportText(shared, { name = "fresh", newFolderName = "New Stuff" }))
assert(target:GetFolder("new stuff").name == "New Stuff")
-- Options need a single tag, a valid name, and an existing folder
before = Json.encode(target.data)
assert(not target:ImportText(backup, { name = "single" }))
assert(not target:ImportText(shared, { name = "a,b" }))
assert(not target:ImportText(shared, { folderKey = "gone" }))
assert(not target:ImportText(shared, { newFolderName = string.rep("x", 41) }))
assert(Json.encode(target.data) == before)

-- Empty layout rows -----------------------------------------------------------------

db = {}
local rowsStore = TagStore.new()
assert(rowsStore:CreateTag("rows"))
local rowItem = TagLayouts.Item
-- Use a wrapped 25-item row, labels, blanks, and reserved slots
local long = {}
for objectID = 1, 25 do long[objectID] = rowItem(5000 + objectID) end
long[11], long[12] = { kind = "blank" }, { kind = "blank" }
local secondRowWhip = rowItem(4151)
rowsStore.data.tags.rows.rows = {
    { kind = "label", text = "Top" },
    { kind = "row", slots = { rowItem(4151), secondRowWhip } },
    { kind = "row", slots = long },
    { kind = "row", slots = {} },
    { kind = "label", text = "End" },
    { kind = "row", slots = { rowItem(385), { kind = "blank", dormant = "gone_item" } } },
}
rowsStore.data.tags.rows.unsorted = { rowItem(385) }
assert(rowsStore:Save())
-- Describe the saved layout in reading order
local function lines()
    local view = TagLayouts.Render(rowsStore.data.tags.rows.rows, 10)
    local out = {}
    for line = 0, view.lines - 1 do
        local text = "-"
        for _, label in ipairs(view.labels) do if label.row == line then text = label.text end end
        for cell = line * 10 + 1, line * 10 + 10 do
            local slot = view.slots[cell]
            if text == "-" and slot.kind == "item" then text = tostring(slot.objectID) end
            if text == "-" and slot.dormant ~= nil then text = "reserved" end
        end
        out[#out + 1] = text
    end
    return table.concat(out, " ")
end
local unsortedBefore = Json.encode(rowsStore.data.tags.rows.unsorted)
assert(lines() == "Top 4151 5001 5013 5021 - End 385", lines())

-- One save moves a label and everything after it down a line
writes = 0
assert(rowsStore:InsertLayoutRow("rows", 0, 10))
assert(writes > 0 and lines() == "- Top 4151 5001 5013 5021 - End 385", lines())
local saveWrites = writes
-- Above a row, and above the label after an empty row
assert(rowsStore:InsertLayoutRow("rows", 2, 10))
assert(lines() == "- Top - 4151 5001 5013 5021 - End 385", lines())
assert(writes == saveWrites * 2, "one insert is one save")
assert(rowsStore:InsertLayoutRow("rows", 8, 10))
assert(lines() == "- Top - 4151 5001 5013 5021 - - End 385", lines())

-- Inside a wrapped row, the row splits at the line; its blank cells stay put
assert(rowsStore:InsertLayoutRow("rows", 5, 10))
assert(lines() == "- Top - 4151 5001 - 5013 5021 - - End 385", lines())
local view = TagLayouts.Render(rowsStore.data.tags.rows.rows, 10)
assert(view.slots[61].kind == "blank" and view.slots[62].kind == "blank" and view.slots[63].objectID == 5013)
assert(view.slots[71].objectID == 5021 and view.slots[75].objectID == 5025)
-- A wrapped line that splits off empty keeps its line as a row of its own
local blanks = {}
for position = 1, 30 do blanks[position] = { kind = "blank" } end
blanks[1], blanks[30] = rowItem(6001), rowItem(6002)
rowsStore.data.tags.rows.rows[#rowsStore.data.tags.rows.rows + 1] = { kind = "row", slots = blanks }
assert(rowsStore:Save())
assert(lines() == "- Top - 4151 5001 - 5013 5021 - - End 385 6001 - 6002", lines())
assert(rowsStore:InsertLayoutRow("rows", 14, 10))
assert(lines() == "- Top - 4151 5001 - 5013 5021 - - End 385 6001 - - 6002", lines())
view = TagLayouts.Render(rowsStore.data.tags.rows.rows, 10)
assert(view.slots[160].objectID == 6002)

-- Repeated objects, reserved slots, and Unsorted all stay as they were
assert(view.slots[32].layoutKey == secondRowWhip.layoutKey)
assert(view.slots[112].dormant == "gone_item")
assert(Json.encode(rowsStore.data.tags.rows.unsorted) == unsortedBefore)

-- The empty rows survive a share code and a reload
-- Reading gives slots new keys, so compare the saved text
local savedRows = TagData.Encode(rowsStore.data, "rows")
local reloaded = assert(TagData.Decode(savedRows))
assert(TagData.Encode(reloaded, "rows") == savedRows)
assert(TagData.Encode(TagStore.new().data, "rows") == savedRows)

-- Lines past the layout, bad lines, and missing tags change nothing
local rowsBefore = Json.encode(rowsStore.data)
writes = 0
for _, case in ipairs({ { "rows", 16 }, { "rows", 99 }, { "rows", -1 }, { "rows", "x" }, { "gone", 0 } }) do
    local saved, reason = rowsStore:InsertLayoutRow(case[1], case[2], 10)
    assert(not saved and reason ~= nil)
end
assert(writes == 0 and Json.encode(rowsStore.data) == rowsBefore)

-- A full tag refuses another row, with a reason the editor can show
local full = {}
for index = 1, TagData.EDIT_ENTRY_LIMIT - 2 do full[index] = { kind = "label", text = "L" .. index } end
full[#full + 1] = { kind = "row", slots = { rowItem(385) } }
rowsStore.data.tags.rows.rows, rowsStore.data.tags.rows.unsorted = full, {}
assert(rowsStore:Save())
rowsBefore = Json.encode(rowsStore.data)
local saved, reason = rowsStore:InsertLayoutRow("rows", 0, 10)
assert(not saved and reason:find("at most", 1, true) and Json.encode(rowsStore.data) == rowsBefore)

-- Removing a row -------------------------------------------------------------------

-- Use a wrapped 12-item row beside labels and reserved slots
local wrapping = {}
for index = 1, 12 do wrapping[index] = rowItem(5000 + index) end
rowsStore.data.tags.rows.rows = {
    { kind = "label", text = "Top" },
    { kind = "row", slots = { rowItem(4151), rowItem(4151) } },
    { kind = "row", slots = wrapping },
    { kind = "row", slots = { rowItem(385), { kind = "blank", dormant = "gone_item" }, rowItem(4151) } },
}
rowsStore.data.tags.rows.unsorted = { rowItem(385) }
assert(rowsStore:Save())
unsortedBefore = Json.encode(rowsStore.data.tags.rows.unsorted)
assert(lines() == "Top 4151 5001 5011 385", lines())
-- Each line reports what removing it takes out of the tag
local contents = rowsStore:LayoutLineContents("rows", 0, 10)
assert(contents.label == "Top" and contents.items == 0 and contents.reserved == 0 and not contents.empty)
contents = rowsStore:LayoutLineContents("rows", 1, 10)
assert(contents.label == nil and contents.items == 2 and contents.reserved == 0 and not contents.empty)
assert(rowsStore:LayoutLineContents("rows", 3, 10).items == 2)
contents = rowsStore:LayoutLineContents("rows", 4, 10)
assert(contents.items == 2 and contents.reserved == 1)
assert(rowsStore:LayoutLineContents("rows", 5, 10) == nil and rowsStore:LayoutLineContents("gone", 0, 10) == nil)
-- A wrapped row loses only the removed line, in one save; every later line moves up
writes = 0
assert(rowsStore:RemoveLayoutRow("rows", 2, 10))
assert(writes > 0 and lines() == "Top 4151 5011 385", lines())
assert(count(rowsStore, "rows", 5001) == 0 and count(rowsStore, "rows", 5010) == 0)
assert(count(rowsStore, "rows", 5011) == 1 and count(rowsStore, "rows", 5012) == 1)
-- A label's line takes only the label
assert(rowsStore:RemoveLayoutRow("rows", 0, 10))
assert(lines() == "4151 5011 385", lines())
-- A row's items leave the tag as Remove does; a slot elsewhere for the same object stays
assert(rowsStore:RemoveLayoutRow("rows", 0, 10))
assert(lines() == "5011 385", lines())
assert(count(rowsStore, "rows", 4151) == 1)
view = TagLayouts.Render(rowsStore.data.tags.rows.rows, 10)
assert(view.slots[12].dormant == "gone_item" and view.slots[13].objectID == 4151)
assert(Json.encode(rowsStore.data.tags.rows.unsorted) == unsortedBefore)
-- Lines past the layout, bad lines, missing tags, and a failed save change nothing
rowsBefore = Json.encode(rowsStore.data)
for _, case in ipairs({ { "rows", 2 }, { "rows", -1 }, { "rows", "x" }, { "gone", 0 } }) do
    local removed, why = rowsStore:RemoveLayoutRow(case[1], case[2], 10)
    assert(not removed and why ~= nil)
end
failWrites = true
local removed, why = rowsStore:RemoveLayoutRow("rows", 0, 10)
failWrites = false
assert(not removed and why ~= nil and Json.encode(rowsStore.data) == rowsBefore)

-- Pasting copies -------------------------------------------------------------------

-- Pasted objects keep their offsets, each in a new slot with its own key
local items = {
    { objectID = 5011, line = 0, column = 0 },
    { objectID = 4151, line = 1, column = 2 },
}
writes = 0
local pasted, pastedKeys = rowsStore:PasteLayoutItems("rows", items, 6, 10)
assert(pasted and #pastedKeys == 2 and pastedKeys[1] ~= pastedKeys[2] and writes > 0)
view = TagLayouts.Render(rowsStore.data.tags.rows.rows, 10)
assert(view.slots[6].layoutKey == pastedKeys[1] and view.slots[6].objectID == 5011)
assert(view.slots[18].layoutKey == pastedKeys[2] and view.slots[18].objectID == 4151)
assert(count(rowsStore, "rows", 5011) == 2 and count(rowsStore, "rows", 4151) == 2)
-- One object pasted twice gets two slots; below the rows they add lines
local pair = {
    { objectID = 4151, line = 0, column = 0 },
    { objectID = 4151, line = 1, column = 1 },
}
pasted, pastedKeys = rowsStore:PasteLayoutItems("rows", pair, 41, 10)
assert(pasted and pastedKeys[1] ~= pastedKeys[2])
view = TagLayouts.Render(rowsStore.data.tags.rows.rows, 10)
assert(view.lines == 6 and view.slots[41].layoutKey == pastedKeys[1] and view.slots[52].layoutKey == pastedKeys[2])
-- An item, a reserved slot, a label, the right edge, or one blocked copy refuses the whole paste
assert(rowsStore:InsertLabel("rows", 2, "Mid", 10))
rowsBefore = Json.encode(rowsStore.data)
local one = { { objectID = 385, line = 0, column = 0 } }
local blocked = { one[1], { objectID = 385, line = 0, column = 1 } }
local offEdge = { one[1], { objectID = 385, line = 0, column = 3 } }
writes = 0
for _, case in ipairs({ { one, 1 }, { one, 12 }, { one, 21 }, { blocked, 5 }, { offEdge, 8 }, { one, 0 }, { {}, 3 } }) do
    local ok, pastedKeys, refusal = rowsStore:PasteLayoutItems("rows", case[1], case[2], 10)
    assert(not ok and pastedKeys == nil and refusal ~= nil, tostring(case[2]))
end
assert(writes == 0 and Json.encode(rowsStore.data) == rowsBefore)
-- A failed save, or a tag already full, pastes nothing
failWrites = true
local ok, _, failure = rowsStore:PasteLayoutItems("rows", one, 5, 10)
failWrites = false
assert(not ok and failure ~= nil and Json.encode(rowsStore.data) == rowsBefore)
full = {}
for index = 1, TagData.EDIT_ENTRY_LIMIT - 2 do full[index] = { kind = "label", text = "L" .. index } end
full[#full + 1] = { kind = "row", slots = { rowItem(385) } }
rowsStore.data.tags.rows.rows, rowsStore.data.tags.rows.unsorted = full, {}
assert(rowsStore:Save())
rowsBefore = Json.encode(rowsStore.data)
ok, _, failure = rowsStore:PasteLayoutItems("rows", one, (#full - 1) * 10 + 2, 10)
assert(not ok and failure:find("at most", 1, true) and Json.encode(rowsStore.data) == rowsBefore)

print("tag_store_test: ok")
