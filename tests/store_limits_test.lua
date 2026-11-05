package.path = "./?.lua;" .. package.path

local TagStore = require("banktags/tags/tag_store")
local TagData = require("banktags/tags/tag_data")
local Json = require("banktags/core/json")
local db, writes = {}, 0
PersistentDB = {
    GetString = function(_, key) return db[key] end,
    SetString = function(_, key, value) db[key], writes = value, writes + 1; return true end,
}

-- Build an empty tag for a limit fixture
local function tag()
    return { rows = {}, unsorted = {} }
end

-- Check a refused edit leaves saved and live data alone
local function refused(store, edit)
    local before, saved = Json.encode(store.data), Json.encode(db)
    writes = 0
    assert(not edit())
    assert(Json.encode(store.data) == before and Json.encode(db) == saved and writes == 0)
end

local store = TagStore.new()
for index = 1, TagData.MAX_TAGS do
    local name = "tag " .. index
    store.data.order[index], store.data.tags[name] = name, tag()
end
assert(store:Save())
assert(#TagStore.new():AllTags() == TagData.MAX_TAGS)
refused(store, function() return store:CreateTag("overflow") end)
local shared = TagData.Encode({ order = { "overflow" }, tags = { overflow = tag() }, folders = {} })
refused(store, function() return store:ImportText(shared) end)
assert(store:ImportText(shared, { name = "tag 1" }))

db = {}
store = TagStore.new()
for index = 1, TagData.MAX_FOLDERS + 1 do
    local name = "tag " .. index
    local record = tag()
    store.data.order[index], store.data.tags[name] = name, record
    if index <= TagData.MAX_FOLDERS then
        local key = "folder " .. index
        record.folder = key
        store.data.folders[key] = { name = key, collapsed = false }
    end
end
assert(store:Save())
local extra = "tag " .. (TagData.MAX_FOLDERS + 1)
refused(store, function() return store:CreateFolder("overflow", extra) end)
refused(store, function() return store:ImportText(shared, { newFolderName = "overflow" }) end)
assert(store:SetTagFolder(extra, "folder 1"))
assert(TagStore.new():GetTagFolder(extra) == "folder 1")

db = {}
store = TagStore.new()
assert(store:CreateTag("large") and store:CreateTag("copy"))
for index = 1, TagData.EDIT_ENTRY_LIMIT do
    store.data.tags.large.rows[index] = { kind = "label", text = string.rep("x", 60) }
end
assert(store:Save())
assert(TagStore.new().loadError == nil)
local state = store:LayoutState("large")
refused(store, function() return store:RestoreLayoutState("copy", state) end)
assert(TagStore.new().data.tags.copy ~= nil)

print("store_limits_test: ok")
