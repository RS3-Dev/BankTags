-- Map config names, display names, and client object IDs

local ObjectConfig = {}

-- Resolve a config name to its client object, allowing missing or renamed configs
function ObjectConfig.Object(configName)
    if type(configName) ~= "string" or configName == ""
        or config == nil or config.Obj == nil then return nil end
    local ok, object = pcall(function() return config.Obj[configName] end)
    if not ok or type(object) == "function" then return nil end
    return object
end

-- Resolve a config name to the current client's object ID
function ObjectConfig.ObjectID(configName)
    local object = ObjectConfig.Object(configName)
    if object == nil then return nil end
    local ok, objectID = pcall(function() return object.id end)
    return ok and math.tointeger(tonumber(objectID)) or nil
end

-- Read an object's stable config name, falling back to its printed form
function ObjectConfig.ConfigName(objectID)
    local object = ObjectConfig.FromID(objectID)
    if object == nil then return nil end
    local nameOK, name = pcall(function() return object.configName end)
    if nameOK and type(name) == "string" and name ~= "" then return name end
    return string.match(tostring(object), "config%.[^.]+%.([^%(]+)%(")
end

-- Look up an object definition by ID, allowing unavailable entries
function ObjectConfig.FromID(objectID)
    objectID = math.tointeger(tonumber(objectID))
    if objectID == nil or config == nil or config.Obj == nil
        or config.Obj.FromID == nil then return nil end
    local ok, object = pcall(function() return config.Obj.FromID(objectID) end)
    return ok and object or nil
end

-- Read an object's display name, or nil when the client has none
function ObjectConfig.DisplayName(objectID)
    local object = ObjectConfig.FromID(objectID)
    if object == nil then return nil end
    local ok, name = pcall(function() return object.name end)
    return ok and type(name) == "string" and name ~= "" and name or nil
end

return ObjectConfig
