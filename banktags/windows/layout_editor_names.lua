-- Name the item under the pointer in the layout editor's grids

local BankGrid = require("banktags/ui/bank_grid")
local Geometry = require("banktags/ui/geometry")
local ObjectConfig = require("banktags/core/object_config")
local Text = require("banktags/core/text")
local Parts = require("banktags/windows/layout_editor_parts")
local Size = Parts.size

local LayoutEditorNames = {}

-- Create the editor's one name tooltip and follow the pointer over each drag surface
-- The surfaces cover the grids and results, so they hear the hover the items cannot
function LayoutEditorNames:CreateItemNames()
    self.nameAnchor = ui.Layer.new(self.content)
    self.nameTooltip = prettyui.Tooltip.attach(self.nameAnchor, self.content, " ")
    self.nameAnchor.clickthrough = true
    self.nameShown = nil
    self.nameSurface = nil
    for _, surface in ipairs({ self.panes.sorted.surface, self.panes.unsorted.surface }) do
        Geometry.trackPointer(surface)
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
    Geometry.trackPointer(self.searchDragSurface)
    self.searchDragSurface:Subscribe(ui.Hook.ONMOUSEOVER, function()
        self.nameSurface = nil
        self:HideItemName()
        return true
    end)
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
    local item = x ~= nil and self:GridItemAt(x, y) or nil
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
