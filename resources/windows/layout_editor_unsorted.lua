-- Search existing Unsorted slots without changing their saved order or identity

local ObjectConfig = require("resources/core/object_config")
local Parts = require("resources/windows/layout_editor_parts")
local Text = require("resources/core/text")
local Theme = require("resources/ui/theme")
local Size = Parts.size
local Unsorted = {}

-- Keep the search field and border around an independently scrolling grid
function Unsorted:CreateUnsorted()
    self.unsortedQuery, self.unsortedNames = "", {}
    self.unsortedSearch = prettyui.TextField.new(self.unsortedPanel, {
        x = Size.SEARCH_INSET, y = Size.SEARCH_FIELD_TOP,
        width = Size.UNSORTED_VIEW_WIDTH, height = Size.SEARCH_FIELD_HEIGHT,
        placeholder = "Search unsorted items...", maxLength = 80,
        onChange = function(field, _, value)
            self.keysOnGrid = false
            self:FilterUnsorted(Text.cleanField(field, value))
        end,
        onSubmit = function(_, value) self:FilterUnsorted(value) end,
    })
    local width, height = Size.UNSORTED_VIEW_WIDTH - 2, Size.SEARCH_LIST_HEIGHT - 2
    local view = prettyui.SimpleView.new(self.unsortedPanel, {
        x = Size.SEARCH_INSET + 1, y = Size.SEARCH_LIST_TOP + 1,
        width = width, height = height, contentHeight = height, scrollStep = Size.GRID_STEP,
    })
    Parts.rectangle(self.unsortedPanel, Size.SEARCH_INSET, Size.SEARCH_LIST_TOP,
        Size.UNSORTED_VIEW_WIDTH, Size.SEARCH_LIST_HEIGHT, Theme.INNER_FRAME, false)
    local columns = math.max(1, (width - Size.SCROLLBAR_RESERVE - 2 * Size.GRID_LEFT
        + Size.GRID_STEP - Size.GRID_SLOT_SIZE) // Size.GRID_STEP)
    self.panes.unsorted = {
        name = "unsorted", columns = columns, gridLeft = Size.GRID_LEFT,
        x = Size.UNSORTED_X + Size.SEARCH_INSET + 1,
        y = Size.PANEL_TOP + Size.SEARCH_LIST_TOP + 1,
        width = width, height = height,
        slots = {}, sprites = {}, labels = {}, rowCount = 0, view = view, outlines = {}, indexes = {},
        marks = Parts.layer(view.content, 0, 0, width, height),
    }
    self.unsortedHint = prettyui.Text.new(self.unsortedPanel, {
        text = "", x = Size.SEARCH_INSET + 8, y = Size.SEARCH_LIST_TOP + 4,
        width = Size.UNSORTED_VIEW_WIDTH - 16, height = 150,
        colour = Theme.MUTED_TEXT, maxLines = 10, alignVertical = ui.AlignMode.TOPLEFT,
    })
end

-- Filter only the current tag's Unsorted items by their displayed names
function Unsorted:FilterUnsorted(value)
    self.unsortedQuery = Text.plain(value)
    self:CancelDrag()
    self:HideItemName()
    self.panes.unsorted.view:SetScrollPosition(0)
    if self.layout ~= nil then self:RefreshUnsorted(); self:ShowSelection() end
end

-- Pack filtered slots into the grid without changing saved order or duplicate keys
function Unsorted:RefreshUnsorted()
    local pane, slots, indexes = self.panes.unsorted, {}, {}
    local query = string.lower(self.unsortedQuery)
    for _, slot in ipairs(self.layout.unsorted) do
        local name = self.unsortedNames[slot.objectID]
        if name == nil then
            name = Text.plain(ObjectConfig.DisplayName(slot.objectID) or ("Item " .. slot.objectID))
            self.unsortedNames[slot.objectID] = name
        end
        if query == "" or string.find(string.lower(name), query, 1, true) ~= nil then
            slots[#slots + 1] = slot
            indexes[slot.layoutKey] = #slots
        end
    end
    pane.slots, pane.indexes = slots, indexes
    self:DrawPane(pane, math.ceil(#slots / pane.columns), {})
    local empty = #slots == 0
    self.unsortedHint.content = #self.layout.unsorted == 0 and "No unsorted items."
        or "No unsorted items match that search."
    self.unsortedHint.hidden = not empty
    if pane.surface ~= nil then self:PlaceDragSurface(pane.surface, "unsorted") end
end

return Unsorted
