-- Clean and format plain text the same way across modules

local Text = {}

-- Remove surrounding spaces from text supplied by the user
function Text.trim(value)
    return tostring(value or ""):match("^%s*(.-)%s*$")
end

-- Capitalize each word for display without changing the stored name
function Text.titleCase(value)
    return (tostring(value or ""):gsub("(%S+)", function(word)
        return (word:gsub("^%l", string.upper))
    end))
end

-- Remove markup and outer spaces, then lowercase, so menu text compares reliably
function Text.normalizeMenuText(value)
    return string.lower(
        tostring(value or "")
            :gsub("<[^>]->", "")
            :match("^%s*(.-)%s*$")
    )
end

return Text
