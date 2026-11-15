-- Name the item under the pointer in the layout editor's grids

local BankGrid = require("resources/ui/bank_grid")
local ObjectConfig = require("resources/core/object_config")
local Text = require("resources/core/text")
local Parts = require("resources/windows/layout_editor_parts")
local Size = Parts.size
local TOOLTIP_GAP = 6

local LayoutEditorNames = {}

-- Create a positioning anchor for the editor's one item-name tooltip
function LayoutEditorNames:CreateItemNames()
    self.nameAnchor = ui.Layer.new(self.content)
    self.nameAnchor.hidden = true
    self.nameTooltipOptions = { text = " ", parent = self.content, placement = "below" }
    self.nameTooltip = prettyui.Tooltip.attach(self.nameAnchor, self.content, self.nameTooltipOptions)
    -- Let the grid surface control this tooltip's visibility
    self.nameAnchor.enabled = false
    self.nameAnchor.clickthrough = true
end

-- Anchor search item names beneath their icons, even when the row name fits
function LayoutEditorNames:SearchItemAt(x, y)
    if not self:OnSearchList(x, y) then return nil end
    local top = Size.PANEL_TOP + Size.SEARCH_LIST_TOP
    local row = (y - top + self.searchList.scrollY) // Size.SEARCH_ROW_HEIGHT
    local result = self.searchResults[row + 1]
    if result == nil then return nil end
    local iconSize = 24
    return { objectID = result.objectId, name = result.displayName, x = Size.SEARCH_X + Size.SEARCH_INSET + 7,
        y = top + row * Size.SEARCH_ROW_HEIGHT - self.searchList.scrollY
            + (Size.SEARCH_ROW_HEIGHT - iconSize) // 2, size = iconSize }
end

-- Find the item and cell under an editor point
function LayoutEditorNames:GridItemAt(x, y)
    local pane, paneX, paneY = self:PaneAt(x, y)
    if pane == nil then return nil end
    local index = self:SlotIndexAt(pane, paneX, paneY)
    local slot = index ~= nil and pane.slots[index] or nil
    if slot == nil or slot.kind ~= "item" then return nil end
    local zero = index - 1
    local cellX = self:GridCellX(pane, zero % pane.columns)
    local cellY = BankGrid.RowItemY(zero // pane.columns, pane.labels) - pane.view.scrollY
    -- The gaps between cells name nothing
    if paneX - cellX >= Size.GRID_SLOT_SIZE or paneY < cellY or paneY - cellY >= Size.GRID_SLOT_SIZE then
        return nil
    end
    return { objectID = slot.objectID,
        name = pane.name == "unsorted" and self.unsortedNames[slot.objectID] or nil,
        x = pane.x + cellX, y = pane.y + cellY, size = Size.GRID_SLOT_SIZE }
end

-- Match the bank's absent-item tooltip, centered below with an above fallback
function LayoutEditorNames:PlaceItemName(item)
    local tooltip = self.nameTooltip
    self.nameTooltipOptions.x = math.floor(item.x + (item.size - tooltip.width) / 2)
    local below = item.y + item.size + TOOLTIP_GAP
    if below + tooltip.height > self.content.height - TOOLTIP_GAP then
        below = item.y - tooltip.height - TOOLTIP_GAP
    end
    self.nameTooltipOptions.y = below
    tooltip:Show()
end

-- Show the hovered item's name after pointer events settle
function LayoutEditorNames:UpdateItemName()
    local surface = self.pointerSurface
    if surface == nil or self.drag ~= nil
        or self.window.root.hidden or self:OverlayShown() or MiniMenu.IsOpen() then
        return self:HideItemName()
    end
    local x, y = self:ContentPointer()
    local item = x ~= nil and (self:GridItemAt(x, y) or self:SearchItemAt(x, y)) or nil
    if item == nil then return self:HideItemName() end
    -- The client's name is read only when the pointer reaches another item or cell
    local shown = item.objectID .. "@" .. item.x .. "," .. item.y
    if self.nameShown ~= shown then
        local name = Text.plain(item.name or ObjectConfig.DisplayName(item.objectID))
        -- An item the client cannot name shows nothing
        if name == "" then return self:HideItemName() end
        self.nameShown = shown
        self.nameAnchor:SetPos(item.x, item.y)
        self.nameAnchor:SetSize(item.size, item.size)
        self.nameTooltip:SetText(name)
        self:PlaceItemName(item)
    end
end

-- Hide the item name
function LayoutEditorNames:HideItemName()
    if self.nameShown == nil then return end
    self.nameShown = nil
    self.nameTooltip:Hide()
end

-- Destroy the item name tooltip and its anchor
function LayoutEditorNames:DestroyItemNames()
    self.nameTooltip:Destroy()
    self.nameAnchor:Destroy()
    self.nameShown = nil
end

return LayoutEditorNames
