-- Read and edit tag layouts and their labels for TagStore

local TagRules = require("banktags/tags/tag_rules")
local TagLayouts = require("banktags/tags/tag_layouts")
local TagData = require("banktags/tags/tag_data")
local ItemIdentity = require("banktags/tags/item_identity")
local trim = require("banktags/core/text").trim
local copy = TagRules.copy
local labelText = TagRules.labelText

local TagStoreLayouts = {}

-- Lay out the rows, then the Unsorted heading and items
function TagStoreLayouts:GetLayout(tag, columnCount)
    local record = self.data.tags[tag]
    local view = TagLayouts.Render(record ~= nil and record.rows or {}, columnCount)
    local slots = copy(view.slots)
    local boundary = view.lines * view.columns
    local unsorted = {}
    for _, slot in ipairs(record ~= nil and record.unsorted or {}) do
        if slot.kind == "item" then unsorted[#unsorted + 1] = slot end
    end
    if #unsorted > 0 then
        while #slots < boundary + view.columns do slots[#slots + 1] = { kind = "blank" } end
        for _, item in ipairs(unsorted) do
            local slot = copy(item)
            slot.unarranged = true
            slots[#slots + 1] = slot
        end
    end
    local labels = {}
    for _, label in ipairs(view.labels) do
        labels[#labels + 1] = { row = label.row, text = label.text }
    end
    return slots, boundary, labels
end

-- List the item copies in a tag, arranged ones first
function TagStoreLayouts:GetTaggedItems(tag)
    local record = self.data.tags[tag]
    local items = {}
    if record == nil then return items end
    for _, slots in ipairs({ TagLayouts.RowSlots(record.rows), record.unsorted }) do
        for _, slot in ipairs(slots) do
            if slot.kind == "item" then
                items[#items + 1] = { objectID = slot.objectID, layoutKey = slot.layoutKey }
            end
        end
    end
    return items
end

-- Place an item at a grid index of the rows, swapping out any item there
-- Indexes past the rows add rows; Unsorted items are not on this grid
function TagStoreLayouts:MoveLayoutItem(tag, layoutKey, destinationIndex, columnCount)
    destinationIndex = math.tointeger(tonumber(destinationIndex))
    if self.data.tags[tag] == nil or destinationIndex == nil or destinationIndex < 1 then
        return false, "The requested layout position is invalid.", false
    end
    local slots = self:GetLayout(tag, columnCount)
    local nextData = copy(self.data)
    local record = nextData.tags[tag]
    local rows = record.rows
    local view = TagLayouts.Render(rows, columnCount)
    local columns = view.columns
    local destinationLine = math.floor((destinationIndex - 1) / columns)
    if destinationLine < view.lines and view.cells[destinationIndex] == nil then
        return false, "A label takes up its whole row.", false
    end
    local sourceIndex = nil
    for index, slot in ipairs(slots) do
        if slot.kind == "item" and slot.layoutKey == layoutKey then
            sourceIndex = index
            break
        end
    end
    if sourceIndex == nil then
        return false, "The selected item is no longer in this layout.", false
    end
    local unsorted = slots[sourceIndex].unarranged == true
    if sourceIndex == destinationIndex and not unsorted then
        return true, nil, false
    end

    local destination = view.cells[destinationIndex]
    local displaced = destination ~= nil and rows[destination.entry].slots[destination.position] or nil
    local origin = view.cells[sourceIndex]
    local source
    if origin ~= nil and not unsorted then
        source = rows[origin.entry].slots[origin.position]
        rows[origin.entry].slots[origin.position] = displaced or { kind = "blank" }
    else
        for index, slot in ipairs(record.unsorted) do
            if slot.layoutKey == layoutKey then
                source = table.remove(record.unsorted, index)
                if displaced ~= nil and displaced.kind == "item" then
                    table.insert(record.unsorted, index, displaced)
                end
                break
            end
        end
    end
    if destination ~= nil then
        local row = rows[destination.entry].slots
        for position = #row + 1, destination.position - 1 do row[position] = { kind = "blank" } end
        row[destination.position] = source
    else
        -- Below the rows, pad down to the drop line, then add the item
        for _ = view.lines, destinationLine - 1 do rows[#rows + 1] = { kind = "row", slots = {} } end
        local row = {}
        local column = (destinationIndex - 1) % columns + 1
        for position = 1, column - 1 do row[position] = { kind = "blank" } end
        row[column] = source
        rows[#rows + 1] = { kind = "row", slots = row }
    end
    local saved, reason = self:Commit(nextData, "Could not save the layout.")
    return saved, reason, saved
end

-- Find where arranged items land when one of them moves to a grid index
-- The others keep their row and column offsets; nothing wraps across the edge
function TagStoreLayouts:PlanLayoutItemsMove(tag, layoutKeys, anchorKey, destinationIndex, columnCount)
    destinationIndex = math.tointeger(tonumber(destinationIndex))
    local record = self.data.tags[tag]
    if record == nil or destinationIndex == nil or destinationIndex < 1
        or type(layoutKeys) ~= "table" or #layoutKeys == 0 then
        return nil, "The requested layout position is invalid."
    end
    local view = TagLayouts.Render(record.rows, columnCount)
    local columns = view.columns
    local sources = {}
    for index, slot in ipairs(view.slots) do
        if slot.kind == "item" then sources[slot.layoutKey] = index end
    end
    local anchor = sources[anchorKey]
    if anchor == nil then return nil, "The selected items are no longer in this layout." end
    local lineShift = (destinationIndex - 1) // columns - (anchor - 1) // columns
    local columnShift = (destinationIndex - 1) % columns - (anchor - 1) % columns
    local plan = { moves = {}, valid = true, changed = lineShift ~= 0 or columnShift ~= 0 }
    local seen = {}
    for _, layoutKey in ipairs(layoutKeys) do
        local source = sources[layoutKey]
        if source == nil or seen[layoutKey] then
            return nil, "The selected items are no longer in this layout."
        end
        seen[layoutKey] = true
        local line = (source - 1) // columns + lineShift
        local column = (source - 1) % columns + columnShift
        local move = { layoutKey = layoutKey, source = source, line = line, column = column }
        if line < 0 or column < 0 or column >= columns then
            move.reason = "The selected items do not fit there."
            plan.offGrid = true
        elseif line < view.lines and view.cells[line * columns + column + 1] == nil then
            move.reason = "A label takes up its whole row."
        else
            move.destination = line * columns + column + 1
        end
        if move.reason ~= nil and plan.valid then
            plan.valid, plan.reason = false, move.reason
        end
        plan.moves[#plan.moves + 1] = move
    end
    if not seen[anchorKey] then return nil, "The selected items are no longer in this layout." end
    return plan, nil
end

-- Move arranged items together in one save, keeping their offsets
-- Whatever sat where they land fills the cells they left, in reading order
function TagStoreLayouts:MoveLayoutItems(tag, layoutKeys, anchorKey, destinationIndex, columnCount)
    local plan, reason = self:PlanLayoutItemsMove(tag, layoutKeys, anchorKey, destinationIndex, columnCount)
    if plan == nil then return false, reason, false end
    if not plan.valid then return false, plan.reason, false end
    if not plan.changed then return true, nil, false end

    local nextData = copy(self.data)
    local rows = nextData.tags[tag].rows
    local view = TagLayouts.Render(rows, columnCount)
    local columns, firstAdded = view.columns, #rows + 1
    local writes, moved = {}, {}
    for _, move in ipairs(plan.moves) do
        writes[move.destination] = view.slots[move.source]
        moved[move.source] = true
    end
    local vacated, displaced = {}, {}
    for _, move in ipairs(plan.moves) do
        if writes[move.source] == nil then vacated[#vacated + 1] = move.source end
        if not moved[move.destination] then displaced[#displaced + 1] = move.destination end
    end
    table.sort(vacated)
    table.sort(displaced)
    for position, index in ipairs(displaced) do
        writes[vacated[position]] = view.slots[index] or { kind = "blank" }
    end
    for index, slot in pairs(writes) do
        local cell = view.cells[index]
        local slots, position
        if cell ~= nil then
            slots, position = rows[cell.entry].slots, cell.position
        else
            -- Below the rows each new line is its own row
            local entry = firstAdded + (index - 1) // columns - view.lines
            for added = #rows + 1, entry do rows[added] = { kind = "row", slots = {} } end
            slots, position = rows[entry].slots, (index - 1) % columns + 1
        end
        for padding = #slots + 1, position - 1 do slots[padding] = { kind = "blank" } end
        slots[position] = slot
    end
    local saved, saveReason = self:Commit(nextData, "Could not save the layout.")
    return saved, saveReason, saved
end

-- Insert an empty grid row at a line, moving that line and every one after it down
-- A row wrapped across the line is split there; Unsorted is untouched
function TagStoreLayouts:InsertLayoutRow(tag, line, columnCount)
    line = math.tointeger(tonumber(line))
    if self.data.tags[tag] == nil or line == nil or line < 0 then
        return false, "The row position is invalid."
    end
    local nextData = copy(self.data)
    local rows = nextData.tags[tag].rows
    local view = TagLayouts.Render(rows, columnCount)
    -- Rows past the layout are already empty, and saving trims them
    if line >= view.lines then return false, "There are no rows below to move down." end
    local index = TagLayouts.EntryAtLine(view, rows, line)
    local added = 1
    local split = line - view.starts[index]
    if split > 0 then
        -- Labels take one line, so only a wrapped row starts above the line
        local slots = rows[index].slots
        local tail = table.move(slots, split * view.columns + 1, #slots, 1, {})
        for position = #slots, split * view.columns + 1, -1 do slots[position] = nil end
        TagRules.trimTrailingLayoutBlanks(slots)
        -- Empty lines trimmed from the first part still need a row each
        added = added + split - math.max(1, math.ceil(#slots / view.columns))
        index = index + 1
        table.insert(rows, index, { kind = "row", slots = tail })
    end
    for _ = 1, added do table.insert(rows, index, { kind = "row", slots = {} }) end
    return self:Commit(nextData, "Could not save the layout.")
end

-- Check whether a laid-out line is in a row and holds nothing at all
-- Labels, reserved blanks, items, and lines past the layout do not count
function TagStoreLayouts:IsEmptyLayoutLine(tag, line, columnCount)
    local record = self.data.tags[tag]
    line = math.tointeger(tonumber(line))
    if record == nil or line == nil or line < 0 then return false end
    local view = TagLayouts.Render(record.rows, columnCount)
    if line >= view.lines then return false end
    for cell = line * view.columns + 1, (line + 1) * view.columns do
        if view.cells[cell] == nil or not TagLayouts.IsOpen(view.slots[cell]) then return false end
    end
    return true
end

-- Remove one empty grid line, moving every line after it up
-- Only that line of a wrapped row goes; Unsorted is untouched
function TagStoreLayouts:RemoveEmptyLayoutRow(tag, line, columnCount)
    if not self:IsEmptyLayoutLine(tag, line, columnCount) then
        return false, "Only an empty row can be removed."
    end
    line = math.tointeger(tonumber(line))
    local nextData = copy(self.data)
    local rows = nextData.tags[tag].rows
    local view = TagLayouts.Render(rows, columnCount)
    local index = TagLayouts.EntryAtLine(view, rows, line)
    local slots = rows[index].slots
    if #slots <= view.columns then
        table.remove(rows, index)
    else
        local first = (line - view.starts[index]) * view.columns + 1
        for position = math.min(first + view.columns - 1, #slots), first, -1 do
            table.remove(slots, position)
        end
    end
    return self:Commit(nextData, "Could not save the layout.")
end

-- Copy a tag's rows and Unsorted list, the part the layout editor changes
function TagStoreLayouts:LayoutState(tag)
    local record = self.data.tags[tag]
    if record == nil then return nil end
    return { rows = copy(record.rows), unsorted = copy(record.unsorted) }
end

-- Put back a tag's rows and Unsorted list, keeping its name, icon, and folder
function TagStoreLayouts:RestoreLayoutState(tag, state)
    if self.data.tags[tag] == nil then return false, "The tag no longer exists." end
    local nextData = copy(self.data)
    nextData.tags[tag].rows = copy(state.rows)
    nextData.tags[tag].unsorted = copy(state.unsorted)
    return self:Commit(nextData, "Could not save the layout.")
end

-- Move one arranged item to Unsorted, leaving a blank in its place
function TagStoreLayouts:UnarrangeLayoutItem(tag, layoutKey)
    local record = self.data.tags[tag]
    for _, slot in ipairs(record ~= nil and TagLayouts.RowSlots(record.rows) or {}) do
        if slot.layoutKey == layoutKey then
            local nextData = copy(self.data)
            local moved = self.TakeSlot(nextData.tags[tag], layoutKey)
            local unsorted = nextData.tags[tag].unsorted
            unsorted[#unsorted + 1] = moved
            return self:Commit(nextData, "Could not save the layout.")
        end
    end
    return false, "The item is no longer in the preserved layout."
end

-- Add a ghost copy that opens its source item, returning its key
function TagStoreLayouts:DuplicateLayoutItem(tag, sourceLayoutKey)
    local record = self.data.tags[tag]
    local items = self:GetTaggedItems(tag)
    local source = nil
    for _, item in ipairs(items) do
        if item.layoutKey == sourceLayoutKey then source = item end
    end
    if source == nil then return false, nil, "The selected item is no longer in this layout." end
    local lastCopy = 0
    for _, item in ipairs(items) do
        if item.objectID == source.objectID then
            lastCopy = math.max(lastCopy, TagData.CopyNumber(item.layoutKey) or 0)
        end
    end
    local nextKey = ItemIdentity.LayoutKey(source.objectID, lastCopy + 1)
    local nextData = copy(self.data)
    local rows = nextData.tags[tag].rows
    local sourceEntry, sourcePosition, interactionKey = nil, nil, sourceLayoutKey
    for index, entry in ipairs(rows) do
        for position, slot in ipairs(entry.slots or {}) do
            if slot.layoutKey == sourceLayoutKey then
                sourceEntry, sourcePosition = index, position
                interactionKey = slot.sourceLayoutKey or sourceLayoutKey
            end
        end
    end
    for _, slot in ipairs(record.unsorted) do
        if slot.layoutKey == sourceLayoutKey then interactionKey = slot.sourceLayoutKey or sourceLayoutKey end
    end
    local ghost = {
        kind = "item",
        objectID = source.objectID,
        layoutKey = nextKey,
        sourceLayoutKey = interactionKey,
    }
    -- Place a copy after its source, earlier, or at its row's end
    local targetEntry, targetPosition = TagLayouts.FirstOpenSlot(rows, sourceEntry, sourcePosition)
    if targetEntry ~= nil then
        rows[targetEntry].slots[targetPosition] = ghost
    elseif sourceEntry ~= nil then
        local slots = rows[sourceEntry].slots
        slots[#slots + 1] = ghost
    else
        TagLayouts.AppendToLastRow(rows, ghost)
    end
    local saved, reason = self:Commit(nextData, "Could not save the layout copy.")
    if not saved then return false, nil, reason end
    return true, nextKey, nil
end

-- Copy the data and lay one tag's rows out for a label edit
local function labelEdit(store, tag, columnCount)
    if store.data.tags[tag] == nil then return nil end
    local nextData = copy(store.data)
    local rows = nextData.tags[tag].rows
    return nextData, rows, TagLayouts.Render(rows, columnCount)
end

-- Find the entry index of the label on a grid row
local function labelEntryAt(view, row)
    for _, label in ipairs(view.labels) do
        if label.row == row then return label.entry end
    end
    return nil
end

-- Return the labels and the grid rows they land on at a column count
function TagStoreLayouts:GetLabels(tag, columnCount)
    local _, _, labels = self:GetLayout(tag, columnCount)
    return labels
end

-- Return the text of the label on a grid row, if any
function TagStoreLayouts:GetLabel(tag, row, columnCount)
    for _, label in ipairs(self:GetLabels(tag, columnCount)) do
        if label.row == row then return label.text end
    end
    return nil
end

-- Add a label starting on a grid row
function TagStoreLayouts:InsertLabel(tag, row, text, columnCount)
    local value = labelText(text)
    if value == nil then return false, "Enter the label text." end
    local nextData, rows, view = labelEdit(self, tag, columnCount)
    row = math.tointeger(tonumber(row))
    if nextData == nil or row == nil or row < 0 then return false, "The label position is invalid." end
    local index = TagLayouts.EntryAtLine(view, rows, row)
    local label = { kind = "label", text = value }
    if TagLayouts.IsEmptyRow(rows[index]) and view.starts[index] == row then
        rows[index] = label
    else
        table.insert(rows, index, label)
    end
    return self:Commit(nextData, "Could not save the label.")
end

-- Set the label on a grid row, removing it when text is empty
function TagStoreLayouts:SetLabel(tag, row, text, columnCount)
    local nextData, rows, view = labelEdit(self, tag, columnCount)
    if nextData == nil then return false, "The label position is invalid." end
    local entry = labelEntryAt(view, row)
    local value = labelText(text)
    if value == nil then
        if text ~= nil and trim(text) ~= "" then return false, "The label text is invalid." end
        if entry == nil then return true, nil end
        table.remove(rows, entry)
    elseif entry == nil then
        return self:InsertLabel(tag, row, value, columnCount)
    else
        rows[entry].text = value
    end
    return self:Commit(nextData, "Could not save the label.")
end

-- Delete the label on a grid row, moving entries up
function TagStoreLayouts:RemoveLabel(tag, row, columnCount)
    local nextData, rows, view = labelEdit(self, tag, columnCount)
    local entry = nextData ~= nil and labelEntryAt(view, row) or nil
    if entry == nil then return false, "The label no longer exists." end
    table.remove(rows, entry)
    return self:Commit(nextData, "Could not save the label.")
end

-- Move only a label to another grid row
function TagStoreLayouts:MoveLabel(tag, fromRow, toRow, columnCount)
    local nextData, rows, view = labelEdit(self, tag, columnCount)
    toRow = math.tointeger(tonumber(toRow))
    if nextData == nil or toRow == nil or toRow < 0 then
        return false, "The label position is invalid.", false
    end
    local from = labelEntryAt(view, fromRow)
    if from == nil then return false, "The label no longer exists.", false end
    local target = TagLayouts.EntryAtLine(view, rows, toRow)
    local replace = TagLayouts.IsEmptyRow(rows[target]) and view.starts[target] == toRow
    if target == from or (target == from + 1 and not replace) then return true, nil, false end
    local label = table.remove(rows, from)
    if target > from then target = target - 1 end
    if replace then
        rows[target] = label
    else
        table.insert(rows, target, label)
    end
    local saved, reason = self:Commit(nextData, "Could not save the label.")
    return saved, reason, saved
end

-- Attach these methods to TagStore
function TagStoreLayouts.install(target)
    for name, method in pairs(TagStoreLayouts) do
        if name ~= "install" then target[name] = method end
    end
end

return TagStoreLayouts
