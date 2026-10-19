-- Hold other plugins' import sources and run their draft requests

local Config = require("banktags/core/config")
local debugLog = require("banktags/core/debug_log").Write
local PlainData = require("banktags/imports/plain_data")

local ImportProviders = {}
ImportProviders.__index = ImportProviders

local WORK_EVENT = Config.PLUGIN_REF .. "_import_provider"
local PROVIDER_FIELDS = {
    label = true, icon = true, input = true, prompt = true, placeholder = true,
    actionLabel = true, unavailable = true, request = true,
}
local INVALID_DRAFT = "The source returned tags Bank Tags cannot read."
local FAILED = "The source could not load this import."
local NO_READER = "Bank Tags cannot read imported tags right now."

ImportProviders.LIMITS = {
    importProviders = 16,
    importProvidersPerOwner = 4,
    importMessageLength = 120,
    -- The tag draft reader's limits, checked by a test
    draftTags = 32,
    draftEntries = 2000,
}
local LIMITS = ImportProviders.LIMITS
local ID_LENGTH = 64
local TEXT_LENGTH = 64

-- Validate a provider description and copy it into data this module owns
local function readProvider(input)
    if type(input) ~= "table" or getmetatable(input) ~= nil
        or not PlainData.HasOnlyFields(input, PROVIDER_FIELDS) then
        return nil, "a provider is a plain table of label, icon, input, prompt, placeholder, "
            .. "actionLabel, unavailable, and request"
    end
    local record = {
        label = PlainData.Label(rawget(input, "label"), TEXT_LENGTH),
        icon = rawget(input, "icon"),
        input = rawget(input, "input"),
        request = rawget(input, "request"),
    }
    if record.label == nil then return nil, "label must be 1 to 64 characters without markup" end
    if record.icon ~= nil and not PlainData.KnownIcon(record.icon) then
        return nil, "icon must be a PrettyUI sprite-button name"
    end
    if record.input ~= "text" and record.input ~= "action" then
        return nil, "input must be \"text\" or \"action\""
    end
    if type(record.request) ~= "function" then return nil, "request must be a function" end
    local fields = { prompt = TEXT_LENGTH, unavailable = LIMITS.importMessageLength }
    if record.input == "text" then fields.placeholder = TEXT_LENGTH else fields.actionLabel = TEXT_LENGTH end
    for field in pairs(PROVIDER_FIELDS) do
        local value = rawget(input, field)
        if fields[field] ~= nil and value ~= nil then
            record[field] = PlainData.Label(value, fields[field])
            if record[field] == nil then
                return nil, field .. " must be 1 to " .. fields[field] .. " characters without markup"
            end
        elseif record[field] == nil and value ~= nil then
            return nil, field .. " does not apply to " .. record.input .. " sources"
        end
    end
    return record
end

-- Reduce a provider's failure message to one plain line, or use the generic one
local function failureMessage(message)
    if type(message) ~= "string" then return FAILED end
    message = string.gsub(string.gsub(message, "[<>]", ""), "%c+", " ")
    return PlainData.Text(message, LIMITS.importMessageLength) or FAILED
end

-- Create an empty import source registry
function ImportProviders.new(options)
    local self = setmetatable({
        isLive = options.isLive,
        onChange = options.onChange,
        readDraft = options.readDraft,
        records = {},
        count = 0,
        sequence = 0,
        queue = {},
        listening = false,
        closed = false,
    }, ImportProviders)
    -- Give each registry its own listener so reloads never share one
    self.workEvent = WORK_EVENT .. ":" .. string.match(tostring(self), "%x+$")
    return self
end

-- Use a new draft reader, or none; requests already answered keep their result
function ImportProviders:SetDraftReader(readDraft)
    self.readDraft = readDraft
end

-- Tell the open Import window that the source list changed
function ImportProviders:Changed()
    if self.onChange ~= nil then self.onChange() end
end

-- Check that a source is still registered to a live owner
function ImportProviders:Current(record)
    return not self.closed and self.records[record.key] == record and self.isLive(record.owner)
end

-- Find an owner's provider, explaining stale handles and unknown providers
function ImportProviders:Owned(owner, providerID)
    if self.closed or not self.isLive(owner) then return nil, "stale_handle" end
    local record = PlainData.ID(providerID, ID_LENGTH) and self.records[owner.id .. "/" .. providerID] or nil
    if record == nil or record.owner ~= owner then return nil, "unknown_import_provider" end
    return record
end

-- List an owner's provider IDs in registration order
function ImportProviders:ProviderIDs(owner)
    local records = {}
    for _, record in pairs(self.records) do
        if record.owner == owner then records[#records + 1] = record end
    end
    table.sort(records, function(left, right) return left.sequence < right.sequence end)
    local providerIDs = {}
    for index, record in ipairs(records) do providerIDs[index] = record.providerID end
    return providerIDs
end

-- Describe every source for the Import window in a stable order
function ImportProviders:Sources()
    local records = {}
    for _, record in pairs(self.records) do records[#records + 1] = record end
    table.sort(records, function(left, right)
        if left.owner.id ~= right.owner.id then return left.owner.id < right.owner.id end
        return left.sequence < right.sequence
    end)
    local sources = {}
    for index, record in ipairs(records) do
        sources[index] = {
            key = record.key,
            revision = record.revision,
            ownerLabel = record.owner.label,
            label = record.label,
            icon = record.icon,
            input = record.input,
            prompt = record.prompt,
            placeholder = record.placeholder,
            actionLabel = record.actionLabel,
            unavailable = record.unavailable,
        }
    end
    return sources
end

-- Add an import source for an owner without selecting it anywhere
function ImportProviders:Register(owner, providerID, input)
    if self.closed or not self.isLive(owner) then return false, "stale_handle" end
    if not PlainData.ID(providerID, ID_LENGTH) then
        return false, "invalid_import_provider_id",
            "provider IDs are 1 to 64 letters, digits, '.', '_' or '-'"
    end
    local key = owner.id .. "/" .. providerID
    if self.records[key] ~= nil then return false, "duplicate_import_provider" end
    if self.count >= LIMITS.importProviders
        or #self:ProviderIDs(owner) >= LIMITS.importProvidersPerOwner then
        return false, "too_many_import_providers"
    end
    local record, detail = readProvider(input)
    if record == nil then return false, "invalid_import_provider", detail end
    self.sequence = self.sequence + 1
    record.key, record.owner, record.providerID = key, owner, providerID
    record.sequence, record.revision, record.tokens = self.sequence, self.sequence, {}
    self.records[key] = record
    self.count = self.count + 1
    self:Changed()
    return true
end

-- Replace a source's description, keeping it if the update is invalid
function ImportProviders:Update(owner, providerID, input)
    local current, reason = self:Owned(owner, providerID)
    if current == nil then return false, reason end
    local record, detail = readProvider(input)
    if record == nil then return false, "invalid_import_provider", detail end
    self.sequence = self.sequence + 1
    record.key, record.owner, record.providerID = current.key, owner, providerID
    record.sequence, record.revision, record.tokens = current.sequence, self.sequence, {}
    self.records[current.key] = record
    -- Requests made under the old description cannot answer the new one
    self:RunCancels(self:Invalidate(current, {}))
    self:Changed()
    return true
end

-- Remove one of an owner's sources; the Import window falls back to the share code
function ImportProviders:Remove(owner, providerID)
    local record, reason = self:Owned(owner, providerID)
    if record == nil then return false, reason end
    self:Drop({ record })
    self:Changed()
    return true
end

-- Remove every source an owner registered, as its handle is disposed or replaced
function ImportProviders:RemoveOwner(owner)
    local records = {}
    for _, record in pairs(self.records) do
        if record.owner == owner then records[#records + 1] = record end
    end
    if #records == 0 then return end
    self:Drop(records)
    self:Changed()
end

-- Forget sources first so cancel callbacks cannot revive or skip one
function ImportProviders:Drop(records)
    local cancels = {}
    for _, record in ipairs(records) do
        self.records[record.key] = nil
        self.count = self.count - 1
        self:Invalidate(record, cancels)
    end
    self:RunCancels(cancels)
end

-- Mark a source's requests stale, collecting ones to cancel
function ImportProviders:Invalidate(record, cancels)
    for token in pairs(record.tokens) do
        token.live = false
        if token.cancel ~= nil and not token.settled then cancels[#cancels + 1] = token end
    end
    record.tokens = {}
    return cancels
end

-- Tell providers their requests are cancelled, in request order
function ImportProviders:RunCancels(tokens)
    table.sort(tokens, function(left, right) return left.sequence < right.sequence end)
    for _, token in ipairs(tokens) do self:RunCancel(token) end
end

-- Run provider work on the next logic tick
function ImportProviders:Schedule(work)
    self.queue[#self.queue + 1] = work
    if self.listening then return end
    self.listening = true
    Event.Logic.Subscribe(self.workEvent, function() self:RunQueue() end)
end

-- Run queued work, including work it queues, then stop listening
function ImportProviders:RunQueue()
    local index = 1
    while self.queue[index] ~= nil do
        local work = self.queue[index]
        index = index + 1
        work()
    end
    self.queue = {}
    self.listening = false
    Event.Logic.Unsubscribe(self.workEvent)
end

-- Ask a source for a draft, answered once on a later tick
function ImportProviders:Begin(key, input, onResult)
    local record = self.records[key]
    if record == nil or not self:Current(record) or record.unavailable ~= nil then return nil end
    self.sequence = self.sequence + 1
    local token = { record = record, onResult = onResult, live = true, settled = false,
        sequence = self.sequence }
    record.tokens[token] = true
    local request = PlainData.ReadOnly({
        input = input,
        source = record.providerID,
        Resolve = function(_, draft) return self:Resolve(token, draft) end,
        Fail = function(_, message) return self:Fail(token, message) end,
        IsCurrent = function() return token.live and not token.settled end,
    })
    self:Schedule(function() self:Start(token, request) end)
    return token
end

-- Call the provider for a request that is still wanted
function ImportProviders:Start(token, request)
    if not token.live or not self:Current(token.record) then return end
    local ok, result = pcall(token.record.request, request)
    if not ok then
        debugLog("Bank Tags import source ", token.record.key, " raised: ", result)
        self:Settle(token, "error", token.record.label .. " stopped with an error.")
        return
    end
    if type(result) ~= "function" then return end
    token.cancel = result
    -- The request went stale while the provider ran
    if not token.live and not token.settled then self:RunCancel(token) end
end

-- Record a request's answer and deliver it next tick
function ImportProviders:Settle(token, state, value)
    if not token.live or token.settled or not self:Current(token.record) then return false end
    token.settled = true
    self:Schedule(function()
        if not token.live or not self:Current(token.record) then return end
        token.live = false
        token.record.tokens[token] = nil
        token.onResult(state, value)
    end)
    return true
end

-- Accept a provider's draft once, copied and checked
function ImportProviders:Resolve(token, draft)
    if not token.live or token.settled or not self:Current(token.record) then
        return false, "stale_request"
    end
    if self.readDraft == nil then
        self:Settle(token, "error", NO_READER)
        return false, "unavailable"
    end
    local text, detail = self.readDraft(draft)
    if text == nil then
        debugLog("Bank Tags rejected a draft from ", token.record.key, ": ", detail)
        self:Settle(token, "invalid", INVALID_DRAFT)
        return false, "invalid_draft", detail
    end
    self:Settle(token, "ready", text)
    return true
end

-- Accept a provider's failure once, keeping only a short plain message
function ImportProviders:Fail(token, message)
    if not token.live or token.settled or not self:Current(token.record) then
        return false, "stale_request"
    end
    self:Settle(token, "error", failureMessage(message))
    return true
end

-- Tell a provider its unanswered request is no longer wanted
function ImportProviders:RunCancel(token)
    local cancel = token.cancel
    token.cancel = nil
    if cancel == nil then return end
    local ok, message = pcall(cancel)
    if not ok then debugLog("Bank Tags import source ", token.record.key, " cancel raised: ", message) end
end

-- Drop a request so its answer never reaches the window
function ImportProviders:Cancel(token)
    if token == nil or not token.live then return end
    token.live = false
    token.record.tokens[token] = nil
    if token.cancel ~= nil and not token.settled then self:RunCancel(token) end
end

-- Drop every source and request, stop listening, and refuse all later calls
function ImportProviders:Close()
    if self.closed then return end
    -- Close first so cancel callbacks cannot register anything
    self.closed = true
    local records = {}
    for _, record in pairs(self.records) do records[#records + 1] = record end
    self:Drop(records)
    self.queue = {}
    self.listening = false
    Event.Logic.Unsubscribe(self.workEvent)
    self:Changed()
end

return ImportProviders
