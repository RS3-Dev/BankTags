-- Load and save Bank Tags' preferences

local Config = require("resources/core/config")

local Settings = {}

local KEYS = { "showTagSprites", "restoreLastTag", "preserveTagLayout", "arrowKeyMovement", "enableDebug", "tutorialSeen" }

local EDITOR_KEYBIND_ORDER = {
    "copy", "paste", "remove", "removeRow", "undo", "redo",
    "moveLeft", "moveRight", "moveUp", "moveDown",
}

local DEFAULT_EDITOR_KEYBINDS = {
    copy = { "CONTROL", "C" },
    paste = { "CONTROL", "V" },
    remove = { "DELETE" },
    removeRow = { "SHIFT", "DELETE" },
    undo = { "CONTROL", "Z" },
    redo = { "CONTROL", "Y" },
    moveLeft = { "LEFT" },
    moveRight = { "RIGHT" },
    moveUp = { "UP" },
    moveDown = { "DOWN" },
}

Settings.EDITOR_KEYBIND_ORDER = EDITOR_KEYBIND_ORDER

-- Copy a single keybind name array (0 to 2 unique key names)
local function copyBinding(value, fallback)
    if type(value) ~= "table" then return copyBinding(fallback, {}) end
    local result, seen = {}, {}
    for index = 1, #value do
        local name = value[index]
        if type(name) ~= "string" or name == "" or seen[name] or #result >= 2 then
            return copyBinding(fallback, {})
        end
        seen[name] = true
        result[#result + 1] = name
    end
    return result
end

-- Return a fresh copy of the default layout editor keybinds
function Settings.defaultEditorKeybinds()
    local result = {}
    for _, action in ipairs(EDITOR_KEYBIND_ORDER) do
        result[action] = copyBinding(DEFAULT_EDITOR_KEYBINDS[action], {})
    end
    return result
end

-- Copy valid editor keybinds over their defaults
function Settings.copyEditorKeybinds(value)
    local result = {}
    for _, action in ipairs(EDITOR_KEYBIND_ORDER) do
        local saved = type(value) == "table" and value[action] or nil
        result[action] = copyBinding(saved, DEFAULT_EDITOR_KEYBINDS[action])
    end
    return result
end

-- Create a fresh set of preferences with their default values
function Settings.defaults()
    return {
        showTagSprites = true,
        restoreLastTag = true,
        preserveTagLayout = true,
        arrowKeyMovement = false,
        enableDebug = false,
        tutorialSeen = false,
        editorKeybinds = Settings.defaultEditorKeybinds(),
    }
end

-- Copy the supported preferences over the defaults
function Settings.copy(value)
    local copy = Settings.defaults()
    for _, key in ipairs(KEYS) do
        if type(value) == "table" and type(value[key]) == "boolean" then copy[key] = value[key] end
    end
    if type(value) == "table" and type(value.editorKeybinds) == "table" then
        copy.editorKeybinds = Settings.copyEditorKeybinds(value.editorKeybinds)
    end
    return copy
end

-- Load saved preferences or use the defaults
function Settings.load()
    local ok, saved = pcall(function() return PersistentDB:GetStructuredData(Config.SETTINGS_KEY) end)
    return Settings.copy(ok and saved or nil)
end

-- Save preferences and report any failure
function Settings.save(value)
    -- Catch a rejected preference write
    local ok, saved = pcall(function()
        return PersistentDB:SetStructuredData(Config.SETTINGS_KEY, Settings.copy(value))
    end)
    return ok and saved ~= false
end

return Settings
