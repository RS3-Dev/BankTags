package.path = "./?.lua;" .. package.path

local TagStore = require("banktags/tags/tag_store")
local TagLayouts = require("banktags/tags/tag_layouts")
local Chunks = require("banktags/core/chunked_string_store")
local Json = require("banktags/core/json")
local db, saves, fail = {}, 0, false
PersistentDB = {
    GetString = function(_, key) return db[key] end,
    SetString = function(_, key, value)
        if fail then return false end
        db[key] = value
        return true
    end,
}
local write = Chunks.Write
Chunks.Write = function(...)
    saves = saves + 1
    return write(...)
end
local store = TagStore.new()
assert(store:CreateTag("gear") and store:CreateTag("food"))
local first, second, third, unsorted = TagLayouts.Item(1), TagLayouts.Item(1), TagLayouts.Item(2), TagLayouts.Item(3)
store.data.tags.gear.rows = {
    { kind = "row", slots = { first, { kind = "blank", dormant = "missing" }, second } },
    { kind = "label", text = "Armour" },
    { kind = "row", slots = { third } },
}
store.data.tags.gear.unsorted = { unsorted }
assert(store:Save())
local before = Json.encode(store.data)
saves, fail = 0, true
assert(not store:RemoveTags("gear", { first.layoutKey, third.layoutKey, unsorted.layoutKey }))
assert(Json.encode(store.data) == before and saves == 1)
fail = false
assert(store:RemoveTags("gear", { first.layoutKey, third.layoutKey, unsorted.layoutKey }))
assert(saves == 2 and #store.data.tags.gear.unsorted == 0)
assert(store.data.tags.gear.rows[1].slots[1].kind == "blank")
assert(store.data.tags.gear.rows[1].slots[2].dormant == "missing")
assert(store.data.tags.gear.rows[1].slots[3].layoutKey == second.layoutKey)
assert(store.data.tags.gear.rows[2].text == "Armour")
assert(store:RemoveTags("gear", { -1 }) and saves == 2)

assert(store:RestoreLayoutState("gear", Json.decode(before).tags.gear))
before = Json.encode(store.data)
saves = 0
assert(not store:UnarrangeLayoutItems("gear", { first.layoutKey, -1 }))
assert(not store:UnarrangeLayoutItems("gear", { first.layoutKey, first.layoutKey }))
assert(Json.encode(store.data) == before and saves == 0)
assert(store:UnarrangeLayoutItems("gear", { third.layoutKey, first.layoutKey }))
assert(saves == 1)
local slots = store.data.tags.gear.unsorted
assert(#slots == 3 and slots[1].layoutKey == unsorted.layoutKey)
assert(slots[2].layoutKey == first.layoutKey and slots[3].layoutKey == third.layoutKey)

-- Roll back folder expansion when its final save fails
assert(store:CreateFolder("Combat", "gear"))
assert(store:SetFolderCollapsed("combat", true))
before = Json.encode(store.data)
saves, fail = 0, true
local saved, reason = store:SaveTogether(function() return store:SetFolderCollapsed("combat", false) end)
assert(not saved and reason ~= nil and Json.encode(store.data) == before and saves == 1)
fail = false
assert(store:SaveTogether(function() return store:SetFolderCollapsed("combat", false) end))
assert(saves == 2 and not TagStore.new():GetFolder("combat").collapsed)

-- Keep nested edits in the outer save and rollback
before = Json.encode(store.data)
local persisted = Json.encode(db)
saves = 0
assert(not store:SaveTogether(function()
    assert(store:SaveTogether(function() return store:AddTag("gear", 4) end))
    assert(store:AddTag("food", 5))
    return false, "cancel the outer edit"
end))
assert(saves == 0 and Json.encode(db) == persisted and Json.encode(store.data) == before)
assert(store:SaveTogether(function()
    assert(store:SaveTogether(function() return store:AddTag("gear", 4) end))
    return store:AddTag("food", 5)
end))
assert(saves == 1 and TagStore.new().loadError == nil)

print("store_batch_test: ok")
