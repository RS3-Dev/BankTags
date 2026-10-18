-- Draw the sidebar's vertical sprite tabs and page through them when they do not fit

local Config = require("lib/core/config")
local BankControls = require("lib/ui/bank_controls")
local Theme = require("lib/ui/theme")
local Geometry = require("lib/ui/geometry")

local SidebarTabRail = {}
SidebarTabRail.__index = SidebarTabRail

local TAB_SIZE = Config.SIDEBAR_TAB_WIDTH
local TAB_GAP = 4
local TAB_STEP = TAB_SIZE + TAB_GAP
local ICON_SIZE = 20
local ARROW_HEIGHT = 20
local ARROW_ICON_SIZE = 16
local MAX_SLOTS = 24
local BACKDROP_SPRITE = 18035 -- RS3_CHILD_CONTENT_TILE

SidebarTabRail.TAB_SIZE = TAB_SIZE
SidebarTabRail.TAB_GAP = TAB_GAP
SidebarTabRail.ARROW_HEIGHT = ARROW_HEIGHT
SidebarTabRail.MAX_SLOTS = MAX_SLOTS

-- Choose which tabs fit in a height, keeping the active one in view when asked.
-- Returns the first shown index, how many are shown, where the first sits, and
-- whether the paging arrows are shown
function SidebarTabRail.Layout(count, activeIndex, first, height)
    local fit = math.min(MAX_SLOTS, math.floor((height + TAB_GAP) / TAB_STEP))
    if count <= fit then
        return { first = 1, shown = count, top = 0, arrows = false }
    end
    local arrowSpace = ARROW_HEIGHT + TAB_GAP
    local slots = math.min(MAX_SLOTS,
        math.floor((height - arrowSpace * 2 + TAB_GAP) / TAB_STEP))
    -- Too short for arrows and a tab: show only the active tab
    if slots < 1 then
        return { first = activeIndex or 1, shown = math.min(1, count), top = 0, arrows = false }
    end
    first = math.max(1, math.min(first or 1, count - slots + 1))
    if activeIndex ~= nil then
        if activeIndex < first then first = activeIndex end
        if activeIndex > first + slots - 1 then first = activeIndex - slots + 1 end
    end
    return { first = first, shown = slots, top = arrowSpace, arrows = true }
end

-- Create an empty rail at a position in its parent
function SidebarTabRail.new(parent, options)
    local self = setmetatable({
        x = options.x,
        y = options.y,
        height = options.height,
        onSelect = options.onSelect,
        tabs = {},
        activeID = nil,
        first = 1,
        controls = {},
        signature = nil,
    }, SidebarTabRail)
    self.root = ui.Layer.new(parent)
    self.root:SetPos(self.x, self.y)
    self.root:SetSize(TAB_SIZE, self.height)
    self.root.clickthrough = false
    -- Draw tooltips in the window rather than clipping them to the narrow rail
    prettyui.Tooltip.registerContext(self.root, parent, function(target)
        return Geometry.relativePosition(target, parent)
    end)
    -- The tile stays an ordinary sibling so the tabs above it keep their order
    self.background = ui.Sprite.new(self.root)
    self.background:SetSize(TAB_SIZE, self.height)
    self.background.spriteID = BACKDROP_SPRITE
    self.background.isTiling = true
    self.background.clickthrough = true
    return self
end

-- Find a tab's position in the current list
function SidebarTabRail:IndexOf(tabID)
    for index, tab in ipairs(self.tabs) do
        if tab.id == tabID then return index end
    end
    return nil
end

-- Show these tabs with one active, bringing the active tab into view
function SidebarTabRail:SetTabs(tabs, activeID)
    self.tabs = tabs
    self.activeID = activeID
    self.view = SidebarTabRail.Layout(#tabs, self:IndexOf(activeID), self.first, self.height)
    self.first = self.view.first
    self:Draw()
end

-- Page the visible tabs up or down without changing the active tab
function SidebarTabRail:Scroll(offset)
    if self.view == nil or not self.view.arrows then return false end
    self.view = SidebarTabRail.Layout(#self.tabs, nil, self.first + offset, self.height)
    if self.view.first == self.first then return false end
    self.first = self.view.first
    self:Draw()
    return true
end

-- Describe what is drawn, so an unchanged rail is not rebuilt
local function drawSignature(self)
    local parts = { tostring(self.activeID), self.view.first, self.view.shown,
        tostring(self.view.arrows) }
    for _, tab in ipairs(self.tabs) do
        parts[#parts + 1] = tab.id .. "|" .. tab.icon .. "|" .. (tab.tooltip or tab.label)
    end
    return table.concat(parts, "\n")
end

-- Destroy the drawn tabs, arrows, and selection frame
function SidebarTabRail:Clear()
    for index = #self.controls, 1, -1 do
        pcall(function() self.controls[index]:Destroy() end)
    end
    self.controls = {}
    self.buttons = {}
    self.upArrow = nil
    self.downArrow = nil
    self.selectionFrame = nil
end

-- Outline the active tab with the native gold frame
local function addSelectionFrame(self, y)
    local edges = {}
    for index, bounds in ipairs({
        { 0, y, TAB_SIZE, 1 },
        { 0, y + TAB_SIZE - 1, TAB_SIZE, 1 },
        { 0, y, 1, TAB_SIZE },
        { TAB_SIZE - 1, y, 1, TAB_SIZE },
    }) do
        local edge = ui.Rectangle.new(self.root)
        edge:SetPos(bounds[1], bounds[2])
        edge:SetSize(bounds[3], bounds[4])
        edge.fill = true
        edge.rgba = Theme.SELECTED_BORDER
        edge.clickthrough = true
        edge:MoveToFront()
        edges[index] = edge
        self.controls[#self.controls + 1] = edge
    end
    self.selectionFrame = edges
end

-- Build the visible tabs, the active frame, and the paging arrows
function SidebarTabRail:Draw()
    local signature = drawSignature(self)
    if signature == self.signature then return end
    self:Clear()
    self.signature = signature
    local view = self.view
    for slot = 1, view.shown do
        local tab = self.tabs[view.first + slot - 1]
        local y = view.top + (slot - 1) * TAB_STEP
        local button = BankControls.button(self.root, nil, function()
            if self.onSelect ~= nil then self.onSelect(tab.id) end
        end, {
            x = 0,
            y = y,
            size = TAB_SIZE,
            iconSize = ICON_SIZE,
            spriteName = tab.icon,
            tooltip = tab.tooltip or tab.label,
            active = tab.id == self.activeID,
        })
        button.tabID = tab.id
        self.buttons[#self.buttons + 1] = button
        self.controls[#self.controls + 1] = button
        if tab.id == self.activeID then addSelectionFrame(self, y) end
    end
    if not view.arrows then return end
    -- Return an arrow that pages the tabs one step
    local function arrow(y, spriteName, tooltip, offset, disabled)
        local button = BankControls.button(self.root, nil, function()
            self:Scroll(offset)
        end, {
            x = 0,
            y = y,
            width = TAB_SIZE,
            height = ARROW_HEIGHT,
            iconSize = ARROW_ICON_SIZE,
            spriteName = spriteName,
            tooltip = tooltip,
            disabled = disabled,
        })
        self.controls[#self.controls + 1] = button
        return button
    end
    self.upArrow = arrow(0, "ARROW_UP", "More tabs above", -1, view.first == 1)
    self.downArrow = arrow(self.height - ARROW_HEIGHT, "ARROW_DOWN",
        "More tabs below", 1, view.first + view.shown - 1 >= #self.tabs)
end

-- Remove the rail and everything drawn on it
function SidebarTabRail:Destroy()
    self:Clear()
    if self.root ~= nil then prettyui.Tooltip.unregisterContext(self.root) end
    if self.root ~= nil then pcall(function() self.root:Destroy() end) end
    self.root = nil
    self.background = nil
end

return SidebarTabRail
