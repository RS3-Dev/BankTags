-- Validate tag names, folder names, labels, and layouts for storage and sharing

local Text = require("lib/core/text")
local trim = Text.trim

local TagRules = {}

-- Saving drops longer tag names, so every entry point must refuse them
TagRules.MAX_TAG_NAME = 80
TagRules.MAX_FOLDER_NAME = 40
TagRules.MAX_LABEL_TEXT = 60

-- Deep-copy tag data so an edit cannot reach the live data before it saves
function TagRules.copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = TagRules.copy(child) end
    return result
end

-- Trim and lowercase one tag name, refusing commas and overlong names
function TagRules.normalizeTag(value)
    local name = string.lower(trim(value))
    if name == "" or #name > TagRules.MAX_TAG_NAME
        or string.find(name, ",", 1, true) then return nil end
    return name
end

-- Parse comma-separated tags into a sorted list of unique normalized names
function TagRules.parseTagList(text)
    local values = {}
    local seen = {}
    for tag in tostring(text or ""):gmatch("([^,]+)") do
        tag = TagRules.normalizeTag(tag)
        if tag ~= nil and not seen[tag] then
            seen[tag] = true
            values[#values + 1] = tag
        end
    end
    table.sort(values)
    return values
end

-- Collapse spacing in a folder name and derive its case-insensitive key
function TagRules.folderName(value)
    local name = trim(value):gsub("%s+", " ")
    if name == "" or #name > TagRules.MAX_FOLDER_NAME then return nil, nil end
    return string.lower(name), name
end

-- Clean page-label text, dropping angle brackets the client treats as markup
function TagRules.labelText(value)
    local text = trim((tostring(value or ""):gsub("[<>]", ""))):gsub("%s+", " ")
    if text == "" then return nil end
    return string.sub(text, 1, TagRules.MAX_LABEL_TEXT)
end

-- Remove empty slots only at the end so interior grid positions stay stable
-- A blank holding an unresolved item is not empty and is kept
function TagRules.trimTrailingLayoutBlanks(slots)
    if type(slots) ~= "table" then return {} end
    while #slots > 0 do
        local slot = slots[#slots]
        if type(slot) ~= "table" or slot.kind ~= "blank" or slot.dormant ~= nil then break end
        slots[#slots] = nil
    end
    return slots
end

return TagRules
