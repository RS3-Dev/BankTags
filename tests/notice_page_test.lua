package.path = "./?.lua;./?/init.lua;" .. package.path

-- Check the banner for tags too large to show
-- FAKE HOST: stand-in components, loader, and saved data

local Harness = require("tools/test_support/tags_harness")
local h = Harness.new("notice_page")
h.bankHost.anchoredLayout = true
h.bankHost:SetItems({ { 4151, 1, "Abyssal whip" }, { 4151, 1, "Abyssal whip" }, { 385, 20, "Shark" } })

local ChunkedStringStore = require("banktags/core/chunked_string_store")
local TagData = require("banktags/tags/tag_data")
local TagStore = require("banktags/tags/tag_store")
local item = require("banktags/tags/tag_layouts").Item

-- Load an old tag at the full storage limit
-- Its Unsorted heading and row exceed the page limit
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
local controls = app.tab.controls
local banner, text = controls.statusBanner, controls.statusText
assert(Harness.Find(h:TabParent(), app.status) == nil)
assert(Harness.Find(app.tab.ctx.overlay, app.status) == text and not banner.hidden)
assert(banner.parent == app.tab.ctx.overlay and banner.clickthrough and text.clickthrough)
assert(banner.y == 5 and banner.height == 26)
assert(banner.x + banner.width / 2 == app.tab.ctx.overlay.width / 2)
assert(text.alignHorizontal == ui.AlignMode.CENTRE and text.maxLines == 2)

-- Notice updates keep the list and footer intact
local list, share = controls.list, controls.importShareButton
local listHeight = list.list.root.height
local notice = app.status
app:ShowStatus("Another failure")
assert(app.tab.controls == controls and controls.list == list and controls.importShareButton == share)
assert(list.list.root.height == listHeight and text.content == "Another failure")
app:ShowStatus(notice)

-- A tag that fits shows and clears the notice
h:ClickRow("small")
h:Tick(2)
assert(app:ShownTag() == "small" and app.status == nil)
assert(app.tab.controls.statusBanner.hidden)
assert(#layout:BuildPageItems() == 1 and layout:BuildPageItems()[1].objectID == 385)
-- Choosing the oversized tag again leaves the shown tag in place
h:ClickRow("full")
h:Tick(2)
assert(app:ShownTag() == "small" and app.status ~= nil)

-- Loading never cut the saved tag
assert(TagData.EntryCount(app.store.data.tags.full) == TagData.MAX_TAG_ENTRIES)

-- Unmounting removes the notice; reopening restores it once
local oldBanner = app.tab.controls.statusBanner
layout:Restore()
assert(oldBanner.destroyed and app.tab.controls == nil)
_, layout = h:OpenBank()
h:Tick(2)
assert(not app.tab.controls.statusBanner.hidden and app.tab.controls.statusText.content == app.status)
oldBanner = app.tab.controls.statusBanner
h.host:Unload("banktags")
assert(oldBanner.destroyed)

print("notice_page_test: ok")
