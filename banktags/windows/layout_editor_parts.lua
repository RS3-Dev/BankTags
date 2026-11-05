-- Share layout editor measurements and drawing helpers

local BankGrid = require("banktags/ui/bank_grid")
local Theme = require("banktags/ui/theme")
local SidebarRows = require("banktags/ui/sidebar_rows")

local Parts = {}
local Size = {}
Parts.size = Size

-- Match the bank and sidebar's default size
Size.SIDEBAR_WIDTH = 32 + 8 + 244
Size.DEFAULT_WIDTH = 714 + Size.SIDEBAR_WIDTH
Size.DEFAULT_HEIGHT = 650
-- Leave a small inset below the title bar
Size.PANEL_TOP = 6
Size.DEFAULT_PANEL_HEIGHT = 600
-- Each column draws its items in one framed area, its view inset alike
Size.VIEW_INSET = 4
Size.COLUMN_GAP = 6
-- Keep Unsorted five columns wide
Size.UNSORTED_X = 8
Size.UNSORTED_COLUMNS = 5
-- The right column ends where the window's border begins
Size.RIGHT_MARGIN = 20
-- The editor grid starts 4px in, not the bank's 8px
Size.GRID_LEFT = 4
Size.GRID_TOP = BankGrid.TOP
Size.GRID_STEP = BankGrid.STEP
Size.GRID_SLOT_SIZE = BankGrid.SLOT_SIZE
Size.LABEL_LINE_OFFSET = BankGrid.LABEL_LINE_OFFSET
-- Item sprites match the native bank's, centred in their cells
Size.ITEM_WIDTH = 36
Size.ITEM_HEIGHT = 32
Size.LABEL_GHOST_WIDTH = 180
Size.LABEL_GHOST_HEIGHT = 28
-- Keep the bank's central grid at its native spacing
Size.DEFAULT_CENTER_WIDTH = 474
-- PrettyUI reserves this much for a scroll list's scrollbar and its gap
Size.SCROLLBAR_RESERVE = 18
-- Fit five cells, their gaps, padding, and a scrollbar
Size.UNSORTED_WIDTH = (Size.UNSORTED_COLUMNS - 1) * Size.GRID_STEP + Size.GRID_SLOT_SIZE
    + Size.SCROLLBAR_RESERVE + 2 * Size.VIEW_INSET + 10
Size.CENTER_X = Size.UNSORTED_X + Size.UNSORTED_WIDTH + Size.COLUMN_GAP
-- Place Layout and Unsorted headings above their items
Size.TAB_HEADER = 42
Size.HEADER_HEIGHT = 20
Size.HEADER_Y = Size.TAB_HEADER - Size.HEADER_HEIGHT - 4
Size.TABS_Y = Size.PANEL_TOP + 3
Size.TABS_INSET = 4
-- Space under both item areas, above the actions
Size.AREA_BOTTOM = 8
Size.SEARCH_INSET = SidebarRows.CONTENT_X
Size.SEARCH_FIELD_TOP = SidebarRows.SEARCH_TOP
Size.SEARCH_FIELD_HEIGHT = SidebarRows.SEARCH_HEIGHT
Size.SEARCH_ROW_HEIGHT = 32
Size.SEARCH_LIST_TOP = SidebarRows.LIST_TOP
-- Both grids start under the header, inset in their item areas
Size.VIEW_Y = Size.PANEL_TOP + Size.TAB_HEADER + Size.VIEW_INSET
-- One row of actions runs under all columns
Size.BUTTON_HEIGHT = 28
Size.BUTTON_GAP = 4
Size.BUTTON_GROUP_GAP = 16
Size.ACTIONS_GAP = 8
Size.ACTION_WIDTH = { 72, 72, 88, 144, 96, 80 }

-- Fit the editor to the bank's columns and size
function Parts.SizeToBank(columns, bankWidth, bankHeight)
    local columnWidth = (columns - BankGrid.DEFAULT_COLUMNS) * Size.GRID_STEP
    local extraWidth = math.max(columnWidth, (bankWidth or 0) - Size.DEFAULT_WIDTH)
    local extraHeight = math.max(0, (bankHeight or 0) - Size.DEFAULT_HEIGHT)
    Size.CENTER_COLUMNS = columns
    -- Labels span the sorted grid's cells
    Size.LABEL_WIDTH = columns * Size.GRID_STEP - (Size.GRID_STEP - Size.GRID_SLOT_SIZE)
    Size.WIDTH = Size.DEFAULT_WIDTH + extraWidth
    Size.HEIGHT = Size.DEFAULT_HEIGHT + extraHeight
    Size.PANEL_HEIGHT = Size.DEFAULT_PANEL_HEIGHT + extraHeight
    Size.CENTER_WIDTH = Size.DEFAULT_CENTER_WIDTH + extraWidth
    Size.CENTER_VIEW_WIDTH = Size.CENTER_WIDTH - 2 * Size.VIEW_INSET
    -- Keep Search fixed while wider banks expand Layout
    Size.SEARCH_X = Size.CENTER_X + Size.CENTER_WIDTH + Size.COLUMN_GAP
    Size.SEARCH_WIDTH = Size.WIDTH - Size.RIGHT_MARGIN - Size.SEARCH_X
    Size.SEARCH_VIEW_WIDTH = SidebarRows.ContentWidth(Size.SEARCH_WIDTH)
    Size.UNSORTED_VIEW_WIDTH = Size.UNSORTED_WIDTH - 2 * Size.VIEW_INSET
    -- The actions end the panel; a taller bank grows both columns above them
    Size.ACTIONS_Y = Size.PANEL_HEIGHT - Size.BUTTON_HEIGHT
    Size.COLUMN_HEIGHT = Size.ACTIONS_Y - Size.ACTIONS_GAP
    -- Both item areas share their top and height
    Size.AREA_HEIGHT = Size.COLUMN_HEIGHT - Size.AREA_BOTTOM - Size.TAB_HEADER
    Size.VIEW_HEIGHT = Size.AREA_HEIGHT - 2 * Size.VIEW_INSET
    Size.SEARCH_LIST_HEIGHT = Size.COLUMN_HEIGHT - Size.SEARCH_INSET - Size.SEARCH_LIST_TOP
    -- Start actions below Unsorted and keep Close at the right
    Size.ACTION_X = { Size.UNSORTED_X }
    for index = 2, #Size.ACTION_WIDTH - 1 do
        Size.ACTION_X[index] = index == 4 and Size.CENTER_X + Size.VIEW_INSET
            or Size.ACTION_X[index - 1] + Size.ACTION_WIDTH[index - 1] + Size.BUTTON_GAP
    end
    Size.ACTION_X[6] = Size.WIDTH - Size.RIGHT_MARGIN - Size.ACTION_WIDTH[6]
    Size.STATUS_X = Size.ACTION_X[5] + Size.ACTION_WIDTH[5] + Size.BUTTON_GROUP_GAP
    Size.STATUS_WIDTH = Size.ACTION_X[6] - Size.BUTTON_GAP - Size.STATUS_X
end
Parts.SizeToBank(BankGrid.DEFAULT_COLUMNS)

-- Create a click-through rectangle, filled or outlined inward
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

-- Create a click-through layer over part of a parent
function Parts.layer(parent, x, y, width, height)
    local value = ui.Layer.new(parent)
    value:SetPos(x, y)
    value:SetSize(width, height)
    value.clickthrough = true
    return value
end

-- Draw a heading above a separator line
function Parts.heading(parent, x, y, width, text)
    prettyui.Text.new(parent, {
        text = text,
        x = x, y = y, width = width, height = Size.LABEL_LINE_OFFSET,
        colour = Theme.HEADING_TEXT,
        font = id.Font.MUSEO_SANS_11PT_REGULAR,
        maxLines = 1,
    }).clickthrough = true
    Parts.rectangle(parent, x, y + Size.LABEL_LINE_OFFSET, width, 1, Theme.HEADING_LINE, true)
end

return Parts
