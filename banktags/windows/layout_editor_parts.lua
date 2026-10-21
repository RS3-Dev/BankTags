-- Share layout editor measurements and drawing helpers

local BankGrid = require("banktags/ui/bank_grid")
local TagRail = require("banktags/windows/layout_editor_rail")

local Parts = {}
local Size = {}
Parts.size = Size

-- Shown in the empty item search panel
Parts.SEARCH_HINT = "Search for an item, then drag it into the layout."
-- Shown under the item actions
Parts.ACTIONS_HELP = "Drag items into the layout. Drag a placed item here to leave it unsorted."
-- Shown under the sorted grid
Parts.SHORTCUTS = "Delete: Remove     Ctrl+C: Create copy"
Parts.SAVED = "Saved automatically"

-- Default sizes match the expanded bank window plus Bank Core's sidebar
-- A tag rail and the sorted grid take the sidebar's place; a larger bank grows the grid
-- Bank Core's sidebar: its tab rail, the gap after it, and its tag column
Size.SIDEBAR_WIDTH = 32 + 8 + 244
Size.DEFAULT_WIDTH = 714 + Size.SIDEBAR_WIDTH
Size.DEFAULT_HEIGHT = 650
Size.PANEL_TOP = 12
Size.DEFAULT_PANEL_HEIGHT = 594
-- The tag rail runs down the left edge, like Bank Core's tab rail
Size.RAIL_X = 8
Size.RAIL_GAP = 8
Size.CENTER_X = Size.RAIL_X + TagRail.WIDTH + Size.RAIL_GAP
Size.DEFAULT_CENTER_WIDTH = 477
-- The right column ends where the window's border begins
Size.RIGHT_MARGIN = 20
-- The open tag's name and Edit tag sit above the sorted grid
Size.TITLE_HEIGHT = 30
Size.EDIT_TAG_WIDTH = 96
Size.SORTED_TOP = Size.TITLE_HEIGHT + 10
-- The shortcuts and saved note sit under the sorted grid
Size.FOOTER_HEIGHT = 28
-- The editor grid starts 4px in, not the bank's 8px
Size.GRID_LEFT = 4
Size.GRID_TOP = BankGrid.TOP
Size.GRID_STEP = BankGrid.STEP
Size.GRID_SLOT_SIZE = BankGrid.SLOT_SIZE
Size.LABEL_LINE_OFFSET = BankGrid.LABEL_LINE_OFFSET
Size.LABEL_GHOST_WIDTH = 180
Size.LABEL_GHOST_HEIGHT = 28
Size.DEFAULT_SURFACE_WIDTH = 473
-- The sorted view fills the sorted surface
Size.CENTER_VIEW_X = 4
Size.SORTED_VIEW_Y = Size.SORTED_TOP + 4
-- A 467px view leaves 449px for items after PrettyUI's scrollbar
Size.DEFAULT_VIEW_WIDTH = 467
-- PrettyUI reserves this much for a scroll list's scrollbar and its gap
Size.SCROLLBAR_RESERVE = 18
-- The right column: Unsorted and Search tabs over shared item actions
Size.RIGHT_INSET = 8
Size.TAB_Y = 4
-- PrettyUI's tab header; pages start under it
Size.TAB_HEADER = 42
Size.TAB_PAGE_Y = Size.TAB_Y + Size.TAB_HEADER
Size.SEARCH_FIELD_HEIGHT = 26
Size.SEARCH_LIST_TOP = Size.TAB_PAGE_Y + Size.SEARCH_FIELD_HEIGHT + 8
Size.BUTTON_HEIGHT = 28
Size.BUTTON_GAP = 4
Size.BUTTON_STEP = Size.BUTTON_HEIGHT + Size.BUTTON_GAP
Size.HELP_HEIGHT = 30
-- Two rows of two buttons, then the help text
Size.ACTIONS_HEIGHT = 2 * Size.BUTTON_STEP + Size.HELP_HEIGHT

-- Size the editor to cover the bank at Bank Core's columns
-- Only one editor is open, so sizes live in Size
function Parts.SizeToBank(columns, bankWidth, bankHeight)
    local columnWidth = (columns - BankGrid.DEFAULT_COLUMNS) * Size.GRID_STEP
    local extraWidth = math.max(columnWidth, (tonumber(bankWidth) or 0) - Size.DEFAULT_WIDTH)
    local extraHeight = math.max(0, (tonumber(bankHeight) or 0) - Size.DEFAULT_HEIGHT)
    Size.CENTER_COLUMNS = columns
    Size.WIDTH = Size.DEFAULT_WIDTH + extraWidth
    Size.HEIGHT = Size.DEFAULT_HEIGHT + extraHeight
    Size.PANEL_HEIGHT = Size.DEFAULT_PANEL_HEIGHT + extraHeight
    Size.CENTER_WIDTH = Size.DEFAULT_CENTER_WIDTH + extraWidth
    Size.CENTER_SURFACE_WIDTH = Size.DEFAULT_SURFACE_WIDTH + extraWidth
    Size.CENTER_SURFACE_HEIGHT = Size.PANEL_HEIGHT - Size.SORTED_TOP - Size.FOOTER_HEIGHT
    Size.CENTER_VIEW_WIDTH = Size.DEFAULT_VIEW_WIDTH + extraWidth
    Size.SORTED_VIEW_HEIGHT = Size.CENTER_SURFACE_HEIGHT - 8
    Size.FOOTER_Y = Size.SORTED_TOP + Size.CENTER_SURFACE_HEIGHT
    -- The right column takes the rest of the width
    Size.RIGHT_X = Size.CENTER_X + Size.CENTER_WIDTH
    Size.RIGHT_WIDTH = Size.WIDTH - Size.RIGHT_MARGIN - Size.RIGHT_X
    Size.RIGHT_VIEW_WIDTH = Size.RIGHT_WIDTH - 2 * Size.RIGHT_INSET
    Size.HALF_BUTTON_WIDTH = (Size.RIGHT_VIEW_WIDTH - Size.BUTTON_GAP) // 2
    -- Unsorted fits as many columns as the right view holds
    Size.UNSORTED_COLUMNS = (Size.RIGHT_VIEW_WIDTH - Size.SCROLLBAR_RESERVE - Size.GRID_LEFT
        + Size.GRID_STEP - Size.GRID_SLOT_SIZE) // Size.GRID_STEP
    -- A taller bank grows both right tabs; the actions stay at the bottom
    Size.ACTIONS_Y = Size.PANEL_HEIGHT - Size.RIGHT_INSET - Size.ACTIONS_HEIGHT
    -- New label shares the second row with Move to Unsorted
    Size.LABEL_BUTTON_X = Size.RIGHT_INSET + Size.HALF_BUTTON_WIDTH + Size.BUTTON_GAP
    Size.LABEL_BUTTON_Y = Size.ACTIONS_Y + Size.BUTTON_STEP
    Size.LABEL_BUTTON_WIDTH = Size.RIGHT_VIEW_WIDTH - Size.HALF_BUTTON_WIDTH - Size.BUTTON_GAP
    Size.UNSORTED_VIEW_HEIGHT = Size.ACTIONS_Y - Size.RIGHT_INSET - Size.TAB_PAGE_Y
    Size.SEARCH_LIST_HEIGHT = Size.ACTIONS_Y - Size.RIGHT_INSET - Size.SEARCH_LIST_TOP
end
Parts.SizeToBank(BankGrid.DEFAULT_COLUMNS)

-- Create a click-through decorative rectangle
function Parts.rectangle(parent, x, y, width, height, colour, fill)
    local value = ui.Rectangle.new(parent)
    value:SetPos(x, y)
    value:SetSize(width, height)
    value.fill = fill ~= false
    value.rgba = colour
    value.clickthrough = true
    if fill == false then value.outlineThickness = 1 end
    return value
end

-- Fill a panel with a repeating native sprite
function Parts.tiledSprite(parent, x, y, width, height, spriteID)
    local value = ui.Sprite.new(parent)
    value:SetPos(x, y)
    value:SetSize(width, height)
    value.spriteID = spriteID
    value.isTiling = true
    value.clickthrough = true
    return value
end

-- Draw a click-through border from four edges
function Parts.frame(parent, x, y, width, height, colour)
    local edges = {
        Parts.rectangle(parent, x, y, width, 1, colour, true),
        Parts.rectangle(parent, x, y + height - 1, width, 1, colour, true),
        Parts.rectangle(parent, x, y, 1, height, colour, true),
        Parts.rectangle(parent, x + width - 1, y, 1, height, colour, true),
    }
    for _, edge in ipairs(edges) do edge:MoveToFront() end
    return edges
end

-- Look up an item definition, allowing missing entries
function Parts.objectFromID(objectID)
    local ok, object = pcall(function()
        return config.Obj.FromID(math.tointeger(objectID))
    end)
    return ok and object or nil
end

return Parts
