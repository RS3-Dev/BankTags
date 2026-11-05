-- Track sidebar presses, row drags, edge scrolling, and drops

local Config = require("banktags/core/config")
local Geometry = require("banktags/ui/geometry")
local SidebarRows = require("banktags/ui/sidebar_rows")
local Theme = require("banktags/ui/theme")
local Parts = require("banktags/sidebar/tag_list_parts")
local debugLog = require("banktags/core/debug_log").Write
local folderKeyOf, sidebarEntry = Parts.folderKeyOf, Parts.sidebarEntry
local FOLDER_ENTRY_PREFIX = Parts.FOLDER_ENTRY_PREFIX
local ROW_HEIGHT, ENTRY_HEIGHT = Parts.ROW_HEIGHT, Parts.ENTRY_HEIGHT

local TagListDrag = {}

local DRAG_HOOK = Config.PLUGIN_REF .. "_row_drag"
-- How far the pointer moves before a press becomes a drag
local DRAG_DISTANCE = 6
-- Reaching this close to the list's top or bottom scrolls it one row
local SCROLL_EDGE = 12
local GHOST_FILL = 0x403728E0
local LINE_HEIGHT = 2

-- Follow a pressed row until release
function TagListDrag:BindRow(row)
    local root = row.root
    -- Follow the held pointer, including when leaving the row
    local function move()
        self:MoveGesture(row)
        return true
    end
    root:Subscribe(ui.Hook.ONHOLD, DRAG_HOOK, move)
    root:Subscribe(ui.Hook.ONDRAG, DRAG_HOOK, move)
    root:Subscribe(ui.Hook.ONMOUSELEAVE, DRAG_HOOK, move)
    -- Finish the gesture for either release event
    local function release()
        self:Release(row)
        return true
    end
    root:Subscribe(ui.Hook.ONRELEASE, DRAG_HOOK, release)
    root:Subscribe(ui.Hook.ONDRAGCOMPLETE, DRAG_HOOK, release)
end

-- Find the pointer within the visible list
function TagListDrag:Pointer()
    local x, y = Geometry.interfaceMousePosition()
    if x == nil then return nil, nil end
    local originX, originY = Geometry.absolutePosition(self.list.viewport)
    return x - originX, y - originY
end

-- Check whether a visible-area point is inside the list
function TagListDrag:Contains(x, y)
    local viewport = self.list.viewport
    return x ~= nil and x >= 0 and x < viewport.width and y >= 0 and y < viewport.height
end

-- Find the hovered tag for a bank item drop
function TagListDrag:ItemDropTarget()
    if self.gesture ~= nil then return nil end
    local entry = self:HoveredEntry()
    return entry ~= nil and entry.kind == "tag" and entry.tag or nil
end

-- Begin a row press or cancel a stuck drag
function TagListDrag:Press(entryID)
    self.clicks = self.clicks + 1
    debugLog("Bank Tags row press ", tostring(entryID), ", clicks ", self.clicks)
    if self:CancelGesture() then return end
    local x, y = self:Pointer()
    self.gesture = { row = self:RowFor(entryID), id = entryID, x = x, y = y, dragging = false }
end

-- Turn an unfiltered row press into a drag
function TagListDrag:MoveGesture(row)
    local gesture = self.gesture
    if gesture == nil or gesture.row ~= row or gesture.x == nil then return end
    local x, y = self:Pointer()
    -- A release outside the list may never arrive
    if not self:Contains(x, y) then
        self:CancelGesture()
        return
    end
    if not gesture.dragging then
        if self.state.searchQuery ~= "" then return end
        if math.abs(x - gesture.x) < DRAG_DISTANCE and math.abs(y - gesture.y) < DRAG_DISTANCE then return end
        self:BeginDrag()
    end
    self:UpdateDrag(y)
end

-- Find the rows belonging to a dragged entry
function TagListDrag:Span(rows, index, withinFolder)
    if withinFolder then return index, index end
    -- Name the folder or top-level tag a row belongs to
    local function block(rowIndex)
        local entry = self.entriesByID[rows[rowIndex].entry.id]
        return entry.folder ~= nil and FOLDER_ENTRY_PREFIX .. entry.folder or entry.id
    end
    local name, first, last = block(index), index, index
    while first > 1 and block(first - 1) == name do first = first - 1 end
    while last < #rows and block(last + 1) == name do last = last + 1 end
    return first, last
end

-- Keep the pressed row over its drag area
function TagListDrag:BeginDrag()
    local gesture = self.gesture
    local row, list = gesture.row, self.list
    gesture.dragging = true
    gesture.rows = {}
    for index, value in ipairs(list.rows) do
        gesture.rows[index] = value
        if value == row then gesture.index = index end
    end
    -- Removed from PrettyUI's rows, scrolling leaves the cover's size alone
    table.remove(list.rows, gesture.index)
    gesture.folder = self.entriesByID[gesture.id].folder
    gesture.first, gesture.last = self:Span(gesture.rows, gesture.index, gesture.folder ~= nil)
    gesture.source = sidebarEntry(gesture.id)
    gesture.width = row.root.width
    for _, part in ipairs(row.parts) do part.hidden = true end
    -- Moving the cover would skew hover coordinates, so calibration stays as it was
    Geometry.untrackPointer(row.root)

    local ghost = ui.Layer.new(list.viewport)
    ghost:SetSize(gesture.width, ROW_HEIGHT)
    ghost.clickthrough = true
    local fill = ui.Rectangle.new(ghost)
    fill:SetSize(gesture.width, ROW_HEIGHT)
    fill.fill = true
    fill.rgba = GHOST_FILL
    fill.clickthrough = true
    SidebarRows.AddSelectedFrame(ghost, ROW_HEIGHT)
    local label = ui.Text.new(ghost)
    label:SetPos(row.label.x, 0)
    label:SetSize(gesture.width - row.label.x - 6, ROW_HEIGHT)
    label.content = row.label.content
    label.font = id.Font.MUSEO_SANS_11PT_REGULAR
    label.rgba = row.label.rgba
    label.isShadowed = true
    label.maxLines = 1
    label.alignVertical = ui.AlignMode.CENTRE
    label.clickthrough = true
    gesture.ghost = ghost

    local line = ui.Rectangle.new(list.viewport)
    line:SetSize(gesture.width, LINE_HEIGHT)
    line.fill = true
    line.rgba = Theme.SELECTED_BORDER
    line.clickthrough = true
    line.hidden = true
    gesture.line = line
end

-- Keep the pressed row over the visible list
function TagListDrag:PlaceCover()
    local gesture, list = self.gesture, self.list
    gesture.row.root:SetPos(0, list.scrollY)
    gesture.row.root:SetSize(gesture.width, list.viewport.height)
    -- Later sibling rows must not intercept the held pointer
    gesture.row.root:MoveToFront()
end

-- Find a valid gap for the dragged row
function TagListDrag:DropTarget(y)
    local gesture = self.gesture
    local rows = gesture.rows
    local index = math.max(1, math.min(#rows, math.floor(y / ENTRY_HEIGHT) + 1))
    -- A folder's tag stays among that folder's tags
    if gesture.folder ~= nil and self.entriesByID[rows[index].entry.id].folder ~= gesture.folder then
        return nil
    end
    local first, last = self:Span(rows, index, gesture.folder ~= nil)
    local after = y >= (first - 1 + (last - first + 1) / 2) * ENTRY_HEIGHT
    -- Rows are numbered from 1, so the gap before row n is n
    local gap = after and last + 1 or first
    if gap == gesture.first or gap == gesture.last + 1 then return nil end
    return { entry = sidebarEntry(rows[first].entry.id), after = after, lineY = (gap - 1) * ENTRY_HEIGHT }
end

-- Show the proposed drop and scroll at the edges
function TagListDrag:UpdateDrag(y)
    local gesture, list = self.gesture, self.list
    local height = list.viewport.height
    local edge = y < SCROLL_EDGE and -1 or y >= height - SCROLL_EDGE and 1 or nil
    if edge ~= gesture.edge then
        gesture.edge = edge
        if edge ~= nil then list:_OnScrollWheel(gesture.row.root, edge) end
    end
    self:PlaceCover()
    local top = list.scrollY
    local ghostY = math.floor(top + y - ROW_HEIGHT / 2)
    gesture.ghost:SetPos(0, math.max(top, math.min(top + height - ROW_HEIGHT, ghostY)))
    gesture.ghost:MoveToFront()
    gesture.target = self:DropTarget(top + y)
    gesture.line.hidden = gesture.target == nil
    if gesture.target ~= nil then
        gesture.line:SetPos(0, math.max(0, gesture.target.lineY - LINE_HEIGHT // 2))
        gesture.line:MoveToFront()
    end
end

-- Select a pressed row or finish its drag
function TagListDrag:Release(row)
    local gesture = self.gesture
    if gesture == nil or gesture.row ~= row then return end
    if not gesture.dragging then
        self.gesture = nil
        local folderKey = folderKeyOf(gesture.id)
        if folderKey ~= nil then
            self.onToggleFolder(folderKey)
        else
            self.onSelect(gesture.id)
        end
        return
    end
    local x, y = self:Pointer()
    local target = self:Contains(x, y) and self:DropTarget(self.list.scrollY + y) or nil
    -- Redraw the rows first; a saved move redraws them again
    self:CancelGesture()
    if target ~= nil then self.onReorder(gesture.source, target.entry, target.after) end
end

-- Forget the gesture and remove its drag controls
function TagListDrag:StopGesture()
    local gesture = self.gesture
    self.gesture = nil
    if gesture == nil or not gesture.dragging then return false end
    for _, part in ipairs({ gesture.ghost, gesture.line, gesture.row.root }) do
        pcall(function() part:Destroy() end)
    end
    return true
end

-- End a drag without moving anything and redraw the rows
function TagListDrag:CancelGesture()
    if not self:StopGesture() then return false end
    self:Refresh()
    return true
end

return TagListDrag
