-- Build the bank editor: Unsorted, tabbed Layout, and Search.

local Config = require("banktags/core/config")
local Text = require("banktags/core/text")
local Theme = require("banktags/ui/theme")
local TagLayouts = require("banktags/tags/tag_layouts")
local Parts = require("banktags/windows/layout_editor_parts")
local Size = Parts.size

local LayoutEditorWindow = {}
LayoutEditorWindow.__index = LayoutEditorWindow
-- Compose the editor from lifecycle-independent view and interaction modules.
for _, methods in ipairs({
    require("banktags/windows/layout_editor_view"),
    require("banktags/windows/layout_editor_rows"),
    require("banktags/windows/layout_editor_drag"),
    require("banktags/windows/layout_editor_search"),
    require("banktags/windows/layout_editor_keys"),
    require("banktags/windows/layout_editor_names"),
    require("banktags/windows/layout_editor_group"),
    require("banktags/windows/layout_editor_history"),
    require("banktags/windows/layout_editor_clipboard"),
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
        -- The copied items of the open tag, kept until the tag changes or the editor closes
        clipboard = nil,
        actionTooltips = {
            copyButton = "Copy the selected item or group (Ctrl+C)",
            pasteButton = "Click an empty cell, then paste the copied items there (Ctrl+V)",
            removeButton = "Remove the selected item or group (Delete). Ctrl+Z undoes and Ctrl+Y redoes;"
                .. " arrow keys move the selection when turned on in Bank Tags' settings",
            unsortButton = "Move the selected item or group to Unsorted",
        },
        drag = nil,
        styles = {},
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
        -- PrettyUI destroys the window after this returns
        onClose = function() self:Destroy(true) end,
    })
    -- PrettyUI has no option to fix a window in place, so its title-bar drag is removed
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

-- Show saved changes, keeping the open tag if it still exists
-- A named tag means only that tag's items or layout changed
function LayoutEditorWindow:StoreChanged(tag)
    if tag ~= nil and tag ~= self.selectedTag then return end
    if tag == nil then self:RefreshTags() end
    if self.selectedTag ~= nil and self.store.data.tags[self.selectedTag] == nil then
        return self:SelectTag(self.store:AllTags()[1])
    end
    self:CheckHistory()
    self:RefreshCenter()
end

-- Show the editor aligned with the bank, then its windows and the tutorial in front, in order
function LayoutEditorWindow:Show()
    local window = self.window
    if window == nil then return end
    self:HideItemName()
    local root, bounds = window.root, self.bounds
    if root.x ~= bounds.x or root.y ~= bounds.y then root:SetPos(bounds.x, bounds.y, 0, 0) end
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

-- Show a failure beside the footer actions
-- Saves happen on every change, so only problems and copying are shown
function LayoutEditorWindow:ShowError(message, colour)
    self.status.content = message or "Something went wrong."
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
            entries[#entries + 1] = { id = tag, label = Text.titleCase(Text.plain(tag)),
                objectID = self.store:GetTagSprite(tag) }
        end
    end
    self.tagTabs:SetEntries(entries, self.selectedTag)
    self:ShowChosenTag()
end

-- Keep the open tag's tab selected and visible.
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
    -- Another tag starts both grids at the top, with no undo steps, copied items, or message
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

-- Redraw both grids from the saved layout, keeping each one's scroll
function LayoutEditorWindow:RefreshCenter()
    self:CancelDrag()
    local layout = self.store:EditorLayout(self.selectedTag, Size.CENTER_COLUMNS)
    local sorted, unsorted = self.panes.sorted, self.panes.unsorted
    self.layout = layout
    self.unsortedTitle.content = "Unsorted (" .. #layout.unsorted .. ")"
    sorted.slots, unsorted.slots = layout.slots, layout.unsorted
    -- A group keeps only the items still sorted
    self:PruneSelection()
    -- Keep one empty drop row after the last used row
    self:DrawPane(sorted, layout.lines + (layout.lines > 0 and 1 or 0), layout.labels)
    -- Unsorted packs its items at its own columns
    self:DrawPane(unsorted, math.ceil(#layout.unsorted / unsorted.columns), {})
    self:ShowSelection()
end

-- Follow the hovered item's name and, every few ticks, the bank's bounds
-- The bank check runs last, since it may close this editor and open another
function LayoutEditorWindow:FollowHoverAndBank()
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

-- Move the selected item or group to Unsorted in one save and undo step.
function LayoutEditorWindow:UnarrangeSelected()
    local entry, paneName = self:SelectedEntry()
    if entry == nil then self:ShowError("Select a layout item first."); return false end
    if self.groupKeys == nil and paneName == "unsorted" then
        self:ShowError("That item is already in Unsorted.")
        return false
    end
    local keys = self.groupKeys ~= nil and self:SortedKeys(self.groupKeys) or { entry.layoutKey }
    if #keys == 0 then return false end
    return (self:SaveEdit("Could not move the selected items to Unsorted.", function()
        local saved, reason = self.store:SaveTogether(function()
            for _, layoutKey in ipairs(keys) do
                local moved, moveReason = self.store:UnarrangeLayoutItem(self.selectedTag, layoutKey)
                if not moved then return false, moveReason end
            end
            return true
        end)
        if saved then self:SelectOnly(nil) end
        return saved, reason
    end))
end

-- Place the selected Unsorted item in the first open cell, skipping labels and reserved slots.
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
    return (self:SaveEdit("Could not move the item to the layout.", function()
        return self.store:MoveLayoutItem(self.selectedTag, entry.layoutKey, destination, Size.CENTER_COLUMNS)
    end))
end

-- Untag the selection in one save and undo step, keeping other grid positions.
function LayoutEditorWindow:RemoveSelected()
    local keys
    if self.groupKeys ~= nil then
        keys = self:SortedKeys(self.groupKeys)
    else
        local entry = self:SelectedEntry()
        keys = entry ~= nil and { entry.layoutKey } or {}
    end
    if #keys == 0 then return false end
    return (self:SaveEdit("Could not remove the selected items.", function()
        local saved, reason = self.store:SaveTogether(function()
            for _, layoutKey in ipairs(keys) do
                local removed, removeReason = self.store:RemoveTag(self.selectedTag, layoutKey)
                if not removed then return false, removeReason end
            end
            return true
        end)
        if saved then self:SelectOnly(nil) end
        return saved, reason
    end))
end

-- Tell the app the open tag's items or layout changed, which redraws the grids
function LayoutEditorWindow:NotifyChanged()
    if self.onChanged ~= nil then self.onChanged(self.selectedTag) end
end

-- Stop events and drags, release the controls and callbacks, then the window
-- A window closing itself is destroyed by PrettyUI once its onClose returns
function LayoutEditorWindow:Destroy(closing)
    local window = self.window
    if window == nil then return end
    self.window = nil
    Event.Logic.Unsubscribe(FOLLOW_EVENT)
    self:StopShortcuts()
    self:CancelDrag()
    self:ClearHistory()
    self.clipboard = nil
    local onClose = self.onClose
    self.onClose, self.onChanged, self.onBankCheck, self.onPromptLabel, self.onConfirmRemoveRow = nil, nil, nil, nil, nil
    if onClose ~= nil then onClose(self) end
    self:DestroyItemNames()
    for _, control in ipairs({
        self.panes.sorted.view, self.panes.unsorted.view, self.itemSearch, self.searchList, self.tagTabs,
        self.copyButton, self.pasteButton, self.removeButton, self.unsortButton, self.newLabelButton,
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
