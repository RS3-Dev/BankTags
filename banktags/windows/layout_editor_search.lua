-- Search items and add results to the layout editor's tag

local Catalog = require("banktags/tags/catalog")
local debugLog = require("banktags/core/debug_log").Write
local Text = require("banktags/core/text")
local Theme = require("banktags/ui/theme")
local Parts = require("banktags/windows/layout_editor_parts")
local Size = Parts.size
local objectFromID = Parts.objectFromID
local trim = Text.trim

local SEARCH_HINT = Parts.SEARCH_HINT
local SEARCH_RESULT_LIMIT = 100
local SEARCH_ICON_SIZE = 24
local ROW_ODD = Theme.ROW_ODD
local ROW_EVEN = Theme.ROW_EVEN
local ROW_HOVER = Theme.ROW_HOVER
local ROW_SELECTED = Theme.ROW_SELECTED
local TEXT = Theme.TEXT

local LayoutEditorSearch = {}

-- Clear previous search hit targets and sprites
function LayoutEditorSearch:ClearSearchInteractions()
    self.searchResults = {}
    if self.searchList ~= nil then self.searchList:SetEntries({}) end
end

-- Show or hide guidance in the empty search panel
function LayoutEditorSearch:SetSearchHint(message)
    if self.searchHint == nil then return end
    self.searchHint.content = tostring(message or "")
    self.searchHint.hidden = message == nil
end

-- Add the limited-search note when RuneQL is missing
local function withLimit(message)
    if Catalog.IsFull() then return message end
    return message .. " " .. Catalog.LIMITED_HINT
end

-- Search items and show matches or an error
function LayoutEditorSearch:RunSearch(value)
    local query = trim(value)
    if query == "" then
        self:ClearSearchInteractions()
        self:SetSearchHint(withLimit(SEARCH_HINT))
        return
    end
    local ok, results, total = pcall(Catalog.Find, query, SEARCH_RESULT_LIMIT, self.bankItemList)
    if not ok then
        self:ClearSearchInteractions()
        self:SetSearchHint("Item search is unavailable right now.")
        debugLog("Bank Tags could not search items: ", results)
        return
    end
    self:ShowSearchResults(results, total)
end

-- Build result rows and their item sprites
function LayoutEditorSearch:ShowSearchResults(results)
    local entries, visible = {}, {}
    for _, result in ipairs(results or {}) do
        local object = objectFromID(result.objectId)
        if object ~= nil then
            visible[#visible + 1] = result
            local row = #visible
            local key = tostring(result.objectId) .. ":" .. tostring(row)
            entries[#entries + 1] = {
                id = key,
                label = tostring(result.displayName or object.name
                    or ("Item " .. tostring(result.objectId))),
                enabled = true,
                backgroundColour = row % 2 == 1 and ROW_ODD or ROW_EVEN,
                hoverColour = ROW_HOVER,
                selectedColour = ROW_SELECTED,
                textColour = TEXT,
            }
        end
        if #visible >= SEARCH_RESULT_LIMIT then break end
    end
    self.searchResults = visible
    self.searchList:SetEntries(entries)
    self:SetSearchHint(#entries == 0 and withLimit("No items match that search.") or nil)
    for index, rowValue in ipairs(self.searchList.rows or {}) do
        local result = visible[index]
        if result ~= nil then
            local icon = ui.Sprite.new(rowValue.root)
            icon:SetPos(7, math.floor((32 - SEARCH_ICON_SIZE) / 2))
            icon:SetSize(SEARCH_ICON_SIZE, SEARCH_ICON_SIZE)
            icon:SetAssociatedObject(math.tointeger(tonumber(result.objectId)))
            icon.associatedObjectQuantityMode = ui.ObjectQuantityDisplayMode.NEVER
            icon.clickthrough = true
            rowValue.label:SetPos(38, 0)
            rowValue.label:SetSize(-44, 32, 1.0, 0)
            rowValue.label:MoveToFront()
        end
    end
    if self.searchDragSurface ~= nil then self.searchDragSurface:MoveToFront() end
    if self.labelDragSurface ~= nil then self.labelDragSurface:MoveToFront() end
end

-- Save a search result to the tag at a sorted slot
-- Adding and placing it is one save and one undo step, or nothing changes
function LayoutEditorSearch:AddCatalogResult(result, destination)
    local tag = self.selectedTag
    local objectID = math.tointeger(tonumber(result.objectId))
    if tag == nil or objectID == nil then return false end
    local layoutKey
    local saved, reason = self:RecordEdit(tag, function()
        return self.store:SaveTogether(function()
            -- An item already in the tag gets another slot, which shows its next stack
            local added, addReason
            added, addReason, layoutKey = self.store:AddTag(tag, objectID)
            if not added then return false, addReason end
            return self.store:MoveLayoutItem(tag, layoutKey, destination, Size.CENTER_COLUMNS)
        end)
    end)
    if not saved then
        self:ShowError(reason or "Could not add the item to this tag.")
        return false
    end
    self:SelectOnly(layoutKey)
    self:NotifyChanged(tag)
    return true
end

-- Attach these methods to LayoutEditorWindow
function LayoutEditorSearch.install(target)
    for name, method in pairs(LayoutEditorSearch) do
        if name ~= "install" then target[name] = method end
    end
end

return LayoutEditorSearch
