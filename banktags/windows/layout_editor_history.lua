-- Undo and redo the open tag's layout edits

local LayoutEditorHistory = {}

-- Undo steps kept for the open tag
local HISTORY_LIMIT = 50

-- Check whether two saved values hold the same data
local function sameValue(left, right)
    if type(left) ~= "table" or type(right) ~= "table" then return left == right end
    for key, value in pairs(left) do
        if not sameValue(value, right[key]) then return false end
    end
    for key in pairs(right) do
        if left[key] == nil then return false end
    end
    return true
end

-- Forget every undo step
function LayoutEditorHistory:ClearHistory()
    self.history = nil
end

-- Forget the steps if the open tag changed outside the editor
function LayoutEditorHistory:CheckHistory()
    local history = self.history
    if history == nil then return end
    if history.tag ~= self.selectedTag
        or not sameValue(self.store:LayoutState(history.tag), history.states[history.index]) then
        self.history = nil
    end
end

-- Run one edit of the open tag, keeping it as one undo step if it changed the layout
-- Returns whether the layout changed, then the edit's results
-- Failed and unchanged edits leave the steps as they were, even when they saved a fresh copy
function LayoutEditorHistory:RecordEdit(edit)
    local tag = self.selectedTag
    local before = self.store:LayoutState(tag)
    local results = table.pack(edit())
    local after = self.store:LayoutState(tag)
    if before == nil or after == nil or sameValue(before, after) then
        return false, table.unpack(results, 1, results.n)
    end
    local history = self.history
    -- Steps from before an outside change would overwrite it
    if history == nil or history.tag ~= tag or not sameValue(history.states[history.index], before) then
        history = { tag = tag, states = { before }, index = 1 }
        self.history = history
    end
    -- A new edit drops the steps that were undone
    for index = #history.states, history.index + 1, -1 do history.states[index] = nil end
    history.states[#history.states + 1] = after
    history.index = #history.states
    if #history.states > HISTORY_LIMIT + 1 then
        table.remove(history.states, 1)
        history.index = history.index - 1
    end
    return true, table.unpack(results, 1, results.n)
end

-- Save one edit of the open tag as an undo step, redrawing when the layout changed
-- A failure shows its reason, or the given text, unless the caller shows it itself
-- Returns whether it saved, the failure reason, and whether the layout changed
function LayoutEditorHistory:SaveEdit(failure, edit)
    local changed, saved, reason = self:RecordEdit(edit)
    if not saved then
        reason = reason or failure
        if failure ~= nil then self:ShowError(reason) end
        return false, reason, false
    end
    self:ClearStatus()
    if changed then self:NotifyChanged() end
    return true, nil, changed
end

-- Report whether there is a step to undo or redo
function LayoutEditorHistory:CanStepHistory(step)
    local history = self.history
    return history ~= nil and history.tag == self.selectedTag
        and history.states[history.index + step] ~= nil
end

-- Restore the layout one step back or forward in one save
function LayoutEditorHistory:StepHistory(step)
    if not self:CanStepHistory(step) then return false end
    local history = self.history
    local tag = history.tag
    if not sameValue(self.store:LayoutState(tag), history.states[history.index]) then
        self.history = nil
        self:ShowError("This tag changed outside the editor, so there is nothing to undo or redo.")
        return false
    end
    local saved, reason = self.store:RestoreLayoutState(tag, history.states[history.index + step])
    if not saved then
        self:ShowError(reason or "Could not restore the layout.")
        return false
    end
    history.index = history.index + step
    self:ClearStatus()
    self:NotifyChanged()
    return true
end

-- Undo the last layout edit
function LayoutEditorHistory:Undo()
    return self:StepHistory(-1)
end

-- Redo the last undone layout edit
function LayoutEditorHistory:Redo()
    return self:StepHistory(1)
end

return LayoutEditorHistory
