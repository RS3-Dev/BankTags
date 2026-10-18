-- Share the layout editor's measurements and drawing helpers between its files

local BankGrid = require("banktags/ui/bank_grid")

local Parts = {}
local Size = {}
Parts.size = Size

-- Shown in the empty item search panel
Parts.SEARCH_HINT = "Search for an item, then drag it into the grid."

-- Match the expanded Bank of Gielinor window. Interface 517 measured 958x650
-- with a 236px tag rail, 8px gutter, 477px bank surface, and 213px right
-- panel; the sidebar now adds a 32px tab rail and an 8px gap before the tag
-- column, making 998x650. PrettyUI's content starts 8px from the left and 32px
-- below the title bar, so these local offsets land on the same screen pixels
-- as the expanded bank (12,44), (296,44), and (773,44). The 998px figures are
-- derived from the earlier measurement, not measured again. A resized bank
-- grows these sizes by however much larger it is than the default window
-- Bank Core's sidebar: its tab rail, the gap after it, and its tag column
Size.SIDEBAR_WIDTH = 32 + 8 + 244
Size.DEFAULT_WIDTH = 714 + Size.SIDEBAR_WIDTH
Size.DEFAULT_HEIGHT = 650
Size.PANEL_TOP = 12
Size.DEFAULT_PANEL_HEIGHT = 594
Size.GAP = 8
-- The tab rail, its gap, and the tag column
Size.LEFT_WIDTH = Size.SIDEBAR_WIDTH - 8
Size.DEFAULT_CENTER_WIDTH = 477
Size.RIGHT_WIDTH = 213
Size.LEFT_X = 4
Size.CENTER_X = Size.LEFT_X + Size.LEFT_WIDTH + Size.GAP
-- The editor's tag column lines up with the bank's, after the space of Bank Core's tab rail
Size.COLUMN_X = Size.LEFT_X + 40
Size.COLUMN_WIDTH = 236
-- The editor's own view starts its first column 4px in, not the bank's 8px
Size.GRID_LEFT = 4
Size.GRID_TOP = BankGrid.TOP
Size.GRID_STEP = BankGrid.STEP
Size.GRID_SLOT_SIZE = BankGrid.SLOT_SIZE
Size.LABEL_LINE_OFFSET = BankGrid.LABEL_LINE_OFFSET
Size.LABEL_GHOST_WIDTH = 180
Size.LABEL_GHOST_HEIGHT = 28
Size.DEFAULT_SURFACE_WIDTH = 473
Size.DEFAULT_SURFACE_HEIGHT = 550
Size.CENTER_VIEW_X = 4
Size.CENTER_VIEW_Y = 4
-- PrettyUI reserves 18px for its 16px scrollbar plus the track gap. A 467px
-- view therefore leaves the native bank's 449px item viewport
Size.DEFAULT_VIEW_WIDTH = 467
-- Grid actions share one footer row, 8px below the grid; New label lines up
-- with the grid's right edge
Size.DEFAULT_FOOTER_Y = 558
Size.FOOTER_HEIGHT = 28
Size.LABEL_BUTTON_WIDTH = 104
Size.UNSORT_BUTTON_WIDTH = 140
Size.SEARCH_LIST_TOP = 42
Size.SEARCH_LIST_BOTTOM = 8
-- PrettyUI reserves this much for a scroll list's scrollbar and its gap
Size.SCROLLBAR_RESERVE = 18

-- Size the editor to cover the bank window and show the columns Bank Core lays pages out
-- at. Only one editor is open at a time, so the resized values live in Size rather than
-- being passed around. The window is never smaller than the default or too narrow for the
-- columns
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
    Size.CENTER_SURFACE_HEIGHT = Size.DEFAULT_SURFACE_HEIGHT + extraHeight
    Size.CENTER_VIEW_WIDTH = Size.DEFAULT_VIEW_WIDTH + extraWidth
    Size.CENTER_VIEW_HEIGHT = Size.CENTER_SURFACE_HEIGHT - 8
    Size.RIGHT_X = Size.CENTER_X + Size.CENTER_WIDTH
    Size.LABEL_BUTTON_X = Size.CENTER_SURFACE_WIDTH - Size.LABEL_BUTTON_WIDTH
    Size.FOOTER_Y = Size.DEFAULT_FOOTER_Y + extraHeight
end
Parts.SizeToBank(BankGrid.DEFAULT_COLUMNS)

-- Create a decorative rectangle that lets mouse input pass through
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

-- Fill a decorative panel with a repeating native sprite
function Parts.tiledSprite(parent, x, y, width, height, spriteID)
    local value = ui.Sprite.new(parent)
    value:SetPos(x, y)
    value:SetSize(width, height)
    value.spriteID = spriteID
    value.isTiling = true
    value.clickthrough = true
    return value
end

-- Draw a non-interactive border from four rectangle edges
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

-- Look up an item definition, allowing unavailable catalog entries
function Parts.objectFromID(objectID)
    local ok, object = pcall(function()
        return config.Obj.FromID(math.tointeger(objectID))
    end)
    return ok and object or nil
end

return Parts
