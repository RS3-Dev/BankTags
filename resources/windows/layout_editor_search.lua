-- Search items and add results to the layout editor's tag

local Catalog = require("resources/tags/catalog")
local debugLog = require("resources/core/debug_log").Write
local Text = require("resources/core/text")
local Parts = require("resources/windows/layout_editor_parts")
local Size = Parts.size

local SEARCH_RESULT_LIMIT = 200
local SEARCH_OPTIONS = { bankableOnly = true, includeFields = false }
local SEARCH_DELAY_TICKS = 3
local SEARCH_TIMEOUT_TICKS = 300

local LayoutEditorSearch = {}

local function logSearchError(message, detail)
    debugLog(message, detail)
    if type(log) == "function" then
        pcall(function() log(message, tostring(detail or "")) end)
    end
end

-- Show or hide guidance in the search panel
function LayoutEditorSearch:SetSearchHint(message)
    self.searchHint.content = message or ""
    self.searchHint.hidden = message == nil
end

-- Add the limited-search note when RuneQL is missing
local function withLimit(message)
    if Catalog.IsFull() then return message end
    return message .. " Without RuneQL search support, only items in your bank can be found."
end

-- Coalesce typing into one name lookup after a short pause
function LayoutEditorSearch:QueueSearch(value)
    local query = Text.trim(value)
    if query == "" then return self:RunSearch("") end
    self.pendingSearch = query
    self.searchDelayTicks = SEARCH_DELAY_TICKS
end

function LayoutEditorSearch:TickSearch()
    local completed = self.completedSearch
    if completed ~= nil then
        self.completedSearch = nil
        local searchPane = self.panes ~= nil and self.panes.search or nil
        if completed.requestId == self.searchRequestId and (self.panes == nil or searchPane ~= nil) then
            self.searchHandle = nil
            self.searchWaitTicks = nil
            self.activeSearchQuery = nil
            local ok, err = pcall(function()
                self:ApplySearchResults(completed.query, completed.results, completed.reason)
            end)
            if not ok then
                logSearchError("Bank Tags search render failed: ", err)
                self:SetSearchHint("Item search is unavailable right now.")
            end
        end
    elseif self.searchHandle ~= nil then
        self.searchWaitTicks = (self.searchWaitTicks or 0) + 1
        if self.searchWaitTicks >= SEARCH_TIMEOUT_TICKS then
            local timedOutQuery = self.activeSearchQuery or ""
            self:CancelSearch()
            logSearchError("Bank Tags search timed out for '" .. timedOutQuery .. "': ", Catalog.Diagnostics())
            self:ApplySearchResults(timedOutQuery, {}, "Item search timed out.")
        end
    end
    if self.pendingSearch == nil then return end
    self.searchDelayTicks = self.searchDelayTicks - 1
    if self.searchDelayTicks <= 0 then self:RunSearch(self.pendingSearch) end
end

-- Cancel any in-flight async item search
function LayoutEditorSearch:CancelSearch()
    self.searchRequestId = (self.searchRequestId or 0) + 1
    self.completedSearch = nil
    self.searchWaitTicks = nil
    self.activeSearchQuery = nil
    if self.searchHandle ~= nil then
        pcall(function() self.searchHandle:Cancel() end)
        self.searchHandle = nil
    end
end

-- Apply search results or an error message to the search grid
function LayoutEditorSearch:ApplySearchResults(query, results, err)
    self.searchResults = results or {}
    self.searchSelected = nil
    local slots, names = {}, {}
    for _, result in ipairs(self.searchResults) do
        local objectID = result.objectId
        if objectID ~= nil then
            local displayName = Text.plain(result.displayName or result.name or ("Item " .. objectID))
            slots[#slots + 1] = {
                kind = "item",
                objectID = objectID,
                result = result,
                displayName = displayName,
            }
            if names[objectID] == nil then names[objectID] = displayName end
        end
    end
    self.searchNames = names
    local pane = self.panes ~= nil and self.panes.search or nil
    if pane ~= nil then
        pane.slots = slots
        if pane.view ~= nil and pane.view.SetScrollPosition ~= nil then pane.view:SetScrollPosition(0) end
        if self.DrawPane ~= nil then self:DrawPane(pane, math.ceil(#slots / pane.columns), {}) end
        if pane.surface ~= nil and not pane.hidden and self.PlaceDragSurface ~= nil then
            self:PlaceDragSurface(pane.surface, "search")
        end
    end
    if err ~= nil then
        logSearchError("Bank Tags could not search items: ", err)
        self:SetSearchHint("Item search is unavailable right now.")
    elseif query == "" then
        self:SetSearchHint(nil)
    else
        self:SetSearchHint(#slots == 0 and withLimit("No items match that search.") or nil)
    end
    if self.layout ~= nil and self.ShowSelection ~= nil then self:ShowSelection() end
end

-- Show item matches or explain an unavailable search
function LayoutEditorSearch:RunSearch(value)
    self.pendingSearch, self.searchDelayTicks = nil, nil
    self:CancelSearch()
    local query = Text.trim(value)
    if query == "" then
        self:ApplySearchResults("", {}, nil)
        return
    end
    local requestId = self.searchRequestId
    local inCall = true
    local settled = false
    self.activeSearchQuery = query
    self.searchWaitTicks = 0
    local handle = Catalog.FindAsync(query, SEARCH_RESULT_LIMIT, self.bankItemList, SEARCH_OPTIONS,
        function(results, _, _, reason)
            settled = true
            local searchPane = self.panes ~= nil and self.panes.search or nil
            if requestId ~= self.searchRequestId or (self.panes ~= nil and searchPane == nil) then return end
            local err = results == nil and (reason or "Item search failed.") or nil
            if inCall then
                self.searchHandle = nil
                self.searchWaitTicks = nil
                self.activeSearchQuery = nil
                local ok, applyErr = pcall(function()
                    self:ApplySearchResults(query, results or {}, err)
                end)
                if not ok then
                    logSearchError("Bank Tags search render failed: ", applyErr)
                    self:SetSearchHint("Item search is unavailable right now.")
                end
            else
                -- Defer UI work onto Bank Tags' own Event.Logic tick (off RuneQL's callback stack)
                self.completedSearch = {
                    requestId = requestId,
                    query = query,
                    results = results or {},
                    reason = err,
                }
            end
        end)
    inCall = false
    if not settled then
        self.searchHandle = handle
        self.searchResults = {}
        self.searchSelected = nil
        self.searchNames = {}
        local pane = self.panes ~= nil and self.panes.search or nil
        if pane ~= nil then
            pane.slots = {}
            if self.DrawPane ~= nil then self:DrawPane(pane, 0, {}) end
        end
        self:SetSearchHint("Searching...")
        if self.layout ~= nil and self.ShowSelection ~= nil then self:ShowSelection() end
    end
end

-- Add and place a search result in one save
function LayoutEditorSearch:AddCatalogResult(result, destination)
    local tag = self.selectedTag
    -- Keep adding and placing an item in one undo step
    return (self:SaveEdit("Could not add the item to this tag.", function()
        local layoutKey
        -- Save item membership and placement together
        local saved, reason = self.store:SaveTogether(function()
            -- Keep a separate layout slot for the repeated item
            local added, addReason
            added, addReason, layoutKey = self.store:AddTag(tag, result.objectId)
            if not added then return false, addReason end
            return self.store:MoveLayoutItem(tag, layoutKey, destination, Size.CENTER_COLUMNS)
        end)
        if saved then self:SelectOnly(layoutKey) end
        return saved, reason
    end))
end

return LayoutEditorSearch
