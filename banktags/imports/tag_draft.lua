-- Read a plain tag draft from an import provider into the shared tag data text

local ItemIdentity = require("banktags/tags/item_identity")
local PlainData = require("banktags/imports/plain_data")
local TagData = require("banktags/tags/tag_data")
local TagRules = require("banktags/tags/tag_rules")

local TagDraft = {}

TagDraft.LIMITS = {
    tags = 32,
    -- Rows, labels, slots, and items across the whole draft
    entries = 2000,
    configNameLength = 128,
}
local LIMITS = TagDraft.LIMITS

local DRAFT_FIELDS = { tags = true }
local TAG_FIELDS = { name = true, icon = true, folder = true, rows = true, items = true }
local LABEL_FIELDS = { label = true }

-- Accept only a table with no metatable, so reading it runs no caller code
local function isPlain(value)
    return type(value) == "table" and getmetatable(value) == nil
end

-- Read an item reference: an object ID, or a config name kept by name when unknown
local function readReference(entry)
    if type(entry) == "number" then
        local objectID = PlainData.ObjectNumber(entry)
        return objectID, nil
    end
    if type(entry) ~= "string" or entry == "" or #entry > LIMITS.configNameLength
        or string.find(entry, "[%c:<>#]") or string.match(entry, "^%s") or string.match(entry, "%s$") then
        return nil, nil
    end
    return ItemIdentity.ObjectID(entry), entry
end

-- Turn one item entry into a slot; a repeated object takes its next copy
local function readSlot(entry, copies)
    local objectID, name = readReference(entry)
    if objectID == nil then
        -- An unknown config name stays saved by name
        if name ~= nil then return { kind = "blank", dormant = name } end
        return nil
    end
    local copy = (copies[objectID] or 0) + 1
    copies[objectID] = copy
    return { kind = "item", objectID = objectID, layoutKey = ItemIdentity.LayoutKey(objectID, copy) }
end

-- Read one draft tag into tag data, spending entries from the shared budget
local function readTag(input, index, budget, data)
    local prefix = "tag " .. index
    if not isPlain(input) or not PlainData.HasOnlyFields(input, TAG_FIELDS) then
        return nil, prefix .. " must be a table of name, icon, folder, rows, and items"
    end
    local name = PlainData.Label(rawget(input, "name"), TagRules.MAX_TAG_NAME)
    name = name ~= nil and TagRules.normalizeTag(name) or nil
    if name == nil then return nil, prefix .. " name must be 1 to 80 characters without commas" end
    if data.tags[name] ~= nil then return nil, prefix .. " repeats the name " .. name end
    local tag = { rows = {}, unsorted = {} }

    local icon = rawget(input, "icon")
    if icon ~= nil then
        local objectID, iconName = readReference(icon)
        if objectID == nil and iconName == nil then
            return nil, prefix .. " icon must be an object ID or config name"
        end
        tag.icon = iconName or ItemIdentity.Reference(objectID)
    end

    local folder = rawget(input, "folder")
    if folder ~= nil then
        local key, display = nil, nil
        if PlainData.Label(folder, TagRules.MAX_FOLDER_NAME) ~= nil then key, display = TagRules.folderName(folder) end
        if key == nil then return nil, prefix .. " folder must be 1 to 40 characters" end
        data.folders[key] = data.folders[key] or { name = display, collapsed = false }
        tag.folder = key
    end

    local copies = {}
    -- Copy a list of items into slots, with false as a blank where blanks are allowed
    local function readSlots(list, target, allowBlank, label)
        local entries = isPlain(list) and PlainData.Array(list, budget.left) or nil
        if entries == nil then return prefix .. " " .. label .. " must be a list within the draft's size" end
        budget.left = budget.left - #entries
        for slotIndex, entry in ipairs(entries) do
            local slot = (entry == false and allowBlank) and { kind = "blank" } or nil
            if slot == nil then slot = readSlot(entry, copies) end
            if slot == nil then
                return prefix .. " " .. label .. " entry " .. slotIndex .. " is not an object ID or config name"
            end
            target[#target + 1] = slot
        end
        return nil
    end

    local rows = rawget(input, "rows")
    if rows ~= nil then
        rows = isPlain(rows) and PlainData.Array(rows, budget.left) or nil
        if rows == nil then return nil, prefix .. " rows must be a list within the draft's size" end
        budget.left = budget.left - #rows
        for rowIndex, row in ipairs(rows) do
            if isPlain(row) and rawget(row, "label") ~= nil then
                local text = PlainData.HasOnlyFields(row, LABEL_FIELDS)
                    and PlainData.Label(rawget(row, "label"), TagRules.MAX_LABEL_TEXT) or nil
                if text == nil then
                    return nil, prefix .. " row " .. rowIndex .. " label must be 1 to 60 characters and alone"
                end
                tag.rows[#tag.rows + 1] = { kind = "label", text = TagRules.labelText(text) }
            else
                local slots = {}
                local reason = readSlots(row, slots, true, "row " .. rowIndex)
                if reason ~= nil then return nil, reason end
                tag.rows[#tag.rows + 1] = { kind = "row", slots = slots }
            end
        end
    end

    local items = rawget(input, "items")
    if items ~= nil then
        local reason = readSlots(items, tag.unsorted, false, "items")
        if reason ~= nil then return nil, reason end
    end
    data.tags[name] = tag
    data.order[#data.order + 1] = name
    return true
end

-- Read a draft into share-code text, or return nil and why
function TagDraft.Read(draft)
    if not isPlain(draft) or not PlainData.HasOnlyFields(draft, DRAFT_FIELDS) then
        return nil, "a draft is a table with a tags list"
    end
    local inputs = rawget(draft, "tags")
    inputs = isPlain(inputs) and PlainData.Array(inputs, LIMITS.tags) or nil
    if inputs == nil or #inputs == 0 then return nil, "tags must be a list of 1 to 32 tags" end
    local data = TagData.Empty()
    local budget = { left = LIMITS.entries }
    for index, input in ipairs(inputs) do
        local read, reason = readTag(input, index, budget, data)
        if not read then return nil, reason end
    end
    return TagData.Encode(data)
end

return TagDraft
