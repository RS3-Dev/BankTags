package.path = "./?.lua;" .. package.path

local Config = require("banktags/core/config")
local Chunks = require("banktags/core/chunked_string_store")
local TagStore = require("banktags/tags/tag_store")
local Json = require("banktags/core/json")
local options = { manifestKey = Config.TAGS_TEXT_MANIFEST_KEY, chunkPrefix = Config.TAGS_TEXT_CHUNK_PREFIX }
local db, writes, failRead, failWrite = {}, 0, nil, nil
PersistentDB = {
    GetString = function(_, key)
        if key == failRead then error("read unavailable") end
        return db[key]
    end,
    SetString = function(_, key, value)
        if key == failWrite then return false end
        db[key], writes = value, writes + 1
        return true
    end,
}

-- Check unreadable saves cannot be replaced by an edit
local function protected()
    local before = Json.encode(db)
    writes = 0
    local store = TagStore.new()
    assert(store.loadError ~= nil)
    local saved, _, reason = store:CreateTag("replacement")
    assert(not saved and reason == store.loadError)
    assert(writes == 0 and Json.encode(db) == before)
end

local empty = TagStore.new()
assert(empty.loadError == nil and #empty:AllTags() == 0)
assert(empty:CreateTag("gear"))
assert(TagStore.new().data.tags.gear ~= nil)
db[options.manifestKey] = "broken"
protected()
local saved, reason = Chunks.Write(options, "replacement")
assert(not saved and reason.stage == "manifest")
db[options.manifestKey] = "a:2"
db[options.chunkPrefix .. "a:1"] = "first part"
protected()
db[options.manifestKey] = "a:1"
failRead = options.chunkPrefix .. "a:1"
protected()
failRead = options.manifestKey
protected()
local before = Json.encode(db)
assert(not Chunks.Write(options, "replacement"))
assert(Json.encode(db) == before and writes == 0)
failRead = nil
db[options.manifestKey] = 42
protected()

-- Keep the current copy when writing its replacement fails
db = {}
local original = string.rep("x", 24001)
assert(Chunks.Write(options, original))
assert(Chunks.Read(options) == original)
failWrite = options.chunkPrefix .. "b:2"
assert(not Chunks.Write(options, string.rep("y", 24001)))
assert(Chunks.Read(options) == original and db[options.manifestKey] == "a:3")
failWrite = options.manifestKey
assert(not Chunks.Write(options, "shorter replacement"))
assert(Chunks.Read(options) == original)
failWrite = nil
assert(Chunks.Write(options, "shorter replacement"))
assert(Chunks.Read(options) == "shorter replacement" and db[options.manifestKey] == "b:1")

print("persistence_test: ok")
