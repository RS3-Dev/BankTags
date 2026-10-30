package.path = "./?.lua;./?/init.lua;" .. package.path

-- Choose a saved tag too large for Bank Core through the running app
-- It is not shown; the Tags tab's status line says why
-- FAKE HOST: stand-in loader, components, and saved data, not the game client

local Harness = require("tools/test_support/tags_harness")
local h = Harness.new("notice_page")
h.bankHost:SetItems({ { 4151, 1, "Abyssal whip" }, { 4151, 1, "Abyssal whip" }, { 385, 20, "Shark" } })

local ChunkedStringStore = require("banktags/core/chunked_string_store")
local TagData = require("banktags/tags/tag_data")
local TagStore = require("banktags/tags/tag_store")
local item = require("banktags/tags/tag_layouts").Item

-- Save a small tag and one at Bank Tags' full stored limit, which edits can no longer reach
-- Its page adds the Unsorted label and row, so it is two entries over Bank Core's limit
local db = h.bankHost.db
local store = TagStore.new()
assert(store:CreateTag("small") and store:AddTag("small", 385))
assert(store:CreateTag("full"))
local slots = {}
for index = 1, TagData.EDIT_ENTRY_LIMIT - 2 do
    slots[index] = index % 2 == 0 and { kind = "blank" } or item(100000 + index)
end
-- A row ends with an item, since saving drops trailing blanks
slots[#slots] = item(99999)
store.data.tags.full.rows = { { kind = "row", slots = slots } }
store.data.tags.full.unsorted = { item(4151), item(4151), item(385) }
assert(TagData.EntryCount(store.data.tags.full) == TagData.MAX_TAG_ENTRIES)
local savedText = TagData.Encode(store.data)
for name in pairs(db) do db[name] = nil end
assert(ChunkedStringStore.Write({ manifestKey = "banktags:tags:v4:manifest",
    chunkPrefix = "banktags:tags:v4:" }, savedText))
-- The built plugin reads its own saved data
h.databases.banktags = {}
for name, value in pairs(db) do h.databases.banktags[name] = value end

h:LoadCore()
h:LoadTags()
local app = h:App()
assert(app.store.loadError == nil)
local _, layout = h:OpenBank()
h:Tick(2)

-- Choosing the oversized tag shows nothing and says how many entries it has
h:ClickRow("full")
h:Tick(2)
assert(app:ShownTag() == nil and layout.shownPage == nil)
assert(string.find(app.status, tostring(TagData.MAX_TAG_ENTRIES + 2) .. " rows, labels, and items", 1, true))
assert(Harness.Find(h:TabParent(), app.status) ~= nil)

-- A tag that fits shows and clears the notice
h:ClickRow("small")
h:Tick(2)
assert(app:ShownTag() == "small" and app.status == nil)
assert(#layout:BuildPageItems() == 1 and layout:BuildPageItems()[1].objectID == 385)
-- Choosing the oversized tag again leaves the shown tag in place
h:ClickRow("full")
h:Tick(2)
assert(app:ShownTag() == "small" and app.status ~= nil)

-- Loading never cut the saved tag
assert(TagData.EntryCount(app.store.data.tags.full) == TagData.MAX_TAG_ENTRIES)

print("notice_page_test: ok")
