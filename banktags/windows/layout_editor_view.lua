-- Draw the layout editor's panels, items, and selection outlines

local NativeUi = require("banktags/ui/native_ui")
local BankControls = require("banktags/ui/bank_controls")
local BankGrid = require("banktags/ui/bank_grid")
local Theme = require("banktags/ui/theme")
local Parts = require("banktags/windows/layout_editor_parts")
local TagTabs = require("banktags/windows/layout_editor_tabs")
local Size = Parts.size
local rectangle, tiledSprite = Parts.rectangle, Parts.tiledSprite

local LayoutEditorView = {}

local GOLD = Theme.SELECTED_BORDER
local FRAME = Theme.FRAME
local PLACEHOLDER_ALPHA = 0.45
local PLACEHOLDER_QUANTITY_MODE = ui.ObjectQuantityDisplayMode.ALWAYS
-- An object missing from the bank is drawn as its placeholder
local ABSENT = { quantity = 0, placeholder = true }
local GRID_SLOT_SPRITE = id.Sprite.RS3_ICON_SLOT_40PX_1
local ITEM_X = (Size.GRID_SLOT_SIZE - Size.ITEM_WIDTH) // 2
local ITEM_Y = (Size.GRID_SLOT_SIZE - Size.ITEM_HEIGHT) // 2

-- Update item quantities without rebuilding the grids
function LayoutEditorView:SetBankItems(items)
    local styles = {}
    for _, item in ipairs(items) do
        local style = { quantity = item.quantity, placeholder = item.quantity <= 0 }
        local existing = styles[item.objectID]
        -- A real stack beats a placeholder for the same object
        if existing == nil or (existing.placeholder and not style.placeholder) then
            styles[item.objectID] = style
        end
    end
    self.styles = styles
    self.bankItemList = items
    if self.panes == nil then return end
    for _, pane in pairs(self.panes) do
        for index, sprite in pairs(pane.sprites) do self:StyleItem(sprite, pane.slots[index].objectID, true) end
    end
end

-- Show an item's best stack quantity, fading placeholders
function LayoutEditorView:StyleItem(sprite, objectID, absentIsPlaceholder)
    local style = self.styles[objectID] or (absentIsPlaceholder and ABSENT or nil)
    if style == nil then
        sprite.associatedObjectQuantityMode = ui.ObjectQuantityDisplayMode.NEVER
        sprite.alpha = 1
        return
    end
    sprite.associatedObjectQuantity = style.quantity
    sprite.associatedObjectQuantityMode = style.placeholder and PLACEHOLDER_QUANTITY_MODE
        or ui.ObjectQuantityDisplayMode.MULTIPLE
    sprite.alpha = style.placeholder and PLACEHOLDER_ALPHA or 1
end

-- Draw an item using its native bank sprite
function LayoutEditorView:ItemSprite(parent, objectID, absentIsPlaceholder)
    local sprite = ui.Sprite.new(parent)
    sprite:SetSize(Size.ITEM_WIDTH, Size.ITEM_HEIGHT)
    sprite:SetAssociatedObject(objectID)
    sprite.outlineWidth = 1
    sprite.clickthrough = true
    self:StyleItem(sprite, objectID, absentIsPlaceholder)
    return sprite
end

-- Draw the frame and background around an item pane
local function itemArea(parent, width, y)
    rectangle(parent, 0, y, width, Size.AREA_HEIGHT, Theme.VIEW_BACKGROUND, true)
    rectangle(parent, 0, y, width, Size.AREA_HEIGHT, FRAME, false)
end

-- Create an independently scrolling item grid
function LayoutEditorView:CreatePane(name, parent, y, columnX, width, columns)
    local view = prettyui.SimpleView.new(parent, {
        x = Size.VIEW_INSET,
        y = y,
        width = width,
        height = Size.VIEW_HEIGHT,
        contentHeight = Size.VIEW_HEIGHT,
        scrollStep = Size.GRID_STEP,
    })
    return {
        name = name,
        x = columnX + Size.VIEW_INSET,
        y = Size.VIEW_Y,
        width = width,
        height = Size.VIEW_HEIGHT,
        columns = columns,
        gridLeft = Size.GRID_LEFT,
        slots = {},
        sprites = {},
        outlines = {},
        view = view,
        marks = Parts.layer(view.content, 0, 0, width, Size.VIEW_HEIGHT),
    }
end

-- Draw one native panel heading
local function panelHeading(parent, width, text)
    local heading = prettyui.Text.new(parent, {
        text = text, x = 8, y = Size.HEADER_Y, width = width - 16, height = Size.HEADER_HEIGHT,
        colour = Theme.HEADING_TEXT, font = id.Font.MUSEO_SANS_15PT_REGULAR,
        alignVertical = ui.AlignMode.CENTRE, maxLines = 1,
    })
    heading.clickthrough = true
    return heading
end

-- Draw the Unsorted heading and Layout tag tabs
function LayoutEditorView:CreateHeader()
    self.unsortedTitle = panelHeading(self.unsortedPanel, Size.UNSORTED_WIDTH, "Unsorted")
    self.tagTabs = TagTabs.new(self.content, {
        x = Size.CENTER_X + Size.TABS_INSET, y = Size.TABS_Y,
        width = Size.CENTER_WIDTH - 2 * Size.TABS_INSET,
        -- Release grid shortcuts and follow the chosen tag
        onChange = function(_, tag)
            self.keysOnGrid = false
            self:HideItemName()
            self:CancelDrag()
            self.pointerSurface = nil
            if tag ~= self.selectedTag then self:SelectTag(tag) end
        end,
    })
end

-- Keep item search visible beside the layout
function LayoutEditorView:CreateSearch()
    local inset, listTop = Size.SEARCH_INSET, Size.SEARCH_LIST_TOP
    self.itemSearch = prettyui.TextField.new(self.searchPanel, {
        x = inset, y = Size.SEARCH_FIELD_TOP,
        width = Size.SEARCH_VIEW_WIDTH, height = Size.SEARCH_FIELD_HEIGHT,
        placeholder = "Search items...", maxLength = 80,
        onChange = function(_, _, value) self.keysOnGrid = false; self:RunSearch(value) end,
        onSubmit = function(_, value) self:RunSearch(value) end,
    })
    self.searchList = prettyui.List.new(self.searchPanel, {
        x = inset, y = listTop,
        width = Size.SEARCH_VIEW_WIDTH, height = Size.SEARCH_LIST_HEIGHT,
        entryHeight = Size.SEARCH_ROW_HEIGHT, maxSelected = 1,
        backgroundColour = 0x00000000, borderColour = Theme.INNER_FRAME,
        selectedColour = Theme.ROW_SELECTED,
    })
    self.searchHint = prettyui.Text.new(self.searchPanel, {
        text = "", x = inset + 8, y = listTop + 4,
        width = Size.SEARCH_VIEW_WIDTH - 16, height = 150,
        colour = Theme.MUTED_TEXT, maxLines = 10, alignVertical = ui.AlignMode.TOPLEFT,
    })
end

-- Group compact actions under a shared divider
function LayoutEditorView:CreateActions()
    local y = Size.PANEL_TOP + Size.ACTIONS_Y
    rectangle(self.content, Size.UNSORTED_X, y - 5, Size.WIDTH - Size.RIGHT_MARGIN - Size.UNSORTED_X, 1, FRAME)
    for index, action in ipairs({
        { "copyButton", "Copy", self.CopySelected, self.actionTooltips.copyButton },
        { "pasteButton", "Paste", self.PasteClipboard, self.actionTooltips.pasteButton },
        { "removeButton", "Remove", self.RemoveSelected, self.actionTooltips.removeButton },
        { "unsortButton", "Move to Unsorted", self.UnarrangeSelected, self.actionTooltips.unsortButton },
        { "newLabelButton", "New label", function() self:PromptNewLabel(self:DefaultLabelRow()) end,
            "Add a label above the selection or paste cell, or at the end. Right-click a row to add one there" },
        { "closeButton", "Close", function() self.window:Close() end, "Close the layout editor" },
    }) do
        local run = action[3]
        self[action[1]] = BankControls.button(self.content, action[2], function() run(self) end, {
            x = Size.ACTION_X[index], y = y,
            width = Size.ACTION_WIDTH[index], height = Size.BUTTON_HEIGHT,
            tooltip = action[4],
        })
    end
    self.status = prettyui.Text.new(self.content, {
        text = "", x = Size.STATUS_X, y = y, width = Size.STATUS_WIDTH, height = Size.BUTTON_HEIGHT,
        font = id.Font.MUSEO_SANS_11PT_REGULAR, alignVertical = ui.AlignMode.CENTRE, maxLines = 2,
    })
    self.status.clickthrough = true
end

-- Build three persistent columns and their input surfaces
function LayoutEditorView:CreatePanels()
    self.searchPanel = Parts.layer(self.content, Size.SEARCH_X, Size.PANEL_TOP,
        Size.SEARCH_WIDTH, Size.COLUMN_HEIGHT)
    self.centerPanel = Parts.layer(self.content, Size.CENTER_X, Size.PANEL_TOP,
        Size.CENTER_WIDTH, Size.COLUMN_HEIGHT)
    self.unsortedPanel = Parts.layer(self.content, Size.UNSORTED_X, Size.PANEL_TOP,
        Size.UNSORTED_WIDTH, Size.COLUMN_HEIGHT)
    for _, panel in ipairs({ self.searchPanel, self.centerPanel, self.unsortedPanel }) do
        -- Bank tabs sit directly on the window background
        if panel ~= self.centerPanel then
            tiledSprite(panel, 0, 0, panel.width, Size.COLUMN_HEIGHT, NativeUi.SPRITES.PANEL_BACKGROUND)
            rectangle(panel, 0, 0, panel.width, Size.COLUMN_HEIGHT, FRAME, false)
        end
        -- Keep the sidebar's tiled background visible
        if panel ~= self.searchPanel then itemArea(panel, panel.width, Size.TAB_HEADER) end
    end
    self:CreateHeader()
    self.panes = {
        sorted = self:CreatePane("sorted", self.centerPanel, Size.TAB_HEADER + Size.VIEW_INSET,
            Size.CENTER_X, Size.CENTER_VIEW_WIDTH, Size.CENTER_COLUMNS),
        unsorted = self:CreatePane("unsorted", self.unsortedPanel, Size.TAB_HEADER + Size.VIEW_INSET,
            Size.UNSORTED_X, Size.UNSORTED_VIEW_WIDTH, Size.UNSORTED_COLUMNS),
    }
    self:CreateSearch()
    self:CreateActions()
    self:CreateDragSurfaces()
    self:RunSearch("")
    self:CreateItemNames()
end

-- Rebuild one grid and keep empty layout drop rows
function LayoutEditorView:DrawPane(pane, rowCount, labels)
    local columns = pane.columns
    pane.labels = labels
    if pane.name == "sorted" then
        rowCount = math.max(rowCount, math.ceil((pane.height - Size.GRID_TOP) / Size.GRID_STEP))
        while BankGrid.RowItemY(rowCount, labels) < pane.height do rowCount = rowCount + 1 end
    end
    local height = math.max(pane.height, BankGrid.RowItemY(rowCount, labels))
    pane.view:SetContentHeight(height)
    local gridWidth = (columns - 1) * Size.GRID_STEP + Size.GRID_SLOT_SIZE
    pane.gridLeft = pane.name == "unsorted" and (pane.view.contentWidth - gridWidth) // 2 or Size.GRID_LEFT
    if pane.cells ~= nil then pane.cells:Destroy() end
    local cells = Parts.layer(pane.view.content, 0, 0, pane.width, height)
    pane.cells, pane.sprites = cells, {}
    local labelRows = {}
    for _, label in ipairs(labels) do
        labelRows[label.row] = true
        Parts.heading(cells, Size.GRID_LEFT, BankGrid.LabelY(label.row, labels), Size.LABEL_WIDTH, label.text)
    end
    for index = 1, rowCount * columns do
        local row = (index - 1) // columns
        if not labelRows[row] then
            local x, y = pane.gridLeft + (index - 1) % columns * Size.GRID_STEP, BankGrid.RowItemY(row, labels)
            local grid = ui.Sprite.new(cells)
            grid:SetPos(x, y)
            grid:SetSize(Size.GRID_SLOT_SIZE, Size.GRID_SLOT_SIZE)
            grid.spriteID = GRID_SLOT_SPRITE
            grid.alpha = 0.34
            grid.clickthrough = true
            local slot = pane.slots[index]
            if slot ~= nil and slot.kind == "item" then
                local sprite = self:ItemSprite(cells, slot.objectID, true)
                sprite:SetPos(x + ITEM_X, y + ITEM_Y)
                pane.sprites[index] = sprite
            end
        end
    end
    pane.marks:SetSize(pane.width, height)
    pane.marks:MoveToFront()
end

-- Reuse outlines to show selected items and paste cells
function LayoutEditorView:ShowSelection()
    for name, pane in pairs(self.panes) do
        local count = 0
        -- Outline one cell, reusing the pane's outlines
        local function outline(index)
            count = count + 1
            local mark = pane.outlines[count]
            if mark == nil then
                mark = rectangle(pane.marks, 0, 0, Size.GRID_SLOT_SIZE, Size.GRID_SLOT_SIZE, GOLD, false)
                pane.outlines[count] = mark
            end
            mark:SetPos(pane.gridLeft + (index - 1) % pane.columns * Size.GRID_STEP,
                BankGrid.RowItemY((index - 1) // pane.columns, pane.labels))
            mark.hidden = false
        end
        for layoutKey, index in pairs(name == "sorted" and self.layout.sortedIndex or self.layout.unsortedIndex) do
            if self:IsSelected(layoutKey) then outline(index) end
        end
        if name == "sorted" and self.pasteCell ~= nil then outline(self.pasteCell) end
        for index = count + 1, #pane.outlines do pane.outlines[index].hidden = true end
    end
end

-- Find a grid row, allowing for the pane's scroll
function LayoutEditorView:RowAt(pane, x, y)
    if x < pane.gridLeft or y < 0 or x >= pane.width or y >= pane.height then return nil end
    return BankGrid.RowAtContentY(y + pane.view.scrollY, pane.labels)
end

-- Find a label row within the sorted pane
function LayoutEditorView:LabelRowAt(pane, x, y)
    if pane.name ~= "sorted" then return nil end
    local row = self:RowAt(pane, x, y)
    for _, label in ipairs(self.layout.labels) do
        if label.row == row then return row end
    end
    return nil
end

-- Find an item cell while skipping label rows
function LayoutEditorView:SlotIndexAt(pane, x, y)
    local row = self:RowAt(pane, x, y)
    if row == nil or self:LabelRowAt(pane, x, y) ~= nil then return nil end
    local column = (x - pane.gridLeft) // Size.GRID_STEP
    if column >= pane.columns then return nil end
    return row * pane.columns + column + 1
end

-- Find a visible pane and the point within it
function LayoutEditorView:PaneAt(x, y)
    for _, pane in pairs(self.panes) do
        if not pane.hidden and x >= pane.x and x < pane.x + pane.width
            and y >= pane.y and y < pane.y + pane.height then
            return pane, x - pane.x, y - pane.y
        end
    end
    return nil
end

return LayoutEditorView
