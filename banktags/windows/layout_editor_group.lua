-- Select several sorted items with Shift-click and drag them together

local BankGrid = require("banktags/ui/bank_grid")
local Theme = require("banktags/ui/theme")
local Parts = require("banktags/windows/layout_editor_parts")
local Size = Parts.size
local rectangle = Parts.rectangle

-- Gold over the cells a group would take, red where it cannot go
local FITS_COLOUR = 0xD2A84D55
local REFUSED_COLOUR = 0xC0392B66
local COUNT_COLOUR = Theme.HEADING_TEXT
-- What the single-item actions say while a group is selected
local GROUP_TOOLTIPS = {
    removeButton = "Select one item to remove it",
    unsortButton = "Select one item to move it to Unsorted",
}

local LayoutEditorGroup = {}

-- Select one item, or nothing, ending any group and the cell to paste into
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
    local ordered = {}
    for _, slot in ipairs(self.panes.sorted.slots) do
        if type(slot) == "table" and slot.kind == "item" and keys[slot.layoutKey] then
            ordered[#ordered + 1] = slot.layoutKey
        end
    end
    return ordered
end

-- Drop group items no longer sorted, ending a group of one
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

-- Add a sorted item to the selection, or take it out
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

-- Refuse a single-item action while a group is selected
function LayoutEditorGroup:RefuseForGroup()
    if self:GroupCount() <= 1 then return false end
    self:ShowError(self:GroupCount() .. " items are selected. Click one item, or Shift-click"
        .. " to deselect, before using this action.")
    return true
end

-- Explain on the item actions when a group blocks them
function LayoutEditorGroup:UpdateActionTooltips()
    local grouped = self:GroupCount() > 1
    if self.groupTooltips == grouped then return end
    self.groupTooltips = grouped
    for name, tooltip in pairs(GROUP_TOOLTIPS) do
        self[name]:SetTooltip(grouped and tooltip or self.actionTooltips[name])
    end
end

-- Start dragging the selected group by one of its items
function LayoutEditorGroup:BeginGroupDrag(slot, pane, hit, pointX, pointY)
    self.selectedLayoutKey = slot.layoutKey
    local keys = self:SortedKeys(self.groupKeys)
    local ghost = ui.Layer.new(self.content)
    ghost:SetSize(Size.GRID_SLOT_SIZE, Size.GRID_SLOT_SIZE)
    ghost.clickthrough = true
    local sprite = ui.Sprite.new(ghost)
    local width, height = self:ApplyRuntimeObjectSprite(sprite, slot.objectID, true)
    sprite:SetPos(0, 0)
    -- The count sits on the item's corner so the whole group is named
    prettyui.Text.new(ghost, {
        text = tostring(#keys),
        x = width - 14, y = height - 14, width = 18, height = 14,
        colour = COUNT_COLOUR,
        maxLines = 1,
    }).clickthrough = true
    ghost.alpha = 0.88
    ghost:SetPos(pointX - math.floor(width / 2), pointY - math.floor(height / 2))
    ghost:MoveToFront()
    self.drag = {
        kind = "group",
        keys = keys,
        anchorKey = slot.layoutKey,
        pointerX = pointX,
        pointerY = pointY,
        ghost = ghost,
        ghostWidth = width,
        ghostHeight = height,
        preview = {},
        sourceSurface = hit,
        sourceSurfaceKind = pane.name,
    }
    self:CaptureDragSurface(hit, pane.name)
    return false
end

-- Find the sorted cell a group's grabbed item would take
function LayoutEditorGroup:GroupDestination(x, y)
    local pane, paneX, paneY = self:PaneAt(x, y)
    if pane == nil or pane.name ~= "sorted" then return nil, pane end
    return self:SlotIndexAt(pane, paneX, paneY), pane
end

-- Remove the cells drawn for a group drop
function LayoutEditorGroup.ClearGroupPreview(drag)
    for index = #drag.preview, 1, -1 do
        local node = drag.preview[index]
        pcall(function() node:Destroy() end)
    end
    drag.preview = {}
    drag.previewIndex = nil
end

-- Shade every cell the group would take, all red when it cannot drop there
function LayoutEditorGroup:ShowGroupPreview(x, y)
    local drag = self.drag
    local destination = self:GroupDestination(x, y)
    if destination == drag.previewIndex then return end
    self.ClearGroupPreview(drag)
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
                Size.GRID_LEFT + move.column * Size.GRID_STEP, BankGrid.RowItemY(move.line),
                Size.GRID_SLOT_SIZE, Size.GRID_SLOT_SIZE, colour, true)
        end
    end
end

-- Save the group at its drop, or explain why it cannot go there
function LayoutEditorGroup:FinishGroupDrag(x, y)
    local drag = self.drag
    local destination, pane = self:GroupDestination(x, y)
    self:FinishDrag(false)
    if pane ~= nil and pane.name == "unsorted" then
        self:ShowError("A group moves only within the layout. Drag one item at a time to Unsorted.")
        return false
    end
    if destination == nil then return false end
    local saved, reason, changed = self:RecordEdit(self.selectedTag, function()
        return self.store:MoveLayoutItems(
            self.selectedTag, drag.keys, drag.anchorKey, destination, Size.CENTER_COLUMNS)
    end)
    if not saved then
        self:ShowError(reason or "Could not move the items.")
    elseif changed then
        self:NotifyChanged(self.selectedTag)
    end
    return false
end

-- Attach these methods to LayoutEditorWindow
function LayoutEditorGroup.install(target)
    for name, method in pairs(LayoutEditorGroup) do
        if name ~= "install" then target[name] = method end
    end
end

return LayoutEditorGroup
