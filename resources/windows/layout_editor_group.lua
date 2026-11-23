-- Select several sorted items with Shift-click and drag them together

local BankGrid = require("resources/ui/bank_grid")
local Theme = require("resources/ui/theme")
local Parts = require("resources/windows/layout_editor_parts")
local Size = Parts.size
local rectangle = Parts.rectangle

-- Gold over the cells a group would take, red where it cannot go
local FITS_COLOUR = 0xD2A84D55
local REFUSED_COLOUR = 0xC0392B66

local LayoutEditorGroup = {}

-- Clear selections belonging to the left-panel source tabs
function LayoutEditorGroup:ClearSourceSelections()
    self.unsortedGroupKeys = nil
    self.bankSelected = nil
    self.searchSelected = nil
end

-- Select one item and clear group and paste targets
function LayoutEditorGroup:SelectOnly(layoutKey)
    self.selectedLayoutKey = layoutKey
    self.groupKeys = nil
    self.pasteCell = nil
    self:ClearSourceSelections()
end

-- Select sorted items, as a group when there are several
function LayoutEditorGroup:SelectItems(layoutKeys)
    self:SelectOnly(layoutKeys[1])
    if #layoutKeys < 2 then return end
    self.groupKeys = {}
    for _, layoutKey in ipairs(layoutKeys) do self.groupKeys[layoutKey] = true end
end

-- Count keys in any selection set
local function setCount(set)
    local count = 0
    for _ in pairs(set or {}) do count = count + 1 end
    return count
end

-- Count the items in a group, or zero without one
function LayoutEditorGroup:GroupCount()
    return setCount(self.groupKeys)
end

-- Check whether a layout or unsorted item is outlined as selected
function LayoutEditorGroup:IsSelected(layoutKey)
    return layoutKey ~= nil and (layoutKey == self.selectedLayoutKey
        or (self.groupKeys ~= nil and self.groupKeys[layoutKey] == true)
        or (self.unsortedGroupKeys ~= nil and self.unsortedGroupKeys[layoutKey] == true))
end

-- List selected Unsorted layoutKeys in visible grid order
function LayoutEditorGroup:SelectedUnsortedKeys()
    local keys = {}
    local pane = self.panes and self.panes.unsorted or nil
    local slots = pane and pane.slots or (self.layout and self.layout.unsorted) or {}
    for _, slot in ipairs(slots) do
        if slot.kind == "item" and (
            (self.unsortedGroupKeys ~= nil and self.unsortedGroupKeys[slot.layoutKey])
            or (self.unsortedGroupKeys == nil and self.selectedLayoutKey == slot.layoutKey)
        ) then
            keys[#keys + 1] = slot.layoutKey
        end
    end
    return keys
end

-- List selected Bank objectIDs in visible grid order
function LayoutEditorGroup:SelectedBankObjectIDs()
    if self.bankSelected == nil then return {} end
    local ids = {}
    local pane = self.panes and self.panes.bank or nil
    for _, slot in ipairs(pane and pane.slots or {}) do
        if slot.kind == "item" and self.bankSelected[slot.objectID] then
            ids[#ids + 1] = slot.objectID
        end
    end
    return ids
end

-- List selected Search objectIds in visible result order
function LayoutEditorGroup:SelectedSearchObjectIDs()
    if self.searchSelected == nil then return {} end
    local ids = {}
    for _, result in ipairs(self.searchResults or {}) do
        if self.searchSelected[result.objectId] then
            ids[#ids + 1] = result.objectId
        end
    end
    return ids
end

-- Report whether any pane currently has at least one selected item
function LayoutEditorGroup:HasAnySelection()
    if self:SelectedEntry() ~= nil then return true end
    if #self:SelectedUnsortedKeys() > 0 then return true end
    if #self:SelectedBankObjectIDs() > 0 then return true end
    return #self:SelectedSearchObjectIDs() > 0
end

-- Toggle an Unsorted item in the Unsorted multi-selection
function LayoutEditorGroup:ToggleUnsortedGroupItem(layoutKey)
    self.groupKeys = nil
    self.pasteCell = nil
    self.bankSelected = nil
    self.searchSelected = nil
    local keys = {}
    if self.unsortedGroupKeys ~= nil then
        for key in pairs(self.unsortedGroupKeys) do keys[key] = true end
    elseif self.selectedLayoutKey ~= nil and self.layout.unsortedIndex[self.selectedLayoutKey] ~= nil then
        keys[self.selectedLayoutKey] = true
    end
    if keys[layoutKey] then
        keys[layoutKey] = nil
        if self.selectedLayoutKey == layoutKey then self.selectedLayoutKey = nil end
    else
        keys[layoutKey] = true
        self.selectedLayoutKey = layoutKey
    end
    local kept = {}
    for key in pairs(keys) do
        if self.layout.unsortedIndex[key] ~= nil then kept[#kept + 1] = key end
    end
    if #kept <= 1 then
        self.unsortedGroupKeys = nil
        self.selectedLayoutKey = kept[1]
    else
        self.unsortedGroupKeys = {}
        for _, key in ipairs(kept) do self.unsortedGroupKeys[key] = true end
        if not self.unsortedGroupKeys[self.selectedLayoutKey] then self.selectedLayoutKey = kept[1] end
    end
end

-- Replace the Unsorted multi-selection with a list of layoutKeys
function LayoutEditorGroup:SelectUnsortedItems(layoutKeys)
    self:SelectOnly(layoutKeys[1])
    if #layoutKeys < 2 then return end
    self.unsortedGroupKeys = {}
    for _, key in ipairs(layoutKeys) do self.unsortedGroupKeys[key] = true end
end

-- Select or toggle Bank item(s)
function LayoutEditorGroup:SelectBankOnly(objectID)
    self:SelectOnly(nil)
    if objectID ~= nil then self.bankSelected = { [objectID] = true } end
end

function LayoutEditorGroup:ToggleBankItem(objectID)
    self.selectedLayoutKey, self.groupKeys, self.pasteCell = nil, nil, nil
    self.unsortedGroupKeys, self.searchSelected = nil, nil
    local selected = {}
    for id in pairs(self.bankSelected or {}) do selected[id] = true end
    if selected[objectID] then selected[objectID] = nil else selected[objectID] = true end
    self.bankSelected = next(selected) ~= nil and selected or nil
end

function LayoutEditorGroup:SelectBankItems(objectIDs)
    self:SelectOnly(nil)
    if #objectIDs == 0 then return end
    self.bankSelected = {}
    for _, id in ipairs(objectIDs) do self.bankSelected[id] = true end
end

-- Select or toggle Search result(s)
function LayoutEditorGroup:SelectSearchOnly(objectID)
    self:SelectOnly(nil)
    if objectID ~= nil then self.searchSelected = { [objectID] = true } end
end

function LayoutEditorGroup:ToggleSearchItem(objectID)
    self.selectedLayoutKey, self.groupKeys, self.pasteCell = nil, nil, nil
    self.unsortedGroupKeys, self.bankSelected = nil, nil
    local selected = {}
    for id in pairs(self.searchSelected or {}) do selected[id] = true end
    if selected[objectID] then selected[objectID] = nil else selected[objectID] = true end
    self.searchSelected = next(selected) ~= nil and selected or nil
end

function LayoutEditorGroup:SelectSearchItems(objectIDs)
    self:SelectOnly(nil)
    if #objectIDs == 0 then return end
    self.searchSelected = {}
    for _, id in ipairs(objectIDs) do self.searchSelected[id] = true end
end

-- List the sorted items in a set, in reading order
function LayoutEditorGroup:SortedKeys(keys)
    local ordered, indexes = {}, self.layout.sortedIndex
    for layoutKey in pairs(keys) do
        if indexes[layoutKey] ~= nil then ordered[#ordered + 1] = layoutKey end
    end
    table.sort(ordered, function(left, right) return indexes[left] < indexes[right] end)
    return ordered
end

-- Keep only group items still in the layout or Unsorted
function LayoutEditorGroup:PruneSelection()
    if self.groupKeys ~= nil then
        local kept = self:SortedKeys(self.groupKeys)
        if #kept <= 1 then
            self.groupKeys = nil
            if self.selectedLayoutKey ~= nil and self.layout.sortedIndex[self.selectedLayoutKey] == nil
                and self.layout.unsortedIndex[self.selectedLayoutKey] == nil then
                self.selectedLayoutKey = kept[1]
            elseif #kept == 1 then
                self.selectedLayoutKey = kept[1]
            end
        else
            self.groupKeys = {}
            for _, layoutKey in ipairs(kept) do self.groupKeys[layoutKey] = true end
            if not self.groupKeys[self.selectedLayoutKey] then self.selectedLayoutKey = kept[1] end
        end
    end
    if self.unsortedGroupKeys ~= nil then
        local kept = {}
        for key in pairs(self.unsortedGroupKeys) do
            if self.layout.unsortedIndex[key] ~= nil then kept[#kept + 1] = key end
        end
        if #kept <= 1 then
            self.unsortedGroupKeys = nil
            if #kept == 1 then self.selectedLayoutKey = kept[1] end
        else
            self.unsortedGroupKeys = {}
            for _, key in ipairs(kept) do self.unsortedGroupKeys[key] = true end
            if not self.unsortedGroupKeys[self.selectedLayoutKey] then self.selectedLayoutKey = kept[1] end
        end
    end
end

-- Add or remove a sorted item from the selection
function LayoutEditorGroup:ToggleGroupItem(layoutKey)
    self.pasteCell = nil
    local keys = {}
    if self.groupKeys ~= nil then
        for selected in pairs(self.groupKeys) do keys[selected] = true end
    elseif self.selectedLayoutKey ~= nil then
        -- An Unsorted selection never joins a group, and the prune drops it
        keys[self.selectedLayoutKey] = true
    end
    if keys[layoutKey] then
        keys[layoutKey] = nil
        if self.selectedLayoutKey == layoutKey then self.selectedLayoutKey = nil end
    else
        keys[layoutKey] = true
        self.selectedLayoutKey = layoutKey
    end
    self.groupKeys = keys
    self:PruneSelection()
end

-- Drag the selected group by its grabbed item
function LayoutEditorGroup:BeginGroupDrag(slot)
    self.selectedLayoutKey = slot.layoutKey
    local keys = self:SortedKeys(self.groupKeys)
    local ghost = self:CreateDragGhost(Size.ITEM_WIDTH, Size.ITEM_HEIGHT)
    self:ItemSprite(ghost, slot.objectID, true)
    prettyui.Text.new(ghost, {
        text = tostring(#keys),
        x = Size.ITEM_WIDTH - 14, y = Size.ITEM_HEIGHT - 14, width = 18, height = 14,
        colour = Theme.HEADING_TEXT,
        maxLines = 1,
    }).clickthrough = true
    return self:StartDrag({ kind = "group", keys = keys, anchorKey = slot.layoutKey, preview = {},
        sourceKind = "sorted" }, ghost, Size.ITEM_WIDTH, Size.ITEM_HEIGHT)
end

-- Find the sorted cell a group's grabbed item would take
function LayoutEditorGroup:GroupDestination(x, y)
    local pane, paneX, paneY = self:PaneAt(x, y)
    if pane == nil or pane.name ~= "sorted" then return nil, pane end
    return self:SlotIndexAt(pane, paneX, paneY), pane
end

-- Remove the cells drawn for a group drop
function LayoutEditorGroup:ClearGroupPreview(drag)
    for index = #drag.preview, 1, -1 do drag.preview[index]:Destroy() end
    drag.preview = {}
    drag.previewIndex = nil
end

-- Shade proposed group cells gold or red
function LayoutEditorGroup:ShowGroupPreview(x, y)
    local drag = self.drag
    local destination = self:GroupDestination(x, y)
    if destination == drag.previewIndex then return end
    self:ClearGroupPreview(drag)
    if destination == nil then return end
    drag.previewIndex = destination
    local plan = self.store:PlanLayoutItemsMove(
        self.selectedTag, drag.keys, drag.anchorKey, destination, Size.CENTER_COLUMNS)
    if plan == nil then return end
    local parent = self.panes.sorted.view.content
    local colour = plan.valid and FITS_COLOUR or REFUSED_COLOUR
    for _, move in ipairs(plan.moves) do
        -- Cells past the grid's edges have nowhere to draw
        if move.line >= 0 and move.column >= 0 and move.column < Size.CENTER_COLUMNS then
            drag.preview[#drag.preview + 1] = rectangle(parent,
                Size.GRID_LEFT + move.column * Size.GRID_STEP,
                BankGrid.RowItemY(move.line, self.panes.sorted.labels),
                Size.GRID_SLOT_SIZE, Size.GRID_SLOT_SIZE, colour, true)
        end
    end
end

-- Save the group drop or explain its refusal
function LayoutEditorGroup:FinishGroupDrag(drag, x, y)
    local destination, pane = self:GroupDestination(x, y)
    if pane ~= nil and pane.name == "unsorted" then
        self:ShowError("Use Move to Unsorted to move the selected group out of the layout.")
        return
    end
    if destination == nil then return end
    -- Save the whole group move as one undo step
    self:SaveEdit("Could not move the items.", function()
        return self.store:MoveLayoutItems(
            self.selectedTag, drag.keys, drag.anchorKey, destination, Size.CENTER_COLUMNS)
    end)
end

-- Start dragging multiple selected items from Unsorted, Bank, or Search into Layout
function LayoutEditorGroup:BeginMultiDrag(kind, sourceKind, objectID, items, absentIsPlaceholder)
    local ghost = self:CreateDragGhost(Size.ITEM_WIDTH, Size.ITEM_HEIGHT)
    self:ItemSprite(ghost, objectID, absentIsPlaceholder)
    prettyui.Text.new(ghost, {
        text = tostring(#items),
        x = Size.ITEM_WIDTH - 14, y = Size.ITEM_HEIGHT - 14, width = 18, height = 14,
        colour = Theme.HEADING_TEXT,
        maxLines = 1,
    }).clickthrough = true
    return self:StartDrag({
        kind = kind,
        sourceKind = sourceKind,
        items = items,
        preview = {},
    }, ghost, Size.ITEM_WIDTH, Size.ITEM_HEIGHT)
end

-- Preview the open layout cells a multi-item drag from Unsorted/Bank/Search will fill
function LayoutEditorGroup:ShowMultiPreview(x, y)
    local drag = self.drag
    local destination = self:GroupDestination(x, y)
    if destination == drag.previewIndex then return end
    self:ClearGroupPreview(drag)
    if destination == nil or self.selectedTag == nil then return end
    drag.previewIndex = destination
    local cells = self.store:OpenLayoutCells(self.selectedTag, #drag.items, destination, Size.CENTER_COLUMNS)
    drag.previewCells = cells
    local parent = self.panes.sorted.view.content
    local columns = Size.CENTER_COLUMNS
    for _, cell in ipairs(cells) do
        local line = (cell - 1) // columns
        local column = (cell - 1) % columns
        drag.preview[#drag.preview + 1] = rectangle(parent,
            Size.GRID_LEFT + column * Size.GRID_STEP,
            BankGrid.RowItemY(line, self.panes.sorted.labels),
            Size.GRID_SLOT_SIZE, Size.GRID_SLOT_SIZE, FITS_COLOUR, true)
    end
end

-- Finish a multi-item drop from Unsorted, Bank, or Search onto Layout
function LayoutEditorGroup:FinishMultiDrag(drag, x, y)
    local destination = self:GroupDestination(x, y)
    if destination == nil or self.selectedTag == nil then return end
    local tag = self.selectedTag
    local cells = self.store:OpenLayoutCells(tag, #drag.items, destination, Size.CENTER_COLUMNS)
    if drag.kind == "unsorted_group" then
        self:SaveEdit("Could not move the items to the layout.", function()
            local saved, keys, reason = self.store:MoveUnsortedItemsToCells(tag, drag.items, cells, Size.CENTER_COLUMNS)
            if saved and keys ~= nil then self:SelectItems(keys) end
            return saved, reason
        end)
    else
        self:SaveEdit("Could not add the items to the layout.", function()
            local saved, keys, reason = self.store:PlaceItemsAtCells(tag, drag.items, cells, Size.CENTER_COLUMNS)
            if saved and keys ~= nil then self:SelectItems(keys) end
            return saved, reason
        end)
    end
end

return LayoutEditorGroup
