-- Describe one saved tag as the Bank Core page that shows it. Every tag is shown through a
-- single page whose key names the tag, so Bank Core keeps one page however many tags exist

local Text = require("banktags/core/text")
local TagData = require("banktags/tags/tag_data")
local ItemIdentity = require("banktags/tags/item_identity")

local TagPage = {}

-- The one page ID Bank Tags registers, and the label above Unsorted items
TagPage.PAGE_ID = "tag"
TagPage.UNSORTED_LABEL = "Unsorted"
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

-- Turn one saved slot into a page slot: an object ID for a first copy, a table for a later
-- copy or a ghost, and false for a blank or an item this client cannot resolve. A copy the
-- page already shows becomes a blank rather than refusing the whole page
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

-- Lay a tag's rows out as page rows, with its Unsorted items last under their own label.
-- Returns the rows and how many page entries they use
function TagPage.Rows(record)
    local rows, seen, count = {}, {}, 0
    for _, entry in ipairs(record.rows) do
        if entry.kind == "label" then
            -- Bank Core refuses control characters, which saved label text may still hold
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

-- Describe the page that shows a tag, or a notice page when the tag is too large to show.
-- noticeMount draws the notice; the second result is the notice text, if any
function TagPage.Build(store, tag, noticeMount)
    local record = store.data.tags[tag]
    if record == nil then return nil, "The tag no longer exists." end
    local title = TagPage.Title(tag)
    local rows, count = TagPage.Rows(record)
    if count <= TagPage.MAX_ENTRIES then
        return { title = title, key = TagPage.Key(tag), layout = rows }, nil
    end
    -- The saved tag stays whole; it is only too large for Bank Core to draw
    local notice = "This tag has " .. count .. " rows, labels, and items. Bank Core shows at most "
        .. TagPage.MAX_ENTRIES .. ". Remove some in the layout editor to show it."
    return { title = title, key = TagPage.Key(tag), mount = noticeMount,
        body = { { ui = "notice", height = 80 } } }, notice
end

return TagPage
