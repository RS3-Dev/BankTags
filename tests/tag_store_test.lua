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
local ItemIdentity = require("banktags/tags/item_identity")

local function key(objectID, copy) return "object:" .. objectID .. ":" .. (copy or 1) end
-- Return the object at a grid index of a tag's rows drawn ten wide
local function objectAt(store, tag, index)
    local slot = TagLayouts.Render(store.data.tags[tag].rows, 10).slots[index]
    return slot ~= nil and slot.kind == "item" and slot.objectID or nil
end

-- Membership ---------------------------------------------------------------------

local store = TagStore.new()
assert(store:CreateTag("melee", 4151))
assert(store:AddTag("melee", 4151, key(4151)))
-- Only the listed copy is in the tag, not a second stack
assert(store:HasTag("melee", key(4151)) and not store:HasTag("melee", key(4151, 2)))
assert(not store:HasTag("ranged", key(4151)))
-- Adding a listed copy again changes nothing
local saved, _, added = store:AddTag("melee", 4151, key(4151))
assert(saved and not added)
assert(not store:AddTag("missing", 4151, key(4151)))
-- With no copy given, an item joins as its first copy
assert(store:AddTag("melee", 385))
assert(store:HasTag("melee", key(385)))

-- New items go to Unsorted, or with fill placement into the layout
assert(#store.data.tags.melee.unsorted == 2 and #store.data.tags.melee.rows == 0)
store:SetLayoutPlacement(false)
assert(store:AddTag("melee", 100) and store:AddTag("melee", 101) and store:AddTag("melee", 102))
assert(objectAt(store, "melee", 1) == 100 and objectAt(store, "melee", 3) == 102)
assert(store:MoveLayoutItem("melee", key(4151), 4, 10))
assert(#store.data.tags.melee.unsorted == 1)

-- Removing an arranged item leaves a blank so later items keep their places
assert(store:RemoveTag("melee", key(102)))
assert(not store:HasTag("melee", key(102)))
assert(objectAt(store, "melee", 3) == nil and objectAt(store, "melee", 4) == 4151)
saved, _, added = store:RemoveTag("melee", key(102))
assert(saved and not added)
-- Fill placement takes the first open slot
assert(store:AddTag("melee", 103) and objectAt(store, "melee", 3) == 103)
store:SetLayoutPlacement(true)
assert(store:RemoveTag("melee", key(103)) and store:RemoveTag("melee", key(101)))
-- A trailing blank is not kept
assert(store:MoveLayoutItem("melee", key(4151), 3, 10))
assert(#store.data.tags.melee.rows[1].slots == 3 and objectAt(store, "melee", 2) == nil)

-- A ghost takes the next open slot after its source and opens it
local copied, ghost = store:DuplicateLayoutItem("melee", key(4151))
assert(copied and ghost == key(4151, 2))
local ghostSlot = TagLayouts.Render(store.data.tags.melee.rows, 10).slots[2]
assert(ghostSlot.layoutKey == ghost and ghostSlot.sourceLayoutKey == key(4151))
-- With no open slot, a copy ends its source's row
-- A copy of a ghost opens the original
local _, ghostOfGhost = store:DuplicateLayoutItem("melee", ghost)
assert(ghostOfGhost == key(4151, 3))
assert(TagLayouts.Render(store.data.tags.melee.rows, 10).slots[4].sourceLayoutKey == key(4151))
-- Removing a ghost removes only that ghost
assert(store:RemoveTag("melee", ghost))
assert(store:HasTag("melee", key(4151)) and store:HasTag("melee", ghostOfGhost))
assert(objectAt(store, "melee", 2) == nil and objectAt(store, "melee", 4) == 4151)

-- Tag names follow the limit saving enforces
assert(not store:CreateTag(string.rep("a", TagStore.MAX_TAG_NAME + 1)))
assert(store:CreateTag(string.rep("a", TagStore.MAX_TAG_NAME)))
assert(store:DeleteTag(string.rep("a", TagStore.MAX_TAG_NAME)))
assert(store:NextPlaceholderTagName() == "placeholder 1")

-- Saving and loading ------------------------------------------------------------

-- Items and icons are saved by config name, so new object IDs still load
local text = TagData.Encode(store.data, "melee")
assert(string.find(text, '"abyssal_whip"', 1, true) and string.find(text, '"abyssal_whip:3<1"', 1, true))
assert(not string.find(text, "4151", 1, true))
objects.abyssal_whip.id, byID[4151], byID[5000] = 5000, nil, objects.abyssal_whip
ItemIdentity.Reset()
local reloaded = TagStore.new()
assert(reloaded:HasTag("melee", key(5000)) and reloaded:GetTagSprite("melee") == 5000)
assert(reloaded:HasTag("melee", key(5000, 3)))
assert(Json.encode(reloaded:AllTags()) == Json.encode(store:AllTags()))

-- An item this client cannot name keeps its place and is written back unchanged
objects.abyssal_whip = nil
ItemIdentity.Reset()
reloaded = TagStore.new()
local dormant = reloaded.data.tags.melee.rows[1].slots[3]
assert(dormant.kind == "blank" and dormant.dormant == "abyssal_whip")
assert(not TagLayouts.IsOpen(dormant))
assert(reloaded:AddTag("melee", 200))
assert(string.find(TagData.Encode(reloaded.data, "melee"), '"abyssal_whip:3<1"', 1, true))

-- A failed save reports why and leaves the live data as it was
failWrites = true
local before = Json.encode(store.data)
local function refused(ok, ...)
    assert(not ok, "a failed save must report failure")
    assert(select("#", ...) > 0)
    assert(Json.encode(store.data) == before, "the live data must not change")
end
refused(store:CreateTag("potions"))
refused(store:AddTag("melee", 300))
refused(store:RemoveTag("melee", key(100)))
refused(store:UpdateTag("melee", "fighting"))
refused(store:DeleteTag("melee"))
refused(store:CreateFolder("Combat", "melee"))
refused(store:InsertLabel("melee", 0, "Weapons", 10))
refused(store:DuplicateLayoutItem("melee", key(100)))
refused(store:MoveLayoutItem("melee", key(100), 9, 10))
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

-- Renaming a tag keeps its folder; renaming the folder keeps its tags in it
assert(store:UpdateTag("mining", "mining gear"))
assert(store:GetTagFolder("mining gear") == folderKey)
local renamed, renamedKey = store:RenameFolder(folderKey, "Skilling")
assert(renamed and renamedKey == "skilling" and store:GetTagFolder("mining gear") == "skilling")
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
for objectID = 1, 12 do assert(store:AddTag("gear", objectID)) end
store:SetLayoutPlacement(true)
-- Return the grid rows the labels land on at a width
local function labelRows(columns)
    local rows = {}
    for _, label in ipairs(store:GetLabels("gear", columns or 10)) do rows[#rows + 1] = label.row end
    return table.concat(rows, ",")
end
-- Twelve items in one row, split into a row of ten and a row of two
assert(store:MoveLayoutItem("gear", key(11), 21, 10))
assert(store:MoveLayoutItem("gear", key(12), 22, 10))
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
assert(not store:MoveLayoutItem("gear", key(1), 5, 10))
local _, boundary = store:GetLayout("gear", 10)
assert(boundary == 50)

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
assert(target:GetTagFolder("alpha") == "combat" and target:HasTag("alpha", key(385)))

-- A tag with the same name is replaced
assert(target:AddTag("alpha", 4151))
assert(target:ImportText(shared))
assert(not target:HasTag("alpha", key(4151)) and target:HasTag("alpha", key(385)))

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
local function rowItem(objectID, copy, source)
    return { kind = "item", objectID = objectID, layoutKey = key(objectID, copy),
        sourceLayoutKey = source ~= nil and key(objectID, source) or nil }
end
-- Lines at ten wide: 0 Top, 1 a whip and its copy, 2-4 a row of 25 wrapping,
-- 5 an empty row, 6 End, 7 a shark beside a reserved slot
local long = {}
for objectID = 1, 25 do long[objectID] = rowItem(5000 + objectID) end
long[11], long[12] = { kind = "blank" }, { kind = "blank" }
rowsStore.data.tags.rows.rows = {
    { kind = "label", text = "Top" },
    { kind = "row", slots = { rowItem(4151, 1), rowItem(4151, 2, 1) } },
    { kind = "row", slots = long },
    { kind = "row", slots = {} },
    { kind = "label", text = "End" },
    { kind = "row", slots = { rowItem(385, 1), { kind = "blank", dormant = "gone_item" } } },
}
rowsStore.data.tags.rows.unsorted = { rowItem(385, 2) }
assert(rowsStore:Save())
-- Describe each grid line ten wide: a label's text, "-" for empty, or its first item
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

-- Copies, their sources, reserved slots, and Unsorted all stay as they were
local whipCopy = view.slots[32]
assert(whipCopy.layoutKey == key(4151, 2) and whipCopy.sourceLayoutKey == key(4151, 1))
assert(view.slots[112].dormant == "gone_item")
assert(Json.encode(rowsStore.data.tags.rows.unsorted) == unsortedBefore)

-- The empty rows survive a share code and a reload
local reloaded = assert(TagData.Decode(TagData.Encode(rowsStore.data, "rows")))
assert(Json.encode(reloaded.tags.rows.rows) == Json.encode(rowsStore.data.tags.rows.rows))
assert(Json.encode(TagStore.new().data.tags.rows.rows) == Json.encode(rowsStore.data.tags.rows.rows))

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
full[#full + 1] = { kind = "row", slots = { rowItem(385, 3) } }
rowsStore.data.tags.rows.rows, rowsStore.data.tags.rows.unsorted = full, {}
assert(rowsStore:Save())
rowsBefore = Json.encode(rowsStore.data)
local saved, reason = rowsStore:InsertLayoutRow("rows", 0, 10)
assert(not saved and reason:find("at most", 1, true) and Json.encode(rowsStore.data) == rowsBefore)

print("tag_store_test: ok")
