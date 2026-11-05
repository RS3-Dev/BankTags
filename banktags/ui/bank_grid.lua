-- Measure the bank grid shared by pages, scrolling, and the editor

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

-- Heading text sits above a separator this far down the row
BankGrid.LABEL_LINE_OFFSET = 22
-- Match Core's section-label headspace inside each label row.
BankGrid.LABEL_TOP = 3
-- Core reserves a 28px heading plus its 3px top inset.
BankGrid.LABEL_HEIGHT = 28 + BankGrid.LABEL_TOP
BankGrid.UNSORTED_LABEL = "Unsorted"

local GRID_TOP = BankGrid.TOP
local GRID_STEP = BankGrid.STEP

-- Find where a row's items sit below the top of the content
function BankGrid.RowItemY(row, labels)
    local y = GRID_TOP + row * GRID_STEP
    for _, label in ipairs(labels or {}) do
        if label.row >= row then break end
        y = y - (GRID_STEP - BankGrid.LABEL_HEIGHT)
    end
    return y
end

-- Place the label just below the top of its reserved row.
function BankGrid.LabelY(row, labels)
    return BankGrid.RowItemY(row, labels) + BankGrid.LABEL_TOP
end

-- Find the zero-based grid row under a content y
function BankGrid.RowAtContentY(contentY, labels)
    contentY = tonumber(contentY)
    if contentY == nil or contentY < 0 then return nil end
    local removed = 0
    for _, label in ipairs(labels or {}) do
        local top = label.row * GRID_STEP - removed
        if contentY < top then break end
        if contentY < top + BankGrid.LABEL_HEIGHT then return label.row end
        removed = removed + GRID_STEP - BankGrid.LABEL_HEIGHT
    end
    return math.floor((contentY + removed) / GRID_STEP)
end

return BankGrid
