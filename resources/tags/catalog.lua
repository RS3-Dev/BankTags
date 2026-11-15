-- Search items by name, using RuneQL's catalog when it is loaded

local Config = require("resources/core/config")
local ObjectConfig = require("resources/core/object_config")

local Catalog = {}

-- Shown beside results when RuneQL is unavailable
Catalog.LIMITED_HINT = "Without RuneQL, search finds items in your bank, an item ID, or a config name."

-- RuneQL's globals can outlive it, so trust the host's last report
local runeqlEnabled = true

-- Follow the host's report that RuneQL loaded or unloaded
function Catalog.SetRuneQLEnabled(enabled)
    runeqlEnabled = enabled == true
end

-- Find RuneQL's catalog search when the plugin is loaded
local function runeqlFind()
    if not runeqlEnabled then return nil end
    -- Loop by index since either one may be missing
    local candidates = { runeql, rawget(_G, Config.RUNEQL_API_KEY) }
    for index = 1, 2 do
        local candidate = candidates[index]
        local catalog = type(candidate) == "table" and candidate.Catalog or nil
        if type(catalog) == "table" and type(catalog.Find) == "function" then return catalog.Find end
    end
    return nil
end

-- Report whether the full item catalog can be searched
function Catalog.IsFull()
    return runeqlFind() ~= nil
end

-- Describe a known item as a search result
local function result(objectID, name)
    name = name or ObjectConfig.DisplayName(objectID)
    if name == nil then return nil end
    return { objectId = objectID, configName = ObjectConfig.ConfigName(objectID),
        displayName = name, name = name }
end

-- Noted item configs are useful as icons but cannot occupy bank layout slots
local function allowedConfig(configName, options)
    return not (options ~= nil and options.bankableOnly
        and type(configName) == "string" and string.sub(configName, 1, 5) == "CERT_")
end

-- Search RuneQL and keep items this client recognizes
local function findFull(find, query, limit, options)
    local results, total, reason = find(query, limit, options)
    if results == nil and reason ~= nil then error(reason) end
    local resolved = {}
    for _, entry in ipairs(results or {}) do
        local objectID = allowedConfig(entry.configName, options) and ObjectConfig.ObjectID(entry.configName) or nil
        if objectID ~= nil and #resolved < limit then
            resolved[#resolved + 1] = {
                objectId = objectID,
                configName = entry.configName,
                displayName = tostring(entry.displayName or entry.name
                    or ObjectConfig.DisplayName(objectID) or ("Item " .. objectID)),
                name = entry.name,
            }
        end
    end
    return resolved, total
end

-- Search exact references and unique bank item names
local function findLimited(query, limit, bankItems, options)
    local resolved, seen = {}, {}
    local bankIDs
    if options ~= nil and options.bankableOnly then
        bankIDs = {}
        for _, item in ipairs(bankItems or {}) do bankIDs[item.objectID] = true end
    end
    -- Add one object once, while there is room
    local function add(objectID, name)
        if objectID == nil or seen[objectID] or #resolved >= limit then return end
        if bankIDs ~= nil and not bankIDs[objectID] then return end
        local entry = result(objectID, name)
        if entry ~= nil and allowedConfig(entry.configName, options) then
            seen[objectID] = true
            resolved[#resolved + 1] = entry
        end
    end
    add(math.tointeger(tonumber((string.gsub(query, "^#", "")))))
    add(ObjectConfig.ObjectID(query))
    local wanted = string.lower(query)
    local checked = {}
    for _, item in ipairs(bankItems or {}) do
        if #resolved >= limit then break end
        if not seen[item.objectID] and not checked[item.objectID] then
            checked[item.objectID] = true
            local name = ObjectConfig.DisplayName(item.objectID)
            if name ~= nil and string.find(string.lower(name), wanted, 1, true) ~= nil then
                add(item.objectID, name)
            end
        end
    end
    return resolved, #resolved
end

-- Search item names, returning results, total, and whether limited
function Catalog.Find(query, limit, bankItems, options)
    local find = runeqlFind()
    if find ~= nil then
        local results, total = findFull(find, query, limit, options)
        return results, total, false
    end
    local results, total = findLimited(query, limit, bankItems, options)
    return results, total, true
end

return Catalog
