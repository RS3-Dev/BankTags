-- Choose tags with native bank tabs and overflow arrows

local BankControls = require("resources/ui/bank_controls")
local Geometry = require("resources/ui/geometry")
local Parts = require("resources/windows/layout_editor_parts")
local Theme = require("resources/ui/theme")

local Tabs = {}
Tabs.__index = Tabs

local WIDTH, HEIGHT, ICON, GAP = 48, 38, 22, 2
local STEP, ARROW = WIDTH + GAP, 24

-- Keep tab tooltips outside their clipping area
local function tooltipContext(collection, parent)
    -- Place tab tooltips relative to the editor
    prettyui.Tooltip.registerContext(collection, parent, function(target)
        local x, y = Geometry.absolutePosition(target)
        local parentX, parentY = Geometry.absolutePosition(parent)
        return x - parentX, y - parentY
    end)
end

-- Create the editor's scrolling tag tabs
function Tabs.new(parent, options)
    local self = setmetatable({ options = options, entries = {}, byID = {}, rows = {}, first = 1 }, Tabs)
    self.root = Parts.layer(parent, options.x, options.y, options.width, HEIGHT)
    tooltipContext(self.root, parent)
    self.left = BankControls.button(self.root, "", function() self:Scroll(-1) end, {
        x = 0, y = 0, width = ARROW, height = HEIGHT, iconSize = 16,
        spriteName = "ARROW_LEFT", tooltip = "Previous tags",
    })
    self.right = BankControls.button(self.root, "", function() self:Scroll(1) end, {
        x = options.width - ARROW, y = 0, width = ARROW, height = HEIGHT, iconSize = 16,
        spriteName = "ARROW_RIGHT", tooltip = "Next tags",
    })
    self.root:Subscribe(ui.Hook.ONSCROLLWHEEL, function(_, delta) return self:Scroll(delta) end)
    self:Draw()
    return self
end

-- Release the drawn tabs and their tooltips
function Tabs:ClearRows()
    for _, row in ipairs(self.rows) do
        prettyui.Tooltip.unbind(row)
        prettyui.Tooltip.unregisterContext(row.root)
        row.root:Destroy()
    end
    self.rows = {}
end

-- Show each tab's selected or hovered appearance
function Tabs:ShowSelection()
    for _, row in ipairs(self.rows) do
        row.background.spriteID = row.entry.id == self.selectedID and id.Sprite.BANK_TABS_HORIZONTAL_1
            or (row.hovered and id.Sprite.BANK_TABS_HORIZONTAL_2 or id.Sprite.BANK_TABS_HORIZONTAL_0)
    end
end

-- Draw visible tabs and any overflow arrows
function Tabs:Draw()
    self:ClearRows()
    local full = math.max(1, (self.options.width + GAP) // STEP)
    local paging = #self.entries > full
    local inset = paging and ARROW + GAP or 0
    self.capacity = paging and math.max(1, (self.options.width - 2 * inset + GAP) // STEP) or full
    self.first = math.max(1, math.min(self.first, #self.entries - self.capacity + 1))
    self.left.hidden, self.right.hidden = not paging, not paging
    self.left:SetDisabled(self.first == 1)
    self.right:SetDisabled(self.first + self.capacity > #self.entries)
    for index = self.first, math.min(#self.entries, self.first + self.capacity - 1) do
        local entry = self.entries[index]
        local root = Parts.layer(self.root, inset + (index - self.first) * STEP, 0, WIDTH, HEIGHT)
        tooltipContext(root, self.root.parent)
        root.clickthrough = false
        local background = ui.Sprite.new(root)
        background:SetSize(WIDTH, HEIGHT)
        background.clickthrough = true
        local row = { entry = entry, root = root, background = background }
        if entry.objectID ~= nil then
            row.icon = ui.Sprite.new(root)
            row.icon:SetPos((WIDTH - ICON) // 2, (HEIGHT - ICON) // 2)
            row.icon:SetSize(ICON, ICON)
            row.icon:SetAssociatedObject(entry.objectID)
            row.icon.outlineWidth = 1
            row.icon.associatedObjectQuantityMode = ui.ObjectQuantityDisplayMode.NEVER
            row.icon.clickthrough = true
        else
            local initial = entry.label:match("^.[\128-\191]*") or ""
            row.label = prettyui.Text.new(root, {
                text = initial, width = WIDTH, height = HEIGHT, colour = Theme.HEADING_TEXT,
                font = id.Font.MUSEO_SANS_15PT_REGULAR, alignHorizontal = ui.AlignMode.CENTRE,
                alignVertical = ui.AlignMode.CENTRE, maxLines = 1,
            })
            row.label.clickthrough = true
        end
        root:Subscribe(ui.Hook.ONCLICK, function() self:Select(entry.id, true); return false end)
        -- Show the tab's hovered appearance
        root:Subscribe(ui.Hook.ONMOUSEOVER, function()
            row.hovered = true; self:ShowSelection(); return true
        end)
        -- Restore the tab after the pointer leaves
        root:Subscribe(ui.Hook.ONMOUSELEAVE, function()
            row.hovered = false; self:ShowSelection(); return true
        end)
        root:Subscribe(ui.Hook.ONSCROLLWHEEL, function(_, delta) return self:Scroll(delta) end)
        prettyui.Tooltip.bind(row, root, root, entry.label)
        self.rows[#self.rows + 1] = row
    end
    self:ShowSelection()
end

-- Scroll until the selected tag is visible
function Tabs:RevealSelected()
    for index, entry in ipairs(self.entries) do
        if entry.id == self.selectedID then
            local first = self.first
            if index < first then first = index end
            if index >= first + self.capacity then first = index - self.capacity + 1 end
            if first ~= self.first then self.first = first; self:Draw() end
            return
        end
    end
end

-- Replace tag tabs and reveal the selection
function Tabs:SetEntries(entries, selectedID)
    self.entries, self.byID = entries, {}
    for _, entry in ipairs(entries) do self.byID[entry.id] = entry end
    self.selectedID = selectedID
    self:Draw()
    self:RevealSelected()
end

-- Select a tag and optionally notify the editor
function Tabs:Select(entryID, notify)
    if self.byID[entryID] == nil then return false end
    self.selectedID = entryID
    self:RevealSelected()
    self:ShowSelection()
    if notify then self.options.onChange(self, entryID) end
    return true
end

-- Scroll the tabs without changing the selected tag
function Tabs:Scroll(delta)
    local first = math.max(1, math.min(self.first + delta, #self.entries - self.capacity + 1))
    if first == self.first then return true end
    self.first = first
    self:Draw()
    return false
end

-- Read the selected tag's name
function Tabs:GetSelectedID() return self.selectedID end

-- Release the tab strip and its arrows
function Tabs:Destroy()
    if self.root == nil then return end
    self:ClearRows()
    self.left:Destroy()
    self.right:Destroy()
    prettyui.Tooltip.unregisterContext(self.root)
    self.root:Destroy()
    self.root, self.entries, self.byID = nil, {}, {}
end

return Tabs
