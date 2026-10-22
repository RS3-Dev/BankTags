-- Build the layout editor over the bank: tag rail, grids, labels, and buttons

local Config = require("banktags/core/config")
local NativeUi = require("banktags/ui/native_ui")
local BankControls = require("banktags/ui/bank_controls")
local BankGrid = require("banktags/ui/bank_grid")
local Geometry = require("banktags/ui/geometry")
local ItemIdentity = require("banktags/tags/item_identity")
local TagRail = require("banktags/windows/layout_editor_rail")
local Parts = require("banktags/windows/layout_editor_parts")
local Size = Parts.size
local rectangle = Parts.rectangle
local tiledSprite = Parts.tiledSprite
local frame = Parts.frame
local Theme = require("banktags/ui/theme")

local LayoutEditorWindow = {}
LayoutEditorWindow.__index = LayoutEditorWindow
-- Drag gestures, catalog search, shortcut keys, item names, groups, undo, and copying live in their own files
require("banktags/windows/layout_editor_drag").install(LayoutEditorWindow)
require("banktags/windows/layout_editor_search").install(LayoutEditorWindow)
require("banktags/windows/layout_editor_keys").install(LayoutEditorWindow)
require("banktags/windows/layout_editor_names").install(LayoutEditorWindow)
require("banktags/windows/layout_editor_group").install(LayoutEditorWindow)
require("banktags/windows/layout_editor_history").install(LayoutEditorWindow)
require("banktags/windows/layout_editor_clipboard").install(LayoutEditorWindow)

-- Messages replace the tag name briefly in the header
local ERROR_HEIGHT = Size.TAG_NAME_HEIGHT
local ERROR_SHOW_TICKS = 200
local ERROR_FADE_TICKS = 50
local ERROR_BACKGROUND = 0x24211EF2
local VIEW_BACKGROUND = Theme.VIEW_BACKGROUND
local ROW_SELECTED = Theme.ROW_SELECTED
local GOLD = Theme.SELECTED_BORDER
local MUTED = Theme.MUTED_TEXT
local ERROR = Theme.ERROR_TEXT
local FRAME = Theme.FRAME
local ITEM_WIDTH = 36
local ITEM_HEIGHT = 32
local PLACEHOLDER_ALPHA = 0.45
local PLACEHOLDER_QUANTITY_MODE = ui.ObjectQuantityDisplayMode.ALWAYS or 2
local GRID_SLOT_SPRITE = id.Sprite.RS3_ICON_SLOT_40PX_1
local LABEL_TEXT_COLOUR = Theme.HEADING_TEXT
local LABEL_LINE_COLOUR = Theme.HEADING_LINE
local DRAG_EVENT = Config.PLUGIN_REF .. "_layout_editor"
-- The sorted grid, then the Unsorted grid in the right column
local PANE_NAMES = { "sorted", "unsorted" }
-- Right-column tabs, left to right; Unsorted shows first
local RIGHT_TABS = { "unsorted", "search" }

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
        onPromptLabel = options.onPromptLabel,
        onConfirmRemoveRow = options.onConfirmRemoveRow,
        overlayWindows = {},
        searchResults = {},
        centerNodes = {},
        centerLabels = {},
        selectedLayoutKey = nil,
        -- Set only while two or more sorted items are selected
        groupKeys = nil,
        -- The empty sorted cell Paste fills, outlined in gold
        pasteCell = nil,
        -- The copied items of the open tag, kept until the tag changes or the editor closes
        clipboard = nil,
        actionTooltips = {
            copyButton = "Copy the selected item or group (Ctrl+C)",
            pasteButton = "Click an empty cell, then paste the copied items there (Ctrl+V)",
            removeButton = "Remove the selected item (Delete). Ctrl+Z undoes and Ctrl+Y redoes;"
                .. " arrow keys move the selection when turned on in Bank settings",
            unsortButton = "Leave the selected item unsorted, or drag it to Unsorted",
        },
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
            self:ClearHistory()
            self:FinishDrag(false)
            self:ClearSearchInteractions()
            self:DestroyCenterNodes()
            self:DestroyControls()
            local onClose = self.onClose
            self.onClose = nil
            self.onChanged = nil
            self.onPromptLabel = nil
            self.onConfirmRemoveRow = nil
            self.clipboard = nil
            self.overlayWindows = {}
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
    if self.panes ~= nil then self:RefreshCenter() end
end

-- Show outside changes, keeping the open tag if it still exists
function LayoutEditorWindow:StoreChanged()
    if self.window == nil then return end
    if self.selectedTag ~= nil and self.store.data.tags[self.selectedTag] == nil then
        self:SelectTag(self.store:AllTags()[1])
        return
    end
    self:CheckHistory()
    self:RefreshTags()
    self:RefreshCenter()
end

-- Create one editor column at its panel offset
function LayoutEditorWindow:Panel(x, width)
    local panel = ui.Layer.new(self.content)
    panel:SetPos(x, Size.PANEL_TOP)
    panel:SetSize(width, Size.COLUMN_HEIGHT)
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
        -- Keep windows opened from the editor in front of it, in order
        for _, overlay in ipairs(self.overlayWindows) do
            if overlay.root ~= nil and not overlay.root.hidden then
                overlay.root:MoveToFront()
                if overlay._SyncOverlays ~= nil then overlay:_SyncOverlays(false) end
            end
        end
    end)
end

-- Keep windows opened from the editor in front of it, the last frontmost
function LayoutEditorWindow:SetOverlays(windows)
    self.overlayWindows = windows
    self:KeepOnTop()
end

-- Build the tag rail down the editor's left edge
function LayoutEditorWindow:CreateTagRail()
    self.tagRail = TagRail.new(self.content, {
        x = Size.RAIL_X,
        y = Size.PANEL_TOP,
        height = Size.PANEL_HEIGHT,
        onSelect = function(tag) self:SelectTag(tag) end,
    })
end

-- Place a column's tab header at its top over its item area
local function tabOptions(width, onChange)
    return {
        x = 0,
        y = Size.TAB_Y,
        width = width,
        height = Size.TAB_HEADER + Size.AREA_HEIGHT,
        scrollable = false,
        onChange = onChange,
    }
end

-- Draw a column's item area, one surface inside one frame
local function itemArea(parent, width)
    rectangle(parent, 0, 0, width, Size.AREA_HEIGHT, VIEW_BACKGROUND, true)
    frame(parent, 0, 0, width, Size.AREA_HEIGHT, FRAME)
end

-- Create one scrolling grid at a content point, with its own columns
function LayoutEditorWindow:CreatePane(name, parent, x, y, width, height, columns)
    local parentX, parentY = Geometry.relativePosition(parent, self.content)
    return {
        name = name,
        x = parentX + x,
        y = parentY + y,
        width = width,
        height = height,
        columns = columns,
        slots = {},
        view = prettyui.SimpleView.new(parent, {
            x = x,
            y = y,
            width = width,
            height = height,
            contentHeight = height,
            scrollStep = Size.GRID_STEP,
        }),
    }
end

-- Build the Layout tab over the sorted grid, the open tag named beside it
function LayoutEditorWindow:CreateLayoutTab()
    local width = Size.CENTER_SURFACE_WIDTH
    self.layoutTabs = prettyui.Tabs.new(self.centerPanel, {
        { kind = "text", text = "Layout", value = "layout" },
    }, tabOptions(width))
    local page = self.layoutTabs:GetPage(1).content
    itemArea(page, width)
    self.panes = {
        sorted = self:CreatePane("sorted", page, Size.VIEW_INSET, Size.VIEW_INSET,
            Size.CENTER_VIEW_WIDTH, Size.SORTED_VIEW_HEIGHT, Size.CENTER_COLUMNS),
    }
    self.tagName = prettyui.Text.new(self.centerPanel, {
        text = "",
        x = Size.TAG_NAME_X,
        y = Size.TAG_NAME_Y,
        width = width - Size.TAG_NAME_X - Size.VIEW_INSET,
        height = Size.TAG_NAME_HEIGHT,
        colour = MUTED,
        alignVertical = ui.AlignMode.CENTRE,
        maxLines = 1,
    })
    self.tagName.clickthrough = true
end

-- Build the Unsorted and Search tabs over the right item area
function LayoutEditorWindow:CreateRightTabs()
    local width = Size.RIGHT_WIDTH
    self.tabs = prettyui.Tabs.new(self.rightPanel, {
        { kind = "text", text = BankGrid.UNSORTED_LABEL, value = "unsorted" },
        { kind = "text", text = "Search", value = "search" },
    }, tabOptions(width, function(_, _, value) self:ShowRightTab(value) end))

    local unsortedPage = self.tabs:GetPage(1).content
    itemArea(unsortedPage, width)
    self.panes.unsorted = self:CreatePane("unsorted", unsortedPage, Size.VIEW_INSET, Size.VIEW_INSET,
        Size.RIGHT_VIEW_WIDTH, Size.UNSORTED_VIEW_HEIGHT, Size.UNSORTED_COLUMNS)

    local searchPage = self.tabs:GetPage(2).content
    local inset, listTop = Size.VIEW_INSET, Size.SEARCH_LIST_TOP - Size.TAB_PAGE_Y
    itemArea(searchPage, width)
    self.itemSearch = prettyui.TextField.new(searchPage, {
        x = inset, y = inset, width = Size.RIGHT_VIEW_WIDTH, height = Size.SEARCH_FIELD_HEIGHT,
        placeholder = "Search items...", maxLength = 80,
        onChange = function(_, _, value) self:RunSearch(value) end,
        onSubmit = function(_, value) self:RunSearch(value) end,
    })
    self.searchList = prettyui.List.new(searchPage, {
        x = inset,
        y = listTop,
        width = Size.RIGHT_VIEW_WIDTH,
        height = Size.SEARCH_LIST_HEIGHT,
        entryHeight = 32,
        maxSelected = 1,
        backgroundColour = 0x00000000,
        borderColour = 0x00000000,
        selectedColour = ROW_SELECTED,
    })
    self.searchHint = prettyui.Text.new(searchPage, {
        text = Parts.SEARCH_HINT,
        x = inset + 10,
        y = listTop + 10,
        width = Size.RIGHT_VIEW_WIDTH - 20,
        height = 120,
        colour = MUTED,
        maxLines = 8,
    })
end

-- Build one row of item actions under both columns
-- These replace the right-click menu, which only Bank Core may change
function LayoutEditorWindow:CreateActions()
    local y = Size.PANEL_TOP + Size.ACTIONS_Y
    for index, action in ipairs({
        { "copyButton", "Copy", function() self:CopySelected() end,
            self.actionTooltips.copyButton },
        { "pasteButton", "Paste", function() self:PasteClipboard() end,
            self.actionTooltips.pasteButton },
        { "removeButton", "Remove", function() self:RemoveSelected() end,
            self.actionTooltips.removeButton },
        { "unsortButton", "Move to Unsorted", function() self:UnarrangeSelected() end,
            self.actionTooltips.unsortButton },
        -- Its drag surface handles clicks too, so the button has no action
        { "newLabelButton", "New label", nil, "Click to add a label above the selection, or drag it onto a row" },
        { "closeButton", "Close", function()
            if self.window ~= nil then self.window:Close() end
        end, "Close the layout editor" },
    }) do
        self[action[1]] = BankControls.button(self.content, action[2], action[3], {
            x = Size.ACTION_X[index], y = y,
            width = Size.ACTION_WIDTH[index], height = Size.BUTTON_HEIGHT,
            tooltip = action[4],
        })
    end
    self.closeButton.root.stylesheetID = id.StyleSheet.BUTTON_CORNERED_BOLD_NEGATIVE
end

-- Build the tag rail, the Layout tab, and the right tabs
function LayoutEditorWindow:CreatePanels()
    self.centerPanel = self:Panel(Size.CENTER_X, Size.CENTER_WIDTH)
    self.rightPanel = self:Panel(Size.RIGHT_X, Size.RIGHT_WIDTH)
    tiledSprite(self.centerPanel, 0, 0, Size.CENTER_WIDTH, Size.COLUMN_HEIGHT, NativeUi.SPRITES.PANEL_BACKGROUND)
    tiledSprite(self.rightPanel, 0, 0, Size.RIGHT_WIDTH, Size.COLUMN_HEIGHT, NativeUi.SPRITES.PANEL_BACKGROUND)
    self:CreateLayoutTab()
    self:CreateTagRail()
    self:CreateRightTabs()
    self:CreateActions()
    self:RunSearch("")
    self:CreateDragSurfaces()
    self:CreateItemNames()
    self:ShowRightTab("unsorted")
    -- Match the bank's outer panel outlines around each header and item area
    frame(self.centerPanel, 0, 0, Size.CENTER_SURFACE_WIDTH, Size.COLUMN_HEIGHT, FRAME)
    frame(self.rightPanel, 0, 0, Size.RIGHT_WIDTH, Size.COLUMN_HEIGHT, FRAME)
end

-- Show one right tab, ending any drag and hiding the other tab's input
-- A tab click calls this too; SetActive without notify does not call back
function LayoutEditorWindow:ShowRightTab(name)
    self:FinishDrag(false)
    -- A held Unsorted scrollbar lets go
    local unsortedView = self.panes.unsorted.view
    if unsortedView.dragStart ~= nil then unsortedView:_StopDrag() end
    self.rightTab = name
    for index, tab in ipairs(RIGHT_TABS) do
        if tab == name then self.tabs:SetActive(index, false) end
    end
    local searching = name == "search"
    self.panes.unsorted.hidden = searching
    self.panes.unsorted.surface.hidden = searching
    self.searchDragSurface.hidden = not searching
    if searching then
        -- The search field is the next thing typed into
        self.keysOnGrid = false
        -- A hidden Unsorted item stays unselected
        local entry = self:SelectedEntry()
        if entry ~= nil and entry.unarranged then
            self.selectedLayoutKey = nil
            self:RefreshCenter()
        end
    end
end

-- Show a failure briefly beside the Layout tab
-- Saves happen on every change, so only problems and copying are shown
function LayoutEditorWindow:ShowError(message, colour)
    self:HideError()
    if self.centerPanel == nil then return end
    local width = Size.CENTER_SURFACE_WIDTH - Size.TAG_NAME_X - Size.VIEW_INSET
    local banner = ui.Layer.new(self.centerPanel)
    banner:SetPos(Size.TAG_NAME_X, Size.TAG_NAME_Y)
    banner:SetSize(width, ERROR_HEIGHT)
    banner.clickthrough = true
    self.tagName.hidden = true
    local text = prettyui.Text.new(banner, {
        text = tostring(message or "Something went wrong."),
        x = 6, y = 0, width = width - 12, height = ERROR_HEIGHT,
        colour = colour or ERROR,
        font = id.Font.MUSEO_SANS_11PT_REGULAR,
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

-- Show a notice in the same header space as errors
function LayoutEditorWindow:ShowNotice(message)
    self:ShowError(message, LABEL_TEXT_COLOUR)
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
    if self.tagName ~= nil then self.tagName.hidden = false end
end

-- Show every tag in the rail, the open one outlined and named
function LayoutEditorWindow:RefreshTags()
    if self.tagRail == nil then return end
    local entries = TagRail.Entries(self.store)
    self.tagRail:SetTags(entries, self.selectedTag)
    local name = ""
    for _, entry in ipairs(entries) do
        if entry.id == self.selectedTag then name = entry.label end
    end
    self.tagName.content = name
end

-- Keep the open tag open under its new name
function LayoutEditorWindow:TagRenamed(oldTag, newTag)
    if self.selectedTag == oldTag then self.selectedTag = newTag end
    if self.history ~= nil and self.history.tag == oldTag then self.history.tag = newTag end
    if self.clipboard ~= nil and self.clipboard.tag == oldTag then self.clipboard.tag = newTag end
end

-- End drags and load the selected tag's layout
function LayoutEditorWindow:SelectTag(tag)
    if type(tag) ~= "string" or tag == "" then tag = nil end
    -- Another tag starts both grids at the top, with no undo steps or copied items
    if tag ~= self.selectedTag then
        self:ClearHistory()
        self.clipboard = nil
        for _, name in ipairs(PANE_NAMES) do self.panes[name].view:SetScrollPosition(0) end
    end
    self.selectedTag = tag
    self:SelectOnly(nil)
    self:RefreshTags()
    self:RefreshCenter()
end

-- Destroy grid decorations and release their references
function LayoutEditorWindow:DestroyCenterNodes()
    destroyAll(self.centerNodes)
    self.centerNodes = {}
end

-- Rebuild both grids from the saved layout, keeping each one's scroll
function LayoutEditorWindow:RefreshCenter()
    self:FinishDrag(false)
    self:DestroyCenterNodes()
    local sorted, unsorted = self.panes.sorted, self.panes.unsorted
    sorted.slots, unsorted.slots, self.centerLabels = {}, {}, {}
    self.usedRows = 0
    if self.selectedTag == nil then
        self:SelectOnly(nil)
        self:UpdateActionTooltips()
        for _, name in ipairs(PANE_NAMES) do
            local pane = self.panes[name]
            pane.view:SetContentHeight(pane.height)
        end
        return
    end

    local columns = Size.CENTER_COLUMNS
    local slots, boundary, labels = self.store:GetLayout(self.selectedTag, columns)
    -- The rows end at the boundary; Unsorted items follow it
    for index, slot in ipairs(slots) do
        if index <= boundary then
            sorted.slots[index] = slot
        elseif slot.unarranged then
            unsorted.slots[#unsorted.slots + 1] = slot
        end
    end
    -- A group keeps only the items still sorted
    self:PruneSelection()
    self:UpdateActionTooltips()
    self.centerLabels = labels
    local labelRows = {}
    for _, label in ipairs(labels) do
        labelRows[label.row] = true
        self.centerNodes[#self.centerNodes + 1] = self:CreateHeading(
            sorted.view.content, Size.GRID_LEFT, BankGrid.LabelY(label.row), label.text)
    end
    local usedRows = boundary // columns
    self.usedRows = usedRows
    -- Keep one empty drop row after the last used row
    self:DrawPane(sorted, usedRows + (usedRows > 0 and 1 or 0), labelRows)
    -- Unsorted packs its items at its own columns
    self:DrawPane(unsorted, math.ceil(#unsorted.slots / unsorted.columns), {})
end

-- Size a pane to its rows, at least its height, and draw each cell not under a label
function LayoutEditorWindow:DrawPane(pane, rowCount, labelRows)
    local columns = pane.columns
    rowCount = math.max(rowCount, math.ceil((pane.height - Size.GRID_TOP) / Size.GRID_STEP))
    pane.view:SetContentHeight(math.max(pane.height, BankGrid.RowItemY(rowCount)))
    for index = 1, rowCount * columns do
        local zero = index - 1
        -- Rows match the live page; columns keep the editor inset
        local row = math.floor(zero / columns)
        if not labelRows[row] then
            local x, y = Size.GRID_LEFT + (zero % columns) * Size.GRID_STEP, BankGrid.RowItemY(row)
            self:CreateGridCell(pane.view.content, x, y, pane.slots[index])
            if pane.name == "sorted" and index == self.pasteCell then
                self.centerNodes[#self.centerNodes + 1] = rectangle(
                    pane.view.content, x, y, Size.GRID_SLOT_SIZE, Size.GRID_SLOT_SIZE, GOLD, false
                )
            end
        end
    end
    if pane.surface ~= nil then pane.surface:MoveToFront() end
end

-- Draw one grid cell and the item saved in it, if any
function LayoutEditorWindow:CreateGridCell(parent, x, y, slot)
    local grid = ui.Sprite.new(parent)
    grid:SetPos(x, y)
    grid:SetSize(Size.GRID_SLOT_SIZE, Size.GRID_SLOT_SIZE)
    grid.spriteID = GRID_SLOT_SPRITE
    grid.alpha = 0.34
    grid.clickthrough = true
    self.centerNodes[#self.centerNodes + 1] = grid

    if type(slot) ~= "table" or slot.kind ~= "item" then return end
    local objectID = math.tointeger(tonumber(slot.objectID))
    if objectID ~= nil then
        local sprite = ui.Sprite.new(parent)
        local width, height = self:ApplyRuntimeObjectSprite(
            sprite, objectID, slot.layoutKey, true
        )
        sprite:SetPos(
            x + math.floor((Size.GRID_SLOT_SIZE - width) / 2),
            y + math.floor((Size.GRID_SLOT_SIZE - height) / 2)
        )
        self.centerNodes[#self.centerNodes + 1] = sprite
    end
    if self:IsSelected(slot.layoutKey) then
        local selection = rectangle(
            parent, x, y, Size.GRID_SLOT_SIZE, Size.GRID_SLOT_SIZE, GOLD, false
        )
        self.centerNodes[#self.centerNodes + 1] = selection
    end
end

-- Draw a heading like the bank's own, text over a line
function LayoutEditorWindow:CreateHeading(parent, x, y, value)
    local width = Size.CENTER_COLUMNS * Size.GRID_STEP - (Size.GRID_STEP - Size.GRID_SLOT_SIZE)
    local header = ui.Layer.new(parent)
    header:SetPos(x, y)
    header:SetSize(width, Size.LABEL_LINE_OFFSET + 1)
    header.clickthrough = true
    local text = prettyui.Text.new(header, {
        text = value,
        x = 0, y = 0, width = width, height = Size.LABEL_LINE_OFFSET,
        colour = LABEL_TEXT_COLOUR,
        font = id.Font.MUSEO_SANS_11PT_REGULAR,
        maxLines = 1,
    })
    text.clickthrough = true
    rectangle(header, 0, Size.LABEL_LINE_OFFSET, width, 1, LABEL_LINE_COLOUR, true)
    return header
end

-- Return the grid row under a point in a pane's view, counting its scroll
function LayoutEditorWindow:RowAt(pane, x, y)
    x, y = tonumber(x), tonumber(y)
    if pane == nil or x == nil or y == nil or x < Size.GRID_LEFT or y < 0
        or x >= pane.width or y >= pane.height then return nil end
    return BankGrid.RowAtContentY(y + (tonumber(pane.view.scrollY) or 0))
end

-- Return the label row under a pane point; only the sorted pane has labels
function LayoutEditorWindow:LabelRowAt(pane, x, y)
    if pane == nil or pane.name ~= "sorted" then return nil end
    local row = self:RowAt(pane, x, y)
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
            local saved, reason = self:RecordEdit(tag, function()
                return self.store:SetLabel(tag, row, value, Size.CENTER_COLUMNS)
            end)
            if not saved then return false, reason end
            self:LabelChanged(tag)
            return true, nil
        end,
        onDelete = function()
            local saved, reason = self:RecordEdit(tag, function()
                return self.store:RemoveLabel(tag, row, Size.CENTER_COLUMNS)
            end)
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
            local saved, reason = self:RecordEdit(tag, function()
                return self.store:InsertLabel(tag, row, value, Size.CENTER_COLUMNS)
            end)
            if not saved then return false, reason end
            self:LabelChanged(tag)
            return true, nil
        end,
    })
    return true
end

-- Find the sorted grid row under the pointer for a right-click menu
-- Only the sorted items count, not its scrollbar, the other panes, or a covering window
function LayoutEditorWindow:RowMenuTarget()
    if self.window == nil or self.window.root.hidden or self.drag ~= nil
        or self.selectedTag == nil or self:OverlayShown() then return nil end
    local x, y = self:ContentPointer()
    local pane, paneX, paneY = self:PaneAt(x, y)
    if pane == nil or pane.name ~= "sorted" or paneX >= pane.width - Size.SCROLLBAR_RESERVE then return nil end
    local row = self:RowAt(pane, paneX, paneY)
    if row == nil then return nil end
    local index = self:SlotIndexAt(pane, paneX, paneY)
    local slot = index ~= nil and pane.slots[index] or nil
    return {
        tag = self.selectedTag,
        row = row,
        usedRows = self.usedRows,
        columns = Size.CENTER_COLUMNS,
        data = self.store.data,
        layoutKey = type(slot) == "table" and slot.kind == "item" and slot.layoutKey or nil,
    }
end

-- Check that a menu's row still means the same place in this editor
function LayoutEditorWindow:RowTargetCurrent(target)
    return self.window ~= nil and not self.window.root.hidden and self.drag == nil
        and self.selectedTag == target.tag
        and self.store.data == target.data
        and Size.CENTER_COLUMNS == target.columns
end

-- Insert an empty row at a grid line, moving the rows below it down
function LayoutEditorWindow:InsertEmptyRow(line)
    local saved, reason = self:RecordEdit(self.selectedTag, function()
        return self.store:InsertLayoutRow(self.selectedTag, line, Size.CENTER_COLUMNS)
    end)
    if not saved then
        self:ShowError(reason or "Could not add the row.")
        return false
    end
    self:RefreshCenter()
    self:NotifyChanged()
    return true
end

-- Describe what removing a line takes out of the tag
local function removeRowMessage(tag, contents)
    local name = "<col=ffcb05>\"" .. tostring(tag) .. "\"</col>"
    if contents.label ~= nil then
        return "Remove the label <col=ffcb05>\"" .. contents.label .. "\"</col> from " .. name
            .. "?<br>The rows below it move up."
    end
    local parts = {}
    if contents.items > 0 then
        parts[#parts + 1] = contents.items .. (contents.items == 1 and " item" or " items")
    end
    if contents.reserved > 0 then
        parts[#parts + 1] = contents.reserved .. (contents.reserved == 1 and " reserved slot" or " reserved slots")
    end
    return "Remove this row and its " .. table.concat(parts, " and ") .. " from " .. name
        .. "?<br>Only the tag changes; your bank keeps every item."
end

-- Remove a grid line and everything on it, moving the rows below it up
-- An empty line goes at once; anything else asks first
function LayoutEditorWindow:RemoveRow(line)
    local tag = self.selectedTag
    local contents = tag ~= nil and self.store:LayoutLineContents(tag, line, Size.CENTER_COLUMNS) or nil
    if contents == nil then return false end
    if contents.empty then return self:SaveRowRemoval(tag, line) end
    if self.onConfirmRemoveRow == nil then return false end
    local target = { tag = tag, row = line, columns = Size.CENTER_COLUMNS, data = self.store.data }
    self.onConfirmRemoveRow({
        message = removeRowMessage(tag, contents),
        onConfirm = function()
            -- Any save, another tag or size, or a closed editor makes it out of date
            if not self:RowTargetCurrent(target) then
                return false, "The layout changed, so the row was not removed. Cancel and try again."
            end
            return self:SaveRowRemoval(tag, line)
        end,
    })
    return true
end

-- Save a line's removal as one undo step
function LayoutEditorWindow:SaveRowRemoval(tag, line)
    local saved, reason = self:RecordEdit(tag, function()
        return self.store:RemoveLayoutRow(tag, line, Size.CENTER_COLUMNS)
    end)
    if not saved then
        self:ShowError(reason or "Could not remove the row.")
        return false, reason
    end
    self:RefreshCenter()
    self:NotifyChanged()
    return true, nil
end

-- Convert a pane point to its grid slot, skipping label rows
function LayoutEditorWindow:SlotIndexAt(pane, x, y)
    local row = self:RowAt(pane, x, y)
    if row == nil or self:LabelRowAt(pane, x, y) ~= nil then return nil end
    local column = math.floor((tonumber(x) - Size.GRID_LEFT) / Size.GRID_STEP)
    if column < 0 or column >= pane.columns then return nil end
    return row * pane.columns + column + 1
end

-- Find the shown pane under an editor content point, and the point in its view
function LayoutEditorWindow:PaneAt(x, y)
    x, y = tonumber(x), tonumber(y)
    if x == nil or y == nil or self.panes == nil then return nil end
    for _, name in ipairs(PANE_NAMES) do
        local pane = self.panes[name]
        if not pane.hidden and x >= pane.x and x < pane.x + pane.width
            and y >= pane.y and y < pane.y + pane.height then
            return pane, x - pane.x, y - pane.y
        end
    end
    return nil
end

-- Keep the editor above native bank redraws and name the hovered item
function LayoutEditorWindow:PollDrag()
    self:KeepOnTop()
    self:TickError()
    self:UpdateItemName()
end

-- Stop the listener that keeps the editor on top
function LayoutEditorWindow:StopDragPolling()
    Event.Logic.Unsubscribe(DRAG_EVENT)
end

-- Find the layout entry matching the selection in either pane
function LayoutEditorWindow:SelectedEntry()
    if self.selectedLayoutKey == nil or self.panes == nil then return nil end
    for _, name in ipairs(PANE_NAMES) do
        for _, slot in ipairs(self.panes[name].slots) do
            if type(slot) == "table" and slot.kind == "item"
                and slot.layoutKey == self.selectedLayoutKey then return slot end
        end
    end
    return nil
end

-- Move the selected item to Unsorted, keeping it tagged
function LayoutEditorWindow:UnarrangeSelected()
    if self:RefuseForGroup() then return false end
    local entry = self:SelectedEntry()
    if entry == nil or self.selectedTag == nil then
        self:ShowError("Select a layout item first.")
        return false
    end
    if entry.unarranged then
        self:ShowError("That item is already in Unsorted.")
        return false
    end
    local saved, reason = self:RecordEdit(self.selectedTag, function()
        return self.store:UnarrangeLayoutItem(self.selectedTag, entry.layoutKey)
    end)
    if not saved then self:ShowError(reason); return false end
    self.selectedLayoutKey = nil
    self:RefreshCenter()
    self:NotifyChanged()
    return true
end

-- Untag the selected item, keeping other grid positions
function LayoutEditorWindow:RemoveSelected()
    if self:RefuseForGroup() then return false end
    local entry = self:SelectedEntry()
    if entry == nil or self.selectedTag == nil then
        self:ShowError("Select a layout item first.")
        return false
    end
    local saved, reason = self:RecordEdit(self.selectedTag, function()
        return self.store:RemoveTag(self.selectedTag, entry.layoutKey)
    end)
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
    self:DestroyItemNames()
    for _, name in ipairs(PANE_NAMES) do
        local pane = self.panes ~= nil and self.panes[name] or nil
        if pane ~= nil then
            for _, part in ipairs({ pane.surface, pane.view }) do pcall(function() part:Destroy() end) end
        end
    end
    self.panes = nil
    for _, surface in ipairs({ self.searchDragSurface, self.labelDragSurface }) do
        if surface ~= nil then pcall(function() surface:Destroy() end) end
    end
    self.searchDragSurface = nil
    self.labelDragSurface = nil
    for _, control in ipairs({
        self.searchHint,
        self.searchList,
        self.itemSearch,
        self.newLabelButton,
        self.unsortButton,
        self.removeButton,
        self.pasteButton,
        self.copyButton,
        self.tagRail,
        self.tagName,
        self.closeButton,
    }) do
        if control ~= nil then pcall(function() control:Destroy() end) end
    end
    -- The tabs own their pages and destroy them
    for _, tabs in ipairs({ self.layoutTabs, self.tabs }) do
        pcall(function() tabs:Destroy() end)
    end
    self.tabs = nil
    self.layoutTabs = nil
    self.tagRail = nil
    self.tagName = nil
    self.searchHint = nil
    self.searchList = nil
    self.itemSearch = nil
    self:HideError()
    self.newLabelButton = nil
    self.closeButton = nil
    self.unsortButton = nil
    self.removeButton = nil
    self.pasteButton = nil
    self.copyButton = nil
end

-- Stop events and drags, then destroy the editor
function LayoutEditorWindow:Destroy()
    self:StopDragPolling()
    self:StopShortcuts()
    self:ClearHistory()
    self:FinishDrag(false)
    self:ClearSearchInteractions()
    self:DestroyCenterNodes()
    self:DestroyControls()
    if self.window ~= nil then pcall(function() self.window:Destroy() end) end
    self.window = nil
    self.content = nil
    self.onChanged = nil
    self.onClose = nil
    self.onPromptLabel = nil
    self.overlayWindows = {}
end

return LayoutEditorWindow
