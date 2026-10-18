-- Build the standalone layout editor: its window, sidebar, grid, labels, and item
-- actions. Drag gestures and catalog search are in layout_editor_drag.lua and
-- layout_editor_search.lua; measurements are shared through layout_editor_parts.lua

local StorageKeys = require("lib/features/storage_keys")
local BankInterface = require("lib/core/bank_interface")
local BankItemIdentity = require("lib/bank/bank_item_identity")
local NativeUi = require("lib/ui/native_ui")
local BankControls = require("lib/ui/bank_controls")
local BankGrid = require("lib/engine/bank_grid")
local NativeItemMenuGuard = require("lib/bank/native_item_menu_guard")
local TagSidebar = require("lib/features/tags/tag_sidebar")
local Parts = require("lib/features/tags/layout_editor_parts")
local Size = Parts.size
local rectangle = Parts.rectangle
local tiledSprite = Parts.tiledSprite
local frame = Parts.frame
local Theme = require("lib/ui/theme")

local LayoutEditorWindow = {}
LayoutEditorWindow.__index = LayoutEditorWindow
-- Drag gestures and catalog search live in their own files
require("lib/features/tags/layout_editor_drag").install(LayoutEditorWindow)
require("lib/features/tags/layout_editor_search").install(LayoutEditorWindow)

-- The editor's sidebar is the bank sidebar with its tabs held on Tags and its
-- footer button closing the editor. This host answers the sidebar's questions
-- about bank state, which the editor does not have
local EditorSidebar = {}
EditorSidebar.__index = EditorSidebar
TagSidebar.install(EditorSidebar)

-- Create the host that connects a sidebar to one editor
function EditorSidebar.new(editor, options)
    return setmetatable({
        editor = editor,
        store = options.store,
        settings = options.settings or {},
        onOpenSettings = options.onOpenSettings,
        onEditLayout = function()
            if editor.window ~= nil then editor.window:Close() end
        end,
        selectedTag = editor.selectedTag,
        searchQuery = "",
        expanded = true,
        tagTooltips = {},
        sidebarLocksMode = true,
        sidebarEditButton = { spriteName = "CROSS", tooltip = "Close layout editor" },
    }, EditorSidebar)
end

-- The editor only edits ordinary tags
function EditorSidebar:IsCleanupMode() return false end
function EditorSidebar:IsRuneSQLMode() return false end
function EditorSidebar:IsPresetViewOpen() return false end
function EditorSidebar:IsGeneratedSelection() return false end
function EditorSidebar:IsRuneQuerySelection() return false end
function EditorSidebar:SetSidebarMode() end

-- Load a chosen tag; clicking the selected tag again keeps it open
function EditorSidebar:SetSelectedTag(tag)
    if tag == nil then
        self:RefreshTags()
        return
    end
    self.editor:SelectTag(tag)
end

LayoutEditorWindow.EditorSidebar = EditorSidebar

-- Open the new-tag draft, which selects the tag once it is saved
function EditorSidebar:CreatePlaceholderTag()
    self.editor:CreateNewTag()
end

-- Tell the bank about order and folder changes made here, so its sidebar matches
local function notifyTagsChanged(sidebar, changed)
    local onChanged = sidebar.editor.onChanged
    if changed and onChanged ~= nil then onChanged(nil) end
    return changed
end

-- Reorder a tag or folder and refresh the bank's sidebar too
function EditorSidebar:MoveTagSidebarEntry(entryID, offset)
    return notifyTagsChanged(self, TagSidebar.MoveTagSidebarEntry(self, entryID, offset))
end

-- Collapse or expand a folder and refresh the bank's sidebar too
function EditorSidebar:ToggleFolder(folderKey)
    return notifyTagsChanged(self, TagSidebar.ToggleFolder(self, folderKey))
end

-- Errors show over the bottom of the grid for about four seconds, fading out
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
local NATIVE_ITEM_WIDTH = 36
local NATIVE_ITEM_HEIGHT = 32
local PLACEHOLDER_ALPHA = 0.45
local PLACEHOLDER_QUANTITY_MODE = ui.ObjectQuantityDisplayMode.ALWAYS or 2
local GRID_SLOT_SPRITE = id.Sprite.RS3_ICON_SLOT_40PX_1
local LABEL_TEXT_COLOUR = Theme.HEADING_TEXT
local LABEL_LINE_COLOUR = Theme.HEADING_LINE
local BANK_ITEMS_STATIC_ID = BankInterface.ITEMS
local DRAG_EVENT = StorageKeys.PLUGIN_REF .. "_layout_editor_drag"

-- Find a native bank component by its interface slot
local component = BankInterface.Find

-- Read a native style field that may be unavailable during a bank rebuild
local function componentValue(value, key)
    local ok, result = pcall(function() return value[key] end)
    return ok and result or nil
end

-- Read the mounted bank's bounds so the editor can align with it
local function bankWindowGeometry()
    local ok, value = pcall(function()
        return ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__BANK_WINDOW)
    end)
    if not ok or value == nil then return nil end
    local x = tonumber(componentValue(value, "x"))
    local y = tonumber(componentValue(value, "y"))
    local width = tonumber(componentValue(value, "width"))
    local height = tonumber(componentValue(value, "height"))
    if x == nil or y == nil or width == nil or height == nil then return nil end
    return { x = x, y = y, width = width, height = height }
end

-- Destroy recorded UI nodes in reverse order, allowing host-removed components
local function destroyAll(values)
    for index = #(values or {}), 1, -1 do
        pcall(function() values[index]:Destroy() end)
    end
end

-- Create the standalone tag layout editor and connect its controls and cleanup callbacks
function LayoutEditorWindow.new(parent, options)
    options = options or {}
    local self = setmetatable({
        store = options.store,
        selectedTag = options.tag,
        onChanged = options.onChanged,
        onClose = options.onClose,
        onOpenSettings = options.onOpenSettings,
        onCreateTag = options.onCreateTag,
        onPromptLabel = options.onPromptLabel,
        overlayWindow = nil,
        searchResults = {},
        centerNodes = {},
        centerSlots = {},
        centerLabels = {},
        selectedLayoutKey = nil,
        drag = nil,
        runtimeStylesByLayoutKey = {},
        runtimeStylesByObjectID = {},
    }, LayoutEditorWindow)

    local bankGeometry = bankWindowGeometry()
    Parts.SizeToBank(Parts.BankColumns(), bankGeometry and bankGeometry.width, bankGeometry and bankGeometry.height)
    self.window = prettyui.Window.new(parent, {
        title = "Bank Layout Editor",
        x = bankGeometry ~= nil and bankGeometry.x or -math.floor(Size.WIDTH / 2),
        y = bankGeometry ~= nil and bankGeometry.y or -math.floor(Size.HEIGHT / 2),
        xAnchor = bankGeometry ~= nil and 0 or 0.5,
        yAnchor = bankGeometry ~= nil and 0 or 0.5,
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
            self:FinishDrag(false)
            self:ClearSearchInteractions()
            self:DestroyCenterNodes()
            self:DestroyControls()
            local onClose = self.onClose
            self.onClose = nil
            self.onChanged = nil
            self.onPromptLabel = nil
            self.overlayWindow = nil
            if onClose ~= nil then onClose(self) end
        end,
    })
    -- This is a modal editing surface rather than a floating utility. Remove
    -- PrettyUI's title-bar drag capture so the bank-sized window remains fixed
    if self.window.titleDrag ~= nil then
        pcall(function() self.window.titleDrag:Destroy() end)
        self.window.titleDrag = nil
    end
    self.content = self.window.content
    self.sidebar = EditorSidebar.new(self, options)
    self:CaptureRuntimeStyles()
    self:CreatePanels()
    self:RefreshTags()
    if self.selectedTag == nil then
        local tags = self.store:AllTags()
        self.selectedTag = tags[1]
    end
    self:SelectTag(self.selectedTag)
    Event.Logic.Unsubscribe(DRAG_EVENT)
    Event.Logic.Subscribe(DRAG_EVENT, function() self:PollDrag() end)
    return self
end

-- Create one editor column at its fixed panel offset
function LayoutEditorWindow:Panel(x, width)
    local panel = ui.Layer.new(self.content)
    panel:SetPos(x, Size.PANEL_TOP)
    panel:SetSize(width, Size.PANEL_HEIGHT)
    panel.clickthrough = true
    return panel
end

-- Remember native item appearance for the editor's runtime object sprites
function LayoutEditorWindow:CaptureRuntimeStyles()
    self.runtimeStylesByLayoutKey = {}
    self.runtimeStylesByObjectID = {}
    local itemLayer = component(BANK_ITEMS_STATIC_ID)
    if itemLayer == nil then return false end

    local entries = BankItemIdentity.Collect(itemLayer)
    for _, entry in ipairs(entries) do
        local native = entry.component
        local style = {
            width = tonumber(componentValue(native, "width")) or NATIVE_ITEM_WIDTH,
            height = tonumber(componentValue(native, "height")) or NATIVE_ITEM_HEIGHT,
            quantity = tonumber(componentValue(native, "associatedObjectQuantity")),
            quantityMode = componentValue(native, "associatedObjectQuantityMode"),
            outlineWidth = componentValue(native, "outlineWidth"),
            shadowRGBA = componentValue(native, "shadowRGBA"),
        }
        self.runtimeStylesByLayoutKey[entry.layoutKey] = style
        local existing = self.runtimeStylesByObjectID[entry.objectID]
        -- A real bank stack is a better source than a zero-quantity placeholder
        -- when both exist for the same object
        if existing == nil
            or ((style.quantity or 0) > 0 and (existing.quantity or 0) <= 0) then
            self.runtimeStylesByObjectID[entry.objectID] = style
        end
    end
    return #entries > 0
end

-- Choose the exact copy's native appearance before falling back to the object's appearance
function LayoutEditorWindow:RuntimeStyle(objectID, layoutKey)
    local byLayout = type(layoutKey) == "string"
        and self.runtimeStylesByLayoutKey[layoutKey] or nil
    if byLayout ~= nil then return byLayout end
    objectID = math.tointeger(tonumber(objectID))
    return objectID ~= nil and self.runtimeStylesByObjectID[objectID] or nil
end

-- Use native object rendering and show absent layout entries as placeholders
function LayoutEditorWindow:ApplyRuntimeObjectSprite(
    sprite, objectID, layoutKey, absentIsPlaceholder
)
    local style = self:RuntimeStyle(objectID, layoutKey)
    local width = style ~= nil and style.width or NATIVE_ITEM_WIDTH
    local height = style ~= nil and style.height or NATIVE_ITEM_HEIGHT
    sprite:SetSize(width, height)
    -- SetAssociatedObject asks the client for its live runtime object sprite;
    -- spriteID-backed icons do not reproduce the native bank rendering
    sprite:SetAssociatedObject(math.tointeger(tonumber(objectID)))
    if style ~= nil then
        if style.quantity ~= nil then
            sprite.associatedObjectQuantity = style.quantity
        end
        if style.quantityMode ~= nil then
            sprite.associatedObjectQuantityMode = style.quantityMode
        elseif style.quantity ~= nil then
            sprite.associatedObjectQuantityMode = ui.ObjectQuantityDisplayMode.MULTIPLE
        end
        if style.outlineWidth ~= nil then sprite.outlineWidth = style.outlineWidth end
        if style.shadowRGBA ~= nil then sprite.shadowRGBA = style.shadowRGBA end
        sprite.alpha = style.quantity ~= nil and style.quantity <= 0
            and PLACEHOLDER_ALPHA or 1
    elseif absentIsPlaceholder then
        sprite.associatedObjectQuantity = 0
        sprite.associatedObjectQuantityMode = PLACEHOLDER_QUANTITY_MODE
        sprite.alpha = PLACEHOLDER_ALPHA
    else
        sprite.associatedObjectQuantityMode = ui.ObjectQuantityDisplayMode.NEVER
        sprite.alpha = 1
    end
    sprite.clickthrough = true
    return width, height
end

-- Align the editor with the bank and keep it above rebuilt native components
function LayoutEditorWindow:KeepOnTop()
    if self.window == nil or self.window.root == nil then return end
    pcall(function()
        local geometry = bankWindowGeometry()
        if geometry ~= nil
            and (self.window.root.x ~= geometry.x
                or self.window.root.y ~= geometry.y) then
            self.window.root:SetPos(geometry.x, geometry.y, 0, 0)
        end
        self.window.root:MoveToFront()
        if self.window._SyncOverlays ~= nil then self.window:_SyncOverlays(false) end
        -- A prompt opened from the editor would otherwise sink behind it
        local overlay = self.overlayWindow
        if overlay ~= nil and overlay.root ~= nil and not overlay.root.hidden then
            overlay.root:MoveToFront()
            if overlay._SyncOverlays ~= nil then overlay:_SyncOverlays(false) end
        end
    end)
end

-- Keep a window opened from the editor, such as the label prompt, in front of it
function LayoutEditorWindow:SetOverlay(window)
    self.overlayWindow = window
    self:KeepOnTop()
end

-- Build the tag selector, editable grid, and catalog search columns
function LayoutEditorWindow:CreatePanels()
    self.sidebar:CreateRail(self.content, Size.PANEL_HEIGHT, Size.LEFT_X, Size.PANEL_TOP)
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
    self.duplicateButton = BankControls.button(
        self.centerPanel, "Create Copy", function() self:DuplicateSelected() end,
        { x = 8, y = Size.FOOTER_Y, width = 104, height = Size.FOOTER_HEIGHT }
    )
    self.removeButton = BankControls.button(
        self.centerPanel, "Remove", function() self:RemoveSelected() end,
        { x = 120, y = Size.FOOTER_Y, width = 84, height = Size.FOOTER_HEIGHT }
    )
    -- Its drag surface handles both clicks and drags, so the button has no action
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
        height = 72,
        colour = MUTED,
        maxLines = 4,
    })
    self:CreateDragSurfaces()
    for _, edges in ipairs({ self.centerFrame, self.rightFrame }) do
        for _, edge in ipairs(edges) do edge:MoveToFront() end
    end
end

-- Show a failure briefly over the bottom of the grid. Saves happen on every
-- change, so successes stay silent and only problems need the player's attention
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

-- Count the error message down, fading it before it goes
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

-- Show the selected tag in the sidebar and rebuild its rows
function LayoutEditorWindow:RefreshTags()
    if self.sidebar == nil or self.sidebar.list == nil then return end
    self.sidebar.selectedTag = self.selectedTag
    self.sidebar:UpdateLayoutControls()
    self.sidebar:RefreshTags()
end

-- Open a tag draft and select it only after its editor saves successfully
function LayoutEditorWindow:CreateNewTag()
    if self.onCreateTag == nil then return false end
    self.onCreateTag(function(tag)
        self:SelectTag(tag)
        self:NotifyChanged()
    end)
    return true
end

-- End current drags and load the selected tag's saved layout
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

-- Destroy recorded grid decorations and release their references
function LayoutEditorWindow:DestroyCenterNodes()
    destroyAll(self.centerNodes)
    self.centerNodes = {}
end

-- Rebuild editable slots and native-looking item sprites from the saved layout
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
    -- Always leave one complete drop row after the final occupied row. If the
    -- existing viewport already contains that space this does not make the
    -- editor scroll; it only extends the canvas when items reach its bottom
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
    -- Unsorted items sit beneath their own heading, drawn like a label but fixed
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

-- Draw a label row with the live bank's heading treatment
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

-- Refresh after a label edit when its tag is still open, and tell the bank either way
function LayoutEditorWindow:LabelChanged(tag)
    if self.window ~= nil and self.selectedTag == tag then
        self:RefreshCenter()
        self:NotifyChanged()
    elseif self.onChanged ~= nil then
        self.onChanged(tag)
    end
end

-- Rename or delete an existing label through the shared text prompt
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

-- Ask for a new label's text, adding its row only once the text is saved
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

-- Convert content coordinates into a one-based grid slot, skipping heading rows
function LayoutEditorWindow:SlotIndexAt(x, y)
    local row = self:RowAt(x, y)
    if row == nil or row == self.centerUnsortedRow
        or self:LabelRowAt(x, y) ~= nil then return nil end
    local column = math.floor((tonumber(x) - Size.GRID_LEFT) / Size.GRID_STEP)
    if column < 0 or column >= Size.CENTER_COLUMNS then return nil end
    return row * Size.CENTER_COLUMNS + column + 1
end

-- Keep the editor above native bank rebuilds on its active logic listener
function LayoutEditorWindow:PollDrag()
    self:KeepOnTop()
    self:TickError()
end

-- Stop the editor listener that keeps its window above native bank rebuilds
function LayoutEditorWindow:StopDragPolling()
    Event.Logic.Unsubscribe(DRAG_EVENT)
end

-- Unsubscribe editor-level events when the window is destroyed
function LayoutEditorWindow.StopGlobalEvents()
    Event.Logic.Unsubscribe(DRAG_EVENT)
end

-- Find the displayed layout entry matching the current selection
function LayoutEditorWindow:SelectedEntry()
    if self.selectedLayoutKey == nil then return nil end
    for _, slot in ipairs(self.centerSlots) do
        if type(slot) == "table" and slot.kind == "item"
            and slot.layoutKey == self.selectedLayoutKey then return slot end
    end
    return nil
end

-- Return the selected item to the flowing tag-only section without removing its tag
function LayoutEditorWindow:UnarrangeSelected()
    local entry = self:SelectedEntry()
    if entry == nil then return false end
    local saved, reason = self.store:UnarrangeLayoutItem(self.selectedTag, entry.layoutKey)
    if not saved then self:ShowError(reason); return false end
    self.selectedLayoutKey = nil
    self:RefreshCenter()
    self:NotifyChanged()
    return true
end

-- Route context actions through the editor's own grid, keeping primary clicks harmless
function LayoutEditorWindow:AddMenuEntries(event)
    if self.window == nil or self.window.root == nil or self.window.root.hidden then return false end
    local x, y = self:ContentPointer()
    local index = x ~= nil and self:DestinationFromContentPoint(x, y) or nil
    local slot = index ~= nil and self.centerSlots[index] or nil
    local menu = event and event.miniMenu
    if menu == nil or slot == nil or slot.kind ~= "item" then return true end
    local tag, itemKey, consumed = self.selectedTag, slot.layoutKey, false
    local function action(method)
        return function()
            if consumed or self.selectedTag ~= tag or self.window == nil
                or self.window.root == nil or self.window.root.hidden then return end
            consumed = true
            self.selectedLayoutKey = itemKey
            self[method](self)
        end
    end
    menu:Add("Remove from tag", action("RemoveSelected"))
    menu:Add("Create Copy", action("DuplicateSelected"))
    if not slot.unarranged then menu:Add("Move to Unsorted", action("UnarrangeSelected")) end
    NativeItemMenuGuard.PromoteCancel(menu)
    return true
end

-- Create a ghost occurrence linked to the selected stack and refresh after saving
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

-- Remove the selected occurrence's tag membership and retain the other grid positions
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

-- Tell the bank owner which tag changed
function LayoutEditorWindow:NotifyChanged()
    if self.onChanged ~= nil then self.onChanged(self.selectedTag) end
end

-- Show the existing editor window
function LayoutEditorWindow:Show()
    self.window:Show()
    self:KeepOnTop()
end

-- Remove editor controls and release callbacks and stores retained by them
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
        self.removeButton,
        self.duplicateButton,
        self.centerView,
    }) do
        if control ~= nil then pcall(function() control:Destroy() end) end
    end
    if self.sidebar ~= nil then
        pcall(function() self.sidebar:DestroyRail() end)
        self.sidebar = nil
    end
    self.searchHint = nil
    self.searchList = nil
    self.itemSearch = nil
    self:HideError()
    self.newLabelButton = nil
    self.removeButton = nil
    self.duplicateButton = nil
    self.centerView = nil
end

-- Stop events and gestures before destroying the editor and all child controls
function LayoutEditorWindow:Destroy()
    self:StopDragPolling()
    self:FinishDrag(false)
    self:ClearSearchInteractions()
    self:DestroyCenterNodes()
    self:DestroyControls()
    if self.window ~= nil then pcall(function() self.window:Destroy() end) end
    self.window = nil
    self.content = nil
    self.onChanged = nil
    self.onClose = nil
    self.onOpenSettings = nil
    self.onCreateTag = nil
    self.onPromptLabel = nil
    self.overlayWindow = nil
end

return LayoutEditorWindow
