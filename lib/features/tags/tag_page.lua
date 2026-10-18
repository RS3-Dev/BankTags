-- Describe how an ordinary tag page is titled, built, and edited

local titleCase = require("lib/core/text").titleCase

local TagPage = {
    -- Players can remove items from a tag while viewing it
    isMembershipEditable = true,
}

-- Show the tag name with each word capitalized
function TagPage.Title(_, tag)
    return titleCase(tag)
end

-- Lay out the tag's saved members at the current bank width
function TagPage.Apply(layout, tag)
    return layout.pageState:Apply(tag)
end

return TagPage
