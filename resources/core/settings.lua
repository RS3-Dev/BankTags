-- Load and save Bank Tags' preferences

local Config = require("resources/core/config")

local Settings = {}

local KEYS = { "showTagSprites", "restoreLastTag", "preserveTagLayout", "arrowKeyMovement", "enableDebug", "tutorialSeen" }

-- Create a fresh set of preferences with their default values
function Settings.defaults()
    return {
        showTagSprites = true,
        restoreLastTag = true,
        preserveTagLayout = true,
        arrowKeyMovement = false,
        enableDebug = false,
        tutorialSeen = false,
    }
end

-- Copy the supported boolean preferences over the defaults
function Settings.copy(value)
    local copy = Settings.defaults()
    for _, key in ipairs(KEYS) do
        if type(value) == "table" and type(value[key]) == "boolean" then copy[key] = value[key] end
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
