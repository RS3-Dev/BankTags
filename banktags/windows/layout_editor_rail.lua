-- Draw the layout editor's edge rail: one icon button per tag
-- Tags follow the Tags tab's order; arrows page through more than fit

local BankControls = require("banktags/ui/bank_controls")
local Geometry = require("banktags/ui/geometry")
local Text = require("banktags/core/text")
local Theme = require("banktags/ui/theme")

local TagRail = {}
TagRail.__index = TagRail

-- Sized like Bank Core's sidebar tab rail
local TAB_SIZE = 32
local TAB_GAP = 4
local TAB_STEP = TAB_SIZE + TAB_GAP
local ICON_SIZE = 24
local ICON_INSET = (TAB_SIZE - ICON_SIZE) // 2
local ARROW_HEIGHT = 20
local ARROW_ICON_SIZE = 16
local BACKDROP_SPRITE = 18035 -- RS3_CHILD_CONTENT_TILE
TagRail.WIDTH = TAB_SIZE

-- List every tag in the Tags tab's order, folder members under their folder's name
function TagRail.Entries(store)
    local entries = {}
    -- Append one tag, named after its folder when it has one
    local function add(tag, folderName)
        local label = Text.titleCase(tag)
        if folderName ~= nil then label = folderName .. " / " .. label end
        entries[#entries + 1] = { id = tag, label = label, objectID = store:GetTagSprite(tag) }
    end
    for _, node in ipairs(store:TagTree()) do
        if node.kind == "tag" then
            add(node.tag, nil)
        else
            for _, tag in ipairs(node.tags) do add(tag, node.name) end
        end
    end
    return entries
end

-- Choose which tabs show, keeping the open tag in view if asked
-- Returns the first index, count, first position, and whether arrows show
function TagRail.Layout(count, activeIndex, first, height)
    local fit = (height + TAB_GAP) // TAB_STEP
    if count <= fit then
        return { first = 1, shown = count, top = 0, arrows = false }
    end
    local arrowSpace = ARROW_HEIGHT + TAB_GAP
    local slots = math.max(1, (height - arrowSpace * 2 + TAB_GAP) // TAB_STEP)
    first = math.max(1, math.min(first or 1, count - slots + 1))
    if activeIndex ~= nil then
        if activeIndex < first then first = activeIndex end
        if activeIndex > first + slots - 1 then first = activeIndex - slots + 1 end
    end
    return { first = first, shown = slots, top = arrowSpace, arrows = true }
end

-- Create an empty rail on a tiled backdrop
function TagRail.new(parent, options)
    local self = setmetatable({
        height = options.height,
        onSelect = options.onSelect,
        entries = {},
        activeID = nil,
        first = 1,
        controls = {},
    }, TagRail)
    self.root = ui.Layer.new(parent)
    self.root:SetPos(options.x, options.y)
    self.root:SetSize(TAB_SIZE, self.height)
    self.root.clickthrough = true
    -- Draw tooltips in the editor rather than clipped to the rail
    prettyui.Tooltip.registerContext(self.root, parent, function(target)
        return Geometry.relativePosition(target, parent)
    end)
    self.background = ui.Sprite.new(self.root)
    self.background:SetSize(TAB_SIZE, self.height)
    self.background.spriteID = BACKDROP_SPRITE
    self.background.isTiling = true
    self.background.clickthrough = true
    return self
end

-- Show these tags with one open, keeping it in view
function TagRail:SetTags(entries, activeID)
    local activeIndex = nil
    for index, entry in ipairs(entries) do
        if entry.id == activeID then activeIndex = index end
    end
    self.entries = entries
    self.activeID = activeID
    self.view = TagRail.Layout(#entries, activeIndex, self.first, self.height)
    self.first = self.view.first
    self:Draw()
end

-- Page the shown tags up or down without changing the open tag
function TagRail:Scroll(offset)
    if not self.view.arrows then return false end
    local view = TagRail.Layout(#self.entries, nil, self.first + offset, self.height)
    if view.first == self.first then return false end
    self.view = view
    self.first = view.first
    self:Draw()
    return true
end

-- Destroy the drawn tabs, icons, frame, and arrows
function TagRail:Clear()
    for index = #self.controls, 1, -1 do
        pcall(function() self.controls[index]:Destroy() end)
    end
    self.controls = {}
    self.buttons = {}
    self.upArrow = nil
    self.downArrow = nil
end

-- Build the shown tabs, the open tag's frame, and the paging arrows
function TagRail:Draw()
    self:Clear()
    local view = self.view
    for slot = 1, view.shown do
        local entry = self.entries[view.first + slot - 1]
        local y = view.top + (slot - 1) * TAB_STEP
        local active = entry.id == self.activeID
        -- A tag without an icon shows its first letters, as the Tags tab shows only its name
        local initials = entry.objectID == nil and Text.titleCase(entry.id):sub(1, 2) or nil
        local button = BankControls.button(self.root, initials, function()
            if self.onSelect ~= nil then self.onSelect(entry.id) end
        end, {
            x = 0, y = y, size = TAB_SIZE,
            tooltip = entry.label,
            active = active,
        })
        button.tagID = entry.id
        self.buttons[#self.buttons + 1] = button
        self.controls[#self.controls + 1] = button
        if entry.objectID ~= nil then self:AddIcon(entry.objectID, y) end
        if active then self:AddSelectionFrame(y) end
    end
    if view.arrows then self:DrawArrows() end
end

-- Show a tag's item icon over its tab
function TagRail:AddIcon(objectID, y)
    local icon = ui.Sprite.new(self.root)
    icon:SetPos(ICON_INSET, y + ICON_INSET)
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    icon:SetAssociatedObject(objectID)
    icon.associatedObjectQuantityMode = ui.ObjectQuantityDisplayMode.NEVER
    icon.clickthrough = true
    self.controls[#self.controls + 1] = icon
end

-- Outline the open tag with the native gold frame
function TagRail:AddSelectionFrame(y)
    local frame = ui.Rectangle.new(self.root)
    frame:SetPos(0, y)
    frame:SetSize(TAB_SIZE, TAB_SIZE)
    frame.fill = false
    frame.outlineThickness = 1
    frame.rgba = Theme.SELECTED_BORDER
    frame.clickthrough = true
    frame:MoveToFront()
    self.controls[#self.controls + 1] = frame
end

-- Build the paging arrows above and below the tabs
function TagRail:DrawArrows()
    local view = self.view
    -- Return an arrow that pages the tabs one step
    local function arrow(y, spriteName, tooltip, offset, disabled)
        local button = BankControls.button(self.root, nil, function() self:Scroll(offset) end, {
            x = 0, y = y, width = TAB_SIZE, height = ARROW_HEIGHT,
            iconSize = ARROW_ICON_SIZE,
            spriteName = spriteName,
            tooltip = tooltip,
            disabled = disabled,
        })
        self.controls[#self.controls + 1] = button
        return button
    end
    self.upArrow = arrow(0, "ARROW_UP", "More tags above", -1, view.first == 1)
    self.downArrow = arrow(self.height - ARROW_HEIGHT, "ARROW_DOWN",
        "More tags below", 1, view.first + view.shown - 1 >= #self.entries)
end

-- Remove the rail and everything drawn on it
function TagRail:Destroy()
    self:Clear()
    prettyui.Tooltip.unregisterContext(self.root)
    pcall(function() self.root:Destroy() end)
    self.root = nil
    self.background = nil
    self.onSelect = nil
end

return TagRail
