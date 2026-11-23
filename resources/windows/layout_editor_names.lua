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
    self.nameAnchor = Parts.layer(self.content, 0, 0, 1, 1)
    self.nameAnchor.hidden = true
    self.nameTooltipOptions = { text = " ", parent = self.content, placement = "below" }
    self.nameTooltip = prettyui.Tooltip.attach(self.nameAnchor, self.content, self.nameTooltipOptions)
    -- Let the grid surface control this tooltip's visibility
    self.nameAnchor.enabled = false
    self.nameAnchor.clickthrough = true
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
    local cachedName = slot.displayName
        or (pane.name == "unsorted" and self.unsortedNames and self.unsortedNames[slot.objectID])
        or (pane.name == "bank" and self.bankNames and self.bankNames[slot.objectID])
        or (pane.name == "search" and self.searchNames and self.searchNames[slot.objectID]) or nil
    return { objectID = slot.objectID,
        name = cachedName,
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
    local item = x ~= nil and self:GridItemAt(x, y) or nil
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
