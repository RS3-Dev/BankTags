package.path = "./?.lua;./?/init.lua;" .. package.path

local TagLayouts = require("banktags/tags/tag_layouts")

-- Create a saved item slot for the test
local function item(name) return { kind = "item", layoutKey = name } end
-- Create an open layout slot
local function blank() return { kind = "blank" } end
-- Build a layout row from the supplied slots
local function row(...) return { kind = "row", slots = { ... } } end
-- Create a layout label for the test
local function label(text) return { kind = "label", text = text } end

-- A short row leaves the rest of its line empty; a label takes a whole line
local entries = { row(item("a"), blank(), item("b")), label("Food"), row(item("c")) }
local view = TagLayouts.Render(entries, 4)
assert(view.lines == 3)
assert(view.slots[1].layoutKey == "a" and view.slots[3].layoutKey == "b" and view.slots[4].kind == "blank")
assert(#view.labels == 1 and view.labels[1].row == 1 and view.labels[1].text == "Food")
assert(view.cells[5] == nil, "label lines have no cells")
assert(view.slots[9].layoutKey == "c" and view.cells[9].entry == 3 and view.cells[9].position == 1)
assert(view.cells[4].entry == 1 and view.cells[4].position == 4, "a row's empty tail maps to its row")

-- A row longer than the width wraps instead of hiding items
local long = { row(item("1"), item("2"), item("3"), item("4"), item("5")), label("Next") }
view = TagLayouts.Render(long, 3)
assert(view.lines == 3 and view.slots[4].layoutKey == "4" and view.slots[5].layoutKey == "5")
assert(view.labels[1].row == 2)
view = TagLayouts.Render(long, 14)
assert(view.lines == 2 and view.slots[5].layoutKey == "5" and view.labels[1].row == 1)

-- New entries start at a line: inside a wrapped row means before that row
view = TagLayouts.Render(long, 3)
assert(TagLayouts.EntryAtLine(view, long, 0) == 1)
assert(TagLayouts.EntryAtLine(view, long, 1) == 1)
assert(TagLayouts.EntryAtLine(view, long, 2) == 2)
assert(TagLayouts.EntryAtLine(view, long, 9) == 3)

-- Trimming drops trailing open slots and trailing empty rows, but keeps gaps
local trimmed = TagLayouts.Trim({ row(item("a"), blank()), row(), row(item("b")), row(blank()) })
assert(#trimmed == 3 and #trimmed[1].slots == 1 and #trimmed[2].slots == 0)
local reserved = TagLayouts.Trim({ row(item("a"), { kind = "blank", dormant = { item = "x" } }) })
assert(#reserved[1].slots == 2, "a reserved slot is not open")

print("tag_layouts_test: ok")
