-- Copy, paste, remove, move, undo, and redo layout items from the keyboard

local Config = require("resources/core/config")
local DebugLog = require("resources/core/debug_log")
local Settings = require("resources/core/settings")
local Parts = require("resources/windows/layout_editor_parts")
local Size = Parts.size

local KEY_EVENT = Config.PLUGIN_REF .. "_layout_editor_keys"
local SHIFT_MODIFIER = ModifierKey.SHIFT
local CONTROL_MODIFIER = ModifierKey.CONTROL
local ALT_MODIFIER = ModifierKey.ALT
local META_MODIFIER = ModifierKey.META or 0
local ANY_MODIFIER = ModifierKey.ANY
local MODIFIER_BITS = {
    CONTROL = CONTROL_MODIFIER,
    SHIFT = SHIFT_MODIFIER,
    ALT = ALT_MODIFIER,
    META = META_MODIFIER ~= 0 and META_MODIFIER or CONTROL_MODIFIER,
}
local MOVE_STEPS = {
    moveLeft = { -1, 0 },
    moveRight = { 1, 0 },
    moveUp = { 0, -1 },
    moveDown = { 0, 1 },
}

local LayoutEditorKeys = {}

-- Listen for shortcut keys while the editor is open
function LayoutEditorKeys:StartShortcuts()
    self.keysOnGrid = false
    self.menuOnGrid = false
    Event.KeyDown.Subscribe(KEY_EVENT, function(event) self:KeyPressed(event) end)
    -- Keep grid shortcuts only for the editor's own menus
    Event.MiniMenuOpened.Subscribe(KEY_EVENT, function()
        if not self.menuOnGrid then self.keysOnGrid = false end
    end)
    -- The player may have typed elsewhere while the game was in the background
    Event.WindowFocusChanged.Subscribe(KEY_EVENT, function()
        self.keysOnGrid = false
        if self.drag ~= nil and self.drag.kind == "box" then self:CancelDrag() end
    end)
    -- ONKEY is a general key hook, not a field-focus event
    local function takeKeys()
        self.keysOnGrid = false
        return true
    end
    self.itemSearch.root:Subscribe(ui.Hook.ONCLICK, KEY_EVENT, takeKeys)
    if self.unsortedSearch ~= nil then self.unsortedSearch.root:Subscribe(ui.Hook.ONCLICK, KEY_EVENT, takeKeys) end
    if self.bankSearch ~= nil then self.bankSearch.root:Subscribe(ui.Hook.ONCLICK, KEY_EVENT, takeKeys) end
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

-- Explain why the grids cannot receive shortcut keys
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

-- Move the sorted selection by one cell
function LayoutEditorKeys:NudgeSelected(columnStep, lineStep)
    local entry, paneName, anchor = self:SelectedEntry()
    if paneName ~= "sorted" then return false end
    local columns = Size.CENTER_COLUMNS
    local line = (anchor - 1) // columns + lineStep
    local column = (anchor - 1) % columns + columnStep
    if line < 0 or column < 0 or column >= columns then return false end
    local keys = self.groupKeys ~= nil and self:SortedKeys(self.groupKeys) or { entry.layoutKey }
    local destination = line * columns + column + 1
    local plan = self.store:PlanLayoutItemsMove(self.selectedTag, keys, entry.layoutKey, destination, columns)
    if plan ~= nil and plan.offGrid then return false end
    -- Save the keyboard move as one undo step
    local _, _, changed = self:SaveEdit("Could not move the items.", function()
        return self.store:MoveLayoutItems(self.selectedTag, keys, entry.layoutKey, destination, columns)
    end)
    return changed
end

-- Combine the held modifiers reported by event and keyboard (including macOS Meta/Command)
local function isMetaDown()
    return type(Keyboard) == "table" and type(Keyboard.IsMetaDown) == "function"
        and Keyboard.IsMetaDown() == true
end

local function heldModifiers(event)
    local raw = tonumber(event.modifiers) or 0
    local held = raw & (ANY_MODIFIER | META_MODIFIER)
    if Keyboard.IsShiftDown() then held = held | SHIFT_MODIFIER end
    if Keyboard.IsControlDown() then held = held | CONTROL_MODIFIER end
    if Keyboard.IsAltDown() then held = held | ALT_MODIFIER end
    if isMetaDown() then
        held = held | (META_MODIFIER ~= 0 and META_MODIFIER or CONTROL_MODIFIER)
    end
    return held
end

-- Read the active editor keybind map with defaults for missing entries
function LayoutEditorKeys:EditorKeybinds()
    local current = self.settings ~= nil and self.settings() or nil
    if type(current) == "table" and type(current.editorKeybinds) == "table" then
        return current.editorKeybinds
    end
    return Settings.defaultEditorKeybinds()
end

-- Format a keybind's display label for tooltips
function LayoutEditorKeys:FormatKeybind(action)
    local names = self:EditorKeybinds()[action]
    if type(names) ~= "table" or #names == 0 then return nil end
    local labels = {}
    for _, name in ipairs(names) do
        if name == "CONTROL" then labels[#labels + 1] = "Ctrl"
        elseif name == "SHIFT" then labels[#labels + 1] = "Shift"
        elseif name == "ALT" then labels[#labels + 1] = "Alt"
        elseif name == "META" then labels[#labels + 1] = "Cmd"
        else labels[#labels + 1] = name:gsub("^_", ""):gsub("_", " ") end
    end
    return table.concat(labels, "+")
end

-- Check whether a configured keybind matches a KeyDown event
-- Any binding requiring CONTROL also accepts macOS Meta/Command
local function matchesBinding(names, eventKey, held)
    if type(names) ~= "table" or #names == 0 then return false end
    local requiredMods, primaryKeys = 0, {}
    local wantsControl, wantsMeta = false, false
    for _, name in ipairs(names) do
        local modBit = MODIFIER_BITS[name]
        if modBit ~= nil then
            requiredMods = requiredMods | modBit
            if name == "CONTROL" then wantsControl = true end
            if name == "META" then wantsMeta = true end
        else
            local code = type(GameKey) == "table" and GameKey[name] or nil
            if code == nil then return false end
            primaryKeys[#primaryKeys + 1] = code
        end
    end
    local effectiveHeld = held
    if wantsControl and not wantsMeta and META_MODIFIER ~= 0 and (effectiveHeld & META_MODIFIER) ~= 0 then
        effectiveHeld = (effectiveHeld & ~META_MODIFIER) | CONTROL_MODIFIER
    end
    if #primaryKeys == 0 then
        if #names == 1 then
            local code = type(GameKey) == "table" and GameKey[names[1]] or nil
            return code ~= nil and eventKey == code and effectiveHeld == requiredMods
        end
        return false
    end
    if effectiveHeld ~= requiredMods then return false end
    if #primaryKeys == 1 then return eventKey == primaryKeys[1] end
    local isDown = type(Keyboard) == "table" and Keyboard.IsGameKeyDown or nil
    if type(isDown) ~= "function" then return false end
    return (eventKey == primaryKeys[1] and isDown(primaryKeys[2]))
        or (eventKey == primaryKeys[2] and isDown(primaryKeys[1]))
end

-- Find the shortcut matching a key and its modifiers
function LayoutEditorKeys:ShortcutFor(key, held)
    local bindings = self:EditorKeybinds()
    for _, action in ipairs(Settings.EDITOR_KEYBIND_ORDER) do
        if matchesBinding(bindings[action], key, held) then
            local step = MOVE_STEPS[action]
            if step ~= nil then return "move", step[1], step[2] end
            return action
        end
    end
    return nil
end

-- Log a shortcut and what prevented it
function LayoutEditorKeys:TraceKey(event, held, shortcut)
    if held == 0 and shortcut == nil and event.gameKey ~= GameKey.CONTROL then return end
    DebugLog.Write("Bank Tags editor key ", tostring(GameKey.FromID(event.gameKey)),
        " gameKey ", tostring(event.gameKey), " systemKey ", tostring(event.systemKey),
        " modifiers ", tostring(event.modifiers), " held ", held, " shortcut ", tostring(shortcut),
        " blocked by ", tostring(self:KeysBlocker() or "nothing"),
        " selected ", tostring(self.selectedLayoutKey))
end

-- Run each shortcut once per key press
function LayoutEditorKeys:KeyPressed(event)
    if event.isRepeat then return end
    if event.gameKey == GameKey.ESCAPE and self.drag ~= nil and self.drag.kind == "box" then
        self:CancelDrag()
        return
    end
    local held = heldModifiers(event)
    local shortcut, columnStep, lineStep = self:ShortcutFor(event.gameKey, held)
    if DebugLog.IsEnabled() then self:TraceKey(event, held, shortcut) end
    if shortcut == nil or not self:KeysReady() then return end
    if shortcut == "undo" then
        self:Undo()
    elseif shortcut == "redo" then
        self:Redo()
    elseif shortcut == "paste" then
        self:PasteClipboard()
    elseif shortcut == "removeRow" then
        self:RemoveTargetRow()
    elseif not (self.HasAnySelection ~= nil and self:HasAnySelection() or self:SelectedEntry() ~= nil) then
        return
    elseif shortcut == "copy" then
        self:CopySelected()
    elseif shortcut == "remove" then
        self:RemoveSelected()
    elseif self.settings ~= nil and self.settings().arrowKeyMovement then
        self:NudgeSelected(columnStep, lineStep)
    end
end

return LayoutEditorKeys
