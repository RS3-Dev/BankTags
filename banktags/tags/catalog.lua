-- Search items by name, using RuneQL's catalog when it is loaded

local Config = require("banktags/core/config")
local ObjectConfig = require("banktags/core/object_config")

local Catalog = {}

-- Shown beside results when RuneQL is unavailable
Catalog.LIMITED_HINT = "Without RuneQL, search finds items in your bank, an item ID, or a config name."

-- RuneQL's globals can outlive it, so trust the host's last report
local runeqlEnabled = true

-- Follow the host's report that RuneQL loaded or unloaded
function Catalog.SetRuneQLEnabled(enabled)
    runeqlEnabled = enabled == true
end

-- Find RuneQL's catalog search when the optional plugin is loaded
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

-- Describe one object as a search result, or nil when the client does not know it
local function result(objectID)
    local name = ObjectConfig.DisplayName(objectID)
    if name == nil then return nil end
    return { objectId = objectID, configName = ObjectConfig.ConfigName(objectID),
        displayName = name, name = name }
end

-- Search RuneQL's catalog and keep the results this client can resolve
local function findFull(find, query, limit)
    local results, total = find(query, limit)
    local resolved = {}
    for _, entry in ipairs(results or {}) do
        local objectID = ObjectConfig.ObjectID(entry.configName)
        if objectID ~= nil then
            resolved[#resolved + 1] = {
                objectId = objectID,
                configName = entry.configName,
                displayName = entry.displayName or entry.name,
                name = entry.name,
            }
        end
    end
    return resolved, total
end

-- Search an exact item ID or config name, then the names of items in the bank
local function findLimited(query, limit, bankItems)
    local resolved, seen = {}, {}
    -- Add one object once, while there is room
    local function add(objectID)
        if objectID == nil or seen[objectID] or #resolved >= limit then return end
        local entry = result(objectID)
        if entry ~= nil then
            seen[objectID] = true
            resolved[#resolved + 1] = entry
        end
    end
    add(math.tointeger(tonumber((string.gsub(query, "^#", "")))))
    add(ObjectConfig.ObjectID(query))
    local wanted = string.lower(query)
    for _, item in ipairs(bankItems or {}) do
        local name = ObjectConfig.DisplayName(item.objectID)
        if name ~= nil and string.find(string.lower(name), wanted, 1, true) ~= nil then
            add(item.objectID)
        end
    end
    return resolved, #resolved
end

-- Search item names, returning results, total, and whether limited
function Catalog.Find(query, limit, bankItems)
    local find = runeqlFind()
    if find ~= nil then
        local results, total = findFull(find, query, limit)
        return results, total, false
    end
    local results, total = findLimited(query, limit, bankItems)
    return results, total, true
end

return Catalog
