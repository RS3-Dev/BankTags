-- Check tag names, folder names, labels, and layouts before saving or sharing

local Text = require("resources/core/text")

local TagRules = {}

-- Saving drops longer tag names, so refuse them everywhere
TagRules.MAX_TAG_NAME = 80
TagRules.MAX_FOLDER_NAME = 40
TagRules.MAX_LABEL_TEXT = 60
local UUID_PATTERN = "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$"

-- Check whether a tag key already uses a UUID
function TagRules.isUUID(value)
    return type(value) == "string" and string.match(value, UUID_PATTERN) ~= nil
end

-- Generate a lowercase UUID v4 that does not collide with existing keys
function TagRules.newUUID(existing)
    local function generate()
        return (string.gsub("xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx", "[xy]", function(char)
            local value = char == "x" and math.random(0, 15) or math.random(8, 11)
            return string.format("%x", value)
        end))
    end
    local id = generate()
    while type(existing) == "table" and existing[id] ~= nil do
        id = generate()
    end
    return id
end

-- Copy data so an unsaved edit stays separate
function TagRules.copy(value)
    if type(value) ~= "table" then return value end
    local result = {}
    for key, child in pairs(value) do result[key] = TagRules.copy(child) end
    return result
end

-- Clean a tag name and check its length
function TagRules.normalizeTag(value)
    local name = string.lower(Text.plain(value))
    if name == "" or #name > TagRules.MAX_TAG_NAME
        or string.find(name, ",", 1, true) then return nil end
    return name
end

-- Clean a folder name and its lookup key
function TagRules.folderName(value)
    local name = Text.plain(value):gsub("%s+", " ")
    if name == "" or #name > TagRules.MAX_FOLDER_NAME then return nil, nil end
    return string.lower(name), name
end

-- Clean label text, dropping complete markup tags
function TagRules.labelText(value)
    local text = Text.plain(value):gsub("%s+", " ")
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
