-- Copy, remove, move, undo, and redo layout items from the keyboard

local Config = require("banktags/core/config")
local Parts = require("banktags/windows/layout_editor_parts")
local Size = Parts.size

local KEY_EVENT = Config.PLUGIN_REF .. "_layout_editor_keys"
-- Ctrl's bit in a key event's modifiers, ModifierKey.CONTROL in the docs
local CONTROL_MODIFIER = 2

local LayoutEditorKeys = {}

-- Listen for shortcut keys while the editor is open
function LayoutEditorKeys:StartShortcuts()
    self.heldKeys = {}
    self.keysOnGrid = false
    Event.KeyDown.Subscribe(KEY_EVENT, function(event) self:KeyPressed(event) end)
    Event.KeyUp.Subscribe(KEY_EVENT, function(event) self.heldKeys[event.gameKey] = nil end)
    -- A menu may lead to a window with its own text field
    Event.MiniMenuOpened.Subscribe(KEY_EVENT, function() self.keysOnGrid = false end)
    -- Key releases are missed while the game is in the background
    Event.WindowFocusChanged.Subscribe(KEY_EVENT, function()
        self.heldKeys = {}
        self.keysOnGrid = false
    end)
    -- Clicking the item search gives it the keys
    self.itemSearch.root:Subscribe(ui.Hook.ONCLICK, function()
        self.keysOnGrid = false
        return true
    end)
end

-- Stop listening for shortcut keys
function LayoutEditorKeys:StopShortcuts()
    Event.KeyDown.Unsubscribe(KEY_EVENT)
    Event.KeyUp.Unsubscribe(KEY_EVENT)
    Event.MiniMenuOpened.Unsubscribe(KEY_EVENT)
    Event.WindowFocusChanged.Unsubscribe(KEY_EVENT)
    self.heldKeys = {}
    self.keysOnGrid = false
end

-- Check whether a window opened from the editor is showing
function LayoutEditorKeys:OverlayShown()
    for _, overlay in ipairs(self.overlayWindows) do
        if overlay.root ~= nil and not overlay.root.hidden then return true end
    end
    return false
end

-- Check whether the grids have the keys
function LayoutEditorKeys:KeysReady()
    return self.keysOnGrid
        and self.window ~= nil
        and not self.window.root.hidden
        and self.drag == nil
        and not self:OverlayShown()
        and not MiniMenu.IsOpen()
        and not prettyui.KeybindField.IsCapturing()
end

-- Check whether a shortcut may act on the selected item
function LayoutEditorKeys:ShortcutsReady()
    return self:KeysReady() and self:SelectedEntry() ~= nil
end

-- Move the selected sorted item or group one cell, as a drag there would
-- The grid's edges stop it quietly; a label's line says why
function LayoutEditorKeys:NudgeSelected(columnStep, lineStep)
    local entry = self:SelectedEntry()
    if entry == nil or entry.unarranged then return false end
    local columns = Size.CENTER_COLUMNS
    local anchor = nil
    for index, slot in ipairs(self.panes.sorted.slots) do
        if type(slot) == "table" and slot.layoutKey == entry.layoutKey then anchor = index end
    end
    if anchor == nil then return false end
    local line = (anchor - 1) // columns + lineStep
    local column = (anchor - 1) % columns + columnStep
    if line < 0 or column < 0 or column >= columns then return false end
    local keys = self.groupKeys ~= nil and self:SortedKeys(self.groupKeys) or { entry.layoutKey }
    local destination = line * columns + column + 1
    local plan = self.store:PlanLayoutItemsMove(self.selectedTag, keys, entry.layoutKey, destination, columns)
    if plan ~= nil and plan.offGrid then return false end
    local saved, reason, changed = self:RecordEdit(self.selectedTag, function()
        return self.store:MoveLayoutItems(self.selectedTag, keys, entry.layoutKey, destination, columns)
    end)
    if not saved then
        self:ShowError(reason or "Could not move the items.")
        return false
    end
    if changed then
        self:RefreshCenter()
        self:NotifyChanged()
    end
    return changed
end

-- Unmodified arrow keys, as column and line steps
local function arrowSteps(key)
    if key == GameKey.LEFT then return -1, 0 end
    if key == GameKey.RIGHT then return 1, 0 end
    if key == GameKey.UP then return 0, -1 end
    if key == GameKey.DOWN then return 0, 1 end
    return nil, nil
end

-- Run each shortcut once per press
function LayoutEditorKeys:KeyPressed(event)
    local key = event.gameKey
    if event.isRepeat or self.heldKeys[key] then return end
    self.heldKeys[key] = true

    local plain = event.modifiers == 0
    local control = event.modifiers == CONTROL_MODIFIER
    if control and (key == GameKey.Z or key == GameKey.Y) then
        if not self:KeysReady() then return end
        if key == GameKey.Z then self:Undo() else self:Redo() end
        return
    end
    local columnStep, lineStep = arrowSteps(key)
    local isDelete = key == GameKey.DELETE and plain
    local isCopy = key == GameKey.C and control
    local isArrow = columnStep ~= nil and plain
    if not (isDelete or isCopy or isArrow) or not self:ShortcutsReady() then return end
    if isArrow then
        self:NudgeSelected(columnStep, lineStep)
    elseif isDelete then
        self:RemoveSelected()
    else
        self:DuplicateSelected()
    end
end

-- Attach these methods to LayoutEditorWindow
function LayoutEditorKeys.install(target)
    for name, method in pairs(LayoutEditorKeys) do
        if name ~= "install" then target[name] = method end
    end
end

return LayoutEditorKeys
