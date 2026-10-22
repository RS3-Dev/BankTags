-- Copy, paste, remove, move, undo, and redo layout items from the keyboard

local Config = require("banktags/core/config")
local DebugLog = require("banktags/core/debug_log")
local Parts = require("banktags/windows/layout_editor_parts")
local Size = Parts.size

local KEY_EVENT = Config.PLUGIN_REF .. "_layout_editor_keys"
-- Modifier bits captured from the live client's key events
local SHIFT_MODIFIER = 1
local CONTROL_MODIFIER = 4
local ALT_MODIFIER = 2
local ANY_MODIFIER = 7

local LayoutEditorKeys = {}

-- Listen for shortcut keys while the editor is open
function LayoutEditorKeys:StartShortcuts()
    self.keysOnGrid = false
    self.menuOnGrid = false
    Event.KeyDown.Subscribe(KEY_EVENT, function(event) self:KeyPressed(event) end)
    -- Another menu may lead to a window with its own text field; the grid's own row menu does not
    Event.MiniMenuOpened.Subscribe(KEY_EVENT, function()
        if not self.menuOnGrid then self.keysOnGrid = false end
    end)
    -- The player may have typed elsewhere while the game was in the background
    Event.WindowFocusChanged.Subscribe(KEY_EVENT, function() self.keysOnGrid = false end)
    -- Clicking the item search gives it the keys
    self.itemSearch.root:Subscribe(ui.Hook.ONCLICK, function()
        self.keysOnGrid = false
        return true
    end)
end

-- Stop listening for shortcut keys
function LayoutEditorKeys:StopShortcuts()
    Event.KeyDown.Unsubscribe(KEY_EVENT)
    Event.MiniMenuOpened.Unsubscribe(KEY_EVENT)
    Event.WindowFocusChanged.Unsubscribe(KEY_EVENT)
    self.keysOnGrid = false
    self.menuOnGrid = false
end

-- Check whether a window opened from the editor is showing
function LayoutEditorKeys:OverlayShown()
    for _, overlay in ipairs(self.overlayWindows) do
        if overlay.root ~= nil and not overlay.root.hidden then return true end
    end
    return false
end

-- Name what keeps the keys from the grids, or nil when they have them
function LayoutEditorKeys:KeysBlocker()
    if not self.keysOnGrid then return "no grid press since focus moved" end
    if self.window == nil or self.window.root.hidden then return "hidden editor" end
    if self.drag ~= nil then return "drag" end
    if self:OverlayShown() then return "window over the editor" end
    if MiniMenu.IsOpen() then return "open menu" end
    if prettyui.KeybindField.IsCapturing() then return "keybind field" end
    return nil
end

-- Check whether the grids have the keys
function LayoutEditorKeys:KeysReady()
    return self:KeysBlocker() == nil
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
    if changed then self:NotifyChanged(self.selectedTag) end
    return changed
end

-- Read the held modifiers from the event and the keyboard
-- Either may report a held key; AltGr arrives as Ctrl and Alt, so it is never Ctrl alone
local function heldModifiers(event)
    local held = (math.tointeger(event.modifiers) or 0) & ANY_MODIFIER
    if Keyboard.IsShiftDown() then held = held | SHIFT_MODIFIER end
    if Keyboard.IsControlDown() then held = held | CONTROL_MODIFIER end
    if Keyboard.IsAltDown() then held = held | ALT_MODIFIER end
    return held
end

-- Name the shortcut a key and its modifiers make, with arrow steps
local function shortcutFor(key, held)
    if held == CONTROL_MODIFIER then
        if key == GameKey.Z then return "undo" end
        if key == GameKey.Y then return "redo" end
        if key == GameKey.C then return "copy" end
        if key == GameKey.V then return "paste" end
        return nil
    end
    if held ~= 0 then return nil end
    if key == GameKey.DELETE then return "remove" end
    if key == GameKey.LEFT then return "move", -1, 0 end
    if key == GameKey.RIGHT then return "move", 1, 0 end
    if key == GameKey.UP then return "move", 0, -1 end
    if key == GameKey.DOWN then return "move", 0, 1 end
    return nil
end

-- Log a chord or shortcut key while debugging, with what blocked it
function LayoutEditorKeys:TraceKey(event, held, shortcut)
    if held == 0 and shortcut == nil and event.gameKey ~= GameKey.CONTROL then return end
    DebugLog.Write("Bank Tags editor key ", tostring(GameKey.FromID(event.gameKey)),
        " gameKey ", tostring(event.gameKey), " systemKey ", tostring(event.systemKey),
        " modifiers ", tostring(event.modifiers), " held ", held, " shortcut ", tostring(shortcut),
        " blocked by ", tostring(self:KeysBlocker() or "nothing"),
        " selected ", tostring(self.selectedLayoutKey))
end

-- Run each shortcut once per press, never on the OS's held-key repeats
function LayoutEditorKeys:KeyPressed(event)
    if event.isRepeat then return end
    local held = heldModifiers(event)
    local shortcut, columnStep, lineStep = shortcutFor(event.gameKey, held)
    if DebugLog.IsEnabled() then self:TraceKey(event, held, shortcut) end
    if shortcut == nil or not self:KeysReady() then return end
    if shortcut == "undo" then
        self:Undo()
    elseif shortcut == "redo" then
        self:Redo()
    elseif shortcut == "paste" then
        self:PasteClipboard()
    elseif self:SelectedEntry() == nil then
        return
    elseif shortcut == "copy" then
        self:CopySelected()
    elseif shortcut == "remove" then
        self:RemoveSelected()
    elseif self.settings().arrowKeyMovement then
        self:NudgeSelected(columnStep, lineStep)
    end
end

-- Attach these methods to LayoutEditorWindow
function LayoutEditorKeys.install(target)
    for name, method in pairs(LayoutEditorKeys) do
        if name ~= "install" then target[name] = method end
    end
end

return LayoutEditorKeys
