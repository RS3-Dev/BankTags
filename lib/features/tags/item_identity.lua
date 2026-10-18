-- Convert between this client's object IDs and the stable references saved for them

local CatalogObjects = require("lib/features/search/catalog_objects")

local ItemIdentity = {}

-- Object IDs can change between game updates, so saved data names items by
-- config name. An ID the client cannot name is saved as "#<id>" until it can
local ID_PREFIX = "#"

local namesByID = {}
local idsByName = {}

-- Return the saved reference for an object ID
function ItemIdentity.Reference(objectID)
    objectID = math.tointeger(tonumber(objectID))
    if objectID == nil or objectID < 0 then return nil end
    local name = namesByID[objectID]
    if name == nil then
        name = CatalogObjects.ConfigName(objectID)
        if name ~= nil then
            namesByID[objectID] = name
            idsByName[name] = objectID
        end
    end
    return name or (ID_PREFIX .. tostring(objectID))
end

-- Resolve a saved reference to this client's object ID, or nil when it is unknown
function ItemIdentity.ObjectID(reference)
    if type(reference) ~= "string" or reference == "" then return nil end
    if string.sub(reference, 1, #ID_PREFIX) == ID_PREFIX then
        local objectID = math.tointeger(tonumber(string.sub(reference, #ID_PREFIX + 1)))
        return objectID ~= nil and objectID >= 0 and objectID or nil
    end
    local objectID = idsByName[reference]
    if objectID == nil then
        objectID = CatalogObjects.ObjectID(reference)
        if objectID ~= nil then
            idsByName[reference] = objectID
            namesByID[objectID] = reference
        end
    end
    return objectID
end

-- Forget cached lookups, such as after the client's configs reload
function ItemIdentity.Reset()
    namesByID = {}
    idsByName = {}
end

return ItemIdentity
