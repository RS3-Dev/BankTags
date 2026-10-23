package.path = "./?.lua;./?/init.lua;" .. package.path

-- Move sidebar tags and folders in the store, each move saved once or not at all

local db, failWrites = {}, false
PersistentDB = {
    GetString = function(_, key) return db[key] end,
    SetString = function(_, key, value)
        if failWrites then return false end
        db[key] = value
        return true
    end,
}
config = { Obj = { FromID = function() return nil end } }

local Json = require("banktags/core/json")
local TagStore = require("banktags/tags/tag_store")
local Chunks = require("banktags/core/chunked_string_store")

-- Count saves, not the chunks one save writes
local saves = 0
local write = Chunks.Write
Chunks.Write = function(...)
    saves = saves + 1
    return write(...)
end

local store = TagStore.new()
for _, name in ipairs({ "alpha", "bravo", "melee", "ranged", "magic", "charlie", "mining", "fishing" }) do
    assert(store:CreateTag(name))
end
assert(store:CreateFolder("Combat", "melee"))
assert(store:SetTagFolder("ranged", "combat") and store:SetTagFolder("magic", "combat"))
assert(store:CreateFolder("Skills", "mining") and store:SetTagFolder("fishing", "skills"))
assert(store:SetFolderCollapsed("skills", true))

local function tag(name) return { kind = "tag", tag = name } end
local function folder(key) return { kind = "folder", key = key } end
local function order() return table.concat(store:AllTags(), ",") end
-- Everything but the order, which a move must leave alone
local function contents()
    local data = {}
    for key, value in pairs(store.data) do
        if key ~= "order" then data[key] = value end
    end
    return Json.encode(data)
end
local unchanged = contents()

-- Move once and check the order, the single save, and that nothing else changed
local function moves(source, target, after, expected)
    local before = saves
    local saved, reason = store:MoveSidebarEntry(source, target, after)
    assert(saved, tostring(reason))
    assert(order() == expected, order())
    assert(saves == before + 1, "one save per move")
    assert(contents() == unchanged, "only the order changes")
end
-- Try a move that must save nothing, returning its reason
local function refused(source, target, after)
    local before, current = saves, order()
    local saved, reason = store:MoveSidebarEntry(source, target, after)
    assert(not saved and saves == before and order() == current)
    return reason
end

assert(order() == "alpha,bravo,melee,ranged,magic,charlie,mining,fishing")

-- Top-level tags move before or after their neighbours, up or down
moves(tag("alpha"), tag("bravo"), true, "bravo,alpha,melee,ranged,magic,charlie,mining,fishing")
moves(tag("alpha"), tag("bravo"), false, "alpha,bravo,melee,ranged,magic,charlie,mining,fishing")
moves(tag("charlie"), tag("alpha"), false, "charlie,alpha,bravo,melee,ranged,magic,mining,fishing")
moves(tag("charlie"), folder("combat"), true, "alpha,bravo,melee,ranged,magic,charlie,mining,fishing")

-- A folder moves as one block with its tags, collapsed or not
moves(folder("combat"), tag("alpha"), false, "melee,ranged,magic,alpha,bravo,charlie,mining,fishing")
moves(folder("skills"), folder("combat"), false, "mining,fishing,melee,ranged,magic,alpha,bravo,charlie")
moves(folder("combat"), tag("charlie"), true, "mining,fishing,alpha,bravo,charlie,melee,ranged,magic")
moves(tag("bravo"), folder("skills"), false, "bravo,mining,fishing,alpha,charlie,melee,ranged,magic")
assert(store:GetFolder("skills").collapsed and store:GetTagFolder("fishing") == "skills")

-- A folder's tags move within it, to its first and last places
moves(tag("magic"), tag("melee"), false, "bravo,mining,fishing,alpha,charlie,magic,melee,ranged")
moves(tag("magic"), tag("ranged"), true, "bravo,mining,fishing,alpha,charlie,melee,ranged,magic")
moves(tag("fishing"), tag("mining"), false, "bravo,fishing,mining,alpha,charlie,melee,ranged,magic")

-- Moves onto the entry itself, or to where it already is, save nothing and give no reason
assert(refused(tag("alpha"), tag("alpha"), true) == nil)
assert(refused(tag("alpha"), tag("charlie"), false) == nil)
assert(refused(tag("charlie"), tag("alpha"), true) == nil)
assert(refused(folder("skills"), tag("bravo"), true) == nil)
assert(refused(tag("ranged"), tag("melee"), true) == nil)

-- Tags never leave or join a folder by moving, and folders never nest
assert(refused(tag("melee"), tag("alpha"), false) ~= nil)
assert(refused(tag("alpha"), tag("melee"), true) ~= nil)
assert(refused(tag("melee"), tag("mining"), false) ~= nil)
assert(refused(folder("combat"), tag("mining"), true) ~= nil)
assert(refused(tag("melee"), folder("combat"), false) ~= nil)
assert(store:GetTagFolder("melee") == "combat" and store:GetTagFolder("alpha") == nil)

-- Entries removed since the drag began move nothing
assert(refused(tag("gone"), tag("alpha"), false) ~= nil)
assert(refused(tag("alpha"), folder("gone"), false) ~= nil)

-- A failed save keeps the old order and data and says why
local before = order()
failWrites = true
local saved, reason = store:MoveSidebarEntry(tag("alpha"), tag("bravo"), false)
failWrites = false
assert(not saved and type(reason) == "string" and reason ~= "")
assert(order() == before and contents() == unchanged)

-- The saved order is what a reload reads, and shares keep each tag's text
local exports = {}
for _, value in ipairs(store:TagExports()) do exports[value.tag] = value.value end
moves(tag("alpha"), tag("bravo"), false, "alpha,bravo,fishing,mining,charlie,melee,ranged,magic")
local reloaded = TagStore.new()
assert(table.concat(reloaded:AllTags(), ",") == order())
assert(reloaded:GetTagFolder("ranged") == "combat" and reloaded:GetFolder("skills").collapsed)
for _, value in ipairs(reloaded:TagExports()) do assert(exports[value.tag] == value.value, value.tag) end

print("sidebar_order_test: ok")
