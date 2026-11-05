-- Edit labels and rows, validating deferred prompts and context-menu targets.

local Parts = require("banktags/windows/layout_editor_parts")
local Size = Parts.size

local LayoutEditorRows = {}

-- Ask for a label's text, saving it with an edit of the open tag
-- A prompt left open after the editor closes or changes tag saves nothing
function LayoutEditorRows:PromptLabel(text, save, remove)
    local tag = self.selectedTag
    if tag == nil or self.onPromptLabel == nil then return false end
    -- Run one prompt action while this editor still shows the tag
    local function current(edit)
        return function(value)
            if self.window == nil or self.selectedTag ~= tag then
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
    return self:PromptLabel(current, function(tag, value)
        return self.store:SetLabel(tag, row, value, Size.CENTER_COLUMNS)
    end, function(tag)
        return self.store:RemoveLabel(tag, row, Size.CENTER_COLUMNS)
    end)
end

-- Ask for a new label's text, adding it at a row once saved
function LayoutEditorRows:PromptNewLabel(row)
    return self:PromptLabel(nil, function(tag, value)
        return self.store:InsertLabel(tag, row, value, Size.CENTER_COLUMNS)
    end)
end

-- Pick a new label's row: above the selection or paste cell, or after the items
function LayoutEditorRows:DefaultLabelRow()
    local index = self.layout.sortedIndex[self.selectedLayoutKey] or self.pasteCell
    -- The store puts rows past the layout at its end
    return index ~= nil and (index - 1) // Size.CENTER_COLUMNS or math.maxinteger
end

-- Find an editor row or Unsorted item under the pointer for a context menu.
-- Scrollbars, Search, empty Unsorted cells, and covering windows offer nothing.
function LayoutEditorRows:RowMenuTarget()
    if self.window == nil or self.window.root.hidden or self.drag ~= nil
        or self.selectedTag == nil or self:OverlayShown() then return nil end
    local x, y = self:ContentPointer()
    local pane, paneX, paneY
    if x ~= nil then pane, paneX, paneY = self:PaneAt(x, y) end
    if pane == nil or paneX >= pane.width - Size.SCROLLBAR_RESERVE then return nil end
    local row = self:RowAt(pane, paneX, paneY)
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

-- Check that a menu's row still means the same place in this editor
function LayoutEditorRows:RowTargetCurrent(target)
    return self.window ~= nil and not self.window.root.hidden and self.drag == nil
        and self.selectedTag == target.tag
        and self.store.data == target.data
        and Size.CENTER_COLUMNS == target.columns
end

-- Insert an empty row at a grid line, moving the rows below it down
function LayoutEditorRows:InsertEmptyRow(line)
    return (self:SaveEdit("Could not add the row.", function()
        return self.store:InsertLayoutRow(self.selectedTag, line, Size.CENTER_COLUMNS)
    end))
end

-- Describe what removing a line takes out of the tag
local function removeRowMessage(tag, contents)
    local name = "<col=ffcb05>\"" .. tostring(tag) .. "\"</col>"
    if contents.label ~= nil then
        return "Remove the label <col=ffcb05>\"" .. contents.label .. "\"</col> from " .. name
            .. "?<br>The rows below it move up."
    end
    local parts = {}
    if contents.items > 0 then
        parts[#parts + 1] = contents.items .. (contents.items == 1 and " item" or " items")
    end
    if contents.reserved > 0 then
        parts[#parts + 1] = contents.reserved .. (contents.reserved == 1 and " reserved slot" or " reserved slots")
    end
    return "Remove this row and its " .. table.concat(parts, " and ") .. " from " .. name
        .. "?<br>Only the tag changes; your bank keeps every item."
end

-- Remove a grid line and everything on it, moving the rows below it up
-- An empty line goes at once; anything else asks first
function LayoutEditorRows:RemoveRow(line)
    local tag = self.selectedTag
    local contents = tag ~= nil and self.store:LayoutLineContents(tag, line, Size.CENTER_COLUMNS) or nil
    if contents == nil then return false end
    -- Save a line's removal as one undo step
    local function remove()
        return self:SaveEdit("Could not remove the row.", function()
            return self.store:RemoveLayoutRow(tag, line, Size.CENTER_COLUMNS)
        end)
    end
    if contents.empty then return (remove()) end
    if self.onConfirmRemoveRow == nil then return false end
    local target = { tag = tag, row = line, columns = Size.CENTER_COLUMNS, data = self.store.data }
    self.onConfirmRemoveRow({
        message = removeRowMessage(tag, contents),
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
