-- Browse and search every item in the player's bank from the left panel

local ObjectConfig = require("resources/core/object_config")
local Parts = require("resources/windows/layout_editor_parts")
local Text = require("resources/core/text")
local Theme = require("resources/ui/theme")
local Size = Parts.size

local Bank = {}

-- RS3 uses object ID 6512 (BLANKOBJECT) for empty slots inside BANK__BANK_INV
local BLANK_OBJECT_ID = 6512

-- Return a real bank item's display name, or nil for empty/placeholder bank slots
local function realBankItemName(objectID)
    if objectID == nil or objectID < 0 or objectID == BLANK_OBJECT_ID then return nil end
    local configName = ObjectConfig.ConfigName(objectID)
    if type(configName) == "string" then
        local upper = string.upper(configName)
        if upper == "BLANKOBJECT" or upper == "NULL" then return nil end
    end
    local raw = ObjectConfig.DisplayName(objectID)
    if raw == nil then return nil end
    local name = Text.trim(Text.plain(raw))
    if name == "" or string.lower(name) == "null" then return nil end
    return name
end

-- Create the bank item search field and scrollable grid inside the Bank tab
function Bank:CreateBank()
    self.bankQuery, self.bankNames = "", {}
    self.bankSearch = prettyui.TextField.new(self.bankPanel, {
        x = Size.SEARCH_INSET, y = Size.SEARCH_FIELD_TOP,
        width = Size.LEFT_VIEW_WIDTH, height = Size.SEARCH_FIELD_HEIGHT,
        placeholder = "Search bank items...", maxLength = 80,
        onChange = function(field, _, value)
            self.keysOnGrid = false
            self:FilterBank(Text.cleanField(field, value))
        end,
        onSubmit = function(_, value) self:FilterBank(value) end,
    })
    local width, height = Size.LEFT_VIEW_WIDTH - 2, Size.SEARCH_LIST_HEIGHT - 2
    local view = prettyui.SimpleView.new(self.bankPanel, {
        x = Size.SEARCH_INSET + 1, y = Size.SEARCH_LIST_TOP + 1,
        width = width, height = height, contentHeight = height, scrollStep = Size.GRID_STEP,
    })
    Parts.rectangle(self.bankPanel, Size.SEARCH_INSET, Size.SEARCH_LIST_TOP,
        Size.LEFT_VIEW_WIDTH, Size.SEARCH_LIST_HEIGHT, Theme.INNER_FRAME, false)
    local columns = math.max(1, (width - Size.SCROLLBAR_RESERVE - 2 * Size.GRID_LEFT
        + Size.GRID_STEP - Size.GRID_SLOT_SIZE) // Size.GRID_STEP)
    local pane = {
        name = "bank", columns = columns, gridLeft = Size.GRID_LEFT,
        x = Size.LEFT_X + Size.SEARCH_INSET + 1,
        y = Size.LEFT_BODY_TOP + Size.SEARCH_LIST_TOP + 1,
        width = width, height = height,
        slots = {}, sprites = {}, labels = {}, rowCount = 0, view = view, outlines = {},
        marks = Parts.layer(view.content, 0, 0, width, height),
    }
    view.onLayout = function()
        if self.RenderPaneWindow ~= nil then self:RenderPaneWindow(pane, false) end
    end
    self.panes.bank = pane
    self.bankHint = prettyui.Text.new(self.bankPanel, {
        text = "", x = Size.SEARCH_INSET + 8, y = Size.SEARCH_LIST_TOP + 4,
        width = Size.LEFT_VIEW_WIDTH - 16, height = 150,
        colour = Theme.MUTED_TEXT, maxLines = 10, alignVertical = ui.AlignMode.TOPLEFT,
    })
end

-- Filter visible bank items by their display names
function Bank:FilterBank(value)
    self.bankQuery = Text.plain(value)
    self:CancelDrag()
    self:HideItemName()
    self.panes.bank.view:SetScrollPosition(0)
    self:RefreshBank()
end

-- Populate the Bank grid with unique items in bank order matching the search
function Bank:RefreshBank()
    local pane = self.panes ~= nil and self.panes.bank or nil
    if pane == nil then return end
    local slots, seen = {}, {}
    local query = string.lower(self.bankQuery or "")
    local total = 0
    for _, item in ipairs(self.bankItemList or {}) do
        local objectID = item.objectID
        if objectID ~= nil and not seen[objectID] then
            seen[objectID] = true
            local name = self.bankNames[objectID]
            if name == nil then
                name = realBankItemName(objectID) or false
                self.bankNames[objectID] = name
            end
            if name ~= false then
                total = total + 1
                if query == "" or string.find(string.lower(name), query, 1, true) ~= nil then
                    slots[#slots + 1] = { kind = "item", objectID = objectID }
                end
            end
        end
    end
    pane.slots = slots
    self:DrawPane(pane, math.ceil(#slots / pane.columns), {})
    local empty = #slots == 0
    self.bankHint.content = total == 0 and "No bank items available."
        or "No bank items match that search."
    self.bankHint.hidden = not empty
    if pane.surface ~= nil then self:PlaceDragSurface(pane.surface, "bank") end
    if self.layout ~= nil and self.ShowSelection ~= nil then self:ShowSelection() end
end

-- Add one or more items into the first open cells of the open tag's layout
function Bank:AddItemsToLayout(objectIDs)
    if self.selectedTag == nil then
        self:ShowError("Choose a tag before adding items.")
        return false
    end
    if type(objectIDs) ~= "table" or #objectIDs == 0 then return false end
    local tag = self.selectedTag
    local cells = self.store:OpenLayoutCells(tag, #objectIDs, 1, Size.CENTER_COLUMNS)
    return (self:SaveEdit("Could not add the items to the layout.", function()
        local saved, keys, reason = self.store:PlaceItemsAtCells(tag, objectIDs, cells, Size.CENTER_COLUMNS)
        if saved and keys ~= nil then self:SelectItems(keys) end
        return saved, reason
    end))
end

-- Add one or more items to the open tag's Unsorted section
function Bank:AddItemsToUnsorted(objectIDs)
    if self.selectedTag == nil then
        self:ShowError("Choose a tag before adding items.")
        return false
    end
    if type(objectIDs) ~= "table" or #objectIDs == 0 then return false end
    local tag = self.selectedTag
    return (self:SaveEdit("Could not add the items to this tag.", function()
        local addedKeys = {}
        local saved, reason = self.store:SaveTogether(function()
            for _, objectID in ipairs(objectIDs) do
                local added, addReason, layoutKey = self.store:AddTag(tag, objectID)
                if not added then return false, addReason end
                if layoutKey ~= nil then addedKeys[#addedKeys + 1] = layoutKey end
            end
            return true
        end)
        if saved and #addedKeys > 0 then self:SelectUnsortedItems(addedKeys) end
        return saved, reason
    end))
end

-- Add a bank item to the first open cell of the open tag's layout
function Bank:AddBankItemToLayout(objectID)
    return self:AddItemsToLayout({ objectID })
end

-- Add a bank item to the open tag's Unsorted section
function Bank:AddBankItemToUnsorted(objectID)
    return self:AddItemsToUnsorted({ objectID })
end

return Bank
