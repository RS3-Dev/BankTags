-- Measure the rendered bank grid shared by the engine, scrolling, and editor

local BankGrid = {}

-- Left inset of the first column inside the bank item layer
BankGrid.LEFT = 8
-- Top inset of the first row
BankGrid.TOP = 4
-- Distance from one row or column to the next
BankGrid.STEP = 44
-- Size of one item cell
BankGrid.SLOT_SIZE = 40
-- Columns in a bank at its default size; players can resize it wider
BankGrid.DEFAULT_COLUMNS = 10

-- Headings draw their text above a separator this far below the heading's top
BankGrid.LABEL_LINE_OFFSET = 22
BankGrid.UNSORTED_LABEL = "Unsorted"

local GRID_LEFT = BankGrid.LEFT
local GRID_TOP = BankGrid.TOP
local GRID_STEP = BankGrid.STEP
local GRID_SLOT_SIZE = BankGrid.SLOT_SIZE
local LABEL_LINE_OFFSET = BankGrid.LABEL_LINE_OFFSET

-- Fit as many grid columns as the current item-layer width allows
function BankGrid.ColumnCount(itemLayerWidth)
    return math.max(
        1,
        math.floor(((tonumber(itemLayerWidth) or 0) - GRID_LEFT) / GRID_STEP)
    )
end

-- Return the content y where a grid row begins; label rows share the grid spacing
function BankGrid.RowTop(row)
    return row * GRID_STEP
end

-- Return the content y of a row's item cells
function BankGrid.RowItemY(row)
    return GRID_TOP + row * GRID_STEP
end

-- Return the content y of a label heading, set low in its row so it sits on
-- the items it introduces
function BankGrid.LabelY(row)
    return BankGrid.RowItemY(row) + GRID_SLOT_SIZE - LABEL_LINE_OFFSET - 2
end

-- Return the Unsorted heading row when items follow the arranged area
function BankGrid.UnsortedRow(slots, boundary, columnCount)
    boundary = math.tointeger(tonumber(boundary))
    columnCount = math.max(1, math.tointeger(tonumber(columnCount)) or 1)
    if boundary == nil or #(slots or {}) <= boundary then return nil end
    return boundary // columnCount
end

-- Convert a one-based slot index into a row and column position
function BankGrid.PositionForIndex(index, columnCount)
    local zeroIndex = math.max(0, (math.tointeger(tonumber(index)) or 1) - 1)
    columnCount = math.max(1, math.tointeger(tonumber(columnCount)) or 1)
    return {
        x = GRID_LEFT + (zeroIndex % columnCount) * GRID_STEP,
        y = BankGrid.RowItemY(math.floor(zeroIndex / columnCount)),
    }
end

-- Find the zero-based grid row under a content y
function BankGrid.RowAtContentY(contentY)
    contentY = tonumber(contentY)
    if contentY == nil or contentY < 0 then return nil end
    return math.floor(contentY / GRID_STEP)
end

-- Measure a labelled page through its last occupied or labelled row
function BankGrid.LabelledContentHeight(slotCount, columnCount, labels)
    columnCount = math.max(1, math.tointeger(tonumber(columnCount)) or 1)
    slotCount = tonumber(slotCount) or 0
    local lastRow = slotCount > 0 and math.floor((slotCount - 1) / columnCount) or -1
    for _, label in ipairs(labels or {}) do
        lastRow = math.max(lastRow, tonumber(label.row) or -1)
    end
    if lastRow < 0 then return 0 end
    return BankGrid.RowItemY(lastRow) + GRID_STEP
end

-- Measure the page from its section bounds or occupied grid rows
function BankGrid.ContentHeight(slotCount, columnCount, sectionContentBottom)
    sectionContentBottom = tonumber(sectionContentBottom) or 0
    if sectionContentBottom > 0 then return sectionContentBottom end
    slotCount = math.max(0, math.tointeger(tonumber(slotCount)) or 0)
    columnCount = math.max(1, math.tointeger(tonumber(columnCount)) or 1)
    if slotCount == 0 then return 0 end
    return GRID_TOP + math.ceil(slotCount / columnCount) * GRID_STEP
end

return BankGrid
