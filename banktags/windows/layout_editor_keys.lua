-- Copy and remove the selected layout item from the keyboard

local Config = require("banktags/core/config")

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
    -- Clicking a search field gives it the keys
    for _, field in ipairs({ self.itemSearch, self.tagList.search }) do
        field.root:Subscribe(ui.Hook.ONCLICK, function()
            self.keysOnGrid = false
            return true
        end)
    end
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

-- Check whether a shortcut may act on the selected item
function LayoutEditorKeys:ShortcutsReady()
    local overlay = self.overlayWindow
    return self.keysOnGrid
        and self.window ~= nil
        and not self.window.root.hidden
        and self.drag == nil
        and not (overlay ~= nil and overlay.root ~= nil and not overlay.root.hidden)
        and not MiniMenu.IsOpen()
        and not prettyui.KeybindField.IsCapturing()
        and self:SelectedEntry() ~= nil
end

-- Run Delete or Ctrl+C once per press
function LayoutEditorKeys:KeyPressed(event)
    local key = event.gameKey
    if event.isRepeat or self.heldKeys[key] then return end
    self.heldKeys[key] = true

    local isDelete = key == GameKey.DELETE and event.modifiers == 0
    local isCopy = key == GameKey.C and event.modifiers == CONTROL_MODIFIER
    if not (isDelete or isCopy) or not self:ShortcutsReady() then return end
    if isDelete then
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
