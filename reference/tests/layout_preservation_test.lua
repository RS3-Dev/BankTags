package.path = "./?.lua;./?/init.lua;" .. package.path

local Json = require("lib/core/json")
local db, writes, failWrites = {}, 0, false
PersistentDB = {
    GetString = function(_, key) return db[key] end,
    SetString = function(_, key, value)
        if failWrites then return false end
        db[key], writes = value, writes + 1
        return true
    end,
    GetStructuredData = function(_, key) return db[key] end,
    SetStructuredData = function(_, key, value)
        db[key] = value
        return true
    end,
}
id = { Sprite = { RS3_ICON_SLOT_40PX_1 = 1 }, Font = { MUSEO_SANS_11PT_REGULAR = 1 } }
local function node()
    local value = {}
    function value:SetPos(x, y) self.x, self.y = x, y end
    function value:SetSize(width, height) self.width, self.height = width, height end
    function value:MoveToFront() end
    function value:Destroy() self.destroyed = true end
    return value
end
ui = { ObjectQuantityDisplayMode = { ALWAYS = 2, NEVER = 0 },
    AlignMode = { CENTRE = 1 }, Sprite = { new = node },
    Layer = { new = node }, Rectangle = { new = node } }
prettyui = { Text = { new = node } }
local TagStore = require("lib/features/tags/tag_store")
local TagData = require("lib/features/tags/tag_data")
local Engine = require("lib/engine/bank_list_engine")
local Editor = require("lib/features/tags/layout_editor_window")
local TagLayouts = require("lib/features/tags/tag_layouts")
local Settings = require("lib/core/settings")

local function key(objectID, occurrence)
    return "object:" .. objectID .. ":" .. (occurrence or 1)
end
-- Draw a tag's rows at ten columns, as a default-width bank shows it
local function grid(store)
    return TagLayouts.Render(store.data.tags.gear.rows, 10).slots
end
local function move(store, objectID, destination, occurrence, force)
    return store:MoveLayoutItem("gear", key(objectID, occurrence), destination, 10, force)
end

-- Arranged rows stay as they are; new items go to the Unsorted list in order
local store = TagStore.new()
assert(store:CreateTag("gear"))
store:SetLayoutPlacement(false)
assert(store:AddTag("gear", 100) and store:AddTag("gear", 200) and move(store, 200, 4))
store:SetLayoutPlacement(true)
local original = Json.encode(store.data.tags.gear.rows)
assert(grid(store)[1].objectID == 100 and grid(store)[4].objectID == 200)
assert(store:AddTag("gear", 300))
assert(Json.encode(store.data.tags.gear.rows) == original)
assert(store.data.tags.gear.unsorted[1].objectID == 300)
local displayed, boundary = store:GetLayout("gear", 10)
-- Row 1 holds the Unsorted heading; unsorted items start on row 2
assert(boundary == 10 and displayed[21].objectID == 300 and displayed[21].unarranged)
assert(displayed[2].kind == "blank" and displayed[4].objectID == 200)
assert(Engine.UnsortedRow(displayed, boundary, 10) == 1)
local positions, _, _, sections = Engine.LayoutPositions(store, "gear", 10)
assert(positions[key(300)].x == 8 and positions[key(300)].y == 92)
assert(#sections == 1 and sections[1].label == "Unsorted" and sections[1].y == Engine.LabelY(1))
-- The heading row cannot take an item
assert(not move(store, 300, 15))

-- Fill mode consumes gaps in row-major order; switching back changes only future additions
store:SetLayoutPlacement(false)
assert(store:AddTag("gear", 400) and store:AddTag("gear", 500) and store:AddTag("gear", 600))
assert(grid(store)[2].objectID == 400 and grid(store)[3].objectID == 500)
assert(grid(store)[5].objectID == 600 and store.data.tags.gear.unsorted[1].objectID == 300)
store:SetLayoutPlacement(true)
assert(store:AddTag("gear", 700))
assert(#store.data.tags.gear.rows[1].slots == 5 and #store.data.tags.gear.unsorted == 2)

-- Moving to Unsorted keeps the item in the tag and leaves a gap
assert(store:UnarrangeLayoutItem("gear", key(200)))
assert(store:HasTag("gear", key(200)) and grid(store)[4].kind == "blank")
assert(store.data.tags.gear.unsorted[3].objectID == 200)
assert(move(store, 300, 4))
assert(grid(store)[4].objectID == 300 and #store.data.tags.gear.unsorted == 2)
-- A drop below the rows adds rows down to it, leaving the other Unsorted items alone
assert(move(store, 400, 27))
displayed, boundary = store:GetLayout("gear", 10)
assert(boundary == 30 and displayed[27].objectID == 400 and displayed[41].objectID == 700)
assert(move(store, 700, 1))
assert(grid(store)[1].objectID == 700 and store.data.tags.gear.unsorted[1].objectID == 100)
-- Merely clicking a loose item is inert; an explicit catalog drop at that cell arranges it
local _, _, changed = move(store, 100, 41)
assert(changed == false and TagLayouts.Render(store.data.tags.gear.rows, 10).lines == 3)
assert(move(store, 100, 41, nil, true))
assert(grid(store)[41].objectID == 100)

-- A ghost keeps its source through Unsorted, a reload, and sharing
local duplicated, ghost = store:DuplicateLayoutItem("gear", key(300))
assert(duplicated and ghost == key(300, 2))
assert(store:UnarrangeLayoutItem("gear", ghost))
local unsorted = store.data.tags.gear.unsorted
assert(unsorted[#unsorted].sourceLayoutKey == key(300))
assert(TagStore.new().data.tags.gear.unsorted[#unsorted].sourceLayoutKey == key(300))
assert(store:SetLabel("gear", 1, "More gear", 10))
local shared = assert(TagData.Decode(TagData.Encode(store.data, "gear"))).tags.gear
assert(TagLayouts.Render(shared.rows, 10).slots[41].objectID == 100)
assert(TagLayouts.Render(shared.rows, 10).labels[1].text == "More gear")
assert(shared.unsorted[#shared.unsorted].layoutKey == ghost)
assert(shared.unsorted[#shared.unsorted].sourceLayoutKey == key(300))

-- Two stacks of one item are separate members, and removing a ghost keeps its source
assert(store:AddTag("gear", 900, key(900)) and store:AddTag("gear", 900, key(900, 2)))
assert(move(store, 900, 2, 2))
assert(store:RemoveTag("gear", key(900, 2)))
assert(store:HasTag("gear", key(900)) and not store:HasTag("gear", key(900, 2)))
assert(store:RemoveTag("gear", ghost))
assert(store:HasTag("gear", key(300)))
for _, item in ipairs(store:GetTaggedItems("gear")) do assert(item.layoutKey ~= ghost) end

-- A rejected save leaves every edit unapplied
local prior = Json.encode(store.data)
failWrites = true
assert(not store:UnarrangeLayoutItem("gear", key(700)))
assert(not move(store, 700, 3))
assert(not store:AddTag("gear", 999))
assert(Json.encode(store.data) == prior)
failWrites = false

-- The Unsorted heading and live item geometry use the same row boundary
local editor = setmetatable({
    store = store, selectedTag = "gear", centerNodes = {},
    centerView = { content = {}, scrollY = 0, SetContentHeight = function() end },
    window = { root = {} },
    FinishDrag = function() end,
    ApplyRuntimeObjectSprite = function(_, sprite, objectID, itemKey)
        sprite.itemKey = itemKey
        return 36, 32
    end,
    NotifyChanged = function() end,
}, Editor)
editor:RefreshCenter()
boundary = editor.centerPreservedBoundary
assert(#store.data.tags.gear.unsorted > 0 and editor.centerUnsortedRow == boundary // 10)
positions = Engine.LayoutPositions(store, "gear", 10)
for _, sprite in ipairs(editor.centerNodes) do
    if sprite.itemKey then
        assert(sprite.y == positions[sprite.itemKey].y + 4)
    end
end
-- The heading row takes no drops; the first unsorted cell sits one row below it
local headingY = Engine.RowItemY(editor.centerUnsortedRow)
editor.centerView.scrollY = headingY - 100
assert(editor:SlotIndexAt(4, 100) == nil)
local looseIndex = boundary + 10 + 1
local looseY = Engine.RowItemY(math.floor((looseIndex - 1) / 10))
editor.centerView.scrollY = looseY - 100
assert(editor:SlotIndexAt(4, 100) == looseIndex)
editor.centerView.scrollY = 0

-- Failures show briefly over the grid, fade, and then go; successes stay silent
editor.centerPanel = {}
editor:ShowError("Could not save the layout.")
local banner = editor.errorBanner
assert(banner ~= nil and banner.parts[3].alpha == nil)
for _ = 1, 160 do editor:TickError() end
assert(editor.errorBanner == banner and banner.parts[3].alpha < 1)
for _ = 1, 40 do editor:TickError() end
assert(editor.errorBanner == nil and banner.root.destroyed)

-- Context actions are safe by default and offer Move to Unsorted only for arranged items
editor.ContentPointer = function() return 0, 0 end
editor.DestinationFromContentPoint = function() return 1 end
local menu = { entries = { { verbText = "Cancel" } }, entryCount = 1 }
function menu:Add(text, action)
    table.insert(self.entries, 1, { fullText = text, action = action })
    self.entryCount = #self.entries
end
function menu:Swap(left, right) self.entries[left], self.entries[right] = self.entries[right], self.entries[left] end
assert(editor:AddMenuEntries({ miniMenu = menu }))
assert(menu.entries[#menu.entries].verbText == "Cancel")
local demoted = false
for _, entry in ipairs(menu.entries) do
    if entry.fullText == "Move to Unsorted" then
        local before = writes
        entry.action()
        entry.action()
        assert(writes > before and store:HasTag("gear", key(700)))
        assert(store.data.tags.gear.unsorted[#store.data.tags.gear.unsorted].objectID == 700)
        demoted = true
    end
end
assert(demoted, "arranged items offer Move to Unsorted")

-- The placement preference survives saving and copying
assert(Settings.defaults().preserveTagLayout)
assert(Settings.save({ preserveTagLayout = false }))
assert(Settings.load().preserveTagLayout == false and Settings.copy({}).preserveTagLayout)

print("layout_preservation_test: ok")
