-- Read and edit stored item layouts, rows, and undo snapshots

local TagRules = require("resources/tags/tag_rules")
local TagLayouts = require("resources/tags/tag_layouts")
local copy = TagRules.copy

local TagStoreLayouts = {}

-- Write grid cells, adding rows below the layout
local function writeCells(rows, view, writes)
    local columns, firstAdded = view.columns, #rows + 1
    for index, slot in pairs(writes) do
        local cell = view.cells[index]
        local slots, position
        if cell ~= nil then
            slots, position = rows[cell.entry].slots, cell.position
        else
            local entry = firstAdded + (index - 1) // columns - view.lines
            for added = #rows + 1, entry do rows[added] = { kind = "row", slots = {} } end
            slots, position = rows[entry].slots, (index - 1) % columns + 1
        end
        for padding = #slots + 1, position - 1 do slots[padding] = { kind = "blank" } end
        slots[position] = slot
    end
end

-- Arrange saved items and labels for the editor
function TagStoreLayouts:EditorLayout(tag, columnCount)
    local record = self.data.tags[tag]
    local view = TagLayouts.Render(record ~= nil and record.rows or {}, columnCount)
    local layout = { slots = view.slots, labels = view.labels, lines = view.lines,
        unsorted = {}, sortedIndex = {}, unsortedIndex = {} }
    for index, slot in ipairs(view.slots) do
        if slot.kind == "item" then layout.sortedIndex[slot.layoutKey] = index end
    end
    for _, slot in ipairs(record ~= nil and record.unsorted or {}) do
        if slot.kind == "item" then
            layout.unsorted[#layout.unsorted + 1] = slot
            layout.unsortedIndex[slot.layoutKey] = #layout.unsorted
        end
    end
    return layout
end

-- List the item slots in a tag, arranged ones first
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

-- Move an item, swapping with its destination
function TagStoreLayouts:MoveLayoutItem(tag, layoutKey, destinationIndex, columnCount)
    destinationIndex = math.tointeger(tonumber(destinationIndex))
    if self.data.tags[tag] == nil or destinationIndex == nil or destinationIndex < 1 then
        return false, "The requested layout position is invalid.", false
    end
    local layout = self:EditorLayout(tag, columnCount)
    local sourceIndex = layout.sortedIndex[layoutKey]
    local unsorted = sourceIndex == nil
    if unsorted and layout.unsortedIndex[layoutKey] == nil then
        return false, "The selected item is no longer in this layout.", false
    end
    if sourceIndex == destinationIndex then
        return true, nil, false
    end
    local nextData = copy(self.data)
    local record = nextData.tags[tag]
    local rows = record.rows
    local view = TagLayouts.Render(rows, columnCount)
    local columns = view.columns
    local destinationLine = math.floor((destinationIndex - 1) / columns)
    if destinationLine < view.lines and view.cells[destinationIndex] == nil then
        return false, "A label takes up its whole row.", false
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

-- Check where a group would land without changing it
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

-- Move a group, filling vacated cells with displaced items
function TagStoreLayouts:MoveLayoutItems(tag, layoutKeys, anchorKey, destinationIndex, columnCount)
    local plan, reason = self:PlanLayoutItemsMove(tag, layoutKeys, anchorKey, destinationIndex, columnCount)
    if plan == nil then return false, reason, false end
    if not plan.valid then return false, plan.reason, false end
    if not plan.changed then return true, nil, false end

    local nextData = copy(self.data)
    local rows = nextData.tags[tag].rows
    local view = TagLayouts.Render(rows, columnCount)
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
    writeCells(rows, view, writes)
    local saved, saveReason = self:Commit(nextData, "Could not save the layout.")
    return saved, saveReason, saved
end

-- Insert a grid row, splitting wrapped rows when needed
function TagStoreLayouts:InsertLayoutRow(tag, line, columnCount)
    line = math.tointeger(tonumber(line))
    if self.data.tags[tag] == nil or line == nil or line < 0 then
        return false, "The row position is invalid."
    end
    local nextData = copy(self.data)
    local rows = nextData.tags[tag].rows
    local view = TagLayouts.Render(rows, columnCount)
    if line > view.lines then return false, "The row position is outside the layout." end
    local index = TagLayouts.EntryAtLine(view, rows, line)
    local added = 1
    local split = line - (view.starts[index] or view.lines)
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

-- Count a grid line's items, label, and reserved slots
function TagStoreLayouts:LayoutLineContents(tag, line, columnCount)
    local record = self.data.tags[tag]
    line = math.tointeger(tonumber(line))
    if record == nil or line == nil or line < 0 then return nil end
    local view = TagLayouts.Render(record.rows, columnCount)
    if line >= view.lines then return nil end
    local contents = { items = 0, reserved = 0 }
    for _, label in ipairs(view.labels) do
        if label.row == line then contents.label = label.text end
    end
    for cell = line * view.columns + 1, (line + 1) * view.columns do
        local slot = view.slots[cell]
        if slot.kind == "item" then
            contents.items = contents.items + 1
        elseif not TagLayouts.IsOpen(slot) then
            contents.reserved = contents.reserved + 1
        end
    end
    contents.empty = contents.label == nil and contents.items == 0 and contents.reserved == 0
    return contents
end

-- Remove one grid line and its contents
function TagStoreLayouts:RemoveLayoutRow(tag, line, columnCount)
    if self:LayoutLineContents(tag, line, columnCount) == nil then
        return false, "There is no row there to remove."
    end
    line = math.tointeger(tonumber(line))
    local nextData = copy(self.data)
    local rows = nextData.tags[tag].rows
    local view = TagLayouts.Render(rows, columnCount)
    local index = TagLayouts.EntryAtLine(view, rows, line)
    if rows[index].kind == "label" or #rows[index].slots <= view.columns then
        table.remove(rows, index)
    else
        local slots = rows[index].slots
        local first = (line - view.starts[index]) * view.columns + 1
        for position = math.min(first + view.columns - 1, #slots), first, -1 do
            table.remove(slots, position)
        end
    end
    return self:Commit(nextData, "Could not save the layout.")
end

-- Copy the rows and Unsorted items for undo
function TagStoreLayouts:LayoutState(tag)
    local record = self.data.tags[tag]
    if record == nil then return nil end
    return { rows = copy(record.rows), unsorted = copy(record.unsorted) }
end

-- Restore rows and Unsorted items without changing tag settings
function TagStoreLayouts:RestoreLayoutState(tag, state)
    if self.data.tags[tag] == nil then return false, "The tag no longer exists." end
    local nextData = copy(self.data)
    nextData.tags[tag].rows = copy(state.rows)
    nextData.tags[tag].unsorted = copy(state.unsorted)
    return self:Commit(nextData, "Could not save the layout.")
end

-- Move selected layout items to Unsorted together
function TagStoreLayouts:UnarrangeLayoutItems(tag, layoutKeys)
    if self.data.tags[tag] == nil or #layoutKeys == 0 then
        return false, "The item is no longer in the preserved layout."
    end
    local nextData = copy(self.data)
    local record = nextData.tags[tag]
    local moved = self.TakeSlots(record, layoutKeys, true)
    if #moved ~= #layoutKeys then return false, "The item is no longer in the preserved layout." end
    for _, slot in ipairs(moved) do record.unsorted[#record.unsorted + 1] = slot end
    return self:Commit(nextData, "Could not save the layout.")
end

-- Move one layout item to Unsorted
function TagStoreLayouts:UnarrangeLayoutItem(tag, layoutKey)
    return self:UnarrangeLayoutItems(tag, { layoutKey })
end

-- Paste item copies only when every destination is empty
function TagStoreLayouts:PasteLayoutItems(tag, items, destinationIndex, columnCount)
    destinationIndex = math.tointeger(tonumber(destinationIndex))
    if self.data.tags[tag] == nil or destinationIndex == nil or destinationIndex < 1
        or type(items) ~= "table" or #items == 0 then
        return false, nil, "The paste position is invalid."
    end
    local nextData = copy(self.data)
    local rows = nextData.tags[tag].rows
    local view = TagLayouts.Render(rows, columnCount)
    local columns = view.columns
    local line, column = (destinationIndex - 1) // columns, (destinationIndex - 1) % columns
    local writes, keys = {}, {}
    for _, item in ipairs(items) do
        local itemLine, itemColumn = line + item.line, column + item.column
        if itemColumn >= columns then return false, nil, "The copies do not fit there." end
        local index = itemLine * columns + itemColumn + 1
        if itemLine < view.lines and (view.cells[index] == nil or not TagLayouts.IsOpen(view.slots[index])) then
            return false, nil, "Paste needs empty cells; an item, reserved slot, or label is in the way."
        end
        local slot = TagLayouts.Item(item.objectID)
        keys[#keys + 1] = slot.layoutKey
        writes[index] = slot
    end
    writeCells(rows, view, writes)
    local saved, reason = self:Commit(nextData, "Could not save the pasted copies.")
    if not saved then return false, nil, reason end
    return true, keys, nil
end

-- Attach these methods to TagStore
function TagStoreLayouts.install(target)
    for name, method in pairs(TagStoreLayouts) do
        if name ~= "install" then target[name] = method end
    end
end

return TagStoreLayouts
