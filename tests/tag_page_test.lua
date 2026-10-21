package.path = "./?.lua;./?/init.lua;" .. package.path

-- Turn saved tags into pages that the real Bank Core accepts
-- Also check the entry budget and that failures never change saved data
-- FAKE HOST: stand-in components and saved data, not the game client

local Harness = require("tools/test_support/tags_harness")
local h = Harness.new("tag_page")
h.bankHost:SetItems({ { 4151, 1, "Abyssal whip" }, { 4151, 1, "Abyssal whip" }, { 385, 20, "Shark" } })
local core = h:LoadCore()
local api = core.result

local Json = require("banktags/core/json")
local TagData = require("banktags/tags/tag_data")
local TagPage = require("banktags/tags/tag_page")
local TagStore = require("banktags/tags/tag_store")
local ItemIdentity = require("banktags/tags/item_identity")

local db = h.bankHost.db
local key = ItemIdentity.LayoutKey
-- Return a saved slot for a copy, optionally a ghost of a source copy
local function item(objectID, copy, source)
    return { kind = "item", objectID = objectID, layoutKey = key(objectID, copy),
        sourceLayoutKey = source ~= nil and key(objectID, source) or nil }
end
local function blank() return { kind = "blank" } end
local function row(...) return { kind = "row", slots = { ... } } end
local function label(text) return { kind = "label", text = text } end

-- A test owner registers pages through Core's public API, as Bank Tags does
local owner = assert(api.RegisterExtension("test.tags", "Tag pages"))
local registered = 0
-- Register a page and report whether Core accepted it
local function accepts(page)
    registered = registered + 1
    local ok, reason, detail = owner:RegisterPage("p" .. registered, page)
    if not ok then return false, tostring(reason) .. ": " .. tostring(detail) end
    assert(owner:RemovePage("p" .. registered))
    return true
end

-- Conversion -------------------------------------------------------------------------

local record = {
    rows = {
        label("Weapons"),
        row(item(4151, 1), blank(), item(4151, 2), item(4151, 3, 1)),
        row(),
        label("Food\tand drink"),
        row({ kind = "blank", dormant = "unknown_item" }, item(385, 1)),
    },
    unsorted = { item(4151, 4), { kind = "blank", dormant = "gone" } },
}
local rows, count = TagPage.Rows(record)
assert(Json.encode(rows) == Json.encode({
    { label = "Weapons" },
    { slots = { 4151, false, { item = 4151, copy = 2 }, { item = 4151, copy = 3, source = 1 } } },
    { slots = {} },
    { label = "Foodand drink" },
    { slots = { false, 385 } },
    { label = "Unsorted" },
    { slots = { { item = 4151, copy = 4 } } },
}), Json.encode(rows))
assert(count == 1 + 5 + 1 + 1 + 3 + 2 + 1)
-- Unresolved items stay as blanks; unresolved Unsorted entries are hidden
assert(rows[5].slots[1] == false and #rows[7].slots == 1)

-- A repeated copy, or a ghost of itself, can't make Core refuse the page
rows = TagPage.Rows({ rows = { row(item(4151, 1), item(4151, 1)), row(item(385, 2, 2)) }, unsorted = {} })
assert(rows[1].slots[2] == false and rows[2].slots[1].source == nil and rows[2].slots[1].copy == 2)

-- An empty tag has no rows and no Unsorted label
rows, count = TagPage.Rows({ rows = {}, unsorted = {} })
assert(#rows == 0 and count == 0)

-- Keys name the tag; other keys are not tags
assert(TagPage.Key("melee gear") == "tag:melee gear" and TagPage.TagFromKey("tag:melee gear") == "melee gear")
assert(TagPage.TagFromKey("other") == nil and TagPage.TagFromKey(nil) == nil)

-- Core accepts the page with an 80-character title and the tag's key
local store = TagStore.new()
local longName = string.rep("a", 79) .. "z"
assert(store:CreateTag(longName))
store.data.tags[longName].rows = record.rows
store.data.tags[longName].unsorted = record.unsorted
-- The tag's items draw in one block, with a pixel-high block for the names mount
local mounts = { notice = { mount = function() end }, names = { mount = function() end } }
local page, notice = TagPage.Build(store, longName, mounts)
assert(notice == nil and page.key == "tag:" .. longName and #page.title == 80)
assert(page.mount == mounts.names and page.body[1].items == TagPage.ITEMS_BLOCK and page.body[2].height == 1)
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
    slots[index] = index % 2 == 0 and blank() or item(100000 + index, 1)
end
slots[#slots] = item(99999, 1)
full.rows[1] = { kind = "row", slots = slots }
full.unsorted = { item(4151, 1) }
assert(TagData.EntryCount(full) == TagData.EDIT_ENTRY_LIMIT)
assert(store:Save())
page, notice = TagPage.Build(store, "full", mounts)
local _, pageEntries = TagPage.Rows(full)
assert(notice == nil and pageEntries == TagPage.MAX_ENTRIES)
assert(accepts(page))

-- An edit cannot grow the tag past the limit or save
local saved = Json.encode(db)
local added, reason = store:AddTag("full", 385, key(385, 1))
assert(not added and string.find(reason, "at most", 1, true))
assert(Json.encode(db) == saved and store.data.tags.full.unsorted[2] == nil)
-- Removing still works
assert(store:RemoveTag("full", key(4151, 1)))

-- A full-limit saved tag loads and saves whole, but its page explains instead
full = store.data.tags.full
full.unsorted = { item(4151, 1), item(4151, 2), item(385, 1), item(385, 2) }
assert(TagData.EntryCount(full) == TagData.MAX_TAG_ENTRIES + 1)
local tooLargeText = TagData.Encode(store.data)
assert(TagData.Decode(tooLargeText, true) == nil, "a save over the full limit is not readable")
table.remove(full.unsorted)
assert(TagData.EntryCount(full) == TagData.MAX_TAG_ENTRIES)
local legacyText = TagData.Encode(store.data)
db = h.bankHost.db
for name in pairs(db) do db[name] = nil end
local ChunkedStringStore = require("banktags/core/chunked_string_store")
assert(ChunkedStringStore.Write({ manifestKey = "banktags:tags:v3:manifest",
    chunkPrefix = "banktags:tags:v3:" }, legacyText))
local legacy = TagStore.new()
assert(legacy.loadError == nil and TagData.EntryCount(legacy.data.tags.full) == TagData.MAX_TAG_ENTRIES)
page, notice = TagPage.Build(legacy, "full", mounts)
assert(notice ~= nil and page.body[1].ui == "notice" and page.mount == mounts.notice)
assert(string.find(notice, tostring(TagData.MAX_TAG_ENTRIES + 2), 1, true))
assert(accepts(page))
-- Loading, unrelated edits, and saving keep the oversized tag whole
assert(legacy:CreateTag("other"))
assert(TagData.EntryCount(TagStore.new().data.tags.full) == TagData.MAX_TAG_ENTRIES)
assert(TagData.Encode(legacy.data, "full") == TagData.Encode(TagData.Decode(legacyText, true), "full"))
-- It may not grow, but it may shrink until it fits again
assert(not legacy:AddTag("full", 385, key(385, 3)))
assert(legacy:RemoveTag("full", key(4151, 2)) and legacy:RemoveTag("full", key(4151, 1)))
page, notice = TagPage.Build(legacy, "full", mounts)
assert(notice == nil and page.body[1].layout ~= nil and accepts(page))
-- Its share code is refused as an import, which must leave room to show the tag
local imported, importReason = TagData.Decode(legacyText)
assert(imported == nil and string.find(importReason, tostring(TagData.EDIT_ENTRY_LIMIT), 1, true))

-- Unreadable saves and failed imports ------------------------------------------------

-- A save that cannot be read is reported and never overwritten
db = h.bankHost.db
for name in pairs(db) do db[name] = nil end
assert(ChunkedStringStore.Write({ manifestKey = "banktags:tags:v3:manifest",
    chunkPrefix = "banktags:tags:v3:" }, "{ not a share code"))
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
    tags = { small = { rows = {}, unsorted = { item(4151, 1) } } } }))
assert(not ok and store.data.tags.small == nil and Json.encode(db) == saved)
PersistentDB.SetString = writes
h.bankHost.rejectWrites = false

print("tag_page_test: ok")
