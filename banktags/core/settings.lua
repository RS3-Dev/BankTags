-- Load and save Bank Tags' preferences

local Config = require("banktags/core/config")

local Settings = {}

local KEYS = { "showTagSprites", "preserveTagLayout", "arrowKeyMovement", "enableDebug" }

-- Create a fresh set of preferences with their default values
function Settings.defaults()
    return {
        showTagSprites = true,
        preserveTagLayout = true,
        arrowKeyMovement = false,
        enableDebug = false,
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

-- Read the saved preferences, or the defaults when there are none
function Settings.load()
    local ok, saved = pcall(function() return PersistentDB:GetStructuredData(Config.SETTINGS_KEY) end)
    return Settings.copy(ok and saved or nil)
end

-- Save a copy of the preferences, reporting whether the host accepted it
function Settings.save(value)
    local ok, saved = pcall(function()
        return PersistentDB:SetStructuredData(Config.SETTINGS_KEY, Settings.copy(value))
    end)
    return ok and saved ~= false
end

return Settings
