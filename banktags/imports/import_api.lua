-- Publish the API other plugins use to add import sources to Bank Tags' Import window.
-- Each plugin registers an owner and adds its sources through the owner's handle; a newer
-- registration under the same owner ID replaces the older one and its sources

local PlainData = require("banktags/imports/plain_data")
local ImportProviders = require("banktags/imports/import_providers")

local ImportAPI = {}
ImportAPI.__index = ImportAPI

ImportAPI.LIMITS = {
    owners = 32,
    idLength = 64,
    labelLength = 64,
}
local LIMITS = ImportAPI.LIMITS

-- Create the owners and the import source registry. readDraft reads a provider's draft into
-- share text, and onChange tells an open Import window that the sources changed
function ImportAPI.new(options)
    local self = setmetatable({ owners = {}, count = 0, closed = false }, ImportAPI)
    self.providers = ImportProviders.new({
        isLive = function(owner) return self:IsLive(owner) end,
        onChange = options.onChange,
        readDraft = options.readDraft,
    })
    self.publicAPI = self:Root()
    return self
end

-- Check that an owner is the live registration for its ID
function ImportAPI:IsLive(owner)
    return not self.closed and self.owners[owner.id] == owner
end

-- Remove an owner and every source it registered
function ImportAPI:Drop(owner)
    if not self:IsLive(owner) then return end
    self.owners[owner.id] = nil
    self.count = self.count - 1
    self.providers:RemoveOwner(owner)
end

-- Register an owner, replacing any earlier registration under the same ID
function ImportAPI:Register(ownerID, label)
    if self.closed then return nil, "stale_api" end
    if not PlainData.ID(ownerID, LIMITS.idLength) then
        return nil, "invalid_owner_id", "owner IDs are 1 to 64 letters, digits, '.', '_' or '-'"
    end
    label = PlainData.Label(label, LIMITS.labelLength)
    if label == nil then return nil, "invalid_label", "label must be 1 to 64 characters without markup" end
    local previous = self.owners[ownerID]
    if previous == nil and self.count >= LIMITS.owners then return nil, "too_many_owners" end
    if previous ~= nil then self:Drop(previous) end
    local owner = { id = ownerID, label = label }
    self.owners[ownerID] = owner
    self.count = self.count + 1
    return self:Handle(owner)
end

-- Build the handle one owner uses for its own import sources
function ImportAPI:Handle(owner)
    local providers = self.providers
    return PlainData.ReadOnly({
        ownerID = owner.id,
        RegisterImportProvider = function(_, providerID, provider)
            return providers:Register(owner, providerID, provider)
        end,
        UpdateImportProvider = function(_, providerID, provider)
            return providers:Update(owner, providerID, provider)
        end,
        RemoveImportProvider = function(_, providerID) return providers:Remove(owner, providerID) end,
        GetState = function()
            local live = self:IsLive(owner)
            return { running = not self.closed, live = live,
                providers = live and providers:ProviderIDs(owner) or {} }
        end,
        Dispose = function()
            self:Drop(owner)
            return true
        end,
    })
end

-- Build the root table other plugins receive as the banktags dependency
function ImportAPI:Root()
    local limits = {}
    for key, value in pairs(LIMITS) do limits[key] = value end
    for key, value in pairs(ImportProviders.LIMITS) do limits[key] = value end
    return PlainData.ReadOnly({
        LIMITS = PlainData.ReadOnly(limits),
        RegisterExtension = function(ownerID, label) return self:Register(ownerID, label) end,
        GetState = function() return { running = not self.closed } end,
    })
end

-- Drop every owner and source and refuse all later calls
function ImportAPI:Close()
    if self.closed then return end
    self.providers:Close()
    self.closed = true
    self.owners = {}
    self.count = 0
end

return ImportAPI
