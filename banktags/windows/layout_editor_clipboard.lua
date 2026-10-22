-- Copy the selected items and paste new copies of them into empty cells

local Parts = require("banktags/windows/layout_editor_parts")
local Size = Parts.size

local LayoutEditorClipboard = {}

-- Copy the selected item or group, keeping each one's offset from the group's top-left cell
-- Nothing is saved; each paste adds new copies of the same bank stacks
function LayoutEditorClipboard:CopySelected()
    local entry = self:SelectedEntry()
    if entry == nil or self.selectedTag == nil then
        self:ShowError("Select a layout item first.")
        return false
    end
    local columns = Size.CENTER_COLUMNS
    local picked = {}
    if entry.unarranged then
        picked[1] = { slot = entry, line = 0, column = 0 }
    else
        local keys = self.groupKeys or { [entry.layoutKey] = true }
        for index, slot in ipairs(self.panes.sorted.slots) do
            if type(slot) == "table" and slot.kind == "item" and keys[slot.layoutKey] then
                picked[#picked + 1] = { slot = slot, line = (index - 1) // columns, column = (index - 1) % columns }
            end
        end
    end
    local top, left = math.huge, math.huge
    for _, item in ipairs(picked) do
        top, left = math.min(top, item.line), math.min(left, item.column)
    end
    local items = {}
    for _, item in ipairs(picked) do
        items[#items + 1] = {
            objectID = item.slot.objectID,
            -- A copy of a copy opens the same stack as the first
            sourceLayoutKey = item.slot.sourceLayoutKey or item.slot.layoutKey,
            line = item.line - top,
            column = item.column - left,
        }
    end
    self.clipboard = { tag = self.selectedTag, items = items }
    self:ShowNotice("Copied " .. #items .. (#items == 1 and " item" or " items")
        .. ". Click an empty cell, then press Ctrl+V or Paste.")
    return true
end

-- Paste new copies with the copied top-left item at the outlined empty cell
-- Every cell they take must be empty, or nothing is pasted
function LayoutEditorClipboard:PasteClipboard()
    local clipboard = self.clipboard
    if clipboard == nil or clipboard.tag ~= self.selectedTag then
        self:ShowError("Copy an item or group first (Ctrl+C).")
        return false
    end
    if self.pasteCell == nil then
        self:ShowError("Click an empty cell in the layout to paste there.")
        return false
    end
    local tag, cell = self.selectedTag, self.pasteCell
    local saved, keys, reason = self:RecordEdit(tag, function()
        return self.store:PasteLayoutItems(tag, clipboard.items, cell, Size.CENTER_COLUMNS)
    end)
    if not saved then
        self:ShowError(reason or "Could not paste the items.")
        return false
    end
    self:SelectItems(keys)
    self:NotifyChanged(tag)
    return true
end

-- Attach these methods to LayoutEditorWindow
function LayoutEditorClipboard.install(target)
    for name, method in pairs(LayoutEditorClipboard) do
        if name ~= "install" then target[name] = method end
    end
end

return LayoutEditorClipboard
