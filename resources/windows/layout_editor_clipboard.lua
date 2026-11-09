-- Copy the selected items and paste more slots for the same objects into empty cells

local Parts = require("resources/windows/layout_editor_parts")
local Size = Parts.size

local LayoutEditorClipboard = {}

-- Copy selected items while keeping their positions relative
function LayoutEditorClipboard:CopySelected()
    local entry, paneName = self:SelectedEntry()
    if entry == nil then
        self:ShowError("Select a layout item first.")
        return false
    end
    local columns = Size.CENTER_COLUMNS
    local picked = {}
    if paneName == "unsorted" then
        picked[1] = { slot = entry, line = 0, column = 0 }
    else
        for _, layoutKey in ipairs(self:SortedKeys(self.groupKeys or { [entry.layoutKey] = true })) do
            local index = self.layout.sortedIndex[layoutKey] - 1
            picked[#picked + 1] = { slot = self.layout.slots[index + 1],
                line = index // columns, column = index % columns }
        end
    end
    local top, left = math.huge, math.huge
    for _, item in ipairs(picked) do
        top, left = math.min(top, item.line), math.min(left, item.column)
    end
    local items = {}
    for _, item in ipairs(picked) do
        items[#items + 1] = { objectID = item.slot.objectID, line = item.line - top, column = item.column - left }
    end
    self.clipboard = { tag = self.selectedTag, items = items }
    self:ShowNotice("Copied " .. #items .. (#items == 1 and " item." or " items."))
    return true
end

-- Paste copies at the selected empty cell
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
    -- Save the copies before selecting their new slots
    return (self:SaveEdit("Could not paste the items.", function()
        local saved, keys, reason = self.store:PasteLayoutItems(tag, clipboard.items, cell, Size.CENTER_COLUMNS)
        -- The copies are selected before the grids redraw
        if saved then self:SelectItems(keys) end
        return saved, reason
    end))
end

return LayoutEditorClipboard
