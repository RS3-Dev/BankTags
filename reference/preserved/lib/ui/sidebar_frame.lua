-- Draw the sidebar's tab rail and content column

local Config = require("lib/core/config")
local NativeUi = require("lib/ui/native_ui")
local Theme = require("lib/ui/theme")
local SidebarTabRail = require("lib/ui/sidebar_tab_rail")
local Geometry = require("lib/ui/geometry")

local SidebarFrame = {}

-- The content column starts after the tab rail and its gap
local CONTENT_OFFSET = Config.SIDEBAR_TAB_WIDTH + Config.SIDEBAR_TAB_GAP

SidebarFrame.CONTENT_OFFSET = CONTENT_OFFSET

-- Build the tab rail and the framed content column at a position in the parent.
-- The owner keeps tabRail and rail; content is added to owner.rail
function SidebarFrame.Create(owner, parent, height, x, y, onSelect)
    owner.tabRail = SidebarTabRail.new(parent, {
        x = x,
        y = y,
        height = height,
        onSelect = onSelect,
    })
    owner.rail = ui.Layer.new(parent)
    owner.rail:SetPos(x + CONTENT_OFFSET, y)
    owner.rail:SetSize(Config.TAG_RAIL_WIDTH - 8, height)
    owner.rail.clickthrough = false
    prettyui.Tooltip.registerContext(owner.rail, parent, function(target)
        return Geometry.relativePosition(target, parent)
    end)
    -- Keep the native tile in the rail's ordinary sibling stack. Giving the
    -- background an explicit category causes it to render above PrettyUI's
    -- default-category search field and list regardless of creation
    -- order
    owner.railBackground = ui.Sprite.new(owner.rail)
    owner.railBackground:SetSize(Config.TAG_RAIL_WIDTH - 8, height)
    owner.railBackground.spriteID = NativeUi.SPRITES.PANEL_BACKGROUND
    owner.railBackground.isTiling = true
    owner.railBackground.clickthrough = true

    owner.railFrame = {
        ui.Rectangle.new(owner.rail),
        ui.Rectangle.new(owner.rail),
        ui.Rectangle.new(owner.rail),
        ui.Rectangle.new(owner.rail),
    }
    owner.railFrame[1]:SetPos(0, 0)
    owner.railFrame[1]:SetSize(0, 1, 1.0, 0)
    owner.railFrame[2]:SetPos(0, height - 1)
    owner.railFrame[2]:SetSize(0, 1, 1.0, 0)
    owner.railFrame[3]:SetPos(0, 0)
    owner.railFrame[3]:SetSize(1, height)
    owner.railFrame[4]:SetPos(-1, 0, 1.0, 0)
    owner.railFrame[4]:SetSize(1, height)
    for _, edge in ipairs(owner.railFrame) do
        edge.fill = true
        edge.rgba = Theme.FRAME
        edge.clickthrough = true
    end
end

-- Keep the frame's edges above content added after it
function SidebarFrame.RaiseEdges(owner)
    for _, edge in ipairs(owner.railFrame or {}) do edge:MoveToFront() end
end

-- Show the tabs with one active
function SidebarFrame.ShowTabs(owner, tabs, activeID)
    if owner.tabRail ~= nil then owner.tabRail:SetTabs(tabs, activeID) end
end

-- Remove the tab rail and the content column with everything inside it
function SidebarFrame.Destroy(owner)
    if owner.tabRail ~= nil then owner.tabRail:Destroy() end
    if owner.rail ~= nil then prettyui.Tooltip.unregisterContext(owner.rail) end
    if owner.rail ~= nil then pcall(function() owner.rail:Destroy() end) end
    owner.tabRail = nil
    owner.rail = nil
    owner.railBackground = nil
    owner.railFrame = nil
end

return SidebarFrame
