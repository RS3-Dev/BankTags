-- Drag items, catalog results, and labels around the layout editor

local BankGrid = require("resources/ui/bank_grid")
local Theme = require("resources/ui/theme")
local Parts = require("resources/windows/layout_editor_parts")
local Size = Parts.size
local rectangle = Parts.rectangle

-- A translucent gold wash over the row a dragged label would take
local LABEL_DROP_COLOUR = 0xD2A84D40
local GHOST_ALPHA = 0.88

local LayoutEditorDrag = {}

-- Place a surface over its grid or search list
function LayoutEditorDrag:PlaceDragSurface(surface, kind)
    local clip = self.surfaceClips[surface]
    local pane = self.panes[kind]
    if pane ~= nil then
        clip:SetPos(pane.x, pane.y)
        clip:SetSize(pane.width - Size.SCROLLBAR_RESERVE, pane.height)
    else
        clip:SetPos(Size.SEARCH_X + Size.SEARCH_INSET, Size.PANEL_TOP + Size.SEARCH_LIST_TOP)
        clip:SetSize(Size.SEARCH_VIEW_WIDTH - Size.SCROLLBAR_RESERVE, Size.SEARCH_LIST_HEIGHT)
    end
    surface:SetPos(-clip.x, -clip.y)
    clip:MoveToFront()
end

-- Find the search result under a search-panel point
function LayoutEditorDrag:SearchSurfaceResult(y)
    return self.searchResults[(y + self.searchList.scrollY) // Size.SEARCH_ROW_HEIGHT + 1]
end

-- Check whether a content point is over search results
function LayoutEditorDrag:OnSearchList(x, y)
    local left, top = Size.SEARCH_X + Size.SEARCH_INSET, Size.PANEL_TOP + Size.SEARCH_LIST_TOP
    return x >= left and x < left + Size.SEARCH_VIEW_WIDTH - Size.SCROLLBAR_RESERVE
        and y >= top and y < top + Size.SEARCH_LIST_HEIGHT
end

-- Scroll the pane under the pointer during a drag
function LayoutEditorDrag:ScrollWheel(delta, kind)
    if self.drag ~= nil then
        local x, y = self:ContentPointer()
        if x == nil then return true end
        local pane = self:PaneAt(x, y)
        kind = pane ~= nil and pane.name or (self:OnSearchList(x, y) and "search" or nil)
    end
    local pane = self.panes[kind]
    if pane ~= nil and not pane.hidden then
        local before = pane.view.scrollY
        pane.view:ScrollBy(delta * Size.GRID_STEP)
        return pane.view.scrollY == before
    end
    if kind == "search" then
        local list = self.searchList
        local before = list.scrollY
        list:SetScrollPosition(before + delta * Size.SEARCH_ROW_HEIGHT)
        return list.scrollY == before
    end
    return true
end

-- Check whether a surface owns the active drag
function LayoutEditorDrag:OwnsDrag(surface)
    return self.drag ~= nil and self.drag.sourceSurface == surface
end

-- Pass native pointer events to the editor
function LayoutEditorDrag:BindDragSurface(surface, kind, onPress)
    -- Keep the originally pressed surface as the owner
    local function remember(x, y)
        if self.drag ~= nil and self.drag.sourceSurface ~= surface then return false end
        self.pointerSurface, self.pointerX, self.pointerY = surface, x, y
        return true
    end
    -- Follow a native point, moving this surface's drag with it
    local function follow(_, x, y)
        if remember(x, y) and self.drag ~= nil then self:UpdateDragAt(self.pointerX, self.pointerY) end
        return true
    end
    surface:Subscribe(ui.Hook.ONMOUSEOVER, follow)
    surface:Subscribe(ui.Hook.ONMOUSEREPEAT, follow)
    -- Follow holds only on the surface owning this drag
    surface:Subscribe(ui.Hook.ONHOLD, function(component, x, y)
        if self:OwnsDrag(surface) then follow(component, x, y) end
        return false
    end)
    -- Forget the hover point when its surface is left
    surface:Subscribe(ui.Hook.ONMOUSELEAVE, function()
        if self.pointerSurface == surface then self.pointerSurface = nil end
        -- Visibility is resolved once on the logic tick, after native hover settles
        return true
    end)
    -- Start a press in the surface's fixed coordinates
    surface:Subscribe(ui.Hook.ONCLICK, function(_, x, y)
        if self.drag ~= nil then return false end
        if surface.hidden then return true end
        remember(x, y)
        local clip = self.surfaceClips[surface]
        return onPress(x - clip.x, y - clip.y)
    end)
    -- ONDRAG supplies the start point; hold and repeat supply current points
    surface:Subscribe(ui.Hook.ONDRAG, function()
        local x, y = self:ContentPointer()
        if self:OwnsDrag(surface) and x ~= nil then self:UpdateDragAt(x, y) end
        return false
    end)
    -- Commit the owning surface's drag at its release point
    surface:Subscribe(ui.Hook.ONRELEASE, function(_, x, y)
        if not self:OwnsDrag(surface) then return false end
        remember(x, y)
        return self:CommitDrag()
    end)
    -- Drop using the latest hover point, not the completion arguments
    surface:Subscribe(ui.Hook.ONDRAGCOMPLETE, function()
        if self:OwnsDrag(surface) then self:CommitDrag() end
        return false
    end)
    -- Pass wheel movement to the appropriate pane
    surface:Subscribe(ui.Hook.ONSCROLLWHEEL, function(_, delta)
        return self:ScrollWheel(delta, kind)
    end)
end

-- Create one input surface over its panel
function LayoutEditorDrag:CreateDragSurface(kind)
    local clip = ui.Layer.new(self.content)
    clip.clickthrough = true
    local surface = ui.Layer.new(clip)
    surface:SetSize(Size.WIDTH, Size.HEIGHT)
    surface.clickthrough = false
    self.surfaceClips[surface] = clip
    self:PlaceDragSurface(surface, kind)
    return surface
end

-- Bind the surfaces that move entries and add search results
function LayoutEditorDrag:CreateDragSurfaces()
    self.surfaceClips = {}
    for _, pane in pairs(self.panes) do
        local surface = self:CreateDragSurface(pane.name)
        pane.surface = surface
        -- Select or drag the item or label pressed here
        self:BindDragSurface(surface, pane.name, function(x, y)
            -- A press here takes focus from any text field
            self.keysOnGrid = true
            -- Label rows sit beneath this surface, so pressing one drags it
            local labelRow = self:LabelRowAt(pane, x, y)
            if labelRow ~= nil then return self:BeginLabelDrag(labelRow) end
            return self:BeginCenterDrag(pane, self:SlotIndexAt(pane, x, y))
        end)
    end
    self.searchDragSurface = self:CreateDragSurface("search")
    -- Begin dragging the search result pressed here
    self:BindDragSurface(self.searchDragSurface, "search", function(_, y)
        return self:BeginSearchDrag(self:SearchSurfaceResult(y))
    end)
end

-- Read the latest pointer position within the editor
function LayoutEditorDrag:ContentPointer()
    local surface = self.pointerSurface
    if surface == nil or surface.hidden or surface.visibleGlobal == false then return nil, nil end
    return self.pointerX, self.pointerY
end

-- Create a hidden ghost at its grab point
function LayoutEditorDrag:CreateDragGhost(width, height)
    local ghost = Parts.layer(self.content, self.pointerX - width // 2, self.pointerY - height // 2, width, height)
    ghost.hidden = true
    return ghost
end

-- Expand its clip without changing the pressed origin
function LayoutEditorDrag:StartDrag(drag, ghost, width, height)
    drag.ghost, drag.ghostWidth, drag.ghostHeight = ghost, width, height
    drag.sourceSurface = self.pointerSurface
    self.drag = drag
    drag.startX, drag.startY = self.pointerX, self.pointerY
    ghost.alpha = GHOST_ALPHA
    ghost:SetPos(self.pointerX - width // 2, self.pointerY - height // 2)
    local surface = drag.sourceSurface
    local clip = self.surfaceClips[surface]
    clip:SetPos(0, 0)
    clip:SetSize(Size.WIDTH, Size.HEIGHT)
    surface:SetPos(0, 0)
    clip:MoveToFront()
    ghost:MoveToFront()
    return false
end

-- Start dragging an item sprite of an object
function LayoutEditorDrag:StartItemDrag(drag, objectID, absentIsPlaceholder)
    local ghost = self:CreateDragGhost(Size.ITEM_WIDTH, Size.ITEM_HEIGHT)
    self:ItemSprite(ghost, objectID, absentIsPlaceholder)
    return self:StartDrag(drag, ghost, Size.ITEM_WIDTH, Size.ITEM_HEIGHT)
end

-- Select an item or begin dragging its group
function LayoutEditorDrag:BeginCenterDrag(pane, index)
    local slot = index ~= nil and pane.slots[index] or nil
    local shift = Keyboard.IsShiftDown()
    if slot == nil or slot.kind ~= "item" then
        -- A Shift-click that misses keeps the group being built
        if shift then return false end
        self:SelectOnly(nil)
        -- An empty sorted cell is where Paste puts copies
        if pane.name == "sorted" then self.pasteCell = index end
        self:ShowSelection()
        return false
    end
    -- Toggling never drags, so a held Shift cannot move the group by accident
    if shift and pane.name == "sorted" then
        self:ToggleGroupItem(slot.layoutKey)
        self:ShowSelection()
        return false
    end
    -- Pressing a group item keeps the group so it can be dragged
    if self:GroupCount() > 1 and self.groupKeys[slot.layoutKey] then
        return self:BeginGroupDrag(slot)
    end
    self:SelectOnly(slot.layoutKey)
    self:ShowSelection()
    return self:StartItemDrag({ kind = "layout", layoutKey = slot.layoutKey, sourceKind = pane.name },
        slot.objectID, true)
end

-- Save the item in Layout or Unsorted
function LayoutEditorDrag:FinishCenterDrag(drag, x, y)
    local pane, paneX, paneY = self:PaneAt(x, y)
    if pane ~= nil and pane.name == "sorted" then
        local destination = self:SlotIndexAt(pane, paneX, paneY)
        if destination == nil then return end
        -- Save the item's new position as one undo step
        self:SaveEdit("Could not save the layout position.", function()
            return self.store:MoveLayoutItem(self.selectedTag, drag.layoutKey, destination, Size.CENTER_COLUMNS)
        end)
    elseif pane ~= nil and drag.sourceKind == "sorted" then
        -- The same as Move to Unsorted
        self:SaveEdit("Could not save the layout position.", function()
            return self.store:UnarrangeLayoutItem(self.selectedTag, drag.layoutKey)
        end)
    end
end

-- Start dragging a search result into the layout
function LayoutEditorDrag:BeginSearchDrag(result)
    if result == nil then return false end
    if self.selectedTag == nil then
        self:ShowError("Choose a tag before adding an item.")
        return false
    end
    return self:StartItemDrag({ kind = "search", result = result, sourceKind = "search" }, result.objectId, false)
end

-- Move the ghost and highlight its destination
function LayoutEditorDrag:UpdateDragAt(x, y)
    local drag = self.drag
    drag.ghost:SetPos(x - drag.ghostWidth // 2, y - drag.ghostHeight // 2)
    if math.abs(x - drag.startX) >= 4 or math.abs(y - drag.startY) >= 4 then drag.ghost.hidden = false end
    if drag.kind == "label" then
        self:ShowLabelDropRow(self:RowFromContentPoint(x, y))
    elseif drag.kind == "group" then
        self:ShowGroupPreview(x, y)
    end
    drag.ghost:MoveToFront()
end

-- Find the sorted row under an editor point
function LayoutEditorDrag:RowFromContentPoint(x, y)
    local pane, paneX, paneY = self:PaneAt(x, y)
    if pane == nil or pane.name ~= "sorted" then return nil end
    return self:RowAt(pane, paneX, paneY)
end

-- Shade the row a dragged label would take
function LayoutEditorDrag:ShowLabelDropRow(row)
    local drag = self.drag
    if drag.highlight == nil then
        drag.highlight = rectangle(self.panes.sorted.view.content, Size.GRID_LEFT, 0,
            Size.LABEL_WIDTH, Size.GRID_SLOT_SIZE, LABEL_DROP_COLOUR, true)
    end
    drag.highlight.hidden = row == nil
    if row == nil then return end
    local labels = self.panes.sorted.labels
    local height = Size.GRID_SLOT_SIZE
    for _, label in ipairs(labels) do
        if label.row == row then height = BankGrid.LABEL_HEIGHT; break end
    end
    drag.highlight:SetSize(Size.LABEL_WIDTH, height)
    drag.highlight:SetPos(Size.GRID_LEFT, BankGrid.RowItemY(row, labels))
    drag.highlight:MoveToFront()
end

-- Start dragging a label row, drawn as a heading
function LayoutEditorDrag:BeginLabelDrag(fromRow)
    local ghost = self:CreateDragGhost(Size.LABEL_GHOST_WIDTH, Size.LABEL_GHOST_HEIGHT)
    rectangle(ghost, 0, 0, Size.LABEL_GHOST_WIDTH, Size.LABEL_GHOST_HEIGHT, Theme.VIEW_BACKGROUND, true)
    Parts.heading(ghost, 6, 2, Size.LABEL_GHOST_WIDTH - 12,
        self.store:GetLabel(self.selectedTag, fromRow, Size.CENTER_COLUMNS))
    return self:StartDrag({ kind = "label", fromRow = fromRow, sourceKind = "sorted" }, ghost,
        Size.LABEL_GHOST_WIDTH, Size.LABEL_GHOST_HEIGHT)
end

-- Rename a label in place or move it
function LayoutEditorDrag:FinishLabelDrag(drag, x, y)
    local row = self:RowFromContentPoint(x, y)
    if row == nil then return end
    if row == drag.fromRow then return self:EditLabel(row) end
    -- Save the label's new row as one undo step
    self:SaveEdit("Could not move the label.", function()
        return self.store:MoveLabel(self.selectedTag, drag.fromRow, row, Size.CENTER_COLUMNS)
    end)
end

-- Add the dragged result at a sorted slot
function LayoutEditorDrag:FinishSearchDrag(drag, x, y)
    local pane, paneX, paneY = self:PaneAt(x, y)
    local destination = pane ~= nil and pane.name == "sorted" and self:SlotIndexAt(pane, paneX, paneY) or nil
    if destination ~= nil then self:AddCatalogResult(drag.result, destination) end
end

-- Finish the drag at the latest native pointer position
function LayoutEditorDrag:CommitDrag()
    local drag = self.drag
    local x, y = self:ContentPointer()
    self:CancelDrag()
    if x == nil then return false end
    if drag.kind == "layout" then
        self:FinishCenterDrag(drag, x, y)
    elseif drag.kind == "group" then
        self:FinishGroupDrag(drag, x, y)
    elseif drag.kind == "search" then
        self:FinishSearchDrag(drag, x, y)
    else
        self:FinishLabelDrag(drag, x, y)
    end
    return false
end

-- Remove the ghost and restore the pressed surface
function LayoutEditorDrag:CancelDrag()
    local drag = self.drag
    if drag == nil then return end
    self.drag = nil
    drag.ghost:Destroy()
    if drag.highlight ~= nil then drag.highlight:Destroy() end
    if drag.preview ~= nil then self:ClearGroupPreview(drag) end
    self:PlaceDragSurface(drag.sourceSurface, drag.sourceKind)
end

return LayoutEditorDrag
