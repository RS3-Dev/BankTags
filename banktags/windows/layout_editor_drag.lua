-- Drag items, catalog results, and labels around the layout editor

local BankGrid = require("banktags/ui/bank_grid")
local Geometry = require("banktags/ui/geometry")
local Theme = require("banktags/ui/theme")
local Parts = require("banktags/windows/layout_editor_parts")
local Size = Parts.size
local rectangle = Parts.rectangle
local relativePosition = Geometry.relativePosition
local interfaceMousePosition = Geometry.interfaceMousePosition

local VIEW_BACKGROUND = Theme.VIEW_BACKGROUND
local LABEL_TEXT_COLOUR = Theme.HEADING_TEXT
local LABEL_LINE_COLOUR = Theme.HEADING_LINE
-- A translucent gold wash over the row a dragged label would take
local LABEL_DROP_COLOUR = 0xD2A84D40

local LayoutEditorDrag = {}

-- Shrink a drag surface back over its own panel
function LayoutEditorDrag:RestoreDragSurface(surface, kind)
    if surface == nil then return end
    local pane = self.panes ~= nil and self.panes[kind] or nil
    local rightX = Size.RIGHT_X + Size.VIEW_INSET
    if pane ~= nil then
        surface:SetPos(pane.x, pane.y)
        surface:SetSize(pane.width - Size.SCROLLBAR_RESERVE, pane.height)
    elseif kind == "search" then
        surface:SetPos(rightX, Size.PANEL_TOP + Size.SEARCH_LIST_TOP)
        surface:SetSize(Size.RIGHT_VIEW_WIDTH - Size.SCROLLBAR_RESERVE, Size.SEARCH_LIST_HEIGHT)
    elseif kind == "label" then
        surface:SetPos(Size.LABEL_BUTTON_X, Size.LABEL_BUTTON_Y)
        surface:SetSize(Size.LABEL_BUTTON_WIDTH, Size.BUTTON_HEIGHT)
    end
    surface:MoveToFront()
end

-- Stretch a drag surface over the editor so drags can cross panels
function LayoutEditorDrag:CaptureDragSurface(surface, kind)
    if surface == nil then return false end
    self:RestoreDragSurface(surface, kind)
    surface:SetPos(0, 0)
    surface:SetSize(
        tonumber(self.content.width) or Size.WIDTH,
        tonumber(self.content.height) or Size.HEIGHT
    )
    surface:MoveToFront()
    if self.drag ~= nil and self.drag.ghost ~= nil then
        self.drag.ghost:MoveToFront()
    end
    return true
end

-- Find the search result under a search-panel point
function LayoutEditorDrag:SearchSurfaceResult(y)
    y = tonumber(y)
    if y == nil then return nil end
    local contentY = y + (tonumber(self.searchList and self.searchList.scrollY) or 0)
    local index = math.floor(contentY / 32) + 1
    return self.searchResults[index]
end

-- Check whether an editor content point is over the shown search results
function LayoutEditorDrag:OnSearchList(x, y)
    x, y = tonumber(x), tonumber(y)
    if x == nil or y == nil or self.rightTab ~= "search" then return false end
    local left, top = Size.RIGHT_X + Size.VIEW_INSET, Size.PANEL_TOP + Size.SEARCH_LIST_TOP
    return x >= left and x < left + Size.RIGHT_VIEW_WIDTH
        and y >= top and y < top + Size.SEARCH_LIST_HEIGHT
end

-- Scroll the list a surface covers, or during a drag the one under the pointer
-- A drag stretches its surface over the editor, so it hears every wheel turn
function LayoutEditorDrag:ScrollWheel(component, delta, kind)
    if self.drag ~= nil then
        local x, y = self:ContentPointer()
        local pane = self:PaneAt(x, y)
        kind = pane ~= nil and pane.name or (self:OnSearchList(x, y) and "search" or nil)
    end
    local pane = self.panes ~= nil and self.panes[kind] or nil
    -- A hidden tab never scrolls
    if pane ~= nil and not pane.hidden then return pane.view._onScrollWheel(component, delta) end
    if kind == "search" and self.rightTab == "search" then
        return self.searchList:_OnScrollWheel(component, delta)
    end
    return true
end

-- Pass a surface's press, drag, release, and wheel to the editor
function LayoutEditorDrag:BindDragSurface(surface, kind, onPress)
    surface:Subscribe(ui.Hook.ONCLICK, function(_, x, y)
        if self.drag ~= nil then return false end
        if surface.hidden then return true end
        return onPress(x, y)
    end)
    -- Update the drag only while this surface owns it
    local function continueDrag()
        if self.drag == nil or self.drag.sourceSurface ~= surface then return false end
        return self:UpdateDragFromMouse()
    end
    surface:Subscribe(ui.Hook.ONHOLD, continueDrag)
    surface:Subscribe(ui.Hook.ONDRAG, continueDrag)
    -- Finish the drop and shrink the surface back
    local function release()
        if self.drag == nil or self.drag.sourceSurface ~= surface then return false end
        return self:CommitDragFromMouse()
    end
    surface:Subscribe(ui.Hook.ONRELEASE, release)
    surface:Subscribe(ui.Hook.ONDRAGCOMPLETE, release)
    surface:Subscribe(ui.Hook.ONSCROLLWHEEL, function(component, delta)
        return self:ScrollWheel(component, delta, kind)
    end)
end

-- Create one input surface at its panel bounds
function LayoutEditorDrag:CreateDragSurface(kind)
    local surface = ui.Layer.new(self.content)
    surface.clickthrough = false
    self:RestoreDragSurface(surface, kind)
    return surface
end

-- Bind the surfaces that move entries and add search results
function LayoutEditorDrag:CreateDragSurfaces()
    for _, pane in ipairs({ self.panes.sorted, self.panes.unsorted }) do
        local surface = self:CreateDragSurface(pane.name)
        pane.surface = surface
        self:BindDragSurface(surface, pane.name, function(x, y)
            -- A press here takes focus from any text field
            self.keysOnGrid = true
            -- Label rows sit beneath this surface, so pressing one drags it
            local labelRow = self:LabelRowAt(pane, x, y)
            if labelRow ~= nil then
                return self:BeginLabelDrag(labelRow, surface, pane.name, x, y)
            end
            return self:BeginCenterDrag(pane, self:SlotIndexAt(pane, x, y), surface, x, y)
        end)
    end

    self.searchDragSurface = self:CreateDragSurface("search")
    self:BindDragSurface(self.searchDragSurface, "search", function(_, y)
        return self:BeginSearchDrag(
            self:SearchSurfaceResult(y), self.searchDragSurface
        )
    end)

    self.labelDragSurface = self:CreateDragSurface("label")
    self:BindDragSurface(self.labelDragSurface, "label", function(x, y)
        return self:BeginLabelDrag(nil, self.labelDragSurface, "label", x, y)
    end)
end

-- Create an item sprite that follows the drag
function LayoutEditorDrag:CreateDragGhost(
    objectID, x, y, layoutKey, absentIsPlaceholder
)
    local ghost = ui.Sprite.new(self.content)
    local width, height = self:ApplyRuntimeObjectSprite(
        ghost, objectID, layoutKey, absentIsPlaceholder
    )
    ghost.alpha = 0.88
    ghost:SetPos(
        (tonumber(x) or 0) - math.floor(width / 2),
        (tonumber(y) or 0) - math.floor(height / 2)
    )
    ghost:MoveToFront()
    return ghost, width, height
end

-- Convert the screen pointer to editor content coordinates
function LayoutEditorDrag:ContentPointer()
    local pointerX, pointerY = interfaceMousePosition()
    local context = self.window ~= nil and self.window.tooltipContext or nil
    if pointerX == nil or context == nil or context.position == nil then
        return nil, nil
    end
    local originX, originY = context.position({ x = 0, y = 0 })
    return pointerX - originX, pointerY - originY
end

-- Move the drag to the latest mouse position
function LayoutEditorDrag:UpdateDragFromMouse()
    local x, y = self:ContentPointer()
    if x == nil then return false end
    return self:UpdateDragAt(x, y)
end

-- Commit the drop at the latest mouse position
function LayoutEditorDrag:CommitDragFromMouse()
    local x, y = self:ContentPointer()
    local drag = self.drag
    if x == nil and drag ~= nil then
        x, y = drag.pointerX, drag.pointerY
    end
    return self:CommitDragAt(x, y)
end

-- Start dragging a pane's item or the group it is in
-- Shift-click adds or removes a sorted item; an empty cell clears the selection
function LayoutEditorDrag:BeginCenterDrag(pane, index, hit, x, y)
    local slot = index ~= nil and pane.slots[index] or nil
    local shift = Keyboard.IsShiftDown()
    if type(slot) ~= "table" or slot.kind ~= "item" then
        -- A Shift-click that misses keeps the group being built
        if shift then return false end
        self:SelectOnly(nil)
        self:RefreshCenter()
        return false
    end
    -- Toggling never drags, so a held Shift cannot move the group by accident
    if shift and pane.name == "sorted" then
        self:ToggleGroupItem(slot.layoutKey)
        self:RefreshCenter()
        return false
    end
    local pointX, pointY = self:ContentPointer()
    if pointX == nil then
        -- The surface sits over the view, so its points are unscrolled
        pointX, pointY = relativePosition(hit, self.content)
        if pointX == nil then return false end
        pointX = pointX + (tonumber(x) or Size.GRID_SLOT_SIZE / 2)
        pointY = pointY + (tonumber(y) or Size.GRID_SLOT_SIZE / 2)
    end
    -- Pressing a group item keeps the group so it can be dragged
    if self:GroupCount() > 1 and self.groupKeys[slot.layoutKey] then
        return self:BeginGroupDrag(slot, pane, hit, pointX, pointY)
    end
    self:SelectOnly(slot.layoutKey)
    local ghost, ghostWidth, ghostHeight = self:CreateDragGhost(
        slot.objectID, pointX, pointY, slot.layoutKey, true
    )
    self.drag = {
        kind = "layout",
        objectID = slot.objectID,
        layoutKey = slot.layoutKey,
        pointerX = pointX,
        pointerY = pointY,
        ghost = ghost,
        ghostWidth = ghostWidth,
        ghostHeight = ghostHeight,
        sourceSurface = hit,
        sourceSurfaceKind = pane.name,
    }
    self:CaptureDragSurface(hit, pane.name)
    return false
end

-- Save a moved item, leaving a plain click as selection
-- A sorted cell takes the item; Unsorted takes only a sorted item
function LayoutEditorDrag:FinishCenterDrag(x, y)
    if self.drag == nil or self.drag.kind ~= "layout" then return false end
    local drag = self.drag
    local pane, paneX, paneY = self:PaneAt(x, y)
    self.drag = nil
    if drag.ghost ~= nil then pcall(function() drag.ghost:Destroy() end) end
    self:RestoreDragSurface(drag.sourceSurface, drag.sourceSurfaceKind)
    local saved, reason, changed = true, nil, false
    if pane ~= nil and pane.name == "sorted" then
        local destination = self:SlotIndexAt(pane, paneX, paneY)
        if destination ~= nil then
            saved, reason, changed = self.store:MoveLayoutItem(
                self.selectedTag, drag.layoutKey, destination, Size.CENTER_COLUMNS)
        end
    elseif pane ~= nil and drag.sourceSurfaceKind == "sorted" then
        -- The same as Move to Unsorted
        saved, reason = self.store:UnarrangeLayoutItem(self.selectedTag, drag.layoutKey)
        changed = saved
    end
    self:RefreshCenter()
    if not saved then
        self:ShowError(reason or "Could not save the layout position.")
    elseif changed then
        self:NotifyChanged()
    end
    return false
end

-- Convert a result-row point to editor content coordinates
function LayoutEditorDrag:SearchPointer(hit, x, y)
    local originX, originY = relativePosition(hit, self.content)
    if originX == nil then return nil, nil end
    return originX + (tonumber(x) or 0),
        originY + (tonumber(y) or 0)
            - (tonumber(self.searchList and self.searchList.scrollY) or 0)
end

-- Start dragging a search result into the layout
function LayoutEditorDrag:BeginSearchDrag(result, hit, x, y)
    if result == nil then return false end
    if self.selectedTag == nil then
        self:ShowError("Choose a tag before adding an item.")
        return false
    end
    local pointX, pointY = self:ContentPointer()
    if pointX == nil and hit ~= nil then
        pointX, pointY = self:SearchPointer(hit, x, y)
    end
    if pointX == nil then return false end
    local ghost, ghostWidth, ghostHeight = self:CreateDragGhost(
        result.objectId, pointX, pointY, nil, false
    )
    self.drag = {
        kind = "search",
        result = result,
        pointerX = pointX,
        pointerY = pointY,
        ghost = ghost,
        ghostWidth = ghostWidth,
        ghostHeight = ghostHeight,
        sourceSurface = hit,
        sourceSurfaceKind = "search",
    }
    self:CaptureDragSurface(hit, "search")
    return false
end

-- Move the ghost and highlight its destination
function LayoutEditorDrag:UpdateDragAt(x, y)
    if self.drag == nil then return false end
    self.drag.pointerX = tonumber(x) or self.drag.pointerX
    self.drag.pointerY = tonumber(y) or self.drag.pointerY
    self.drag.ghost:SetPos(
        (tonumber(x) or 0) - math.floor((self.drag.ghostWidth or 36) / 2),
        (tonumber(y) or 0) - math.floor((self.drag.ghostHeight or 32) / 2)
    )
    if self.drag.kind == "label" then
        if self.drag.ghost.hidden and not self:OnLabelButton(x, y) then
            self.drag.ghost.hidden = false
        end
        self:ShowLabelDropRow(self:RowFromContentPoint(x, y))
    elseif self.drag.kind == "group" then
        self:ShowGroupPreview(x, y)
    end
    self.drag.ghost:MoveToFront()
    return false
end

-- Find the sorted grid row under a content point; labels stay out of Unsorted
function LayoutEditorDrag:RowFromContentPoint(x, y)
    local pane, paneX, paneY = self:PaneAt(x, y)
    if pane == nil or pane.name ~= "sorted" then return nil end
    return self:RowAt(pane, paneX, paneY)
end

-- Shade the row a dragged label would take
function LayoutEditorDrag:ShowLabelDropRow(row)
    if self.drag == nil then return end
    if row == nil then
        if self.drag.highlight ~= nil then self.drag.highlight.hidden = true end
        return
    end
    local width = Size.CENTER_COLUMNS * Size.GRID_STEP - (Size.GRID_STEP - Size.GRID_SLOT_SIZE)
    if self.drag.highlight == nil then
        self.drag.highlight = rectangle(self.panes.sorted.view.content, Size.GRID_LEFT, 0,
            width, Size.GRID_SLOT_SIZE, LABEL_DROP_COLOUR, true)
    end
    self.drag.highlight:SetPos(Size.GRID_LEFT, BankGrid.RowItemY(row))
    self.drag.highlight.hidden = false
    self.drag.highlight:MoveToFront()
end

-- Create a heading-styled ghost for a label drag
function LayoutEditorDrag:CreateLabelGhost(text, x, y)
    local ghost = ui.Layer.new(self.content)
    ghost:SetPos(
        (tonumber(x) or 0) - math.floor(Size.LABEL_GHOST_WIDTH / 2),
        (tonumber(y) or 0) - math.floor(Size.LABEL_GHOST_HEIGHT / 2)
    )
    ghost:SetSize(Size.LABEL_GHOST_WIDTH, Size.LABEL_GHOST_HEIGHT)
    ghost.clickthrough = true
    rectangle(ghost, 0, 0, Size.LABEL_GHOST_WIDTH, Size.LABEL_GHOST_HEIGHT, VIEW_BACKGROUND, true)
    prettyui.Text.new(ghost, {
        text = text,
        x = 6, y = 2, width = Size.LABEL_GHOST_WIDTH - 12, height = Size.LABEL_LINE_OFFSET,
        colour = LABEL_TEXT_COLOUR,
        font = id.Font.MUSEO_SANS_11PT_REGULAR,
        maxLines = 1,
    }).clickthrough = true
    rectangle(ghost, 6, 2 + Size.LABEL_LINE_OFFSET, Size.LABEL_GHOST_WIDTH - 12, 1,
        LABEL_LINE_COLOUR, true)
    ghost.alpha = 0.88
    ghost:MoveToFront()
    return ghost
end

-- Start dragging a label row or a new label
function LayoutEditorDrag:BeginLabelDrag(fromRow, hit, kind, x, y)
    if self.selectedTag == nil then
        self:ShowError("Choose a tag before adding a label.")
        return false
    end
    local pointX, pointY = self:ContentPointer()
    if pointX == nil then
        pointX, pointY = relativePosition(hit, self.content)
        if pointX == nil then return false end
        pointX = pointX + (tonumber(x) or 0)
        pointY = pointY + (tonumber(y) or 0)
    end
    local text = fromRow ~= nil and self.store:GetLabel(self.selectedTag, fromRow, Size.CENTER_COLUMNS)
        or "New label"
    local ghost = self:CreateLabelGhost(text, pointX, pointY)
    -- A press on New label may be a click, so the ghost waits
    ghost.hidden = fromRow == nil
    self.drag = {
        kind = "label",
        fromRow = fromRow,
        pointerX = pointX,
        pointerY = pointY,
        ghost = ghost,
        ghostWidth = Size.LABEL_GHOST_WIDTH,
        ghostHeight = Size.LABEL_GHOST_HEIGHT,
        sourceSurface = hit,
        sourceSurfaceKind = kind,
    }
    self:CaptureDragSurface(hit, kind)
    return false
end

-- Check whether a content point is over New label
function LayoutEditorDrag:OnLabelButton(x, y)
    x, y = tonumber(x), tonumber(y)
    if x == nil or y == nil then return false end
    local left, top = Size.LABEL_BUTTON_X, Size.LABEL_BUTTON_Y
    return x >= left and x < left + Size.LABEL_BUTTON_WIDTH
        and y >= top and y < top + Size.BUTTON_HEIGHT
end

-- Pick a new label's row: above the selection, or after the items
function LayoutEditorDrag:DefaultLabelRow()
    for index, slot in ipairs(self.panes.sorted.slots) do
        if type(slot) == "table" and slot.kind == "item"
            and slot.layoutKey == self.selectedLayoutKey then
            return math.floor((index - 1) / Size.CENTER_COLUMNS)
        end
    end
    -- The store clamps rows past the layout to its end
    return math.maxinteger
end

-- Drop a label, asking for text, moving it, or renaming in place
function LayoutEditorDrag:FinishLabelDrag(x, y)
    local drag = self.drag
    if drag == nil or drag.kind ~= "label" then return false end
    local row = self:RowFromContentPoint(x, y)
    self:FinishDrag(false)
    if row == nil and drag.fromRow == nil and self:OnLabelButton(x, y) then
        return self:PromptNewLabel(self:DefaultLabelRow())
    end
    if row == nil then return false end
    if drag.fromRow == nil then return self:PromptNewLabel(row) end
    if row == drag.fromRow then return self:EditLabel(row) end
    local saved, reason, changed = self.store:MoveLabel(
        self.selectedTag, drag.fromRow, row, Size.CENTER_COLUMNS)
    self:RefreshCenter()
    if not saved then
        self:ShowError(reason or "Could not move the label.")
    elseif changed then
        self:NotifyChanged()
    end
    return false
end

-- Add the dragged result at a sorted slot
function LayoutEditorDrag:FinishSearchDrag(x, y)
    if self.drag == nil or self.drag.kind ~= "search" then return false end
    local drag = self.drag
    local pane, paneX, paneY = self:PaneAt(x, y)
    local destination = pane ~= nil and pane.name == "sorted"
        and self:SlotIndexAt(pane, paneX, paneY) or nil
    self.drag = nil
    if drag.ghost ~= nil then pcall(function() drag.ghost:Destroy() end) end
    self:RestoreDragSurface(drag.sourceSurface, drag.sourceSurfaceKind)
    if destination ~= nil then self:AddCatalogResult(drag.result, destination) end
    return false
end

-- Finish a layout or search drag
function LayoutEditorDrag:CommitDragAt(x, y)
    local drag = self.drag
    local kind = drag ~= nil and drag.kind or nil
    x = tonumber(x) or (drag ~= nil and drag.pointerX or nil)
    y = tonumber(y) or (drag ~= nil and drag.pointerY or nil)
    if x == nil or y == nil then return self:FinishDrag(false) end
    if kind == "layout" then return self:FinishCenterDrag(x, y) end
    if kind == "group" then return self:FinishGroupDrag(x, y) end
    if kind == "search" then return self:FinishSearchDrag(x, y) end
    if kind == "label" then return self:FinishLabelDrag(x, y) end
    return false
end

-- Commit or cancel the active drag
function LayoutEditorDrag:FinishDrag(commit)
    local drag = self.drag
    self.drag = nil
    if drag ~= nil and drag.ghost ~= nil then
        pcall(function() drag.ghost:Destroy() end)
    end
    if drag ~= nil and drag.highlight ~= nil then
        pcall(function() drag.highlight:Destroy() end)
    end
    if drag ~= nil and drag.preview ~= nil then self.ClearGroupPreview(drag) end
    if drag ~= nil then
        self:RestoreDragSurface(drag.sourceSurface, drag.sourceSurfaceKind)
    end
    return commit == true
end

-- Attach these methods to LayoutEditorWindow
function LayoutEditorDrag.install(target)
    for name, method in pairs(LayoutEditorDrag) do
        if name ~= "install" then target[name] = method end
    end
end

return LayoutEditorDrag
