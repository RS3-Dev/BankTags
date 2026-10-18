-- Drag items, catalog results, and labels around the layout editor

local BankGrid = require("lib/engine/bank_grid")
local Geometry = require("lib/ui/geometry")
local Theme = require("lib/ui/theme")
local Parts = require("lib/features/tags/layout_editor_parts")
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

-- Return an expanded drag-capture surface to its normal panel bounds
function LayoutEditorDrag:RestoreDragSurface(surface, kind)
    if surface == nil then return end
    if kind == "center" then
        surface:SetPos(Size.CENTER_X + Size.CENTER_VIEW_X, Size.PANEL_TOP + Size.CENTER_VIEW_Y)
        surface:SetSize(Size.CENTER_VIEW_WIDTH - Size.SCROLLBAR_RESERVE, Size.CENTER_VIEW_HEIGHT)
    elseif kind == "search" then
        surface:SetPos(Size.RIGHT_X + 8, Size.PANEL_TOP + Size.SEARCH_LIST_TOP)
        surface:SetSize(Size.RIGHT_WIDTH - 16 - Size.SCROLLBAR_RESERVE,
            Size.PANEL_HEIGHT - Size.SEARCH_LIST_TOP - Size.SEARCH_LIST_BOTTOM)
    elseif kind == "label" then
        surface:SetPos(Size.CENTER_X + Size.LABEL_BUTTON_X, Size.PANEL_TOP + Size.FOOTER_Y)
        surface:SetSize(Size.LABEL_BUTTON_WIDTH, Size.FOOTER_HEIGHT)
    end
    surface:MoveToFront()
end

-- Expand the active input surface so a drag continues across editor panels
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

-- Resolve a center-panel pointer to an editable layout slot
function LayoutEditorDrag:CenterSurfaceSlot(x, y)
    return self:SlotIndexAt(tonumber(x), tonumber(y))
end

-- Resolve a search-panel pointer to a catalog result row
function LayoutEditorDrag:SearchSurfaceResult(y)
    y = tonumber(y)
    if y == nil then return nil end
    local contentY = y + (tonumber(self.searchList and self.searchList.scrollY) or 0)
    local index = math.floor(contentY / 32) + 1
    return self.searchResults[index]
end

-- Route one input surface's press, drag, and release into the editor's gesture
function LayoutEditorDrag:BindDragSurface(surface, onPress, onScroll)
    surface:Subscribe(ui.Hook.ONCLICK, function(_, x, y)
        if self.drag ~= nil then return false end
        return onPress(x, y)
    end)
    -- Update the active drag only while this surface owns the gesture
    local function continueDrag()
        if self.drag == nil or self.drag.sourceSurface ~= surface then return false end
        return self:UpdateDragFromMouse()
    end
    surface:Subscribe(ui.Hook.ONHOLD, continueDrag)
    surface:Subscribe(ui.Hook.ONDRAG, continueDrag)
    -- Commit the drop and restore the normal input surface
    local function release()
        if self.drag == nil or self.drag.sourceSurface ~= surface then return false end
        return self:CommitDragFromMouse()
    end
    surface:Subscribe(ui.Hook.ONRELEASE, release)
    surface:Subscribe(ui.Hook.ONDRAGCOMPLETE, release)
    if onScroll ~= nil then surface:Subscribe(ui.Hook.ONSCROLLWHEEL, onScroll) end
end

-- Create one input surface at its panel bounds
function LayoutEditorDrag:CreateDragSurface(kind)
    local surface = ui.Layer.new(self.content)
    surface.clickthrough = false
    self:RestoreDragSurface(surface, kind)
    return surface
end

-- Bind persistent input surfaces for moving layout entries and adding catalog results
function LayoutEditorDrag:CreateDragSurfaces()
    self.centerDragSurface = self:CreateDragSurface("center")
    self:BindDragSurface(self.centerDragSurface, function(x, y)
        -- Label rows sit beneath this surface, so pressing one starts a label drag
        local labelRow = self:LabelRowAt(x, y)
        if labelRow ~= nil then
            return self:BeginLabelDrag(labelRow, self.centerDragSurface, "center", x, y)
        end
        local index = self:CenterSurfaceSlot(x, y)
        return self:BeginCenterDrag(index, self.centerDragSurface, x, y)
    end, function(component, delta)
        return self.centerView._onScrollWheel(component, delta)
    end)

    self.searchDragSurface = self:CreateDragSurface("search")
    self:BindDragSurface(self.searchDragSurface, function(_, y)
        return self:BeginSearchDrag(
            self:SearchSurfaceResult(y), self.searchDragSurface
        )
    end, function(component, delta)
        return self.searchList:_OnScrollWheel(component, delta)
    end)

    self.labelDragSurface = self:CreateDragSurface("label")
    self:BindDragSurface(self.labelDragSurface, function(x, y)
        return self:BeginLabelDrag(nil, self.labelDragSurface, "label", x, y)
    end)
end

-- Create a non-interactive item sprite that follows the editor drag
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

-- Convert the screen pointer into coordinates within the editor content
function LayoutEditorDrag:ContentPointer()
    local pointerX, pointerY = interfaceMousePosition()
    local context = self.window ~= nil and self.window.tooltipContext or nil
    if pointerX == nil or context == nil or context.position == nil then
        return nil, nil
    end
    local originX, originY = context.position({ x = 0, y = 0 })
    return pointerX - originX, pointerY - originY
end

-- Move the current drag from the host's latest mouse position
function LayoutEditorDrag:UpdateDragFromMouse()
    local x, y = self:ContentPointer()
    if x == nil then return false end
    return self:UpdateDragAt(x, y)
end

-- Commit the current drop using the host's latest mouse position
function LayoutEditorDrag:CommitDragFromMouse()
    local x, y = self:ContentPointer()
    local drag = self.drag
    if x == nil and drag ~= nil then
        x, y = drag.pointerX, drag.pointerY
    end
    return self:CommitDragAt(x, y)
end

-- Remember the selected layout entry and begin moving its ghost sprite
function LayoutEditorDrag:BeginCenterDrag(index, hit, x, y)
    local slot = index ~= nil and self.centerSlots[index] or nil
    if type(slot) ~= "table" or slot.kind ~= "item" then
        self.selectedLayoutKey = nil
        self:RefreshCenter()
        return false
    end
    self.selectedLayoutKey = slot.layoutKey
    local pointX, pointY = self:ContentPointer()
    if pointX == nil then
        pointX, pointY = relativePosition(hit, self.content)
        if pointX == nil then return false end
        pointX = pointX + (tonumber(x) or Size.GRID_SLOT_SIZE / 2)
        pointY = pointY + (tonumber(y) or Size.GRID_SLOT_SIZE / 2)
            - (tonumber(self.centerView.scrollY) or 0)
    end
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
        sourceSurfaceKind = "center",
    }
    self:CaptureDragSurface(hit, "center")
    return false
end

-- Preserve a changed drop position while leaving ordinary click-release selection inert
function LayoutEditorDrag:FinishCenterDrag(x, y)
    if self.drag == nil or self.drag.kind ~= "layout" then return false end
    local drag = self.drag
    local destination = self:DestinationFromContentPoint(x, y)
    self.drag = nil
    if drag.ghost ~= nil then pcall(function() drag.ghost:Destroy() end) end
    self:RestoreDragSurface(drag.sourceSurface, drag.sourceSurfaceKind)
    if destination ~= nil then
        local saved, reason, changed = self.store:MoveLayoutItem(
            self.selectedTag, drag.layoutKey, destination, Size.CENTER_COLUMNS)
        self:RefreshCenter()
        if not saved then
            self:ShowError(reason or "Could not save the layout position.")
        elseif changed then
            self:NotifyChanged()
        end
    else
        self:RefreshCenter()
    end
    return false
end

-- Convert a result-row pointer into editor content coordinates
function LayoutEditorDrag:SearchPointer(hit, x, y)
    local originX, originY = relativePosition(hit, self.content)
    if originX == nil then return nil, nil end
    return originX + (tonumber(x) or 0),
        originY + (tonumber(y) or 0)
            - (tonumber(self.searchList and self.searchList.scrollY) or 0)
end

-- Remember a catalog result and begin dragging it into the editable layout
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

-- Move the ghost and highlight the current destination within the layout grid
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
    end
    self.drag.ghost:MoveToFront()
    return false
end

-- Find the grid row under an editor-content pointer
function LayoutEditorDrag:RowFromContentPoint(x, y)
    x, y = tonumber(x), tonumber(y)
    if x == nil or y == nil then return nil end
    local viewX = Size.CENTER_X + Size.CENTER_VIEW_X
    local viewY = Size.PANEL_TOP + Size.CENTER_VIEW_Y
    if x < viewX or x >= viewX + Size.CENTER_VIEW_WIDTH
        or y < viewY or y >= viewY + Size.CENTER_VIEW_HEIGHT then return nil end
    return self:RowAt(x - viewX, y - viewY)
end

-- Shade the whole row a dragged label would claim
function LayoutEditorDrag:ShowLabelDropRow(row)
    if self.drag == nil then return end
    if row == nil then
        if self.drag.highlight ~= nil then self.drag.highlight.hidden = true end
        return
    end
    local width = Size.CENTER_COLUMNS * Size.GRID_STEP - (Size.GRID_STEP - Size.GRID_SLOT_SIZE)
    if self.drag.highlight == nil then
        self.drag.highlight = rectangle(self.centerView.content, Size.GRID_LEFT, 0,
            width, Size.GRID_SLOT_SIZE, LABEL_DROP_COLOUR, true)
    end
    self.drag.highlight:SetPos(Size.GRID_LEFT, BankGrid.RowItemY(row))
    self.drag.highlight.hidden = false
    self.drag.highlight:MoveToFront()
end

-- Create a heading-styled ghost that follows a label drag
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

-- Begin dragging an existing label row, or a new label from the right panel
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
    -- A press on New label may only be a click, so its ghost waits for a drag
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

-- Report whether an editor-content point is over the New label button
function LayoutEditorDrag:OnLabelButton(x, y)
    x, y = tonumber(x), tonumber(y)
    if x == nil or y == nil then return false end
    local left, top = Size.CENTER_X + Size.LABEL_BUTTON_X, Size.PANEL_TOP + Size.FOOTER_Y
    return x >= left and x < left + Size.LABEL_BUTTON_WIDTH
        and y >= top and y < top + Size.FOOTER_HEIGHT
end

-- Choose where a clicked New label goes: above the selected item's row, or
-- after the arranged items when nothing is selected
function LayoutEditorDrag:DefaultLabelRow()
    for index, slot in ipairs(self.centerSlots) do
        if type(slot) == "table" and slot.kind == "item" and not slot.unarranged
            and slot.layoutKey == self.selectedLayoutKey then
            return math.floor((index - 1) / Size.CENTER_COLUMNS)
        end
    end
    -- The store clamps rows past the layout to the first row after it
    return math.maxinteger
end

-- Drop a label: a new one asks for its text, a moved one saves its new row,
-- and releasing a label where it started opens it for renaming
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

-- Find a valid layout slot under an editor-content pointer
function LayoutEditorDrag:DestinationFromContentPoint(x, y)
    local viewX = Size.CENTER_X + Size.CENTER_VIEW_X
    local viewY = Size.PANEL_TOP + Size.CENTER_VIEW_Y
    if x < viewX or x >= viewX + Size.CENTER_VIEW_WIDTH
        or y < viewY or y >= viewY + Size.CENTER_VIEW_HEIGHT then return nil end
    return self:SlotIndexAt(x - viewX, y - viewY)
end

-- Add the dragged catalog item only when released onto a valid layout slot
function LayoutEditorDrag:FinishSearchDrag(x, y)
    if self.drag == nil or self.drag.kind ~= "search" then return false end
    local drag = self.drag
    local destination = self:DestinationFromContentPoint(x, y)
    self.drag = nil
    if drag.ghost ~= nil then pcall(function() drag.ghost:Destroy() end) end
    self:RestoreDragSurface(drag.sourceSurface, drag.sourceSurfaceKind)
    if destination ~= nil then self:AddCatalogResult(drag.result, destination) end
    return false
end

-- Finish the active drag according to whether its source is the layout or catalog
function LayoutEditorDrag:CommitDragAt(x, y)
    local drag = self.drag
    local kind = drag ~= nil and drag.kind or nil
    x = tonumber(x) or (drag ~= nil and drag.pointerX or nil)
    y = tonumber(y) or (drag ~= nil and drag.pointerY or nil)
    if x == nil or y == nil then return self:FinishDrag(false) end
    if kind == "layout" then return self:FinishCenterDrag(x, y) end
    if kind == "search" then return self:FinishSearchDrag(x, y) end
    if kind == "label" then return self:FinishLabelDrag(x, y) end
    return false
end

-- Commit or cancel the active gesture according to its source panel
function LayoutEditorDrag:FinishDrag(commit)
    local drag = self.drag
    self.drag = nil
    if drag ~= nil and drag.ghost ~= nil then
        pcall(function() drag.ghost:Destroy() end)
    end
    if drag ~= nil and drag.highlight ~= nil then
        pcall(function() drag.highlight:Destroy() end)
    end
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
