-- Build the bank editor's Unsorted, Layout, and Search panels

local Config = require("resources/core/config")
local Text = require("resources/core/text")
local Theme = require("resources/ui/theme")
local TagLayouts = require("resources/tags/tag_layouts")
local Parts = require("resources/windows/layout_editor_parts")
local Size = Parts.size

local LayoutEditorWindow = {}
LayoutEditorWindow.__index = LayoutEditorWindow
-- Combine the editor's drawing and input helpers
for _, methods in ipairs({
    require("resources/windows/layout_editor_view"),
    require("resources/windows/layout_editor_unsorted"),
    require("resources/windows/layout_editor_rows"),
    require("resources/windows/layout_editor_drag"),
    require("resources/windows/layout_editor_search"),
    require("resources/windows/layout_editor_keys"),
    require("resources/windows/layout_editor_names"),
    require("resources/windows/layout_editor_group"),
    require("resources/windows/layout_editor_marquee"),
    require("resources/windows/layout_editor_history"),
    require("resources/windows/layout_editor_clipboard"),
}) do
    for name, method in pairs(methods) do LayoutEditorWindow[name] = method end
end

local FOLLOW_EVENT = Config.PLUGIN_REF .. "_layout_editor_follow"
-- Core reports no bank move, so the editor asks for the bank's bounds this often
local BANK_CHECK_TICKS = 10

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
        onBankCheck = options.onBankCheck,
        bankCheckTicks = 0,
        onPromptLabel = options.onPromptLabel,
        onConfirmRemoveRow = options.onConfirmRemoveRow,
        overlayWindows = {},
        searchResults = {},
        selectedLayoutKey = nil,
        -- Set only while two or more sorted items are selected
        groupKeys = nil,
        -- The empty sorted cell Paste fills, outlined in gold
        pasteCell = nil,
        -- Keep copied items until the tag or editor changes
        clipboard = nil,
        actionTooltips = {
            copyButton = "Copy the selected item or group (Ctrl+C)",
            pasteButton = "Click an empty cell, then paste the copied items there (Ctrl+V)",
            removeButton = "Remove the selected item or group (Delete). Ctrl+Z undoes and Ctrl+Y redoes;"
                .. " arrow keys move the selection when turned on in Bank Tags' settings",
        },
        drag = nil,
        styles = {},
    }, LayoutEditorWindow)

    self:SetBankItems(options.bankItems)
    Parts.SizeToBank(self.columns, self.bounds.width, self.bounds.height)
    self.window = prettyui.Window.new(parent, {
        categoryID = "auto",
        title = "Bank Layout Editor",
        x = self.bounds.x - Size.WINDOW_BORDER,
        y = self.bounds.y - Size.WINDOW_BORDER,
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
        -- PrettyUI destroys the window after this returns
        onClose = function() self:Destroy(true) end,
    })
    -- Remove title-bar dragging so the editor follows the bank
    if self.window.titleDrag ~= nil then
        self.window.titleDrag:Destroy()
        self.window.titleDrag = nil
    end
    self.content = self.window.content
    self:CreatePanels()
    self:RefreshTags()
    self:SelectTag(self.selectedTag)
    Event.Logic.Subscribe(FOLLOW_EVENT, function() self:FollowHoverAndBank() end)
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
    local moved = self.bounds.x ~= bounds.x or self.bounds.y ~= bounds.y
    self.bounds = bounds
    if moved then self:Show() end
end

-- Refresh the open tag after relevant saved changes
function LayoutEditorWindow:StoreChanged(tag)
    if tag ~= nil and tag ~= self.selectedTag then return end
    if tag == nil then self:RefreshTags() end
    if self.selectedTag ~= nil and self.store.data.tags[self.selectedTag] == nil then
        return self:SelectTag(self.store:AllTags()[1])
    end
    self:CheckHistory()
    self:RefreshCenter()
end

-- Align the editor and keep its dialogs in front
function LayoutEditorWindow:Show()
    local window = self.window
    if window == nil then return end
    self:HideItemName()
    local root, bounds = window.root, self.bounds
    local x, y = bounds.x - Size.WINDOW_BORDER, bounds.y - Size.WINDOW_BORDER
    if root.x ~= x or root.y ~= y then root:SetPos(x, y, 0, 0) end
    -- Show raises a PrettyUI window with its overlays
    window:Show()
    for _, overlay in ipairs(self.overlayWindows) do
        if overlay.root ~= nil and not overlay.root.hidden then overlay:Show() end
    end
    -- Tutorial decoration stays above the editor without blocking its input
    if self.guideLayer ~= nil and not self.guideLayer.hidden then self.guideLayer:MoveToFront() end
end

-- Keep editor windows and the click-through tutorial in front
function LayoutEditorWindow:SetOverlays(windows, guideLayer)
    self.overlayWindows = windows
    self.guideLayer = guideLayer
    self:Show()
end

-- Show an error beside the footer actions
function LayoutEditorWindow:ShowError(message, colour)
    self.status.content = Text.plain(message or "Something went wrong.")
    self.status.rgba = colour or Theme.ERROR_TEXT
end

-- Show a notice where errors show
function LayoutEditorWindow:ShowNotice(message)
    self:ShowError(message, Theme.HEADING_TEXT)
end

-- Clear the footer message
function LayoutEditorWindow:ClearStatus()
    self.status.content = ""
end

-- List tag buttons in the sidebar order
function LayoutEditorWindow:RefreshTags()
    local entries = {}
    for _, node in ipairs(self.store:TagTree()) do
        for _, tag in ipairs(node.kind == "tag" and { node.tag } or node.tags) do
            entries[#entries + 1] = { id = tag, label = Text.titleCase(Text.plain(self.store:GetTagName(tag))),
                objectID = self.store:GetTagSprite(tag) }
        end
    end
    self.tagTabs:SetEntries(entries, self.selectedTag)
    self:ShowChosenTag()
end

-- Keep the open tag selected and visible
function LayoutEditorWindow:ShowChosenTag()
    self.tagTabs:Select(self.selectedTag)
end

-- Keep the open tag open under its new name
function LayoutEditorWindow:TagRenamed(oldTag, newTag)
    if self.selectedTag == oldTag then self.selectedTag = newTag end
    if self.history ~= nil and self.history.tag == oldTag then self.history.tag = newTag end
    if self.clipboard ~= nil and self.clipboard.tag == oldTag then self.clipboard.tag = newTag end
end

-- End drags and load the selected tag's layout
function LayoutEditorWindow:SelectTag(tag)
    self:CancelDrag()
    -- Reset scrolling and editing state when switching tags
    if tag ~= self.selectedTag then
        self:ClearHistory()
        self:ClearStatus()
        self.clipboard = nil
        for _, pane in pairs(self.panes) do pane.view:SetScrollPosition(0) end
    end
    self.selectedTag = tag
    self:SelectOnly(nil)
    self:ShowChosenTag()
    self:RefreshCenter()
end

-- Redraw both grids while keeping their scroll positions
function LayoutEditorWindow:RefreshCenter()
    self:CancelDrag()
    local layout = self.store:EditorLayout(self.selectedTag, Size.CENTER_COLUMNS)
    local sorted = self.panes.sorted
    self.layout = layout
    sorted.slots = layout.slots
    -- A group keeps only the items still sorted
    self:PruneSelection()
    self:DrawPane(sorted, layout.lines, layout.labels)
    self:RefreshUnsorted()
    self:ShowSelection()
end

-- Follow item names and periodically check the bank's position
function LayoutEditorWindow:FollowHoverAndBank()
    self:TickSearch()
    self:TickBoxSelection()
    self:UpdateItemName()
    self.bankCheckTicks = self.bankCheckTicks + 1
    if self.bankCheckTicks % BANK_CHECK_TICKS == 0 then self.onBankCheck() end
end

-- Find the selected item, its pane, and its index there
function LayoutEditorWindow:SelectedEntry()
    local layoutKey, layout = self.selectedLayoutKey, self.layout
    local index = layout.sortedIndex[layoutKey]
    if index ~= nil then return layout.slots[index], "sorted", index end
    index = layout.unsortedIndex[layoutKey]
    if index ~= nil then return layout.unsorted[index], "unsorted", index end
    return nil
end

-- Move selected items to Unsorted in one undo step
function LayoutEditorWindow:UnarrangeSelected()
    local entry, paneName = self:SelectedEntry()
    if entry == nil then self:ShowError("Select a layout item first."); return false end
    if self.groupKeys == nil and paneName == "unsorted" then
        self:ShowError("That item is already in Unsorted.")
        return false
    end
    local keys = self.groupKeys ~= nil and self:SortedKeys(self.groupKeys) or { entry.layoutKey }
    if #keys == 0 then return false end
    -- Move the entire selection before clearing its outlines
    return (self:SaveEdit("Could not move the selected items to Unsorted.", function()
        local saved, reason = self.store:UnarrangeLayoutItems(self.selectedTag, keys)
        if saved then self:SelectOnly(nil) end
        return saved, reason
    end))
end

-- Place the Unsorted selection in the first open cell
function LayoutEditorWindow:ArrangeSelected()
    local entry, paneName = self:SelectedEntry()
    if entry == nil or paneName ~= "unsorted" then return false end
    local labelRows = {}
    for _, label in ipairs(self.layout.labels) do labelRows[label.row] = true end
    local destination = self.layout.lines * Size.CENTER_COLUMNS + 1
    for index, slot in ipairs(self.layout.slots) do
        if not labelRows[(index - 1) // Size.CENTER_COLUMNS] and TagLayouts.IsOpen(slot) then
            destination = index
            break
        end
    end
    -- Save the first available layout position
    return (self:SaveEdit("Could not move the item to the layout.", function()
        return self.store:MoveLayoutItem(self.selectedTag, entry.layoutKey, destination, Size.CENTER_COLUMNS)
    end))
end

-- Remove selected items from the tag in one step
function LayoutEditorWindow:RemoveSelected()
    local keys
    if self.groupKeys ~= nil then
        keys = self:SortedKeys(self.groupKeys)
    else
        local entry = self:SelectedEntry()
        keys = entry ~= nil and { entry.layoutKey } or {}
    end
    if #keys == 0 then return false end
    -- Remove the entire selection before clearing its outlines
    return (self:SaveEdit("Could not remove the selected items.", function()
        local saved, reason = self.store:RemoveTags(self.selectedTag, keys)
        if saved then self:SelectOnly(nil) end
        return saved, reason
    end))
end

-- Notify the app that the open tag changed
function LayoutEditorWindow:NotifyChanged()
    if self.onChanged ~= nil then self.onChanged(self.selectedTag) end
end

-- Stop listeners and release editor controls before its window
function LayoutEditorWindow:Destroy(closing)
    local window = self.window
    if window == nil then return end
    self.window = nil
    Event.Logic.Unsubscribe(FOLLOW_EVENT)
    self:StopShortcuts()
    self:CancelSearch()
    self:CancelDrag()
    self:ClearHistory()
    self.clipboard = nil
    local onClose = self.onClose
    self.onClose, self.onChanged, self.onBankCheck, self.onPromptLabel, self.onConfirmRemoveRow = nil, nil, nil, nil, nil
    if onClose ~= nil then onClose(self) end
    self:DestroyItemNames()
    for _, control in ipairs({
        self.panes.sorted.view, self.panes.unsorted.view, self.unsortedSearch, self.itemSearch, self.searchList, self.tagTabs,
        self.copyButton, self.pasteButton, self.removeButton, self.addRowButton, self.newLabelButton,
        self.closeButton,
    }) do
        control:Destroy()
    end
    self.panes = nil
    self.surfaceClips = nil
    self.overlayWindows = {}
    self.guideLayer = nil
    if not closing then window:Destroy() end
    self.content = nil
end

return LayoutEditorWindow
