-- Describe a saved tag as the single Bank Core page that shows it

local Text = require("banktags/core/text")
local TagData = require("banktags/tags/tag_data")
local ItemIdentity = require("banktags/tags/item_identity")
local BankGrid = require("banktags/ui/bank_grid")

local TagPage = {}

-- The one page ID Bank Tags registers
TagPage.PAGE_ID = "tag"
TagPage.UNSORTED_LABEL = "Unsorted"
-- The page block Bank Core draws the tag's items in
TagPage.ITEMS_BLOCK = "items"
-- Bank Core's page labels take this much height, not a full grid row
TagPage.LABEL_HEIGHT = 34
local KEY_PREFIX = "tag:"
-- Bank Core's limit on labels, rows, and slots in one page
TagPage.MAX_ENTRIES = TagData.MAX_TAG_ENTRIES

-- Return the page key that shows a tag
function TagPage.Key(tag)
    return KEY_PREFIX .. tag
end

-- Return the tag a page key shows, or nil for any other key
function TagPage.TagFromKey(key)
    if type(key) ~= "string" or string.sub(key, 1, #KEY_PREFIX) ~= KEY_PREFIX then return nil end
    return string.sub(key, #KEY_PREFIX + 1)
end

-- Show a tag name with each word capitalized
function TagPage.Title(tag)
    return Text.titleCase(tag)
end

-- Turn a saved slot into a page slot, blanking repeated copies
local function pageSlot(slot, seen)
    if slot.kind ~= "item" then return false end
    local objectID, copy = ItemIdentity.ParseKey(slot.layoutKey)
    if objectID == nil or copy == nil or seen[slot.layoutKey] then return false end
    seen[slot.layoutKey] = true
    local _, source = ItemIdentity.ParseKey(slot.sourceLayoutKey)
    if source == copy then source = nil end
    if copy == 1 and source == nil then return objectID end
    return { item = objectID, copy = copy, source = source }
end

-- Lay a tag out as page rows, with Unsorted items last
function TagPage.Rows(record)
    local rows, seen, count = {}, {}, 0
    for _, entry in ipairs(record.rows) do
        if entry.kind == "label" then
            -- Bank Core refuses control characters in label text
            local text = string.gsub(entry.text, "%c", "")
            rows[#rows + 1] = text ~= "" and { label = text } or { slots = {} }
            count = count + 1
        else
            local slots = {}
            for index, slot in ipairs(entry.slots) do slots[index] = pageSlot(slot, seen) end
            rows[#rows + 1] = { slots = slots }
            count = count + 1 + #slots
        end
    end
    local unsorted = {}
    for _, slot in ipairs(record.unsorted) do
        if slot.kind == "item" then
            local value = pageSlot(slot, seen)
            if value ~= false then unsorted[#unsorted + 1] = value end
        end
    end
    if #unsorted > 0 then
        rows[#rows + 1] = { label = TagPage.UNSORTED_LABEL }
        rows[#rows + 1] = { slots = unsorted }
        count = count + 2 + #unsorted
    end
    return rows, count
end

-- Read a page slot as its object, copy, and source copy
local function slotItem(slot)
    if type(slot) == "table" then return slot.item, slot.copy, slot.source end
    return slot, 1, nil
end

-- Check whether Bank Core puts a bank stack under a page slot
-- Its own copy, else its named source, else the object's only stack with items
local function hasStack(slot, stacks)
    local objectID, copy, source = slotItem(slot)
    local copies = stacks[objectID]
    if copies == nil then return false end
    local own = copies.byCopy[copy]
    if own ~= nil then return own end
    if source ~= nil and copies.byCopy[source] then return true end
    return copies.held == 1
end

-- List the slots Bank Core draws with no bank stack, where pages are laid out
-- Positions follow Bank Core's page grid, with each label line shorter than a row
function TagPage.EmptySlots(rows, columns, bankItems)
    local stacks = {}
    for _, item in ipairs(bankItems) do
        local copies = stacks[item.objectID]
        if copies == nil then
            copies = { byCopy = {}, held = 0 }
            stacks[item.objectID] = copies
        end
        local held = not item.placeholder and (tonumber(item.quantity) or 0) > 0
        copies.byCopy[item.copy] = held
        if held then copies.held = copies.held + 1 end
    end
    local slots, offset = {}, 0
    for _, row in ipairs(rows) do
        if row.label ~= nil then
            offset = offset + TagPage.LABEL_HEIGHT
        else
            for index, slot in ipairs(row.slots) do
                if slot ~= false and not hasStack(slot, stacks) then
                    slots[#slots + 1] = {
                        objectID = (slotItem(slot)),
                        x = BankGrid.LEFT + (index - 1) % columns * BankGrid.STEP,
                        y = BankGrid.TOP + offset + (index - 1) // columns * BankGrid.STEP,
                    }
                end
            end
            offset = offset + math.max(1, math.ceil(#row.slots / columns)) * BankGrid.STEP
        end
    end
    return slots
end

-- Describe a tag's page, or a notice page when it is too large
-- The tag's page carries a one-pixel block so its names mount can draw over the items
function TagPage.Build(store, tag, mounts)
    local record = store.data.tags[tag]
    if record == nil then return nil, "The tag no longer exists." end
    local title = TagPage.Title(tag)
    local rows, count = TagPage.Rows(record)
    if count <= TagPage.MAX_ENTRIES then
        return { title = title, key = TagPage.Key(tag), mount = mounts.names, body = {
            { items = TagPage.ITEMS_BLOCK, layout = rows },
            { ui = "names", height = 1 },
        } }, nil
    end
    -- The saved tag stays whole; Bank Core just cannot draw it
    local notice = "This tag has " .. count .. " rows, labels, and items. Bank Core shows at most "
        .. TagPage.MAX_ENTRIES .. ". Remove some in the layout editor to show it."
    return { title = title, key = TagPage.Key(tag), mount = mounts.notice,
        body = { { ui = "notice", height = 80 } } }, notice
end

return TagPage
