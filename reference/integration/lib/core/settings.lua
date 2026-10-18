-- Load and save the supported user preferences

local StorageKeys = require("lib/features/storage_keys")

local Settings = {}

-- Create a fresh set of supported preferences with their default values
function Settings.defaults()
    return {
        schemaVersion = 1,
        autoExpandSidebar = true,
        showTagSprites = true,
        preserveTagLayout = true,
        enableAdvancedSearch = true,
        enableRuneSQL = false,
        enableDebug = false,
    }
end

-- Overlay saved boolean preferences onto the defaults
function Settings.load()
    local value = Settings.defaults()
    local saved = PersistentDB:GetStructuredData(StorageKeys.SETTINGS_KEY)
    if type(saved) ~= "table" then return value end

    for _, key in ipairs({
        "autoExpandSidebar",
        "showTagSprites",
        "preserveTagLayout",
        "enableAdvancedSearch",
        "enableRuneSQL",
        "enableDebug",
    }) do
        if type(saved[key]) == "boolean" then value[key] = saved[key] end
    end
    return value
end

-- Copy supported boolean preferences without retaining the caller's table
function Settings.copy(value)
    local copy = Settings.defaults()
    for key in pairs(copy) do
        if key ~= "schemaVersion" and type(value and value[key]) == "boolean" then
            copy[key] = value[key]
        end
    end
    return copy
end

-- Persist a sanitized settings copy under the current schema
function Settings.save(value)
    local saved = Settings.copy(value)
    saved.schemaVersion = 1
    return PersistentDB:SetStructuredData(StorageKeys.SETTINGS_KEY, saved) ~= false
end

return Settings
