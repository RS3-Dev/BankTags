package.path = "./?.lua;./?/init.lua;" .. package.path

-- Check page conversion, size limits, and safe failures
-- FAKE HOST: stand-in components and storage

local Harness = require("tools/test_support/tags_harness")
local h = Harness.new("tag_page")
h.bankHost:SetItems({ { 4151, 1, "Abyssal whip" }, { 4151, 1, "Abyssal whip" }, { 385, 20, "Shark" } })
local core = h:LoadCore()
local api = core.result

local Json = require("banktags/core/json")
local TagData = require("banktags/tags/tag_data")
local TagPage = require("banktags/tags/tag_page")
local TagStore = require("banktags/tags/tag_store")
local item = require("banktags/tags/tag_layouts").Item

local db = h.bankHost.db
-- Create an open layout slot
local function blank() return { kind = "blank" } end
-- Build a layout row from the supplied slots
local function row(...) return { kind = "row", slots = { ... } } end
-- Create a layout label for the test
local function label(text) return { kind = "label", text = text } end

-- A test extension passes pages to Core's public API, as Bank Tags does
local ext = assert(api.Register({ id = "test.tags", name = "Tag pages" }))
-- Report whether Core accepted a page
local function accepts(page)
    local ok, reason, detail = ext:SetPage(page)
    if not ok then return false, tostring(reason) .. ": " .. tostring(detail) end
    return true
end

-- Conversion -------------------------------------------------------------------------

-- An object listed again keeps each slot; Core shows its next stack there
local whip, second, third, shark = item(4151), item(4151), item(4151), item(385)
local extra = item(4151)
local record = {
    rows = {
        label("Weapons"),
        row(whip, blank(), second, third),
        row(),
        label("Food\tand drink"),
        row({ kind = "blank", dormant = "unknown_item" }, shark),
    },
    unsorted = { extra, { kind = "blank", dormant = "gone" } },
}
local rows, keys, count = TagPage.Rows(record)
assert(Json.encode(rows) == Json.encode({
    { label = "Weapons" },
    { slots = { 4151, false, 4151, 4151 } },
    { slots = {} },
    { label = "Foodand drink" },
    { slots = { false, 385 } },
    { label = "Unsorted" },
    { slots = { 4151 } },
}), Json.encode(rows))
assert(count == 1 + 5 + 1 + 1 + 3 + 2 + 1)
-- Unresolved items stay as blanks; unresolved Unsorted entries are hidden
assert(rows[5].slots[1] == false and #rows[7].slots == 1)
-- Each page slot, blanks included and labels not, maps back to its saved slot
assert(#keys == 7 and keys[1] == whip.layoutKey and keys[2] == false and keys[3] == second.layoutKey)
assert(keys[4] == third.layoutKey and keys[5] == false and keys[6] == shark.layoutKey)
assert(keys[7] == extra.layoutKey)

-- An empty tag has no rows and no Unsorted label
rows, keys, count = TagPage.Rows({ rows = {}, unsorted = {} })
assert(#rows == 0 and #keys == 0 and count == 0)

-- Core accepts rows without a page title
local store = TagStore.new()
assert(store:CreateTag("supplies"))
store.data.tags.supplies.rows = record.rows
store.data.tags.supplies.unsorted = record.unsorted
local page, pageKeys = TagPage.Build(store, "supplies")
assert(page.title == nil and #pageKeys == 7)
assert(accepts(page))
assert(TagPage.Build(store, "missing") == nil)

-- The entry budget -------------------------------------------------------------------

-- A tag at the edit limit, with Unsorted items, fits Bank Core's page limit exactly
db = h.bankHost.db
for name in pairs(db) do db[name] = nil end
store = TagStore.new()
assert(store:CreateTag("full"))
local full = store.data.tags.full
full.rows = {}
-- One row and one Unsorted item add up to the edit limit
local slots = {}
for index = 1, TagData.EDIT_ENTRY_LIMIT - 2 do
    slots[index] = index % 2 == 0 and blank() or item(100000 + index)
end
slots[#slots] = item(99999)
full.rows[1] = { kind = "row", slots = slots }
local unsortedWhip = item(4151)
full.unsorted = { unsortedWhip }
assert(TagData.EntryCount(full) == TagData.EDIT_ENTRY_LIMIT)
assert(store:Save())
page = TagPage.Build(store, "full")
local _, _, pageEntries = TagPage.Rows(full)
assert(page ~= nil and pageEntries == TagPage.MAX_ENTRIES)
assert(accepts(page))

-- An edit cannot grow the tag past the limit or save
local saved = Json.encode(db)
local added, reason = store:AddTag("full", 385)
assert(not added and string.find(reason, "at most", 1, true))
assert(Json.encode(db) == saved and store.data.tags.full.unsorted[2] == nil)
-- Removing still works
assert(store:RemoveTag("full", unsortedWhip.layoutKey))

-- A full-limit saved tag loads and saves whole, but is too large to show
full = store.data.tags.full
full.unsorted = { item(4151), item(4151), item(385), item(385) }
assert(TagData.EntryCount(full) == TagData.MAX_TAG_ENTRIES + 1)
local tooLargeText = TagData.Encode(store.data)
assert(TagData.Decode(tooLargeText, true) == nil, "a save over the full limit is not readable")
table.remove(full.unsorted)
assert(TagData.EntryCount(full) == TagData.MAX_TAG_ENTRIES)
local legacyText = TagData.Encode(store.data)
db = h.bankHost.db
for name in pairs(db) do db[name] = nil end
local ChunkedStringStore = require("banktags/core/chunked_string_store")
assert(ChunkedStringStore.Write({ manifestKey = "banktags:tags:v4:manifest",
    chunkPrefix = "banktags:tags:v4:" }, legacyText))
local legacy = TagStore.new()
assert(legacy.loadError == nil and TagData.EntryCount(legacy.data.tags.full) == TagData.MAX_TAG_ENTRIES)
local notice
page, notice = TagPage.Build(legacy, "full")
assert(page == nil and string.find(notice, tostring(TagData.MAX_TAG_ENTRIES + 2), 1, true))
-- Loading, unrelated edits, and saving keep the oversized tag whole
assert(legacy:CreateTag("other"))
assert(TagData.EntryCount(TagStore.new().data.tags.full) == TagData.MAX_TAG_ENTRIES)
assert(TagData.Encode(legacy.data, "full") == TagData.Encode(TagData.Decode(legacyText, true), "full"))
-- It may not grow, but it may shrink until it fits again
assert(not legacy:AddTag("full", 385))
local loaded = legacy.data.tags.full.unsorted
assert(legacy:RemoveTag("full", loaded[2].layoutKey) and legacy:RemoveTag("full", loaded[1].layoutKey))
page = TagPage.Build(legacy, "full")
assert(page ~= nil and accepts(page))
-- Its share code is refused as an import, which must leave room to show the tag
local imported, importReason = TagData.Decode(legacyText)
assert(imported == nil and string.find(importReason, tostring(TagData.EDIT_ENTRY_LIMIT), 1, true))

-- Unreadable saves and failed imports ------------------------------------------------

-- A save that cannot be read is reported and never overwritten
db = h.bankHost.db
for name in pairs(db) do db[name] = nil end
assert(ChunkedStringStore.Write({ manifestKey = "banktags:tags:v4:manifest",
    chunkPrefix = "banktags:tags:v4:" }, "{ not a share code"))
saved = Json.encode(db)
local broken = TagStore.new()
assert(broken.loadError ~= nil and #broken:AllTags() == 0)
local created, _, createReason = broken:CreateTag("new")
assert(not created and createReason == broken.loadError)
assert(not broken:ImportText(TagData.Encode(store.data, "other")))
assert(Json.encode(db) == saved)

-- A backup with one oversized tag saves nothing
for name in pairs(db) do db[name] = nil end
store = TagStore.new()
assert(store:CreateTag("keep"))
saved = Json.encode(db)
local backup = Json.decode(legacyText)
backup.tags.small = { rows = { { "#4151" } }, unsorted = {} }
backup.order = { "small", "full" }
local ok, _, failure = store:ImportText(Json.encode(backup))
assert(not ok and string.find(failure, "full", 1, true))
assert(Json.encode(db) == saved and store.data.tags.small == nil)

-- A host that refuses the write keeps the live tags as they were
h.bankHost.rejectWrites = true
local writes = PersistentDB.SetString
PersistentDB.SetString = function() return false end
ok = store:ImportText(TagData.Encode({ order = { "small" }, folders = {},
    tags = { small = { rows = {}, unsorted = { item(4151) } } } }))
assert(not ok and store.data.tags.small == nil and Json.encode(db) == saved)
PersistentDB.SetString = writes
h.bankHost.rejectWrites = false

print("tag_page_test: ok")
