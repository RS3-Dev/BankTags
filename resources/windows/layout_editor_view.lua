-- Draw the layout editor's panels, items, and selection outlines

local NativeUi = require("resources/ui/native_ui")
local BankControls = require("resources/ui/bank_controls")
local BankGrid = require("resources/ui/bank_grid")
local Theme = require("resources/ui/theme")
local Parts = require("resources/windows/layout_editor_parts")
local TagTabs = require("resources/windows/layout_editor_tabs")
local Text = require("resources/core/text")
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
    for name, pane in pairs(self.panes) do
        if name ~= "bank" then
            local absentIsPlaceholder = name ~= "search"
            for index, sprite in pairs(pane.sprites or {}) do
                self:StyleItem(sprite, pane.slots[index].objectID, absentIsPlaceholder)
            end
        end
    end
    if self.RefreshBank ~= nil then self:RefreshBank() end
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
    local sprite = NativeUi.newComponent(ui.Sprite, parent)
    sprite:SetSize(Size.ITEM_WIDTH, Size.ITEM_HEIGHT)
    sprite:SetAssociatedObject(objectID)
    sprite.outlineWidth = 1
    sprite.clickthrough = true
    self:StyleItem(sprite, objectID, absentIsPlaceholder)
    return sprite
end

-- Draw the frame and background around an item pane
local function itemArea(parent, width, y, height)
    rectangle(parent, 0, y, width, height, Theme.VIEW_BACKGROUND, true)
    rectangle(parent, 0, y, width, height, FRAME, false)
end

-- Create an independently scrolling item grid
function LayoutEditorView:CreatePane(name, parent, y, columnX, width, columns)
    local height = Size.VIEW_HEIGHT + (name == "sorted" and Size.AREA_BOTTOM or 0)
    local view = prettyui.SimpleView.new(parent, {
        categoryID = "auto",
        x = Size.VIEW_INSET,
        y = y,
        width = width,
        height = height,
        contentHeight = height,
        scrollStep = Size.GRID_STEP,
    })
    local pane = {
        name = name,
        x = columnX + Size.VIEW_INSET,
        y = Size.VIEW_Y,
        width = width,
        height = height,
        columns = columns,
        gridLeft = Size.GRID_LEFT,
        slots = {},
        sprites = {},
        outlines = {},
        view = view,
        marks = Parts.layer(view.content, 0, 0, width, height),
    }
    view.onLayout = function() self:RenderPaneWindow(pane, false) end
    return pane
end

-- Draw the Layout tag tabs above the central grid
function LayoutEditorView:CreateHeader()
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

-- Create the searchable item grid inside the Search tab (matching the Bank grid)
function LayoutEditorView:CreateSearch()
    local inset, listTop = Size.SEARCH_INSET, Size.SEARCH_LIST_TOP
    self.searchNames = {}
    self.itemSearch = prettyui.TextField.new(self.searchPanel, {
        x = inset, y = Size.SEARCH_FIELD_TOP,
        width = Size.SEARCH_VIEW_WIDTH, height = Size.SEARCH_FIELD_HEIGHT,
        placeholder = "Search items...", maxLength = 80,
        onChange = function(field, _, value) self.keysOnGrid = false; self:QueueSearch(Text.cleanField(field, value)) end,
        onSubmit = function(_, value) self:RunSearch(value) end,
    })
    local width, height = Size.SEARCH_VIEW_WIDTH - 2, Size.SEARCH_LIST_HEIGHT - 2
    local view = prettyui.SimpleView.new(self.searchPanel, {
        x = inset + 1, y = listTop + 1,
        width = width, height = height, contentHeight = height, scrollStep = Size.GRID_STEP,
    })
    rectangle(self.searchPanel, inset, listTop,
        Size.SEARCH_VIEW_WIDTH, Size.SEARCH_LIST_HEIGHT, Theme.INNER_FRAME, false)
    local columns = math.max(1, (width - Size.SCROLLBAR_RESERVE - 2 * Size.GRID_LEFT
        + Size.GRID_STEP - Size.GRID_SLOT_SIZE) // Size.GRID_STEP)
    local pane = {
        name = "search", columns = columns, gridLeft = Size.GRID_LEFT,
        x = Size.SEARCH_X + inset + 1,
        y = Size.LEFT_BODY_TOP + listTop + 1,
        width = width, height = height,
        slots = {}, sprites = {}, labels = {}, rowCount = 0, view = view, outlines = {},
        marks = Parts.layer(view.content, 0, 0, width, height),
    }
    view.onLayout = function()
        if self.RenderPaneWindow ~= nil then self:RenderPaneWindow(pane, false) end
    end
    self.panes.search = pane
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
        { "addRowButton", "Add row", function() self:InsertEmptyRow(self.layout.lines) end,
            "Add an empty row at the end of the layout" },
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

local LEFT_TAB_INDEX = { unsorted = 1, bank = 2, search = 3 }

-- Create PrettyUI tabs for Unsorted, Bank, and Search on the left panel
function LayoutEditorView:CreateLeftTabs()
    self.leftTabs = prettyui.Tabs.new(self.content, {
        { kind = "text", text = "Unsorted", value = "unsorted", scrollable = false },
        { kind = "text", text = "Bank", value = "bank", scrollable = false },
        { kind = "text", text = "Search", value = "search", scrollable = false },
    }, {
        x = Size.LEFT_X,
        y = Size.PANEL_TOP,
        width = Size.LEFT_WIDTH,
        height = Size.COLUMN_HEIGHT,
        scrollable = false,
        tabInset = Size.TABS_INSET,
        onChange = function(_, _, value)
            self:OnLeftTabChanged(value)
        end,
    })
    self.unsortedPanel = self.leftTabs:GetPage(1).content
    self.bankPanel = self.leftTabs:GetPage(2).content
    self.searchPanel = self.leftTabs:GetPage(3).content
end

-- Synchronize pane visibility and drag surfaces after switching left tabs
function LayoutEditorView:OnLeftTabChanged(tabID)
    self.activeLeftTab = tabID
    self.keysOnGrid = false
    self:HideItemName()
    self:CancelDrag()
    self.pointerSurface = nil
    if self.panes ~= nil then
        for _, name in ipairs({ "unsorted", "bank", "search" }) do
            local pane = self.panes[name]
            if pane ~= nil then
                pane.hidden = tabID ~= name
                self:RenderPaneWindow(pane, true)
            end
        end
    end
    if self.surfaceClips ~= nil then
        for _, kind in ipairs({ "unsorted", "bank", "search" }) do
            local surface = self.panes and self.panes[kind] and self.panes[kind].surface or nil
            if surface ~= nil then
                local hidden = kind ~= tabID
                surface.hidden = hidden
                self.surfaceClips[surface].hidden = hidden
                if not hidden then self:PlaceDragSurface(surface, kind) end
            end
        end
    end
end

-- Switch the active left panel tab programmatically
function LayoutEditorView:SelectLeftTab(tabID)
    local index = LEFT_TAB_INDEX[tabID]
    if index == nil then return end
    if self.leftTabs ~= nil and self.leftTabs.SetActive ~= nil then
        self.leftTabs:SetActive(index, false)
    end
    self:OnLeftTabChanged(tabID)
end

-- Build the tabbed left panel, right layout column, and input surfaces
function LayoutEditorView:CreatePanels()
    -- Keep the panel backdrop in category 0 ahead of leftTabs so tab pages draw in front of it
    self.leftPanel = Parts.contentLayer(self.content, Size.LEFT_X, Size.LEFT_BODY_TOP,
        Size.LEFT_WIDTH, Size.LEFT_BODY_HEIGHT)
    tiledSprite(self.leftPanel, 0, 0, Size.LEFT_WIDTH, Size.LEFT_BODY_HEIGHT, NativeUi.SPRITES.PANEL_BACKGROUND)
    rectangle(self.leftPanel, 0, 0, Size.LEFT_WIDTH, Size.LEFT_BODY_HEIGHT, FRAME, false)
    self:CreateLeftTabs()

    self.centerPanel = Parts.contentLayer(self.content, Size.CENTER_X, Size.PANEL_TOP,
        Size.CENTER_WIDTH, Size.COLUMN_HEIGHT)
    itemArea(self.centerPanel, Size.CENTER_WIDTH, Size.TAB_HEADER, Size.AREA_HEIGHT + Size.AREA_BOTTOM)

    self:CreateHeader()
    self.panes = {
        sorted = self:CreatePane("sorted", self.centerPanel, Size.TAB_HEADER + Size.VIEW_INSET,
            Size.CENTER_X, Size.CENTER_VIEW_WIDTH, Size.CENTER_COLUMNS),
    }
    self:CreateSearch()
    self:CreateUnsorted()
    self:CreateBank()
    self.panes.bank.hidden = true
    self.panes.search.hidden = true
    self:CreateActions()
    self:CreateDragSurfaces()
    self:RunSearch("")
    self:RefreshBank()
    self:CreateItemNames()
    self:SelectLeftTab("unsorted")
end

-- Share exact cell positions between drawing, selection, tooltips, and input
function LayoutEditorView:GridCellX(pane, column)
    if pane.gridSpan ~= nil and pane.columns > 1 then
        return pane.gridLeft + math.floor(column * pane.gridSpan / (pane.columns - 1) + 0.5)
    end
    return pane.gridLeft + column * Size.GRID_STEP
end

local WINDOW_OVERSCAN_ROWS = 2

-- Hide all pooled cells and clear visible labels for an empty or hidden pane
local function hidePanePool(pane)
    if pane.labelLayer ~= nil then
        pane.labelLayer:Destroy()
        pane.labelLayer = nil
    end
    for _, grid in ipairs(pane.gridPool or {}) do grid.hidden = true end
    for _, sprite in ipairs(pane.itemPool or {}) do sprite.hidden = true end
    pane.sprites = {}
    pane.renderedFirstRow, pane.renderedLastRow = nil, nil
end

-- Render only the rows currently inside or near the pane's scroll viewport
function LayoutEditorView:RenderPaneWindow(pane, force)
    if pane == nil or pane.drawing then return end
    local rowCount = pane.rowCount or 0
    if pane.hidden or rowCount <= 0 then
        hidePanePool(pane)
        return
    end
    local labels = pane.labels or {}
    local scrollY = pane.view ~= nil and pane.view.scrollY or 0
    local topRow = BankGrid.RowAtContentY(math.max(0, scrollY), labels) or 0
    local bottomRow = BankGrid.RowAtContentY(math.max(0, scrollY + (pane.height or 0)), labels) or (rowCount - 1)
    local firstRow = math.max(0, topRow - WINDOW_OVERSCAN_ROWS)
    local lastRow = math.min(rowCount - 1, bottomRow + WINDOW_OVERSCAN_ROWS)
    if not force and pane.renderedFirstRow == firstRow and pane.renderedLastRow == lastRow then
        return
    end
    pane.renderedFirstRow, pane.renderedLastRow = firstRow, lastRow

    local height = pane.contentHeight or pane.height
    if pane.cells == nil then
        pane.cells = Parts.layer(pane.view.content, 0, 0, pane.width, height)
        pane.gridPool = {}
        pane.itemPool = {}
        pane.itemPoolObjectIDs = {}
    else
        pane.cells:SetSize(pane.width, height)
    end
    local cells = pane.cells

    if pane.labelLayer ~= nil then
        pane.labelLayer:Destroy()
        pane.labelLayer = nil
    end
    if #labels > 0 then
        local labelLayer = nil
        for _, label in ipairs(labels) do
            if label.row >= firstRow and label.row <= lastRow then
                if labelLayer == nil then
                    labelLayer = Parts.layer(cells, 0, 0, pane.width, height)
                    pane.labelLayer = labelLayer
                end
                Parts.heading(labelLayer, Size.GRID_LEFT, BankGrid.LabelY(label.row, labels),
                    Size.LABEL_WIDTH, label.text)
            end
        end
    end

    local columns = pane.columns
    local labelRows = pane.labelRows or {}
    local gridPool, itemPool, itemPoolObjectIDs = pane.gridPool, pane.itemPool, pane.itemPoolObjectIDs
    local gridCount, itemCount = 0, 0
    local sprites = {}
    for row = firstRow, lastRow do
        if not labelRows[row] then
            local y = BankGrid.RowItemY(row, labels)
            for col = 0, columns - 1 do
                local index = row * columns + col + 1
                local x = self:GridCellX(pane, col)
                gridCount = gridCount + 1
                local grid = gridPool[gridCount]
                if grid == nil then
                    grid = NativeUi.newComponent(ui.Sprite, cells)
                    grid:SetSize(Size.GRID_SLOT_SIZE, Size.GRID_SLOT_SIZE)
                    grid.spriteID = GRID_SLOT_SPRITE
                    grid.alpha = 0.34
                    grid.clickthrough = true
                    gridPool[gridCount] = grid
                end
                grid:SetPos(x, y)
                grid.hidden = false
                local slot = pane.slots[index]
                if slot ~= nil and slot.kind == "item" then
                    itemCount = itemCount + 1
                    local sprite = itemPool[itemCount]
                    if sprite == nil then
                        sprite = NativeUi.newComponent(ui.Sprite, cells)
                        sprite:SetSize(Size.ITEM_WIDTH, Size.ITEM_HEIGHT)
                        sprite.outlineWidth = 1
                        sprite.clickthrough = true
                        itemPool[itemCount] = sprite
                    end
                    sprite:SetPos(x + ITEM_X, y + ITEM_Y)
                    if itemPoolObjectIDs[itemCount] ~= slot.objectID then
                        sprite:SetAssociatedObject(slot.objectID)
                        itemPoolObjectIDs[itemCount] = slot.objectID
                    end
                    self:StyleItem(sprite, slot.objectID, pane.name ~= "search")
                    sprite.hidden = false
                    sprites[index] = sprite
                end
            end
        end
    end
    for i = gridCount + 1, #gridPool do gridPool[i].hidden = true end
    for i = itemCount + 1, #itemPool do itemPool[i].hidden = true end
    pane.sprites = sprites
    pane.marks:SetSize(pane.width, height)
    pane.marks:MoveToFront()
end

-- Update pane geometry and render the currently visible row window
function LayoutEditorView:DrawPane(pane, rowCount, labels)
    pane.drawing = true
    pane.labels, pane.rowCount = labels, rowCount
    local labelRows = {}
    for _, label in ipairs(labels) do labelRows[label.row] = true end
    pane.labelRows = labelRows
    local height = math.max(pane.height, BankGrid.RowItemY(rowCount, labels))
    pane.contentHeight = height
    pane.view:SetContentHeight(height)
    pane.gridLeft, pane.gridSpan = Size.GRID_LEFT, nil
    if pane.name == "unsorted" or pane.name == "bank" or pane.name == "search" then
        -- Side padding matches the first row's top padding inside the border
        pane.gridLeft = BankGrid.TOP
        pane.gridSpan = math.max(0, pane.view.contentWidth - 2 * pane.gridLeft - Size.GRID_SLOT_SIZE)
        if pane.columns == 1 then pane.gridLeft = (pane.view.contentWidth - Size.GRID_SLOT_SIZE) // 2 end
    end
    pane.marks:SetSize(pane.width, height)
    pane.drawing = false
    self:RenderPaneWindow(pane, true)
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
            mark:SetPos(self:GridCellX(pane, (index - 1) % pane.columns),
                BankGrid.RowItemY((index - 1) // pane.columns, pane.labels))
            mark.hidden = false
        end
        if name == "bank" then
            if self.bankSelected ~= nil then
                for index, slot in ipairs(pane.slots or {}) do
                    if slot.kind == "item" and self.bankSelected[slot.objectID] then outline(index) end
                end
            end
        elseif name == "search" then
            if self.searchSelected ~= nil then
                for index, slot in ipairs(pane.slots or {}) do
                    if slot.kind == "item" and self.searchSelected[slot.objectID] then outline(index) end
                end
            end
        else
            for layoutKey, index in pairs(name == "sorted" and self.layout.sortedIndex
                or pane.indexes or self.layout.unsortedIndex) do
                if self:IsSelected(layoutKey) then outline(index) end
            end
            if name == "sorted" and self.pasteCell ~= nil then outline(self.pasteCell) end
        end
        for index = count + 1, #pane.outlines do pane.outlines[index].hidden = true end
    end
end

-- Find a grid row, allowing for the pane's scroll
function LayoutEditorView:RowAt(pane, x, y)
    if x < pane.gridLeft or y < 0 or x >= pane.width or y >= pane.height then return nil end
    local row = BankGrid.RowAtContentY(y + pane.view.scrollY, pane.labels)
    return row < pane.rowCount and row or nil
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
    if pane.gridSpan ~= nil then
        column = nil
        for candidate = 0, pane.columns - 1 do
            local left = self:GridCellX(pane, candidate)
            if x >= left and x < left + Size.GRID_SLOT_SIZE then column = candidate; break end
        end
        if column == nil then return nil end
    end
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
