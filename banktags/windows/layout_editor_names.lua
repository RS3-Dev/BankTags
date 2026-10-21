-- Name the item under the pointer in the layout editor's grids and search results

local BankGrid = require("banktags/ui/bank_grid")
local ObjectConfig = require("banktags/core/object_config")
local Text = require("banktags/core/text")
local Parts = require("banktags/windows/layout_editor_parts")
local Size = Parts.size

-- Search rows are 32px tall with a 24px icon 7px in
local SEARCH_ROW_HEIGHT = 32
local SEARCH_ICON_X = 7
local SEARCH_ICON_SIZE = 24

local LayoutEditorNames = {}

-- Create the editor's one name tooltip and follow the pointer over each drag surface
-- The surfaces cover the grids and results, so they hear the hover the items cannot
function LayoutEditorNames:CreateItemNames()
    self.nameAnchor = ui.Layer.new(self.content)
    self.nameTooltip = prettyui.Tooltip.attach(self.nameAnchor, self.content, " ")
    self.nameAnchor.clickthrough = true
    self.nameShown = nil
    self.nameSurface = nil
    for _, surface in ipairs({ self.panes.sorted.surface, self.panes.unsorted.surface, self.searchDragSurface }) do
        surface:Subscribe(ui.Hook.ONMOUSEOVER, function()
            self.nameSurface = surface
            return true
        end)
        surface:Subscribe(ui.Hook.ONMOUSELEAVE, function()
            if self.nameSurface == surface then self.nameSurface = nil end
            self:HideItemName()
            return true
        end)
    end
end

-- Find a grid item's name and cell under a content point
function LayoutEditorNames:GridItemAt(x, y)
    local pane, paneX, paneY = self:PaneAt(x, y)
    if pane == nil then return nil end
    local index = self:SlotIndexAt(pane, paneX, paneY)
    local slot = index ~= nil and pane.slots[index] or nil
    if type(slot) ~= "table" or slot.kind ~= "item" then return nil end
    local zero = index - 1
    local cellX = Size.GRID_LEFT + zero % pane.columns * Size.GRID_STEP
    local cellY = BankGrid.RowItemY(zero // pane.columns) - (tonumber(pane.view.scrollY) or 0)
    -- The gaps between cells name nothing
    if paneX - cellX >= Size.GRID_SLOT_SIZE or paneY < cellY or paneY - cellY >= Size.GRID_SLOT_SIZE then
        return nil
    end
    return {
        name = ObjectConfig.DisplayName(slot.objectID),
        x = pane.x + cellX, y = pane.y + cellY, size = Size.GRID_SLOT_SIZE,
    }
end

-- Find a search result's name and icon under a content point
function LayoutEditorNames:SearchItemAt(x, y)
    if not self:OnSearchList(x, y) then return nil end
    local top = Size.PANEL_TOP + Size.SEARCH_LIST_TOP
    local scrollY = tonumber(self.searchList.scrollY) or 0
    local index = (y - top + scrollY) // SEARCH_ROW_HEIGHT + 1
    local result = self.searchResults[index]
    if result == nil then return nil end
    return {
        name = result.displayName or ObjectConfig.DisplayName(result.objectId),
        x = Size.RIGHT_X + Size.VIEW_INSET + SEARCH_ICON_X,
        y = top + (index - 1) * SEARCH_ROW_HEIGHT - scrollY + (SEARCH_ROW_HEIGHT - SEARCH_ICON_SIZE) // 2,
        size = SEARCH_ICON_SIZE,
    }
end

-- Show the name of the item under the pointer, or hide it
-- Runs every tick, since moving within a surface raises no hover event
-- A window opened over the editor or a menu may cover the grids without a leave
function LayoutEditorNames:UpdateItemName()
    if self.nameSurface == nil or self.nameSurface.hidden or self.drag ~= nil
        or self.window == nil or self.window.root.hidden
        or self:OverlayShown() or MiniMenu.IsOpen() then
        return self:HideItemName()
    end
    local x, y = self:ContentPointer()
    local item = x ~= nil and (self:GridItemAt(x, y) or self:SearchItemAt(x, y)) or nil
    local name = item ~= nil and Text.plain(item.name) or ""
    -- An item the client cannot name shows nothing
    if name == "" then return self:HideItemName() end
    local shown = name .. "@" .. item.x .. "," .. item.y
    if self.nameShown ~= shown then
        self.nameShown = shown
        self.nameAnchor:SetPos(item.x, item.y)
        self.nameAnchor:SetSize(item.size, item.size)
        self.nameTooltip:SetText(name)
    end
    -- The tooltip draws beside the window, which KeepOnTop raises every tick
    self.nameTooltip:Show()
end

-- Hide the item name
function LayoutEditorNames:HideItemName()
    if self.nameShown == nil then return end
    self.nameShown = nil
    self.nameTooltip:Hide()
end

-- Destroy the item name tooltip
function LayoutEditorNames:DestroyItemNames()
    if self.nameTooltip ~= nil then pcall(function() self.nameTooltip:Destroy() end) end
    if self.nameAnchor ~= nil then pcall(function() self.nameAnchor:Destroy() end) end
    self.nameTooltip, self.nameAnchor, self.nameShown, self.nameSurface = nil, nil, nil, nil
end

-- Attach these methods to LayoutEditorWindow
function LayoutEditorNames.install(target)
    for name, method in pairs(LayoutEditorNames) do
        if name ~= "install" then target[name] = method end
    end
end

return LayoutEditorNames
