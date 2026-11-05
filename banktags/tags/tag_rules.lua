-- Check tag names, folder names, labels, and layouts before saving or sharing

local Text = require("banktags/core/text")
local trim = Text.trim

local TagRules = {}

-- Saving drops longer tag names, so refuse them everywhere
TagRules.MAX_TAG_NAME = 80
TagRules.MAX_FOLDER_NAME = 40
TagRules.MAX_LABEL_TEXT = 60

-- Copy tag data fully so an edit can't touch the real data before it saves
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

-- Tidy a folder name's spaces and return it with its lowercase key
function TagRules.folderName(value)
    local name = trim(value):gsub("%s+", " ")
    if name == "" or #name > TagRules.MAX_FOLDER_NAME then return nil, nil end
    return string.lower(name), name
end

-- Clean label text, dropping markup angle brackets
function TagRules.labelText(value)
    local text = trim((tostring(value or ""):gsub("[<>]", ""))):gsub("%s+", " ")
    if text == "" then return nil end
    return string.sub(text, 1, TagRules.MAX_LABEL_TEXT)
end

-- Remove trailing empty slots, keeping unresolved item blanks
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
