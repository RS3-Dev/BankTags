-- Edit labels and rows while checking pending actions

local Parts = require("resources/windows/layout_editor_parts")
local Size = Parts.size

local LayoutEditorRows = {}

-- Ask for label text while the layout remains unchanged
function LayoutEditorRows:PromptLabel(text, save, remove)
    local tag = self.selectedTag
    if tag == nil or self.onPromptLabel == nil then return false end
    local target = { tag = tag, columns = Size.CENTER_COLUMNS, data = self.store.data }
    -- Run a prompt action only while its target remains valid
    local function current(edit)
        -- Refuse label edits after their captured layout changes
        return function(value)
            if not self:RowTargetCurrent(target) then
                return false, "The editor changed, so the label was not saved. Cancel and try again."
            end
            return self:SaveEdit(nil, function() return edit(tag, value) end)
        end
    end
    self.onPromptLabel({ text = text, onSave = current(save), onDelete = remove ~= nil and current(remove) or nil })
    return true
end

-- Rename or delete a label through the text prompt
function LayoutEditorRows:EditLabel(row)
    local current = self.store:GetLabel(self.selectedTag, row, Size.CENTER_COLUMNS)
    if current == nil then return false end
    -- Save the new text for this label
    return self:PromptLabel(current, function(tag, value)
        return self.store:SetLabel(tag, row, value, Size.CENTER_COLUMNS)
    end, function(tag)
        return self.store:RemoveLabel(tag, row, Size.CENTER_COLUMNS)
    end)
end

-- Ask for a new label at the chosen row
function LayoutEditorRows:PromptNewLabel(row)
    -- Insert the new label at the captured row
    return self:PromptLabel(nil, function(tag, value)
        return self.store:InsertLabel(tag, row, value, Size.CENTER_COLUMNS)
    end)
end

-- Choose a label row from the selection or paste cell
function LayoutEditorRows:DefaultLabelRow()
    local index = self.layout.sortedIndex[self.selectedLayoutKey] or self.pasteCell
    -- The store puts rows past the layout at its end
    return index ~= nil and (index - 1) // Size.CENTER_COLUMNS or math.maxinteger
end

-- Find an uncovered editor row or Unsorted item
function LayoutEditorRows:RowMenuTarget()
    if self.window == nil or self.window.root.hidden or self.drag ~= nil
        or self.selectedTag == nil or self:OverlayShown() then return nil end
    local x, y = self:ContentPointer()
    local pane, paneX, paneY
    if x ~= nil then pane, paneX, paneY = self:PaneAt(x, y) end
    if pane == nil then return nil end
    local contentWidth = pane.name == "unsorted" and pane.view.contentWidth or nil
    if paneX >= (contentWidth or pane.width - Size.SCROLLBAR_RESERVE) then return nil end
    local row = self:RowAt(pane, paneX, paneY)
    -- An empty layout offers a first row from its background
    if pane.name == "sorted" and self.layout.lines == 0 and paneX >= pane.gridLeft then row = 0 end
    if row == nil then return nil end
    local index = self:SlotIndexAt(pane, paneX, paneY)
    local slot = index ~= nil and pane.slots[index] or nil
    if pane.name == "unsorted" and (slot == nil or slot.kind ~= "item") then return nil end
    return {
        tag = self.selectedTag,
        pane = pane.name,
        row = row,
        usedRows = self.layout.lines,
        columns = Size.CENTER_COLUMNS,
        data = self.store.data,
        layoutKey = slot ~= nil and slot.kind == "item" and slot.layoutKey or nil,
    }
end

-- Check whether a captured layout target is still valid
function LayoutEditorRows:RowTargetCurrent(target)
    return self.window ~= nil and not self.window.root.hidden and self.drag == nil
        and self.selectedTag == target.tag
        and self.store.data == target.data
        and Size.CENTER_COLUMNS == target.columns
end

-- Insert an empty row at the chosen line
function LayoutEditorRows:InsertEmptyRow(line)
    -- Save the row insertion as one undo step
    return (self:SaveEdit("Could not add the row.", function()
        return self.store:InsertLayoutRow(self.selectedTag, line, Size.CENTER_COLUMNS)
    end))
end

-- Describe what removing a line takes out of the tag as separate lines (RS3 fonts do not render \n)
local function removeRowLines(tag, contents)
    local name = "\"" .. tostring(tag) .. "\""
    if contents.label ~= nil then
        return {
            "Remove the label \"" .. contents.label .. "\" from " .. name .. "?",
            "The rows below it move up.",
        }
    end
    local parts = {}
    if contents.items > 0 then
        parts[#parts + 1] = contents.items .. (contents.items == 1 and " item" or " items")
    end
    if contents.reserved > 0 then
        parts[#parts + 1] = contents.reserved .. (contents.reserved == 1 and " reserved slot" or " reserved slots")
    end
    return {
        "Remove this row and its " .. table.concat(parts, " and ") .. " from " .. name .. "?",
        "Only the tag changes; your bank keeps every item.",
    }
end

-- Remove an empty row or ask before removing contents
function LayoutEditorRows:RemoveRow(line)
    local tag = self.selectedTag
    local contents = tag ~= nil and self.store:LayoutLineContents(tag, line, Size.CENTER_COLUMNS) or nil
    if contents == nil then return false end
    -- Save a line's removal as one undo step
    local function remove()
        -- Save the row removal as one undo step
        return self:SaveEdit("Could not remove the row.", function()
            return self.store:RemoveLayoutRow(tag, line, Size.CENTER_COLUMNS)
        end)
    end
    if contents.empty then return (remove()) end
    if self.onConfirmRemoveRow == nil then return false end
    local target = { tag = tag, row = line, columns = Size.CENTER_COLUMNS, data = self.store.data }
    local displayName = self.store.GetTagName ~= nil and self.store:GetTagName(tag) or tag
    local lines = removeRowLines(displayName, contents)
    self.onConfirmRemoveRow({
        message = lines[1] .. " " .. lines[2],
        messageLines = lines,
        -- Refuse removal if the confirmed row has changed
        onConfirm = function()
            -- Any save, another tag or size, or a closed editor makes it out of date
            if not self:RowTargetCurrent(target) then
                return false, "The layout changed, so the row was not removed. Cancel and try again."
            end
            local saved, reason = remove()
            return saved, reason
        end,
    })
    return true
end

return LayoutEditorRows
