-- Name the items a shown tag page draws with no bank stack beneath them
-- Bank Core's own stacks keep their native tooltips; ghosts and placeholders get a name

local Geometry = require("banktags/ui/geometry")
local ObjectConfig = require("banktags/core/object_config")
local TagPage = require("banktags/tags/tag_page")
local Text = require("banktags/core/text")

local PageItemNames = {}
PageItemNames.__index = PageItemNames

-- A hover area matches the 40px cell Bank Core centers a 36 by 32 item in
local CELL_SIZE = 40
local CELL_INSET_X = 2
local CELL_INSET_Y = 4
local SCROLL_EVENT = "banktags_page_item_names"

-- Create the page's names mount, reading rows, items, and columns from the app
function PageItemNames.new(options)
    local self = setmetatable({
        bankItems = options.bankItems,
        columns = options.columns,
        rows = nil,
        ctx = nil,
        anchor = nil,
        tooltip = nil,
        targets = {},
        shownScroll = nil,
    }, PageItemNames)
    self.callbacks = {
        mount = function(ctx) self:Mount(ctx) end,
        resize = function() self:Refresh() end,
        unmount = function() self:Unmount() end,
    }
    return self
end

-- Remember the rows of the page Bank Core shows next
function PageItemNames:SetRows(rows)
    self.rows = rows
    self:Refresh()
end

-- Prepare the shared tooltip in Bank Core's overlay, then place hover areas
function PageItemNames:Mount(ctx)
    self.ctx = ctx
    local parent, overlay = ctx.parent, ctx.overlay
    -- The parent scrolls with the page, so its children move up by the scroll
    prettyui.Tooltip.registerContext(parent, overlay, function(target)
        local x, y = Geometry.absolutePosition(target)
        local originX, originY = Geometry.absolutePosition(overlay)
        return x - originX, y - originY - (ctx:GetScroll() or 0)
    end)
    -- One tooltip follows whichever area is hovered, so a large tag adds no tooltip per item
    self.anchor = ui.Layer.new(parent)
    self.anchor:SetSize(CELL_SIZE, CELL_SIZE)
    self.tooltip = prettyui.Tooltip.attach(self.anchor, parent, " ")
    self.anchor.clickthrough = true
    self:Refresh()
end

-- Destroy the hover areas
function PageItemNames:DestroyTargets()
    for _, target in ipairs(self.targets) do pcall(function() target:Destroy() end) end
    self.targets = {}
end

-- Place one hover area over each slot with no bank stack
function PageItemNames:Refresh()
    local ctx = self.ctx
    if ctx == nil then return end
    self:HideName()
    self:DestroyTargets()
    local columns = self.columns()
    if self.rows == nil or columns == nil then return end
    local names = {}
    for _, slot in ipairs(TagPage.EmptySlots(self.rows, columns, self.bankItems())) do
        local objectID = slot.objectID
        if names[objectID] == nil then
            names[objectID] = Text.plain(ObjectConfig.DisplayName(objectID))
        end
        local name = names[objectID]
        -- An item the client cannot name keeps no tooltip
        if name ~= "" then
            local target = ui.Layer.new(ctx.parent)
            target:SetPos(slot.x - CELL_INSET_X, slot.y - CELL_INSET_Y)
            target:SetSize(CELL_SIZE, CELL_SIZE)
            target.clickthrough = false
            ctx:BindPageScroll(target)
            target:Subscribe(ui.Hook.ONMOUSEOVER, function()
                self:ShowName(target, name)
                return true
            end)
            target:Subscribe(ui.Hook.ONMOUSELEAVE, function()
                self:HideName()
                return true
            end)
            self.targets[#self.targets + 1] = target
        end
    end
end

-- Show an item's name beside its hover area
function PageItemNames:ShowName(target, name)
    if self.tooltip == nil then return end
    self.anchor:SetPos(target.x, target.y)
    self.tooltip:SetText(name)
    self.tooltip:Show()
    -- Scrolling moves the item away, so the name goes with it
    self.shownScroll = self.ctx:GetScroll()
    Event.Logic.Subscribe(SCROLL_EVENT, function()
        if self.ctx == nil or self.ctx:GetScroll() ~= self.shownScroll then self:HideName() end
    end)
end

-- Hide the shown name and stop watching the scroll
function PageItemNames:HideName()
    if self.shownScroll == nil then return end
    self.shownScroll = nil
    Event.Logic.Unsubscribe(SCROLL_EVENT)
    if self.tooltip ~= nil then self.tooltip:Hide() end
end

-- Let go of the page's controls; Bank Core destroys its layers next
function PageItemNames:Unmount()
    self:HideName()
    self:DestroyTargets()
    if self.tooltip ~= nil then self.tooltip:Destroy() end
    if self.ctx ~= nil then prettyui.Tooltip.unregisterContext(self.ctx.parent) end
    self.ctx, self.anchor, self.tooltip = nil, nil, nil
end

return PageItemNames
