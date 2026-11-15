-- Search items and add results to the layout editor's tag

local Catalog = require("resources/tags/catalog")
local debugLog = require("resources/core/debug_log").Write
local Text = require("resources/core/text")
local Theme = require("resources/ui/theme")
local Parts = require("resources/windows/layout_editor_parts")
local Size = Parts.size

local SEARCH_RESULT_LIMIT = 100
local SEARCH_OPTIONS = { bankableOnly = true, includeFields = false }
local SEARCH_ICON_SIZE = 24
local ROW_HEIGHT = Size.SEARCH_ROW_HEIGHT
local SEARCH_DELAY_TICKS = 3

local LayoutEditorSearch = {}

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
    if self.pendingSearch == nil then return end
    self.searchDelayTicks = self.searchDelayTicks - 1
    if self.searchDelayTicks <= 0 then self:RunSearch(self.pendingSearch) end
end

-- Show item matches or explain an unavailable search
function LayoutEditorSearch:RunSearch(value)
    self.pendingSearch, self.searchDelayTicks = nil, nil
    local query = Text.trim(value)
    local ok, results = true, {}
    if query ~= "" then
        ok, results = pcall(Catalog.Find, query, SEARCH_RESULT_LIMIT, self.bankItemList, SEARCH_OPTIONS)
    end
    if not ok then
        debugLog("Bank Tags could not search items: ", results)
        results = {}
    end
    self.searchResults = results
    self.searchList:SetEntries(self:SearchEntries(results))
    if not ok then
        self:SetSearchHint("Item search is unavailable right now.")
    elseif query == "" then
        self:SetSearchHint(nil)
    else
        self:SetSearchHint(#results == 0 and withLimit("No items match that search.") or nil)
    end
    self:DrawSearchIcons(self.searchList, results)
    self.searchDragSurface:MoveToFront()
end

-- Place the same icon and name in either side panel's result rows
function LayoutEditorSearch:DrawSearchIcons(list, results, sprites, bankStyles)
    for index, row in ipairs(list.rows) do
        local icon = ui.Sprite.new(row.root)
        icon:SetPos(7, (ROW_HEIGHT - SEARCH_ICON_SIZE) // 2)
        icon:SetSize(SEARCH_ICON_SIZE, SEARCH_ICON_SIZE)
        icon:SetAssociatedObject(results[index].objectId)
        icon.outlineWidth = 1
        if bankStyles then self:StyleItem(icon, results[index].objectId, true)
        else icon.associatedObjectQuantityMode = ui.ObjectQuantityDisplayMode.NEVER end
        if sprites ~= nil then sprites[index] = icon end
        icon.clickthrough = true
        row.label:SetPos(38, 0)
        -- Follow row width so scrolling and name tooltips agree
        row.label:SetSize(-44, ROW_HEIGHT, 1.0, 0)
        row.label:MoveToFront()
    end
end

-- Build named rows for item search results
function LayoutEditorSearch:SearchEntries(results)
    local entries = {}
    for row, result in ipairs(results) do
        entries[row] = {
            id = row,
            label = Text.plain(result.displayName),
            backgroundColour = row % 2 == 1 and Theme.ROW_ODD or Theme.ROW_EVEN,
            hoverColour = Theme.ROW_HOVER,
            selectedColour = Theme.ROW_SELECTED,
            textColour = Theme.TEXT,
        }
    end
    return entries
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
