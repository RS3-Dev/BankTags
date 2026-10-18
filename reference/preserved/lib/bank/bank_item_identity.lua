-- Keep native component slots separate from persistent same-object copy identities

local BankItemIdentity = {}

-- Read a whole number, returning nil when the value is invalid
local function integer(value)
    local number = tonumber(value)
    return number ~= nil and math.tointeger(number) or nil
end

-- Read the item ID associated with a native bank component
function BankItemIdentity.ObjectID(component)
    return component ~= nil and integer(component.associatedObjectID) or nil
end

-- Identify the current native slot, using an item-copy key when slot IDs are unavailable
function BankItemIdentity.ComponentKey(component, objectID, occurrence)
    if component ~= nil then
        local categoryID = integer(component.categoryID)
        local dynamicID = integer(component.dynamicID)
        if categoryID ~= nil and categoryID >= 0
            and dynamicID ~= nil and dynamicID >= 0 then
            -- Bank components currently use the same value for category and
            -- dynamic ID. Keep that common path numeric so the per-tick
            -- parking scan does not allocate thousands of key strings
            if categoryID == dynamicID then return dynamicID end
            return "component:" .. tostring(categoryID) .. ":" .. tostring(dynamicID)
        end
    end
    return BankItemIdentity.LayoutKey(objectID, occurrence)
end

-- Identify an item copy by its object ID and position among matching copies
function BankItemIdentity.LayoutKey(objectID, occurrence)
    objectID = integer(objectID)
    occurrence = integer(occurrence) or 1
    if objectID == nil then return nil end
    return "object:" .. tostring(objectID) .. ":" .. tostring(occurrence)
end

-- Compare original bank positions so matching copies receive consistent identities
local function nativeOrder(left, right)
    if left.y == right.y then
        if left.x == right.x then
            local leftDynamic = integer(left.component and left.component.dynamicID) or -1
            local rightDynamic = integer(right.component and right.component.dynamicID) or -1
            return leftDynamic < rightDynamic
        end
        return left.x < right.x
    end
    return left.y < right.y
end

-- Order bank entries and record each copy's identity and matching-copy count
function BankItemIdentity.Assign(entries)
    table.sort(entries, nativeOrder)
    local occurrences = {}
    for _, entry in ipairs(entries) do
        local objectID = integer(entry.objectID)
        local occurrence = (occurrences[objectID] or 0) + 1
        occurrences[objectID] = occurrence
        entry.objectID = objectID
        entry.occurrence = occurrence
        entry.layoutKey = BankItemIdentity.LayoutKey(objectID, occurrence)
        entry.instanceKey = BankItemIdentity.ComponentKey(
            entry.component,
            objectID,
            occurrence
        )
    end
    for _, entry in ipairs(entries) do
        entry.siblingCount = occurrences[entry.objectID] or 1
    end
    return entries
end

-- Read native bank items and assign identities in their original bank order
function BankItemIdentity.Collect(itemLayer)
    local entries = {}
    if itemLayer == nil then return entries end
    itemLayer:IterateDynamicComponents(function(item)
        local objectID = BankItemIdentity.ObjectID(item)
        if objectID ~= nil and objectID >= 0 then
            entries[#entries + 1] = {
                component = item,
                objectID = objectID,
                x = tonumber(item.x) or 0,
                y = tonumber(item.y) or 0,
                quantity = item.associatedObjectQuantity,
            }
        end
        return false
    end)
    return BankItemIdentity.Assign(entries)
end

return BankItemIdentity
