-- Build the sidebar's search field, row list, and the row decorations every tab shares

local Config = require("lib/core/config")
local Geometry = require("lib/ui/geometry")
local Theme = require("lib/ui/theme")
local relativePosition = Geometry.relativePosition

local SidebarRows = {}

local SEARCH_TOP = 8
local SEARCH_HEIGHT = 26
local LIST_TOP = SEARCH_TOP + SEARCH_HEIGHT + 8
local FOOTER_HEIGHT = 44
local CONTENT_X = 8
local CONTENT_WIDTH = Config.TAG_RAIL_WIDTH - 24
local SECTION_HEIGHT = 28
local GROUP_ENTRY_PREFIX = "__bankutils_group:"

SidebarRows.SEARCH_TOP = SEARCH_TOP
SidebarRows.SEARCH_HEIGHT = SEARCH_HEIGHT
SidebarRows.LIST_TOP = LIST_TOP
SidebarRows.FOOTER_HEIGHT = FOOTER_HEIGHT
SidebarRows.CONTENT_X = CONTENT_X
SidebarRows.CONTENT_WIDTH = CONTENT_WIDTH
SidebarRows.GROUP_ENTRY_PREFIX = GROUP_ENTRY_PREFIX
SidebarRows.ROW_TEXT = 0xE7D7B0FF
SidebarRows.STATUS_TEXT = 0xAFA58FFF
SidebarRows.ROW_LEFT = 6

-- Read host hover state whether the wrapper exposes a flag or method
function SidebarRows.IsMouseOver(value)
    local hovered = value.isMouseOver
    if type(hovered) == "function" then hovered = value:isMouseOver() end
    return hovered == true
end

-- Recognize non-selectable section header rows
function SidebarRows.IsGroupEntry(entry)
    local entryID = type(entry) == "table" and entry.id or entry
    return string.sub(tostring(entryID or ""), 1, #GROUP_ENTRY_PREFIX)
        == GROUP_ENTRY_PREFIX
end

-- Describe a non-selectable section header row
function SidebarRows.HeaderEntry(entryID, label)
    return {
        id = GROUP_ENTRY_PREFIX .. entryID,
        label = label,
        kind = "header",
        height = SECTION_HEIGHT,
        enabled = false,
        textColour = Theme.HEADING_TEXT,
        disabledTextColour = Theme.HEADING_TEXT,
        font = id.Font.MUSEO_SANS_11PT_REGULAR,
    }
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

-- Draw a section header row as a gold label over a dividing line
function SidebarRows.StyleHeaderRow(row)
    row.label.font = id.Font.MUSEO_SANS_11PT_REGULAR
    row.label.rgba = Theme.HEADING_TEXT
    row.label:SetPos(8, 0)
    row.label:SetSize(-16, 22, 1.0, 0)
    row.label.alignVertical = ui.AlignMode.CENTRE

    local separator = ui.Rectangle.new(row.root)
    separator:SetPos(8, 22)
    separator:SetSize(-16, 1, 1.0, 0)
    separator.fill = true
    separator.rgba = Theme.HEADING_LINE
    separator.clickthrough = true
    separator:MoveToFront()
    row.label:MoveToFront()
end

-- Show a short status, such as a count, at the right of a row
function SidebarRows.AddRowStatus(row, status, rowHeight)
    local count = ui.Text.new(row.root)
    count:SetPos(-42, 0, 1.0, 0)
    count:SetSize(34, rowHeight)
    count.content = status
    count.font = id.Font.MUSEO_SANS_11PT_REGULAR
    count.rgba = SidebarRows.STATUS_TEXT
    count.isShadowed = true
    count.maxLines = 1
    count.alignHorizontal = ui.AlignMode.BOTTOMRIGHT
    count.alignVertical = ui.AlignMode.CENTRE
    count.clickthrough = true
    count:MoveToFront()
    return count
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
function SidebarRows.CreateSearch(parent, options)
    return prettyui.TextField.new(parent, {
        x = CONTENT_X,
        y = SEARCH_TOP,
        width = CONTENT_WIDTH,
        height = SEARCH_HEIGHT,
        placeholder = options.placeholder,
        text = options.text,
        maxLength = 40,
        onChange = options.onChange,
    })
end

-- Create the message shown in place of an empty row list
function SidebarRows.CreateEmptyLabel(parent, text)
    return prettyui.Text.new(parent, {
        text = text,
        x = 9,
        y = LIST_TOP + 6,
        width = Config.TAG_RAIL_WIDTH - 26,
        height = 72,
        colour = 0xB7AA8EFF,
        maxLines = 4,
    })
end

-- The row list's height in a content column of this height
function SidebarRows.ListHeight(height)
    return math.max(1, height - LIST_TOP - FOOTER_HEIGHT)
end

-- Create the scrolling row list between the search field and the footer
function SidebarRows.CreateList(parent, height, onEntryClick)
    return prettyui.List.new(parent, {
        x = CONTENT_X,
        y = LIST_TOP,
        width = CONTENT_WIDTH,
        height = height - LIST_TOP - FOOTER_HEIGHT,
        entryHeight = 32,
        entryIconScale = 125,
        maxSelected = 1,
        backgroundColour = 0x00000000,
        borderColour = Theme.INNER_FRAME,
        selectedColour = 0x5A4526FF,
        _onEntryClick = onEntryClick,
    })
end

-- Place row tooltips relative to the list's scrolled viewport
function SidebarRows.RegisterTooltips(list, parent)
    return prettyui.Tooltip.registerContext(
        list.viewport,
        parent,
        function(target)
            local x, y = relativePosition(list.viewport, parent)
            if x == nil then return target.x or 0, target.y or 0 end
            return x + (target.x or 0),
                y + (target.y or 0) - (list.scrollY or 0)
        end
    )
end

-- Release a list's tooltip placement before the list is destroyed
function SidebarRows.UnregisterTooltips(list)
    if list ~= nil and list.viewport ~= nil then
        prettyui.Tooltip.unregisterContext(list.viewport)
    end
end

return SidebarRows
