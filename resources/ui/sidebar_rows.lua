-- Build the tag column's search field, row list, and row decorations

local Theme = require("resources/ui/theme")

local SidebarRows = {}

SidebarRows.CONTENT_X = 8
SidebarRows.SEARCH_TOP = 8
SidebarRows.SEARCH_HEIGHT = 26
SidebarRows.LIST_TOP = SidebarRows.SEARCH_TOP + SidebarRows.SEARCH_HEIGHT + 8
SidebarRows.FOOTER_HEIGHT = 44
SidebarRows.ENTRY_HEIGHT = 32
SidebarRows.ROW_TEXT = 0xE7D7B0FF
SidebarRows.ROW_LEFT = 6

-- Width of the controls inside a column
function SidebarRows.ContentWidth(columnWidth)
    return math.max(1, columnWidth - SidebarRows.CONTENT_X * 2)
end

-- Outline a selected row with the native gold frame
function SidebarRows.AddSelectedFrame(root, rowHeight)
    local edges = {
        ui.Rectangle.new(root),
        ui.Rectangle.new(root),
        ui.Rectangle.new(root),
        ui.Rectangle.new(root),
    }
    edges[1]:SetPos(0, 0)
    edges[1]:SetSize(0, 1, 1.0, 0)
    edges[2]:SetPos(0, rowHeight - 1)
    edges[2]:SetSize(0, 1, 1.0, 0)
    edges[3]:SetPos(0, 0)
    edges[3]:SetSize(1, rowHeight)
    edges[4]:SetPos(-1, 0, 1.0, 0)
    edges[4]:SetSize(1, rowHeight)
    for _, edge in ipairs(edges) do
        edge.fill = true
        edge.rgba = Theme.SELECTED_BORDER
        edge.clickthrough = true
        edge:MoveToFront()
    end
    return edges
end

-- Show an item's icon at the left of a row
function SidebarRows.AddRowIcon(row, objectID, left)
    local icon = ui.Sprite.new(row.root)
    icon:SetPos(left, 3)
    icon:SetSize(24, 24)
    icon:SetAssociatedObject(objectID)
    icon.associatedObjectQuantityMode = ui.ObjectQuantityDisplayMode.NEVER
    icon.clickthrough = true
    icon:MoveToFront()
    return icon
end

-- Create the search field above the rows
function SidebarRows.CreateSearch(parent, width, options)
    return prettyui.TextField.new(parent, {
        x = SidebarRows.CONTENT_X,
        y = SidebarRows.SEARCH_TOP,
        width = width,
        height = SidebarRows.SEARCH_HEIGHT,
        placeholder = options.placeholder,
        text = options.text,
        maxLength = 40,
        onChange = options.onChange,
    })
end

-- Create the message shown when no rows are visible
function SidebarRows.CreateEmptyLabel(parent, width, text)
    return prettyui.Text.new(parent, {
        text = text,
        x = SidebarRows.CONTENT_X + 1,
        y = SidebarRows.LIST_TOP + 6,
        width = width - 2,
        height = 72,
        colour = 0xB7AA8EFF,
        maxLines = 4,
    })
end

-- Create the scrolling row list below the search field
function SidebarRows.CreateList(parent, width, height, onEntryClick)
    return prettyui.List.new(parent, {
        x = SidebarRows.CONTENT_X,
        y = SidebarRows.LIST_TOP,
        width = width,
        height = height,
        entryHeight = SidebarRows.ENTRY_HEIGHT,
        entryIconScale = 125,
        maxSelected = 1,
        backgroundColour = 0x00000000,
        borderColour = Theme.INNER_FRAME,
        selectedColour = 0x5A4526FF,
        _onEntryClick = onEntryClick,
    })
end

return SidebarRows
