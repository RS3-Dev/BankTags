-- Edit saved section labels

local TagRules = require("banktags/tags/tag_rules")
local TagLayouts = require("banktags/tags/tag_layouts")
local trim = require("banktags/core/text").trim
local copy, labelText = TagRules.copy, TagRules.labelText

local TagStoreLabels = {}

-- Copy a tag's rows before editing a label
local function labelEdit(store, tag, columnCount)
    if store.data.tags[tag] == nil then return nil end
    local nextData = copy(store.data)
    local rows = nextData.tags[tag].rows
    return nextData, rows, TagLayouts.Render(rows, columnCount)
end

-- Find the saved label on a grid row
local function labelEntryAt(view, row)
    for _, label in ipairs(view.labels) do
        if label.row == row then return label.entry end
    end
    return nil
end

-- List labels at the current grid width
function TagStoreLabels:GetLabels(tag, columnCount)
    local record = self.data.tags[tag]
    return TagLayouts.Render(record ~= nil and record.rows or {}, columnCount).labels
end

-- Read the label on a grid row
function TagStoreLabels:GetLabel(tag, row, columnCount)
    for _, label in ipairs(self:GetLabels(tag, columnCount)) do
        if label.row == row then return label.text end
    end
    return nil
end

-- Add a label starting on a grid row
function TagStoreLabels:InsertLabel(tag, row, text, columnCount)
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

-- Set a row's label or remove empty text
function TagStoreLabels:SetLabel(tag, row, text, columnCount)
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
function TagStoreLabels:RemoveLabel(tag, row, columnCount)
    local nextData, rows, view = labelEdit(self, tag, columnCount)
    local entry = nextData ~= nil and labelEntryAt(view, row) or nil
    if entry == nil then return false, "The label no longer exists." end
    table.remove(rows, entry)
    return self:Commit(nextData, "Could not save the label.")
end

-- Move only a label to another grid row
function TagStoreLabels:MoveLabel(tag, fromRow, toRow, columnCount)
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

-- Add label editing to the tag store
function TagStoreLabels.install(target)
    for name, method in pairs(TagStoreLabels) do
        if name ~= "install" then target[name] = method end
    end
end

return TagStoreLabels
