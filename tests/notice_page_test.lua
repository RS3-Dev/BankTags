package.path = "./?.lua;./?/init.lua;" .. package.path

-- Open a saved tag too large for Bank Core through the running app
-- Its notice page is an empty layout whose mounted text explains why
-- FAKE HOST: stand-in loader, components, and saved data, not the game client

local Harness = require("tools/test_support/tags_harness")
local h = Harness.new("notice_page")
h.bankHost:SetItems({ { 4151, 1, "Abyssal whip" }, { 4151, 1, "Abyssal whip" }, { 385, 20, "Shark" } })

local ChunkedStringStore = require("banktags/core/chunked_string_store")
local ItemIdentity = require("banktags/tags/item_identity")
local TagData = require("banktags/tags/tag_data")
local TagPage = require("banktags/tags/tag_page")
local TagStore = require("banktags/tags/tag_store")

-- Save a small tag and one at Bank Tags' full stored limit, which edits can no longer reach
-- Its page adds the Unsorted label and row, so it is two entries over Bank Core's limit
local db = h.bankHost.db
local store = TagStore.new()
assert(store:CreateTag("small") and store:AddTag("small", 385))
assert(store:CreateTag("full"))
local function item(objectID, copy)
    return { kind = "item", objectID = objectID, layoutKey = ItemIdentity.LayoutKey(objectID, copy) }
end
local slots = {}
for index = 1, TagData.EDIT_ENTRY_LIMIT - 2 do
    slots[index] = index % 2 == 0 and { kind = "blank" } or item(100000 + index, 1)
end
-- A row ends with an item, since saving drops trailing blanks
slots[#slots] = item(99999, 1)
store.data.tags.full.rows = { { kind = "row", slots = slots } }
store.data.tags.full.unsorted = { item(4151, 1), item(4151, 2), item(385, 1) }
assert(TagData.EntryCount(store.data.tags.full) == TagData.MAX_TAG_ENTRIES)
local savedText = TagData.Encode(store.data)
for name in pairs(db) do db[name] = nil end
assert(ChunkedStringStore.Write({ manifestKey = "banktags:tags:v3:manifest",
    chunkPrefix = "banktags:tags:v3:" }, savedText))
-- The built plugin reads its own saved data
h.databases.banktags = {}
for name, value in pairs(db) do h.databases.banktags[name] = value end

h:LoadCore()
h:LoadTags()
local app = h:App()
assert(app.store.loadError == nil)
assert(app.store.loadError == nil)
local session, layout = h:OpenBank()
local engine = layout.pageDisplay
h:Tick(2)

-- Find the notice text the app drew in the page's mounted parent
local function noticeText()
    local mount = engine.pageMount
    if mount == nil or not mount:IsMounted() then return nil end
    local found = nil
    for _, child in ipairs(mount.values.parent.children) do
        if not child.destroyed then
            assert(found == nil, "the notice page holds more than its text")
            found = child
        end
    end
    return found, mount
end

-- Showing the oversized tag opens its notice page through Bank Core
local opened, reason = app:ShowTag("full")
assert(opened, tostring(reason))
h:Tick(2)
assert(app.shownTag == "full" and layout.selection ~= nil)
assert(session.pluginPages:PageTitle(layout.selection) == TagPage.Title("full"))
local text, mount = noticeText()
assert(text ~= nil, "the notice page mounted no text")
-- The text says how many entries the tag has and what to do
assert(text.content == app.notice and app.notice ~= nil)
assert(string.find(text.content, tostring(TagData.MAX_TAG_ENTRIES + 2) .. " rows, labels, and items", 1, true))
assert(string.find(text.content, "Bank Core shows at most " .. TagPage.MAX_ENTRIES, 1, true))
assert(text.clickthrough == true and text.maxLines == 4)
-- It sits inside the clipped page parent, which covers the empty page
local parent, bounds = mount.values.parent, mount.ctx:GetBounds()
assert(parent.parent == engine.pageUILayer and text.parent == parent)
assert(text.x == 12 and text.y == 8 and text.width == bounds.width - 24 and text.height == 64)
assert(text.x + text.width <= bounds.width and text.y + text.height <= bounds.height)
-- The page has no slots, so nothing native is moved under it
assert(#layout:BuildPageItems() == 0 and #mount.ctx:GetLayout().slots == 0)
assert(#layout.itemHover.clickablePageItems == 0)
for slot, native in ipairs(h.bankHost.items) do assert(native.x == 10 + (slot - 1) * 44, slot) end

-- Showing a tag that fits replaces the notice with that tag's items
assert(app:ShowTag("small"))
h:Tick(2)
assert(text.destroyed and engine.pageMount == nil and app.notice == nil)
assert(#layout:BuildPageItems() == 1 and layout:BuildPageItems()[1].objectID == 385)
-- And showing the oversized tag again mounts a fresh notice
assert(app:ShowTag("full"))
h:Tick(2)
local again = noticeText()
assert(again ~= nil and again ~= text and again.content == app.notice)

-- Closing the bank unmounts the notice and leaves the page
h:CloseBank()
h:Tick(2)
assert(again.destroyed and engine.pageMount == nil and engine.pageUILayer == nil)
assert(layout.selection == nil)
for slot, native in ipairs(h.bankHost.items) do assert(native.x == 10 + (slot - 1) * 44, slot) end
-- Loading never cut the saved tag
assert(TagData.EntryCount(app.store.data.tags.full) == TagData.MAX_TAG_ENTRIES)

print("notice_page_test: ok")
