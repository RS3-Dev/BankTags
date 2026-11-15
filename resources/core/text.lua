-- Clean and format plain text the same way across modules

local Text = {}
local Config = require("resources/core/config")

-- Strip complete tags and stray brackets even when Core is absent or outdated
function Text.sanitize(value)
    local text = tostring(value or "")
    local candidates = { bankcore, rawget(_G, Config.CORE_API_KEY) }
    for index = 1, 2 do
        local api = candidates[index]
        if type(api) == "table" and type(api.SanitizeString) == "function" then
            local ok, sanitized = pcall(api.SanitizeString, text)
            if ok and type(sanitized) == "string" then text = sanitized; break end
        end
    end
    return (text:gsub("<[^<>]*>", ""):gsub("[<>]", ""))
end

-- Scrub pasted text before a text field can render it
function Text.cleanField(field, value)
    local sanitized = Text.sanitize(value)
    if sanitized ~= value then field:SetText(sanitized, false) end
    return sanitized
end

-- Remove surrounding spaces from text supplied by the user
function Text.trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

-- Capitalize each word for display without changing the stored name
function Text.titleCase(value)
    -- Capitalize the first letter of each word
    return (Text.plain(value):gsub("(%S+)", function(word)
        return (word:gsub("^%l", string.upper))
    end))
end

-- Remove control characters and markup brackets
function Text.plain(value)
    local text = string.gsub(Text.sanitize(value), "%c", "")
    return Text.trim(text)
end

return Text
