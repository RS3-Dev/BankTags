-- Describe a saved tag as the Bank Core page that shows it

local TagData = require("banktags/tags/tag_data")

local TagPage = {}

TagPage.UNSORTED_LABEL = "Unsorted"
-- Bank Core's limit on labels, rows, and slots in one page
TagPage.MAX_ENTRIES = TagData.MAX_TAG_ENTRIES

-- Build bank rows and the keys identifying their items
function TagPage.Rows(record)
    local rows, keys, count = {}, {}, 0
    -- Add a saved slot and its page key
    local function add(slots, slot)
        local item = slot.kind == "item"
        slots[#slots + 1] = item and slot.objectID or false
        keys[#keys + 1] = item and slot.layoutKey or false
    end
    for _, entry in ipairs(record.rows) do
        if entry.kind == "label" then
            -- Bank Core refuses control characters in label text
            local text = string.gsub(entry.text, "%c", "")
            rows[#rows + 1] = text ~= "" and { label = text } or { slots = {} }
            count = count + 1
        else
            local slots = {}
            for _, slot in ipairs(entry.slots) do add(slots, slot) end
            rows[#rows + 1] = { slots = slots }
            count = count + 1 + #slots
        end
    end
    local unsorted = {}
    for _, slot in ipairs(record.unsorted) do
        if slot.kind == "item" then add(unsorted, slot) end
    end
    if #unsorted > 0 then
        rows[#rows + 1] = { label = TagPage.UNSORTED_LABEL }
        rows[#rows + 1] = { slots = unsorted }
        count = count + 2 + #unsorted
    end
    return rows, keys, count
end

-- Build a tag's page or explain why it cannot open
function TagPage.Build(store, tag)
    local record = store.data.tags[tag]
    if record == nil then return nil, "The tag no longer exists." end
    local rows, keys, count = TagPage.Rows(record)
    -- The saved tag stays whole; Bank Core just cannot draw it
    if count > TagPage.MAX_ENTRIES then
        return nil, "This tag has " .. count .. " rows, labels, and items, more than the "
            .. TagPage.MAX_ENTRIES .. " Bank Core shows. Remove some in the layout editor."
    end
    return { rows = rows }, keys
end

return TagPage
