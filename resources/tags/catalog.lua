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

-- Find RuneQL's Catalog API table when the plugin is loaded
local function runeqlCatalog()
    if not runeqlEnabled then return nil end
    -- Loop by index since either one may be missing
    local candidates = { runeql, rawget(_G, Config.RUNEQL_API_KEY) }
    for index = 1, 2 do
        local candidate = candidates[index]
        local catalog = type(candidate) == "table" and candidate.Catalog or nil
        if type(catalog) == "table"
            and (type(catalog.FindAsync) == "function" or type(catalog.Find) == "function") then
            return catalog
        end
    end
    return nil
end

-- Report whether the full item catalog can be searched
function Catalog.IsFull()
    return runeqlCatalog() ~= nil
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

-- Keep only RuneQL matches this client recognizes
local function resolveEntries(results, limit, options)
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
    return resolved
end

-- Search RuneQL synchronously and keep items this client recognizes
local function findFull(find, query, limit, options)
    local results, total, reason = find(query, limit, options)
    if results == nil and reason ~= nil then error(reason) end
    return resolveEntries(results, limit, options), total
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

local function noopHandle()
    return { Cancel = function() end }
end

-- Search item names synchronously, returning results, total, and whether limited
function Catalog.Find(query, limit, bankItems, options)
    local catalog = runeqlCatalog()
    if catalog ~= nil and type(catalog.Find) == "function" then
        local results, total = findFull(catalog.Find, query, limit, options)
        return results, total, false
    end
    local results, total = findLimited(query, limit, bankItems, options)
    return results, total, true
end

-- Return a short diagnostic string describing RuneQL's current mode/status
function Catalog.Diagnostics()
    local candidates = { runeql, rawget(_G, Config.RUNEQL_API_KEY) }
    local api = candidates[1] or candidates[2]
    if type(api) ~= "table" then return "runeql=missing" end
    local parts = {}
    local okMode, mode = pcall(function() return type(api.Mode) == "function" and api.Mode() or nil end)
    if okMode and mode ~= nil then parts[#parts + 1] = "mode=" .. tostring(mode) end
    local okStatus, st = pcall(function() return type(api.Status) == "function" and api.Status() or nil end)
    if okStatus and type(st) == "table" then
        local remote = type(st.remote) == "table" and st.remote or st
        if remote.state ~= nil then parts[#parts + 1] = "state=" .. tostring(remote.state) end
        if remote.httpPermission ~= nil then parts[#parts + 1] = "http=" .. tostring(remote.httpPermission) end
        if remote.queuedRequests ~= nil then parts[#parts + 1] = "queued=" .. tostring(remote.queuedRequests) end
        if remote.lastError ~= nil then parts[#parts + 1] = "err=" .. tostring(remote.lastError) end
    end
    return #parts > 0 and table.concat(parts, " ") or "runeql=loaded"
end

-- Search item names asynchronously (works in both RuneQL remote and local modes)
function Catalog.FindAsync(query, limit, bankItems, options, callback)
    if type(options) == "function" and callback == nil then
        callback, options = options, nil
    end
    local catalog = runeqlCatalog()
    if catalog ~= nil and type(catalog.FindAsync) == "function" then
        local ok, handle = pcall(function()
            return catalog.FindAsync(query, limit, options, function(results, total, reason)
                if results == nil then
                    callback(nil, 0, false, reason or "Item search failed.")
                    return
                end
                local okResolve, resolved = pcall(function()
                    return resolveEntries(results, limit, options)
                end)
                if not okResolve then
                    callback(nil, 0, false, tostring(resolved))
                    return
                end
                callback(resolved, total or 0, false, nil)
            end)
        end)
        if not ok then
            callback(nil, 0, false, handle)
            return noopHandle()
        end
        return handle or noopHandle()
    end
    local ok, results, total, limited = pcall(function()
        return Catalog.Find(query, limit, bankItems, options)
    end)
    if not ok then
        callback(nil, 0, false, results)
        return noopHandle()
    end
    callback(results, total or 0, limited == true, nil)
    return noopHandle()
end

return Catalog
