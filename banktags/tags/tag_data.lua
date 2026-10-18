-- Read and write the one JSON form of tag data used for saving, sharing, and backups

local Json = require("banktags/core/json")
local TagRules = require("banktags/tags/tag_rules")
local TagLayouts = require("banktags/tags/tag_layouts")
local ItemIdentity = require("banktags/tags/item_identity")
local trim = require("banktags/core/text").trim

local TagData = {}

local FORMAT = "bankutilities-tags"
local VERSION = 3
local MAX_TEXT_LENGTH = 1000000
local MAX_TAGS = 1000
local MAX_FOLDERS = 200
-- Rows, labels, and slots one saved tag may hold, which matches Bank Core's page limit
local MAX_TAG_ENTRIES = 10000
-- A shown tag adds an Unsorted label and row, so edits and imports leave room for them
local RENDER_RESERVE = 2

TagData.MAX_TAG_ENTRIES = MAX_TAG_ENTRIES
TagData.EDIT_ENTRY_LIMIT = MAX_TAG_ENTRIES - RENDER_RESERVE

-- Return data with no tags
function TagData.Empty()
    return { order = {}, folders = {}, tags = {} }
end

-- Read the copy number at the end of a layout key
function TagData.CopyNumber(layoutKey)
    return math.tointeger(tonumber(string.match(tostring(layoutKey or ""), ":(%d+)$")))
end

-- Write a slot as "" when blank, otherwise as its item reference, then ":<copy>"
-- after the first copy, then "<<copy>" for a ghost's source copy. A blank still
-- holding an item this client cannot resolve writes its saved text back
local function slotText(slot)
    if slot.kind ~= "item" then return slot.dormant or "" end
    local copy = TagData.CopyNumber(slot.layoutKey) or 1
    local text = ItemIdentity.Reference(slot.objectID) .. (copy > 1 and (":" .. copy) or "")
    local source = TagData.CopyNumber(slot.sourceLayoutKey)
    return source ~= nil and (text .. "<" .. source) or text
end

-- Read one saved slot; an item this client cannot resolve becomes a blank that keeps its text
local function readSlot(text)
    if type(text) ~= "string" or text == "" then return { kind = "blank" } end
    local item, source = string.match(text, "^(.-)<(%d+)$")
    item = item or text
    local reference, copy = string.match(item, "^(.-):(%d+)$")
    local objectID = ItemIdentity.ObjectID(reference or item)
    if objectID == nil then return { kind = "blank", dormant = text } end
    return {
        kind = "item",
        objectID = objectID,
        layoutKey = ItemIdentity.LayoutKey(objectID, math.max(1, tonumber(copy) or 1)),
        sourceLayoutKey = source ~= nil and ItemIdentity.LayoutKey(objectID, source) or nil,
    }
end

-- Encode every tag, or only the named one, as JSON
function TagData.Encode(data, onlyTag)
    local saved = { format = FORMAT, version = VERSION, order = {}, folders = {}, tags = {} }
    for _, name in ipairs(data.order) do
        local tag = data.tags[name]
        if onlyTag == nil or onlyTag == name then
            local rows, unsorted = {}, {}
            for _, entry in ipairs(tag.rows) do
                if entry.kind == "label" then
                    rows[#rows + 1] = entry.text
                else
                    local slots = {}
                    for _, slot in ipairs(entry.slots) do slots[#slots + 1] = slotText(slot) end
                    rows[#rows + 1] = slots
                end
            end
            for _, slot in ipairs(tag.unsorted) do unsorted[#unsorted + 1] = slotText(slot) end
            saved.order[#saved.order + 1] = name
            saved.tags[name] = { icon = tag.icon, folder = tag.folder, rows = rows, unsorted = unsorted }
            if tag.folder ~= nil then saved.folders[tag.folder] = data.folders[tag.folder] end
        end
    end
    return Json.encode(saved)
end

-- Count a tag's rows, labels, row slots, and Unsorted entries, as a save counts them
function TagData.EntryCount(tag)
    local count = #tag.unsorted
    for _, entry in ipairs(tag.rows) do
        count = count + 1 + (entry.kind == "row" and #entry.slots or 0)
    end
    return count
end

-- Read one saved tag, dropping anything invalid and repeated item copies
local function readTag(value, entryLimit)
    local tag = {
        icon = type(value.icon) == "string" and value.icon or nil,
        rows = {},
        unsorted = {},
    }
    local seen, count = {}, 0
    -- Keep a slot unless it repeats an item copy already in this tag
    local function add(list, text, keepBlank)
        count = count + 1
        local slot = readSlot(text)
        if slot.kind == "item" and seen[slot.layoutKey] then slot = { kind = "blank" } end
        if slot.kind == "item" then seen[slot.layoutKey] = true end
        if slot.kind == "item" or keepBlank or slot.dormant ~= nil then list[#list + 1] = slot end
    end
    for _, entry in ipairs(type(value.rows) == "table" and value.rows or {}) do
        count = count + 1
        if type(entry) == "string" then
            local text = TagRules.labelText(entry)
            if text ~= nil then tag.rows[#tag.rows + 1] = { kind = "label", text = text } end
        elseif type(entry) == "table" then
            local slots = {}
            for _, text in ipairs(entry) do add(slots, text, true) end
            tag.rows[#tag.rows + 1] = { kind = "row", slots = slots }
        end
    end
    for _, text in ipairs(type(value.unsorted) == "table" and value.unsorted or {}) do
        add(tag.unsorted, text, false)
    end
    if count > entryLimit then return nil end
    TagLayouts.Trim(tag.rows)
    return tag
end

-- Decode and check saved or pasted tag data. Only a save may hold no tags, and only a
-- save may use the full entry limit; a share code must leave room to show each tag
function TagData.Decode(text, allowEmpty)
    if type(text) ~= "string" or trim(text) == "" then
        return nil, "Paste a bank tag share code first."
    end
    local entryLimit = allowEmpty and MAX_TAG_ENTRIES or TagData.EDIT_ENTRY_LIMIT
    if #text > MAX_TEXT_LENGTH then return nil, "The import is too large." end
    local ok, saved = pcall(Json.decode, trim(text))
    if not ok or type(saved) ~= "table" or saved.format ~= FORMAT or saved.version ~= VERSION
        or type(saved.tags) ~= "table" then
        return nil, "This is not a bank tag share code."
    end
    local folders = type(saved.folders) == "table" and saved.folders or {}
    -- Tags missing from the order go last, alphabetically
    local names, listed = {}, {}
    for _, name in ipairs(type(saved.order) == "table" and saved.order or {}) do
        if type(name) == "string" and not listed[name] then
            listed[name] = true
            names[#names + 1] = name
        end
    end
    local unlisted = {}
    for name in pairs(saved.tags) do
        if type(name) == "string" and not listed[name] then unlisted[#unlisted + 1] = name end
    end
    table.sort(unlisted)
    for _, name in ipairs(unlisted) do names[#names + 1] = name end

    local data, folderCount = TagData.Empty(), 0
    for _, savedName in ipairs(names) do
        local name, value = TagRules.normalizeTag(savedName), saved.tags[savedName]
        if name ~= nil and type(value) == "table" and data.tags[name] == nil then
            if #data.order >= MAX_TAGS then return nil, "The import has too many tags." end
            local tag = readTag(value, entryLimit)
            if tag == nil then
                return nil, "The tag " .. name .. " has more than " .. entryLimit .. " entries."
            end
            local folder = type(value.folder) == "string" and folders[value.folder] or nil
            local key, display = nil, nil
            if type(folder) == "table" and type(folder.name) == "string" then
                key, display = TagRules.folderName(folder.name)
            end
            if key ~= nil and data.folders[key] == nil then
                folderCount = folderCount + 1
                if folderCount > MAX_FOLDERS then return nil, "The import has too many folders." end
                data.folders[key] = { name = display, collapsed = folder.collapsed == true }
            end
            tag.folder = key
            data.tags[name] = tag
            data.order[#data.order + 1] = name
        end
    end
    if #data.order == 0 and not allowEmpty then return nil, "The import has no tags." end
    return data, nil
end

return TagData
