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
        onEditTag = options.onEditTag,
        onPromptLabel = options.onPromptLabel,
        overlayWindows = {},
        searchResults = {},
        centerNodes = {},
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
            self.onEditTag = nil
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

-- Build the open tag's name and Rename above the sorted grid
function LayoutEditorWindow:CreateTitle()
    local x, y = Size.CENTER_X, Size.PANEL_TOP
    self.tagTitle = prettyui.Text.new(self.content, {
        text = "",
        x = x + 4,
        y = y,
        width = Size.CENTER_SURFACE_WIDTH - Size.EDIT_TAG_WIDTH - Size.BUTTON_GAP * 2 - 4,
        height = Size.TITLE_HEIGHT,
        colour = LABEL_TEXT_COLOUR,
        maxLines = 1,
    })
    self.editTagButton = BankControls.button(self.content, "Rename", function() self:EditTag() end, {
        x = x + Size.CENTER_SURFACE_WIDTH - Size.EDIT_TAG_WIDTH, y = y,
        width = Size.EDIT_TAG_WIDTH, height = Size.TITLE_HEIGHT,
        tooltip = "Rename this tag or change its icon",
    })
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

-- Build the Unsorted and Search tabs; their pages start under the tab header
function LayoutEditorWindow:CreateRightTabs()
    self.tabs = prettyui.Tabs.new(self.rightPanel, {
        { kind = "text", text = BankGrid.UNSORTED_LABEL, value = "unsorted" },
        { kind = "text", text = "Search", value = "search" },
    }, {
        x = Size.RIGHT_INSET,
        y = Size.TAB_Y,
        width = Size.RIGHT_VIEW_WIDTH,
        height = Size.ACTIONS_Y - Size.RIGHT_INSET - Size.TAB_Y,
        scrollable = false,
        onChange = function(_, _, value) self:ShowRightTab(value) end,
    })

    local width = Size.RIGHT_VIEW_WIDTH
    local unsortedPage = self.tabs:GetPage(1).content
    rectangle(unsortedPage, 0, 0, width, Size.UNSORTED_VIEW_HEIGHT, VIEW_BACKGROUND, true)
    frame(unsortedPage, 0, 0, width, Size.UNSORTED_VIEW_HEIGHT, INNER_FRAME)
    self.panes.unsorted = self:CreatePane("unsorted", unsortedPage, 0, 0,
        width, Size.UNSORTED_VIEW_HEIGHT, Size.UNSORTED_COLUMNS)

    local searchPage = self.tabs:GetPage(2).content
    local listTop = Size.SEARCH_LIST_TOP - Size.TAB_PAGE_Y
    self.itemSearch = prettyui.TextField.new(searchPage, {
        x = 0, y = 0, width = width, height = Size.SEARCH_FIELD_HEIGHT,
        placeholder = "Search items...", maxLength = 80,
        onChange = function(_, _, value) self:RunSearch(value) end,
        onSubmit = function(_, value) self:RunSearch(value) end,
    })
    self.searchList = prettyui.List.new(searchPage, {
        x = 0,
        y = listTop,
        width = width,
        height = Size.SEARCH_LIST_HEIGHT,
        entryHeight = 32,
        maxSelected = 1,
        backgroundColour = 0x00000000,
        borderColour = INNER_FRAME,
        selectedColour = ROW_SELECTED,
    })
    self.searchHint = prettyui.Text.new(searchPage, {
        text = Parts.SEARCH_HINT,
        x = 10,
        y = listTop + 10,
        width = width - 20,
        height = 120,
        colour = MUTED,
        maxLines = 8,
    })
end

-- Build the item actions and help under the right tabs, two buttons a row
-- These replace the right-click menu, which only Bank Core may change
function LayoutEditorWindow:CreateActions()
    local x, y = Size.RIGHT_INSET, Size.ACTIONS_Y
    local half, height = Size.HALF_BUTTON_WIDTH, Size.BUTTON_HEIGHT
    self.duplicateButton = BankControls.button(
        self.rightPanel, "Create Copy", function() self:DuplicateSelected() end,
        { x = x, y = y, width = half, height = height, tooltip = "Copy the selected item (Ctrl+C)" }
    )
    self.removeButton = BankControls.button(
        self.rightPanel, "Remove", function() self:RemoveSelected() end,
        { x = Size.LABEL_BUTTON_X, y = y, width = Size.LABEL_BUTTON_WIDTH, height = height,
            tooltip = "Remove the selected item (Delete)" }
    )
    self.unsortButton = BankControls.button(
        self.rightPanel, "Move to Unsorted", function() self:UnarrangeSelected() end,
        { x = x, y = Size.LABEL_BUTTON_Y, width = half, height = height }
    )
    -- Its drag surface handles clicks too, so the button has no action
    self.newLabelButton = BankControls.button(self.rightPanel, "New label", nil, {
        x = Size.LABEL_BUTTON_X, y = Size.LABEL_BUTTON_Y,
        width = Size.LABEL_BUTTON_WIDTH, height = height,
    })
    self.actionsHelp = prettyui.Text.new(self.rightPanel, {
        text = Parts.ACTIONS_HELP,
        x = x, y = Size.LABEL_BUTTON_Y + Size.BUTTON_STEP,
        width = Size.RIGHT_VIEW_WIDTH, height = Size.HELP_HEIGHT,
        colour = MUTED,
        font = id.Font.MUSEO_SANS_11PT_REGULAR,
        maxLines = 2,
    })
end

-- Build the shortcut and saved notes under the sorted grid
function LayoutEditorWindow:CreateFooter()
    local width = Size.CENTER_SURFACE_WIDTH - 8
    self.footerNotes = {}
    for _, note in ipairs({
        { text = Parts.SHORTCUTS, align = ui.AlignMode.TOPLEFT },
        { text = Parts.SAVED, align = ui.AlignMode.BOTTOMRIGHT },
    }) do
        self.footerNotes[#self.footerNotes + 1] = prettyui.Text.new(self.centerPanel, {
            text = note.text,
            x = 4, y = Size.FOOTER_Y, width = width, height = Size.FOOTER_HEIGHT,
            colour = MUTED,
            font = id.Font.MUSEO_SANS_11PT_REGULAR,
            alignHorizontal = note.align,
            maxLines = 1,
        })
    end
end

-- Build the tag rail, sorted grid, and right tabs
function LayoutEditorWindow:CreatePanels()
    self.centerPanel = self:Panel(Size.CENTER_X, Size.CENTER_WIDTH)
    self.rightPanel = self:Panel(Size.RIGHT_X, Size.RIGHT_WIDTH)

    self.centerBackground = tiledSprite(
        self.centerPanel, 0, 0, Size.CENTER_WIDTH, Size.PANEL_HEIGHT,
        NativeUi.SPRITES.PANEL_BACKGROUND
    )
    self.centerSurface = rectangle(
        self.centerPanel, 0, Size.SORTED_TOP,
        Size.CENTER_SURFACE_WIDTH, Size.CENTER_SURFACE_HEIGHT,
        VIEW_BACKGROUND, true
    )
    self.centerFrame = frame(
        self.centerPanel, 0, Size.SORTED_TOP,
        Size.CENTER_SURFACE_WIDTH, Size.CENTER_SURFACE_HEIGHT, FRAME
    )
    self.panes = {
        sorted = self:CreatePane("sorted", self.centerPanel, Size.CENTER_VIEW_X, Size.SORTED_VIEW_Y,
            Size.CENTER_VIEW_WIDTH, Size.SORTED_VIEW_HEIGHT, Size.CENTER_COLUMNS),
    }
    self:CreateFooter()
    self:CreateTagRail()
    self:CreateTitle()
    self.rightBackground = tiledSprite(
        self.rightPanel, 0, 0, Size.RIGHT_WIDTH, Size.PANEL_HEIGHT,
        NativeUi.SPRITES.PANEL_BACKGROUND
    )
    self.rightFrame = frame(
        self.rightPanel, 0, 0, Size.RIGHT_WIDTH, Size.PANEL_HEIGHT, FRAME
    )
    self:CreateRightTabs()
    self:CreateActions()
    self:RunSearch("")
    self:CreateDragSurfaces()
    for _, edges in ipairs({ self.centerFrame, self.rightFrame }) do
        for _, edge in ipairs(edges) do edge:MoveToFront() end
    end
    self:ShowRightTab("unsorted")
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

-- Show a failure briefly over the grid
-- Saves happen on every change, so only problems are shown
function LayoutEditorWindow:ShowError(message)
    self:HideError()
    if self.centerPanel == nil then return end
    local width = Size.CENTER_SURFACE_WIDTH - ERROR_INSET * 2
    local banner = ui.Layer.new(self.centerPanel)
    banner:SetPos(ERROR_INSET, Size.FOOTER_Y - ERROR_HEIGHT - ERROR_INSET)
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

-- Show every tag in the rail and the open one's name above the grid
function LayoutEditorWindow:RefreshTags()
    if self.tagRail == nil then return end
    local entries = TagRail.Entries(self.store)
    self.tagRail:SetTags(entries, self.selectedTag)
    local title = "No tags"
    for _, entry in ipairs(entries) do
        if entry.id == self.selectedTag then title = entry.label end
    end
    self.tagTitle.content = title
    self.editTagButton:SetDisabled(self.selectedTag == nil)
end

-- Open the open tag's settings to rename it or change its icon
function LayoutEditorWindow:EditTag()
    if self.selectedTag == nil or self.onEditTag == nil then return false end
    -- Tag settings has a name field of its own
    self.keysOnGrid = false
    self.onEditTag(self.selectedTag)
    return true
end

-- Keep the open tag open under its new name
function LayoutEditorWindow:TagRenamed(oldTag, newTag)
    if self.selectedTag == oldTag then self.selectedTag = newTag end
end

-- End drags and load the selected tag's layout
function LayoutEditorWindow:SelectTag(tag)
    if type(tag) ~= "string" or tag == "" then tag = nil end
    -- Another tag starts both grids at the top
    if tag ~= self.selectedTag then
        for _, name in ipairs(PANE_NAMES) do self.panes[name].view:SetScrollPosition(0) end
    end
    self.selectedTag = tag
    self.selectedLayoutKey = nil
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
    if self.selectedTag == nil then
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
    self.centerLabels = labels
    local labelRows = {}
    for _, label in ipairs(labels) do
        labelRows[label.row] = true
        self.centerNodes[#self.centerNodes + 1] = self:CreateHeading(
            sorted.view.content, Size.GRID_LEFT, BankGrid.LabelY(label.row), label.text)
    end
    local usedRows = boundary // columns
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
            self:CreateGridCell(pane.view.content, Size.GRID_LEFT + (zero % columns) * Size.GRID_STEP,
                BankGrid.RowItemY(row), pane.slots[index])
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
    if slot.layoutKey == self.selectedLayoutKey then
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

-- Keep the editor above native bank redraws
function LayoutEditorWindow:PollDrag()
    self:KeepOnTop()
    self:TickError()
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
        self.duplicateButton,
        self.actionsHelp,
        self.tagRail,
        self.tagTitle,
        self.editTagButton,
    }) do
        if control ~= nil then pcall(function() control:Destroy() end) end
    end
    -- The tabs own their pages and destroy them
    if self.tabs ~= nil then pcall(function() self.tabs:Destroy() end) end
    self.tabs = nil
    destroyAll(self.footerNotes)
    self.footerNotes = nil
    self.tagRail = nil
    self.tagTitle = nil
    self.editTagButton = nil
    self.searchHint = nil
    self.searchList = nil
    self.itemSearch = nil
    self:HideError()
    self.newLabelButton = nil
    self.unsortButton = nil
    self.removeButton = nil
    self.duplicateButton = nil
    self.actionsHelp = nil
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
    self.onEditTag = nil
    self.onPromptLabel = nil
    self.overlayWindows = {}
end

return LayoutEditorWindow
