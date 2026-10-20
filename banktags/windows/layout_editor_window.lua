-- Build the layout editor over the bank: tag column, grid, labels, and buttons

local Config = require("banktags/core/config")
local NativeUi = require("banktags/ui/native_ui")
local BankControls = require("banktags/ui/bank_controls")
local BankGrid = require("banktags/ui/bank_grid")
local Geometry = require("banktags/ui/geometry")
local ItemIdentity = require("banktags/tags/item_identity")
local SidebarRows = require("banktags/ui/sidebar_rows")
local TagList = require("banktags/sidebar/tag_list")
local Parts = require("banktags/windows/layout_editor_parts")
local Size = Parts.size
local rectangle = Parts.rectangle
local tiledSprite = Parts.tiledSprite
local frame = Parts.frame
local Theme = require("banktags/ui/theme")

local LayoutEditorWindow = {}
LayoutEditorWindow.__index = LayoutEditorWindow
-- Drag gestures, catalog search, and shortcut keys live in their own files
require("banktags/windows/layout_editor_drag").install(LayoutEditorWindow)
require("banktags/windows/layout_editor_search").install(LayoutEditorWindow)
require("banktags/windows/layout_editor_keys").install(LayoutEditorWindow)

-- Errors show over the grid's bottom for about four seconds
local ERROR_HEIGHT = 40
local ERROR_INSET = 8
local ERROR_SHOW_TICKS = 200
local ERROR_FADE_TICKS = 50
local ERROR_BACKGROUND = 0x24211EF2
local VIEW_BACKGROUND = Theme.VIEW_BACKGROUND
local ROW_SELECTED = Theme.ROW_SELECTED
local GOLD = Theme.SELECTED_BORDER
local MUTED = Theme.MUTED_TEXT
local ERROR = Theme.ERROR_TEXT
local FRAME = Theme.FRAME
local INNER_FRAME = Theme.INNER_FRAME
local ITEM_WIDTH = 36
local ITEM_HEIGHT = 32
local PLACEHOLDER_ALPHA = 0.45
local PLACEHOLDER_QUANTITY_MODE = ui.ObjectQuantityDisplayMode.ALWAYS or 2
local GRID_SLOT_SPRITE = id.Sprite.RS3_ICON_SLOT_40PX_1
local LABEL_TEXT_COLOUR = Theme.HEADING_TEXT
local LABEL_LINE_COLOUR = Theme.HEADING_LINE
local DRAG_EVENT = Config.PLUGIN_REF .. "_layout_editor"
local FOOTER_BUTTON_GAP = 8
local ICON_BUTTON_SIZE = 28

-- Destroy saved UI parts newest first, skipping ones already gone
local function destroyAll(values)
    for index = #(values or {}), 1, -1 do
        pcall(function() values[index]:Destroy() end)
    end
end

-- Create the layout editor over the bank
function LayoutEditorWindow.new(parent, options)
    local self = setmetatable({
        store = options.store,
        settings = options.settings,
        selectedTag = options.tag,
        columns = options.columns,
        bounds = options.bounds,
        onChanged = options.onChanged,
        onClose = options.onClose,
        onOpenImport = options.onOpenImport,
        onCreateTag = options.onCreateTag,
        onPromptLabel = options.onPromptLabel,
        overlayWindow = nil,
        listState = { searchQuery = "" },
        searchResults = {},
        centerNodes = {},
        centerSlots = {},
        centerLabels = {},
        selectedLayoutKey = nil,
        drag = nil,
        styles = { byKey = {}, byObject = {} },
    }, LayoutEditorWindow)

    self:SetBankItems(options.bankItems)
    Parts.SizeToBank(self.columns, self.bounds.width, self.bounds.height)
    self.window = prettyui.Window.new(parent, {
        title = "Bank Layout Editor",
        x = self.bounds.x,
        y = self.bounds.y,
        xAnchor = 0,
        yAnchor = 0,
        width = Size.WIDTH,
        height = Size.HEIGHT,
        minWidth = Size.WIDTH,
        maxWidth = Size.WIDTH,
        minHeight = Size.HEIGHT,
        maxHeight = Size.HEIGHT,
        scrollable = false,
        destroyOnClose = true,
        onClose = function()
            self:StopDragPolling()
            self:StopShortcuts()
            self:FinishDrag(false)
            self:ClearSearchInteractions()
            self:DestroyCenterNodes()
            self:DestroyControls()
            local onClose = self.onClose
            self.onClose = nil
            self.onChanged = nil
            self.onPromptLabel = nil
            self.overlayWindow = nil
            -- PrettyUI destroys the window after this returns
            self.window = nil
            if onClose ~= nil then onClose(self) end
        end,
    })
    -- Remove PrettyUI's title-bar drag so the editor stays over the bank
    if self.window.titleDrag ~= nil then
        pcall(function() self.window.titleDrag:Destroy() end)
        self.window.titleDrag = nil
    end
    self.content = self.window.content
    self:CreatePanels()
    if self.selectedTag == nil then
        local tags = self.store:AllTags()
        self.selectedTag = tags[1]
    end
    self:SelectTag(self.selectedTag)
    Event.Logic.Unsubscribe(DRAG_EVENT)
    Event.Logic.Subscribe(DRAG_EVENT, function() self:PollDrag() end)
    self:StartShortcuts()
    return self
end

-- Check whether the editor fits the bank's columns and size
function LayoutEditorWindow:FitsBank(columns, bounds)
    return columns == self.columns and bounds.width == self.bounds.width
        and bounds.height == self.bounds.height
end

-- Follow the bank to a new position
function LayoutEditorWindow:MoveTo(bounds)
    self.bounds = bounds
    self:KeepOnTop()
end

-- Remember copy quantities and each object's best stack
function LayoutEditorWindow:SetBankItems(items)
    local byKey, byObject = {}, {}
    for _, item in ipairs(items or {}) do
        local style = { quantity = item.quantity, placeholder = item.placeholder }
        byKey[ItemIdentity.LayoutKey(item.objectID, item.copy)] = style
        local existing = byObject[item.objectID]
        -- A real stack beats a placeholder for the same object
        if existing == nil or (existing.placeholder and not style.placeholder) then
            byObject[item.objectID] = style
        end
    end
    self.styles = { byKey = byKey, byObject = byObject }
    self.bankItemList = items or {}
    if self.centerView ~= nil then self:RefreshCenter() end
end

-- Show outside changes, keeping the open tag if it still exists
function LayoutEditorWindow:StoreChanged()
    if self.window == nil then return end
    if self.selectedTag ~= nil and self.store.data.tags[self.selectedTag] == nil then
        self:SelectTag(self.store:AllTags()[1])
        return
    end
    self:RefreshTags()
    self:RefreshCenter()
end

-- Create one editor column at its panel offset
function LayoutEditorWindow:Panel(x, width)
    local panel = ui.Layer.new(self.content)
    panel:SetPos(x, Size.PANEL_TOP)
    panel:SetSize(width, Size.PANEL_HEIGHT)
    panel.clickthrough = true
    return panel
end

-- Prefer the exact copy's quantity over the object's best stack
function LayoutEditorWindow:RuntimeStyle(objectID, layoutKey)
    local byLayout = type(layoutKey) == "string" and self.styles.byKey[layoutKey] or nil
    if byLayout ~= nil then return byLayout end
    objectID = math.tointeger(tonumber(objectID))
    return objectID ~= nil and self.styles.byObject[objectID] or nil
end

-- Draw an item with its client sprite and bank quantity
-- Placeholders and absent entries are faded
function LayoutEditorWindow:ApplyRuntimeObjectSprite(sprite, objectID, layoutKey, absentIsPlaceholder)
    local style = self:RuntimeStyle(objectID, layoutKey)
    sprite:SetSize(ITEM_WIDTH, ITEM_HEIGHT)
    -- Only the live object sprite matches the native bank look
    sprite:SetAssociatedObject(math.tointeger(tonumber(objectID)))
    if style ~= nil then
        sprite.associatedObjectQuantity = style.quantity
        sprite.associatedObjectQuantityMode = style.placeholder and PLACEHOLDER_QUANTITY_MODE
            or ui.ObjectQuantityDisplayMode.MULTIPLE
        sprite.alpha = style.placeholder and PLACEHOLDER_ALPHA or 1
    elseif absentIsPlaceholder then
        sprite.associatedObjectQuantity = 0
        sprite.associatedObjectQuantityMode = PLACEHOLDER_QUANTITY_MODE
        sprite.alpha = PLACEHOLDER_ALPHA
    else
        sprite.associatedObjectQuantityMode = ui.ObjectQuantityDisplayMode.NEVER
        sprite.alpha = 1
    end
    sprite.clickthrough = true
    return ITEM_WIDTH, ITEM_HEIGHT
end

-- Align the editor with the bank and keep it on top
function LayoutEditorWindow:KeepOnTop()
    if self.window == nil or self.window.root == nil then return end
    pcall(function()
        local bounds = self.bounds
        if self.window.root.x ~= bounds.x or self.window.root.y ~= bounds.y then
            self.window.root:SetPos(bounds.x, bounds.y, 0, 0)
        end
        self.window.root:MoveToFront()
        if self.window._SyncOverlays ~= nil then self.window:_SyncOverlays(false) end
        -- Keep prompts opened from the editor in front of it
        local overlay = self.overlayWindow
        if overlay ~= nil and overlay.root ~= nil and not overlay.root.hidden then
            overlay.root:MoveToFront()
            if overlay._SyncOverlays ~= nil then overlay:_SyncOverlays(false) end
        end
    end)
end

-- Keep a window opened from the editor in front of it
function LayoutEditorWindow:SetOverlay(window)
    self.overlayWindow = window
    self:KeepOnTop()
end

-- Build the tag column where the bank's own one sits
function LayoutEditorWindow:CreateTagColumn()
    local column = ui.Layer.new(self.content)
    column:SetPos(Size.COLUMN_X, Size.PANEL_TOP)
    column:SetSize(Size.COLUMN_WIDTH, Size.PANEL_HEIGHT)
    column.clickthrough = false
    self.tagColumn = column
    prettyui.Tooltip.registerContext(column, self.content, function(target)
        return Geometry.relativePosition(target, self.content)
    end)
    tiledSprite(column, 0, 0, Size.COLUMN_WIDTH, Size.PANEL_HEIGHT, NativeUi.SPRITES.PANEL_BACKGROUND)
    self.tagList = TagList.new(column, {
        store = self.store,
        settings = self.settings,
        state = self.listState,
        width = Size.COLUMN_WIDTH,
        listHeight = Size.PANEL_HEIGHT - SidebarRows.LIST_TOP - SidebarRows.FOOTER_HEIGHT,
        isSelected = function(tag) return tag == self.selectedTag end,
        onSelect = function(tag) self:SelectTag(tag) end,
        onChanged = function() self:NotifyChanged() end,
    })
    local width = SidebarRows.ContentWidth(Size.COLUMN_WIDTH)
    local top = Size.PANEL_HEIGHT - 36
    local newTagX = SidebarRows.CONTENT_X + ICON_BUTTON_SIZE + FOOTER_BUTTON_GAP
    local newTagWidth = width - (ICON_BUTTON_SIZE + FOOTER_BUTTON_GAP) * 2
    self.columnButtons = {
        BankControls.button(column, nil, function()
            -- Import/Share has text fields of its own
            self.keysOnGrid = false
            if self.onOpenImport ~= nil then self.onOpenImport() end
        end, {
            x = SidebarRows.CONTENT_X, y = top, size = ICON_BUTTON_SIZE, iconSize = 18,
            spriteName = "EXPORT", tooltip = "Import and share bank tags",
        }),
        BankControls.button(column, "New Tag", function() self:CreateNewTag() end, {
            x = newTagX, y = top, width = newTagWidth, height = 28, tooltip = "Create a new bank tag",
        }),
        BankControls.button(column, nil, function()
            if self.window ~= nil then self.window:Close() end
        end, {
            x = newTagX + newTagWidth + FOOTER_BUTTON_GAP, y = top, size = ICON_BUTTON_SIZE, iconSize = 18,
            spriteName = "CROSS", tooltip = "Close layout editor",
        }),
    }
    self.columnFrame = frame(column, 0, 0, Size.COLUMN_WIDTH, Size.PANEL_HEIGHT, FRAME)
end

-- Build the tag column, grid, and search columns
function LayoutEditorWindow:CreatePanels()
    self:CreateTagColumn()
    self.centerPanel = self:Panel(Size.CENTER_X, Size.CENTER_WIDTH)
    self.rightPanel = self:Panel(Size.RIGHT_X, Size.RIGHT_WIDTH)

    self.centerBackground = tiledSprite(
        self.centerPanel, 0, 0, Size.CENTER_WIDTH, Size.PANEL_HEIGHT,
        NativeUi.SPRITES.PANEL_BACKGROUND
    )
    self.centerSurface = rectangle(
        self.centerPanel, 0, 0,
        Size.CENTER_SURFACE_WIDTH, Size.CENTER_SURFACE_HEIGHT,
        VIEW_BACKGROUND, true
    )
    self.centerFrame = frame(
        self.centerPanel, 0, 0,
        Size.CENTER_SURFACE_WIDTH, Size.CENTER_SURFACE_HEIGHT, FRAME
    )
    self.centerView = prettyui.SimpleView.new(self.centerPanel, {
        x = Size.CENTER_VIEW_X,
        y = Size.CENTER_VIEW_Y,
        width = Size.CENTER_VIEW_WIDTH,
        height = Size.CENTER_VIEW_HEIGHT,
        contentHeight = Size.CENTER_VIEW_HEIGHT,
        scrollStep = Size.GRID_STEP,
    })
    -- These replace the right-click menu, which only Bank Core may change
    self.duplicateButton = BankControls.button(
        self.centerPanel, "Create Copy", function() self:DuplicateSelected() end,
        { x = 8, y = Size.FOOTER_Y, width = 104, height = Size.FOOTER_HEIGHT,
            tooltip = "Copy the selected item (Ctrl+C)" }
    )
    self.removeButton = BankControls.button(
        self.centerPanel, "Remove", function() self:RemoveSelected() end,
        { x = 120, y = Size.FOOTER_Y, width = 84, height = Size.FOOTER_HEIGHT,
            tooltip = "Remove the selected item (Delete)" }
    )
    self.unsortButton = BankControls.button(
        self.centerPanel, "Move to Unsorted", function() self:UnarrangeSelected() end,
        { x = 212, y = Size.FOOTER_Y, width = Size.UNSORT_BUTTON_WIDTH, height = Size.FOOTER_HEIGHT }
    )
    -- Its drag surface handles clicks too, so the button has no action
    self.newLabelButton = BankControls.button(self.centerPanel, "New label", nil, {
        x = Size.LABEL_BUTTON_X,
        y = Size.FOOTER_Y,
        width = Size.LABEL_BUTTON_WIDTH,
        height = Size.FOOTER_HEIGHT,
    })
    self.rightBackground = tiledSprite(
        self.rightPanel, 0, 0, Size.RIGHT_WIDTH, Size.PANEL_HEIGHT,
        NativeUi.SPRITES.PANEL_BACKGROUND
    )
    self.rightFrame = frame(
        self.rightPanel, 0, 0, Size.RIGHT_WIDTH, Size.PANEL_HEIGHT, FRAME
    )
    self.itemSearch = prettyui.TextField.new(self.rightPanel, {
        x = 8, y = 8, width = Size.RIGHT_WIDTH - 16, height = 26,
        placeholder = "Search items...", maxLength = 80,
        onChange = function(_, _, value) self:RunSearch(value) end,
        onSubmit = function(_, value) self:RunSearch(value) end,
    })
    self.searchList = prettyui.List.new(self.rightPanel, {
        x = 8,
        y = Size.SEARCH_LIST_TOP,
        width = Size.RIGHT_WIDTH - 16,
        height = Size.PANEL_HEIGHT - Size.SEARCH_LIST_TOP - Size.SEARCH_LIST_BOTTOM,
        entryHeight = 32,
        maxSelected = 1,
        backgroundColour = 0x00000000,
        borderColour = INNER_FRAME,
        selectedColour = ROW_SELECTED,
    })
    self.searchHint = prettyui.Text.new(self.rightPanel, {
        text = Parts.SEARCH_HINT,
        x = 18,
        y = Size.SEARCH_LIST_TOP + 10,
        width = Size.RIGHT_WIDTH - 36,
        height = 120,
        colour = MUTED,
        maxLines = 8,
    })
    self:RunSearch("")
    self:CreateDragSurfaces()
    for _, edges in ipairs({ self.centerFrame, self.rightFrame }) do
        for _, edge in ipairs(edges) do edge:MoveToFront() end
    end
end

-- Show a failure briefly over the grid
-- Saves happen on every change, so only problems are shown
function LayoutEditorWindow:ShowError(message)
    self:HideError()
    if self.centerPanel == nil then return end
    local width = Size.CENTER_SURFACE_WIDTH - ERROR_INSET * 2
    local banner = ui.Layer.new(self.centerPanel)
    banner:SetPos(ERROR_INSET, Size.CENTER_SURFACE_HEIGHT - ERROR_HEIGHT - ERROR_INSET)
    banner:SetSize(width, ERROR_HEIGHT)
    banner.clickthrough = true
    local text = prettyui.Text.new(banner, {
        text = tostring(message or "Something went wrong."),
        x = 10, y = 0, width = width - 20, height = ERROR_HEIGHT,
        colour = ERROR,
        maxLines = 2,
    })
    text.clickthrough = true
    self.errorBanner = {
        root = banner,
        parts = {
            rectangle(banner, 0, 0, width, ERROR_HEIGHT, FRAME, true),
            rectangle(banner, 1, 1, width - 2, ERROR_HEIGHT - 2, ERROR_BACKGROUND, true),
            text,
        },
        ticks = ERROR_SHOW_TICKS,
    }
    text:MoveToFront()
    banner:MoveToFront()
end

-- Count the error down, fading it out
function LayoutEditorWindow:TickError()
    local banner = self.errorBanner
    if banner == nil then return end
    banner.ticks = banner.ticks - 1
    if banner.ticks <= 0 then
        self:HideError()
    elseif banner.ticks < ERROR_FADE_TICKS then
        for _, part in ipairs(banner.parts) do part.alpha = banner.ticks / ERROR_FADE_TICKS end
    end
end

-- Remove the error message
function LayoutEditorWindow:HideError()
    local banner = self.errorBanner
    self.errorBanner = nil
    if banner ~= nil then pcall(function() banner.root:Destroy() end) end
end

-- Show the selected tag and rebuild the tag rows
function LayoutEditorWindow:RefreshTags()
    if self.tagList ~= nil then self.tagList:Refresh() end
end

-- Open a tag draft, selecting it once its editor saves
function LayoutEditorWindow:CreateNewTag()
    if self.onCreateTag == nil then return false end
    -- The tag draft has a name field of its own
    self.keysOnGrid = false
    self.onCreateTag(function(tag)
        self:SelectTag(tag)
        self:NotifyChanged()
    end)
    return true
end

-- End drags and load the selected tag's layout
function LayoutEditorWindow:SelectTag(tag)
    if type(tag) ~= "string" or tag == "" then
        self.selectedTag = nil
    else
        self.selectedTag = tag
    end
    self.selectedLayoutKey = nil
    self:RefreshTags()
    self:RefreshCenter()
end

-- Destroy grid decorations and release their references
function LayoutEditorWindow:DestroyCenterNodes()
    destroyAll(self.centerNodes)
    self.centerNodes = {}
end

-- Rebuild slots and item sprites from the saved layout
function LayoutEditorWindow:RefreshCenter()
    self:FinishDrag(false)
    self:DestroyCenterNodes()
    self.centerSlots = {}
    if self.selectedTag == nil then
        self.centerView:SetContentHeight(Size.CENTER_VIEW_HEIGHT)
        return
    end

    local slots, boundary, labels = self.store:GetLayout(self.selectedTag, Size.CENTER_COLUMNS)
    self.centerSlots = slots
    self.centerPreservedBoundary = boundary
    self.centerLabels = labels
    local visibleRows = math.ceil((Size.CENTER_VIEW_HEIGHT - Size.GRID_TOP) / Size.GRID_STEP)
    local occupiedRows = math.ceil(#slots / Size.CENTER_COLUMNS)
    for _, label in ipairs(labels) do occupiedRows = math.max(occupiedRows, label.row + 1) end
    -- Keep one empty drop row after the last occupied row
    local rowCount = math.max(visibleRows,
        occupiedRows + (occupiedRows > 0 and 1 or 0))
    local contentHeight = BankGrid.LabelledContentHeight(
        rowCount * Size.CENTER_COLUMNS, Size.CENTER_COLUMNS, labels)
    self.centerView:SetContentHeight(math.max(Size.CENTER_VIEW_HEIGHT, contentHeight))
    local labelRows = {}
    for _, label in ipairs(labels) do
        labelRows[label.row] = true
        self:CreateLabelHeader(label)
    end
    -- Unsorted items sit under a fixed heading drawn like a label
    self.centerUnsortedRow = BankGrid.UnsortedRow(slots, boundary, Size.CENTER_COLUMNS)
    if self.centerUnsortedRow ~= nil then
        labelRows[self.centerUnsortedRow] = true
        self:CreateLabelHeader({
            row = self.centerUnsortedRow,
            text = BankGrid.UNSORTED_LABEL,
        })
    end

    for index = 1, rowCount * Size.CENTER_COLUMNS do
        local zero = index - 1
        local x = Size.GRID_LEFT + (zero % Size.CENTER_COLUMNS) * Size.GRID_STEP
        -- Rows match the live page; columns keep the editor inset
        local row = math.floor(zero / Size.CENTER_COLUMNS)
        local y = BankGrid.RowItemY(row)
        -- Label rows show their heading instead of empty cells
        if not labelRows[row] then
            self:CreateGridCell(x, y, slots[index])
        end
    end
    if self.centerDragSurface ~= nil then self.centerDragSurface:MoveToFront() end
end

-- Draw one grid cell and the item saved in it, if any
function LayoutEditorWindow:CreateGridCell(x, y, slot)
    local grid = ui.Sprite.new(self.centerView.content)
    grid:SetPos(x, y)
    grid:SetSize(Size.GRID_SLOT_SIZE, Size.GRID_SLOT_SIZE)
    grid.spriteID = GRID_SLOT_SPRITE
    grid.alpha = 0.34
    grid.clickthrough = true
    self.centerNodes[#self.centerNodes + 1] = grid

    if type(slot) ~= "table" or slot.kind ~= "item" then return end
    local objectID = math.tointeger(tonumber(slot.objectID))
    if objectID ~= nil then
        local sprite = ui.Sprite.new(self.centerView.content)
        local width, height = self:ApplyRuntimeObjectSprite(
            sprite, objectID, slot.layoutKey, true
        )
        sprite:SetPos(
            x + math.floor((Size.GRID_SLOT_SIZE - width) / 2),
            y + math.floor((Size.GRID_SLOT_SIZE - height) / 2)
        )
        self.centerNodes[#self.centerNodes + 1] = sprite
    end
    if slot.layoutKey == self.selectedLayoutKey then
        local selection = rectangle(
            self.centerView.content,
            x, y, Size.GRID_SLOT_SIZE, Size.GRID_SLOT_SIZE, GOLD, false
        )
        self.centerNodes[#self.centerNodes + 1] = selection
    end
end

-- Draw a label row like the bank's own headings
function LayoutEditorWindow:CreateLabelHeader(label)
    local width = Size.CENTER_COLUMNS * Size.GRID_STEP - (Size.GRID_STEP - Size.GRID_SLOT_SIZE)
    local header = ui.Layer.new(self.centerView.content)
    header:SetPos(Size.GRID_LEFT, BankGrid.LabelY(label.row))
    header:SetSize(width, Size.LABEL_LINE_OFFSET + 1)
    header.clickthrough = true
    local text = prettyui.Text.new(header, {
        text = label.text,
        x = 0, y = 0, width = width, height = Size.LABEL_LINE_OFFSET,
        colour = LABEL_TEXT_COLOUR,
        font = id.Font.MUSEO_SANS_11PT_REGULAR,
        maxLines = 1,
    })
    text.clickthrough = true
    rectangle(header, 0, Size.LABEL_LINE_OFFSET, width, 1, LABEL_LINE_COLOUR, true)
    self.centerNodes[#self.centerNodes + 1] = header
end

-- Return the grid row under a center-view point
function LayoutEditorWindow:RowAt(x, y)
    x, y = tonumber(x), tonumber(y)
    if x == nil or y == nil or x < Size.GRID_LEFT or y < 0
        or x >= Size.CENTER_VIEW_WIDTH or y >= Size.CENTER_VIEW_HEIGHT then return nil end
    return BankGrid.RowAtContentY(y + (tonumber(self.centerView.scrollY) or 0))
end

-- Return the label row under a center-view point
function LayoutEditorWindow:LabelRowAt(x, y)
    local row = self:RowAt(x, y)
    for _, label in ipairs(self.centerLabels) do
        if label.row == row then return row end
    end
    return nil
end

-- Refresh after a label edit if its tag is open, then tell the app
function LayoutEditorWindow:LabelChanged(tag)
    if self.window ~= nil and self.selectedTag == tag then self:RefreshCenter() end
    self:NotifyChanged()
end

-- Rename or delete a label through the text prompt
function LayoutEditorWindow:EditLabel(row)
    local tag = self.selectedTag
    local current = tag ~= nil and self.store:GetLabel(tag, row, Size.CENTER_COLUMNS) or nil
    if current == nil or self.onPromptLabel == nil then return false end
    self.onPromptLabel({
        text = current,
        onSave = function(value)
            local saved, reason = self.store:SetLabel(tag, row, value, Size.CENTER_COLUMNS)
            if not saved then return false, reason end
            self:LabelChanged(tag)
            return true, nil
        end,
        onDelete = function()
            local saved, reason = self.store:RemoveLabel(tag, row, Size.CENTER_COLUMNS)
            if not saved then return false, reason end
            self:LabelChanged(tag)
            return true, nil
        end,
    })
    return true
end

-- Ask for a new label's text, adding it once saved
function LayoutEditorWindow:PromptNewLabel(row)
    local tag = self.selectedTag
    if tag == nil or self.onPromptLabel == nil then return false end
    self.onPromptLabel({
        onSave = function(value)
            local saved, reason = self.store:InsertLabel(tag, row, value, Size.CENTER_COLUMNS)
            if not saved then return false, reason end
            self:LabelChanged(tag)
            return true, nil
        end,
    })
    return true
end

-- Convert content coordinates to a grid slot, skipping headings
function LayoutEditorWindow:SlotIndexAt(x, y)
    local row = self:RowAt(x, y)
    if row == nil or row == self.centerUnsortedRow
        or self:LabelRowAt(x, y) ~= nil then return nil end
    local column = math.floor((tonumber(x) - Size.GRID_LEFT) / Size.GRID_STEP)
    if column < 0 or column >= Size.CENTER_COLUMNS then return nil end
    return row * Size.CENTER_COLUMNS + column + 1
end

-- Keep the editor above native bank redraws
function LayoutEditorWindow:PollDrag()
    self:KeepOnTop()
    self:TickError()
end

-- Stop the listener that keeps the editor on top
function LayoutEditorWindow:StopDragPolling()
    Event.Logic.Unsubscribe(DRAG_EVENT)
end

-- Find the layout entry matching the selection
function LayoutEditorWindow:SelectedEntry()
    if self.selectedLayoutKey == nil then return nil end
    for _, slot in ipairs(self.centerSlots) do
        if type(slot) == "table" and slot.kind == "item"
            and slot.layoutKey == self.selectedLayoutKey then return slot end
    end
    return nil
end

-- Move the selected item to Unsorted, keeping it tagged
function LayoutEditorWindow:UnarrangeSelected()
    local entry = self:SelectedEntry()
    if entry == nil or self.selectedTag == nil then
        self:ShowError("Select a layout item first.")
        return false
    end
    if entry.unarranged then
        self:ShowError("That item is already in Unsorted.")
        return false
    end
    local saved, reason = self.store:UnarrangeLayoutItem(self.selectedTag, entry.layoutKey)
    if not saved then self:ShowError(reason); return false end
    self.selectedLayoutKey = nil
    self:RefreshCenter()
    self:NotifyChanged()
    return true
end

-- Add a ghost copy of the selected item
function LayoutEditorWindow:DuplicateSelected()
    local entry = self:SelectedEntry()
    if entry == nil or self.selectedTag == nil then
        self:ShowError("Select a layout item first.")
        return false
    end
    local saved, nextKey, reason = self.store:DuplicateLayoutItem(self.selectedTag, entry.layoutKey)
    if not saved then
        self:ShowError(reason or "Could not duplicate the item.")
        return false
    end
    self.selectedLayoutKey = nextKey
    self:RefreshCenter()
    self:NotifyChanged()
    return true
end

-- Untag the selected item, keeping other grid positions
function LayoutEditorWindow:RemoveSelected()
    local entry = self:SelectedEntry()
    if entry == nil or self.selectedTag == nil then
        self:ShowError("Select a layout item first.")
        return false
    end
    local saved, reason = self.store:RemoveTag(self.selectedTag, entry.layoutKey)
    if not saved then
        self:ShowError(reason or "Could not remove the item.")
        return false
    end
    self.selectedLayoutKey = nil
    self:RefreshCenter()
    self:NotifyChanged()
    return true
end

-- Tell the app the store changed
function LayoutEditorWindow:NotifyChanged()
    if self.onChanged ~= nil then self.onChanged() end
end

-- Show the editor window
function LayoutEditorWindow:Show()
    self.window:Show()
    self:KeepOnTop()
end

-- Remove the editor controls and release their callbacks
function LayoutEditorWindow:DestroyControls()
    for _, surface in ipairs({
        self.centerDragSurface,
        self.searchDragSurface,
        self.labelDragSurface,
    }) do
        if surface ~= nil then pcall(function() surface:Destroy() end) end
    end
    self.centerDragSurface = nil
    self.searchDragSurface = nil
    self.labelDragSurface = nil
    for _, control in ipairs({
        self.searchHint,
        self.searchList,
        self.itemSearch,
        self.newLabelButton,
        self.unsortButton,
        self.removeButton,
        self.duplicateButton,
        self.centerView,
    }) do
        if control ~= nil then pcall(function() control:Destroy() end) end
    end
    if self.tagList ~= nil then
        self.tagList:Destroy()
        for _, button in ipairs(self.columnButtons) do pcall(function() button:Destroy() end) end
        pcall(function() prettyui.Tooltip.unregisterContext(self.tagColumn) end)
        pcall(function() self.tagColumn:Destroy() end)
        self.tagList, self.columnButtons, self.tagColumn = nil, nil, nil
    end
    self.searchHint = nil
    self.searchList = nil
    self.itemSearch = nil
    self:HideError()
    self.newLabelButton = nil
    self.unsortButton = nil
    self.removeButton = nil
    self.duplicateButton = nil
    self.centerView = nil
end

-- Stop events and drags, then destroy the editor
function LayoutEditorWindow:Destroy()
    self:StopDragPolling()
    self:StopShortcuts()
    self:FinishDrag(false)
    self:ClearSearchInteractions()
    self:DestroyCenterNodes()
    self:DestroyControls()
    if self.window ~= nil then pcall(function() self.window:Destroy() end) end
    self.window = nil
    self.content = nil
    self.onChanged = nil
    self.onClose = nil
    self.onOpenImport = nil
    self.onCreateTag = nil
    self.onPromptLabel = nil
    self.overlayWindow = nil
end

return LayoutEditorWindow
