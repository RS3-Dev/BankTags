-- Add layout items to the selection with a Shift-drag from empty space

local BankGrid = require("resources/ui/bank_grid")
local Theme = require("resources/ui/theme")
local Parts = require("resources/windows/layout_editor_parts")
local Size = Parts.size
local Marquee = {}

local function copy(keys)
    local result = {}
    for key, value in pairs(keys or {}) do result[key] = value end
    return result
end

-- Store the anchor in scrolling content coordinates, not screen coordinates
function Marquee:BeginBoxSelection(x, y)
    local pane = self.panes.sorted
    local base = copy(self.groupKeys)
    if self.selectedLayoutKey ~= nil and self.layout.sortedIndex[self.selectedLayoutKey] ~= nil then
        base[self.selectedLayoutKey] = true
    end
    local drag = {
        kind = "box", sourceKind = "sorted", base = base,
        selectedBefore = self.selectedLayoutKey, groupBefore = self.groupKeys, pasteBefore = self.pasteCell,
        anchorX = x, anchorY = y + pane.view.scrollY, holdTicks = 0,
        fill = Parts.rectangle(pane.view.content, 0, 0, 1, 1, 0xD2A84D28, true),
        border = Parts.rectangle(pane.view.content, 0, 0, 1, 1, Theme.SELECTED_BORDER, false),
    }
    drag.fill.hidden, drag.border.hidden = true, true
    return self:StartDrag(drag)
end

-- Select item centers inside the box, retaining the selection at the press
function Marquee:UpdateBoxSelection(x, y, scroll)
    local drag, pane = self.drag, self.panes.sorted
    if not Keyboard.IsShiftDown() then self:CancelDrag(); return end
    if not drag.active and math.max(math.abs(x - drag.startX), math.abs(y - drag.startY)) < 4 then return end
    drag.active = true
    if scroll then
        if y < pane.y + 8 then pane.view:ScrollBy(-5)
        elseif y > pane.y + pane.height - 8 then pane.view:ScrollBy(5) end
    end
    local endX = math.max(0, math.min(pane.width - Size.SCROLLBAR_RESERVE, x - pane.x))
    local endY = math.max(0, math.min(pane.height, y - pane.y)) + pane.view.scrollY
    if drag.lastX == endX and drag.lastY == endY then return end
    drag.lastX, drag.lastY = endX, endY
    local left, right = math.min(drag.anchorX, endX), math.max(drag.anchorX, endX)
    local top, bottom = math.min(drag.anchorY, endY), math.max(drag.anchorY, endY)
    local keys = copy(drag.base)
    for key, index in pairs(self.layout.sortedIndex) do
        local centerX = pane.gridLeft + (index - 1) % pane.columns * Size.GRID_STEP + Size.GRID_SLOT_SIZE / 2
        local centerY = BankGrid.RowItemY((index - 1) // pane.columns, pane.labels) + Size.GRID_SLOT_SIZE / 2
        if centerX >= left and centerX <= right and centerY >= top and centerY <= bottom then keys[key] = true end
    end
    self:SelectItems(self:SortedKeys(keys))
    self:ShowSelection()
    for _, part in ipairs({ drag.fill, drag.border }) do
        part:SetPos(left, top)
        part:SetSize(math.max(1, right - left), math.max(1, bottom - top))
        part.hidden = false
        part:MoveToFront()
    end
end

-- Only native holds renew capture; scrolling must not keep a lost release alive
function Marquee:TickBoxSelection()
    local drag = self.drag
    if drag == nil or drag.kind ~= "box" then return end
    if not Keyboard.IsShiftDown() or self.window.root.hidden or self:OverlayShown() or MiniMenu.IsOpen() then
        self:CancelDrag()
        return
    end
    drag.holdTicks = drag.holdTicks + 1
    if drag.holdTicks >= 10 then self:CommitDrag(); return end
    local x, y = self:ContentPointer()
    if x ~= nil then self:UpdateBoxSelection(x, y, true) end
end

return Marquee
