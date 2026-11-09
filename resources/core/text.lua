-- Clean and format plain text the same way across modules

local Text = {}

-- Remove surrounding spaces from text supplied by the user
function Text.trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

-- Capitalize each word for display without changing the stored name
function Text.titleCase(value)
    -- Capitalize the first letter of each word
    return (tostring(value or ""):gsub("(%S+)", function(word)
        return (word:gsub("^%l", string.upper))
    end))
end

-- Remove control characters and markup brackets
function Text.plain(value)
    local text = string.gsub(tostring(value or ""), "[%c<>]", "")
    return Text.trim(text)
end

return Text
