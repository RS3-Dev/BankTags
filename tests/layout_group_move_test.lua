package.path = "./?.lua;./?/init.lua;" .. package.path

-- Move several arranged items at once, keeping their offsets, in one save

local db, failWrites = {}, false
PersistentDB = {
    GetString = function(_, key) return db[key] end,
    SetString = function(_, key, value)
        if failWrites then return false end
        db[key] = value
        return true
    end,
}
config = { Obj = setmetatable({ FromID = function() return nil end }, { __index = function() return nil end }) }

local Json = require("banktags/core/json")
local TagStore = require("banktags/tags/tag_store")
local TagData = require("banktags/tags/tag_data")
local TagLayouts = require("banktags/tags/tag_layouts")

-- Find the saved key for an item
local function key(objectID, copy) return "object:" .. objectID .. ":" .. (copy or 1) end
-- Create a saved item slot for the test
local function item(objectID, copy, source)
    return { kind = "item", objectID = objectID, layoutKey = key(objectID, copy),
        sourceLayoutKey = source ~= nil and key(objectID, source) or nil }
end
-- Create an open layout slot
local function blank() return { kind = "blank" } end
-- Build a layout row from the supplied slots
local function row(...) return { kind = "row", slots = { ... } } end

local store = TagStore.new()
assert(store:CreateTag("gear"))
local commits = 0
local commit = store.Commit
store.Commit = function(...)
    commits = commits + 1
    return commit(...)
end

-- Replace the tag's rows and Unsorted, saved
local function setRows(rows, unsorted)
    store.data.tags.gear.rows = rows
    store.data.tags.gear.unsorted = unsorted or {}
    assert(store:Save())
    commits = 0
end
-- Describe the saved layout in reading order
local function lines()
    local view = TagLayouts.Render(store.data.tags.gear.rows, 10)
    local out = {}
    for line = 0, view.lines - 1 do
        local text = nil
        for _, label in ipairs(view.labels) do
            if label.row == line then text = "[" .. label.text .. "]" end
        end
        if text == nil then
            local cells = {}
            for cell = line * 10 + 1, line * 10 + 10 do
                local slot = view.slots[cell]
                cells[#cells + 1] = slot.kind == "item" and tostring(slot.objectID)
                    or (slot.dormant ~= nil and "r" or ".")
            end
            text = table.concat(cells, " "):gsub("[ .]+$", "")
            if text == "" then text = "-" end
        end
        out[#out + 1] = text
    end
    return table.concat(out, " | ")
end
-- Move the selected group to a grid cell
local function move(keys, anchor, destination)
    return store:MoveLayoutItems("gear", keys, anchor, destination, 10)
end

-- Three side by side move right one: only the item beyond them fills the left cell
setRows({ row(item(1), item(2), item(3), item(4)) })
local saved, reason, changed = move({ key(1), key(2), key(3) }, key(1), 2)
assert(saved and reason == nil and changed and commits == 1)
assert(lines() == "4 1 2 3", lines())
-- And back left one: the item they cover returns to the right
assert(move({ key(1), key(2), key(3) }, key(2), 2))
assert(lines() == "1 2 3 4", lines())

-- Apart from where they were, the items they cover take their cells in order
setRows({ row(item(1), item(2), blank(), blank(), item(5), item(6)) })
assert(move({ key(1), key(2) }, key(2), 6))
assert(lines() == "5 6 . . 1 2", lines())

-- A scattered group keeps its shape across rows; blanks and reserved slots swap too
setRows({
    row(item(1), blank(), blank(), item(7)),
    row(blank(), blank(), item(3), { kind = "blank", dormant = "gone" }, blank(), item(8)),
})
assert(move({ key(3), key(1) }, key(1), 4))
assert(lines() == "7 . . 1 | . . 8 r . 3", lines())
-- Moving down onto a reserved slot puts the slot where the item was
assert(move({ key(3) }, key(3), 14))
assert(lines() == "7 . . 1 | . . 8 3 . r", lines())

-- Copies keep their source; labels, Unsorted, and other items stay put
setRows({
    { kind = "label", text = "Top" },
    row(item(4151, 1), item(4151, 2, 1), item(9)),
    row(item(10)),
}, { item(385), { kind = "blank", dormant = "old" } })
local unsortedBefore = Json.encode(store.data.tags.gear.unsorted)
assert(move({ key(4151, 1), key(4151, 2) }, key(4151, 1), 25))
assert(lines() == "[Top] | . . 9 | 10 . . . 4151 4151", lines())
local copy = TagLayouts.Render(store.data.tags.gear.rows, 10).slots[26]
assert(copy.layoutKey == key(4151, 2) and copy.sourceLayoutKey == key(4151, 1))
assert(Json.encode(store.data.tags.gear.unsorted) == unsortedBefore)

-- Below the rows, each line it reaches is added; trailing empties are trimmed
setRows({ row(item(1), item(2)), row(nil), row(item(3)) })
assert(move({ key(1), key(3) }, key(1), 32))
assert(lines() == ". 2 | - | - | . 1 | - | . 3", lines())
assert(move({ key(1), key(3) }, key(1), 1))
assert(lines() == "1 2 | - | 3", lines())

-- Inside a wrapped row the second line moves like any other
local long = {}
for index = 1, 14 do long[index] = item(100 + index) end
setRows({ row(table.unpack(long)) })
assert(move({ key(111), key(112) }, key(111), 15))
assert(lines() == "101 102 103 104 105 106 107 108 109 110 | . . 113 114 111 112", lines())

-- Dropped where it started, nothing saves
local before = Json.encode(store.data)
commits = 0
saved, reason, changed = move({ key(111), key(112) }, key(112), 16)
assert(saved and not changed and commits == 0 and Json.encode(store.data) == before)

-- Every refusal leaves the data alone and saves nothing
setRows({
    row(item(1), item(2), blank(), blank(), blank(), blank(), blank(), blank(), item(9), item(10)),
    { kind = "label", text = "Mid" },
    row(item(3)),
}, { item(385) })
before = Json.encode(store.data)
-- Reaching past either edge, onto a label, above the first line, or missing items
for _, case in ipairs({
    { { key(1), key(2) }, key(1), 10, "do not fit" },
    { { key(9), key(10) }, key(10), 1, "do not fit" },
    { { key(1), key(2) }, key(1), 12, "label" },
    { { key(1), key(3) }, key(3), 3, "do not fit" },
    { { key(1), key(385) }, key(1), 4, "no longer" },
    { { key(1), key(77) }, key(1), 4, "no longer" },
    { { key(1), key(1) }, key(1), 4, "no longer" },
    { { key(1) }, key(2), 4, "no longer" },
    { {}, key(1), 4, "invalid" },
    { { key(1) }, key(1), 0, "invalid" },
}) do
    saved, reason, changed = move(case[1], case[2], case[3])
    assert(not saved and not changed and reason:find(case[4], 1, true), tostring(reason))
end
assert(commits == 0 and Json.encode(store.data) == before)

-- The plan names each cell and whether it fits, for the editor's preview
local plan = store:PlanLayoutItemsMove("gear", { key(9), key(10) }, key(9), 2, 10)
assert(plan.valid and plan.changed and plan.moves[1].destination == 2 and plan.moves[2].destination == 3)
plan = store:PlanLayoutItemsMove("gear", { key(1), key(2) }, key(1), 10, 10)
assert(not plan.valid and plan.moves[1].destination == 10 and plan.moves[2].destination == nil)
assert(plan.moves[2].line == 0 and plan.moves[2].column == 10)

-- A failed save keeps the old layout
failWrites = true
saved, reason = move({ key(1), key(2) }, key(1), 3)
assert(not saved and reason ~= nil and Json.encode(store.data) == before)
failWrites = false

-- A full tag cannot grow rows for a move, but can move within them
local full = {}
for index = 1, TagData.EDIT_ENTRY_LIMIT - 5 do full[index] = { kind = "label", text = "L" .. index } end
full[#full + 1] = row(blank(), blank(), item(1), item(2))
setRows(full)
before = Json.encode(store.data)
local lastLine = TagLayouts.Render(full, 10).lines - 1
saved, reason = move({ key(1), key(2) }, key(1), (lastLine + 3) * 10 + 3)
assert(not saved and reason:find("at most", 1, true) and Json.encode(store.data) == before)
assert(move({ key(1), key(2) }, key(1), lastLine * 10 + 1))

print("layout_group_move_test: ok")
