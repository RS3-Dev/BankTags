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

-- Select one item and clear group and paste targets
function LayoutEditorGroup:SelectOnly(layoutKey)
    self.selectedLayoutKey = layoutKey
    self.groupKeys = nil
    self.pasteCell = nil
end

-- Select sorted items, as a group when there are several
function LayoutEditorGroup:SelectItems(layoutKeys)
    self:SelectOnly(layoutKeys[1])
    if #layoutKeys < 2 then return end
    self.groupKeys = {}
    for _, layoutKey in ipairs(layoutKeys) do self.groupKeys[layoutKey] = true end
end

-- Count the items in a group, or zero without one
function LayoutEditorGroup:GroupCount()
    local count = 0
    for _ in pairs(self.groupKeys or {}) do count = count + 1 end
    return count
end

-- Check whether an item is outlined as selected
function LayoutEditorGroup:IsSelected(layoutKey)
    return layoutKey ~= nil and (layoutKey == self.selectedLayoutKey
        or (self.groupKeys ~= nil and self.groupKeys[layoutKey] == true))
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

-- Keep only group items still in the layout
function LayoutEditorGroup:PruneSelection()
    if self.groupKeys == nil then return end
    local kept = self:SortedKeys(self.groupKeys)
    if #kept <= 1 then
        self:SelectOnly(kept[1])
        return
    end
    self.groupKeys = {}
    for _, layoutKey in ipairs(kept) do self.groupKeys[layoutKey] = true end
    if not self.groupKeys[self.selectedLayoutKey] then self.selectedLayoutKey = kept[1] end
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

return LayoutEditorGroup
