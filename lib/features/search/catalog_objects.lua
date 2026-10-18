-- Search the RuneQL v2 object catalog and resolve results to native object IDs

local ObjectConfig = require("lib/core/object_config")

local CatalogObjects = {}

-- Config-name identity is shared with the bank core; catalog search stays here
CatalogObjects.Object = ObjectConfig.Object
CatalogObjects.ObjectID = ObjectConfig.ObjectID
CatalogObjects.ConfigName = ObjectConfig.ConfigName

-- Search display names and attach object IDs, skipping configs this client cannot resolve
function CatalogObjects.Find(query, limit)
    local results, total = runeql.Catalog.Find(query, limit)
    local resolved = {}
    for _, result in ipairs(results or {}) do
        local objectID = CatalogObjects.ObjectID(result.configName)
        if objectID ~= nil then
            resolved[#resolved + 1] = {
                objectId = objectID,
                configName = result.configName,
                displayName = result.displayName or result.name,
                name = result.name,
            }
        end
    end
    return resolved, total
end

return CatalogObjects
