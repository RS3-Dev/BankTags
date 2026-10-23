-- Build the tag list shown in the Tags tab and layout editor
-- A row pressed and released selects it; dragged, it moves to a new place

local Config = require("banktags/core/config")
local Geometry = require("banktags/ui/geometry")
local NativeUi = require("banktags/ui/native_ui")
local SidebarRows = require("banktags/ui/sidebar_rows")
local Text = require("banktags/core/text")
local Theme = require("banktags/ui/theme")
local debugLog = require("banktags/core/debug_log").Write

local TagList = {}
TagList.__index = TagList

local HELP_BUTTON_SIZE = 26
local HELP_BUTTON_GAP = 6
local FOLDER_ENTRY_PREFIX = "__banktags_folder:"
local TAG_ROW_LEFT = SidebarRows.ROW_LEFT
local FOLDER_CHEVRON_RIGHT = 8
local FOLDER_CHEVRON_SIZE = 14
local FOLDER_LABEL_LEFT = 26
-- Indent folder members to line up with the folder name
local FOLDER_INDENT = FOLDER_LABEL_LEFT - TAG_ROW_LEFT
local FOLDER_ROW = 0x3B352DFF
-- Folder members use warmer striped rows
local FOLDER_ROW_ODD = 0x27231DFF
local FOLDER_ROW_EVEN = 0x2D2823FF
local FOLDER_ACCENT_WIDTH = 2
local ROW_HEIGHT = 30
local ENTRY_HEIGHT = SidebarRows.ENTRY_HEIGHT
local DRAG_HOOK = Config.PLUGIN_REF .. "_row_drag"
-- How far the pointer moves before a press becomes a drag
local DRAG_DISTANCE = 6
-- Reaching this close to the list's top or bottom scrolls it one row
local SCROLL_EDGE = 12
local GHOST_FILL = 0x403728E0
local LINE_HEIGHT = 2

-- Return the folder key behind a folder header row, or nil for a tag row
local function folderKeyOf(entryID)
    entryID = tostring(entryID or "")
    if string.sub(entryID, 1, #FOLDER_ENTRY_PREFIX) ~= FOLDER_ENTRY_PREFIX then return nil end
    return string.sub(entryID, #FOLDER_ENTRY_PREFIX + 1)
end

-- Name a row's tag or folder the way the store does
local function sidebarEntry(entryID)
    local folderKey = folderKeyOf(entryID)
    if folderKey ~= nil then return { kind = "folder", key = folderKey } end
    return { kind = "tag", tag = entryID }
end

-- Draw a left bar along a folder's header and members
local function addFolderAccent(root, rowHeight)
    local accent = ui.Rectangle.new(root)
    accent:SetPos(0, 0)
    accent:SetSize(FOLDER_ACCENT_WIDTH, rowHeight)
    accent.fill = true
    accent.rgba = Theme.HEADING_LINE
    accent.clickthrough = true
    accent:MoveToFront()
    return accent
end

-- Create the tag list in a parent
function TagList.new(parent, options)
    local self = setmetatable({
        parent = parent,
        store = options.store,
        settings = options.settings,
        state = options.state,
        width = options.width,
        isSelected = options.isSelected,
        onSelect = options.onSelect,
        onChanged = options.onChanged,
        onReorder = options.onReorder,
        entries = {},
        entriesByID = {},
        -- The press or drag in progress, which never outlives the rows it began on
        gesture = nil,
        -- Row presses so far, so a menu can tell one happened after it was built
        clicks = 0,
    }, TagList)
    local contentWidth = SidebarRows.ContentWidth(self.width)
    self.search = SidebarRows.CreateSearch(parent, contentWidth - HELP_BUTTON_SIZE - HELP_BUTTON_GAP, {
        placeholder = "Search tags...",
        text = self.state.searchQuery,
        onChange = function(_, _, content)
            self.state.searchQuery = tostring(content or "")
            self:Refresh()
        end,
    })
    self.emptyLabel = SidebarRows.CreateEmptyLabel(parent, contentWidth,
        "Create a tag, then drag bank items onto it.")
    -- PrettyUI's own row press is the only press Bank Tags hears; it starts the gesture
    self.list = SidebarRows.CreateList(parent, contentWidth, options.listHeight, function(_, entryID)
        self:Press(entryID)
    end)
    self:Refresh()
    return self
end

-- Describe the rows in sidebar order, with folders where they start
function TagList:Entries()
    local query = string.lower(self.state.searchQuery)
    local entries, rowNumber = {}, 0
    -- Choose alternating row colours, warmer inside folders
    local function rowColour(inFolder)
        rowNumber = rowNumber + 1
        if inFolder then return rowNumber % 2 == 1 and FOLDER_ROW_ODD or FOLDER_ROW_EVEN end
        return rowNumber % 2 == 1 and Theme.ROW_ODD or Theme.ROW_EVEN
    end
    -- Check a tag or folder name against the search
    local function matches(value)
        return query == "" or string.find(string.lower(value), query, 1, true) ~= nil
    end
    -- Append one tag row, indented inside a folder
    local function addTag(tag, folderKey)
        entries[#entries + 1] = {
            id = tag,
            label = Text.titleCase(tag),
            selected = self.isSelected(tag),
            enabled = true,
            backgroundColour = rowColour(folderKey ~= nil),
            hoverColour = Theme.ROW_HOVER,
            selectedColour = Theme.ROW_SELECTED,
            textColour = SidebarRows.ROW_TEXT,
            folder = folderKey,
        }
    end
    for _, node in ipairs(self.store:TagTree()) do
        if node.kind == "tag" then
            if matches(node.tag) then addTag(node.tag, nil) end
        else
            -- A folder name match lists every member; searches expand folders
            local folderMatches = query ~= "" and matches(node.name)
            local visible, containsSelected = {}, false
            for _, tag in ipairs(node.tags) do
                if folderMatches or matches(tag) then visible[#visible + 1] = tag end
                if self.isSelected(tag) then containsSelected = true end
            end
            if #visible > 0 then
                local expanded = query ~= "" or not node.collapsed
                entries[#entries + 1] = {
                    id = FOLDER_ENTRY_PREFIX .. node.key,
                    label = node.name,
                    enabled = true,
                    expanded = expanded,
                    memberCount = #node.tags,
                    -- A collapsed folder outlines its hidden selected tag
                    selected = containsSelected and not expanded,
                    backgroundColour = FOLDER_ROW,
                    hoverColour = Theme.ROW_HOVER,
                    selectedColour = Theme.ROW_SELECTED,
                    textColour = Theme.HEADING_TEXT,
                }
                if expanded then
                    for _, tag in ipairs(visible) do addTag(tag, node.key) end
                end
            end
        end
    end
    return entries
end

-- Rebuild the rows from the store, keeping the search text
function TagList:Refresh()
    -- Any drag ends with the rows it was drawn over
    self:StopGesture()
    self.entries = self:Entries()
    self.entriesByID = {}
    for _, entry in ipairs(self.entries) do self.entriesByID[entry.id] = entry end
    if #self.entries == 0 then
        self.emptyLabel.content = #self.store:AllTags() == 0
            and "Create a tag, then drag bank items onto it." or "No matching tags."
        self.emptyLabel.hidden = false
        self.list.root.hidden = true
        self.list:SetEntries({})
        return
    end
    self.emptyLabel.hidden = true
    self.list.root.hidden = false
    self.list:SetEntries(self.entries)
    self:DecorateRows()
end

-- Decorate rows with chevrons, accents, icons, and frames
-- Each row keeps its drawn parts so a drag can hide them
function TagList:DecorateRows()
    local rows = self.list.rows or {}
    -- Extend the folder bar across gaps until its last member
    local function accentHeight(index)
        local nextRow = rows[index + 1]
        if nextRow == nil then return ROW_HEIGHT end
        return self.entriesByID[nextRow.entry.id].folder ~= nil and ENTRY_HEIGHT or ROW_HEIGHT
    end
    for index, row in ipairs(rows) do
        Geometry.trackPointer(row.root)
        self:BindRow(row)
        -- PrettyUI may keep only the entry fields it knows, so read our own entry
        local entry = self.entriesByID[row.entry.id]
        local parts = { row.background, row.label }
        row.parts = parts
        row.background:SetSize(0, ROW_HEIGHT, 1.0, 0)
        row.label.font = id.Font.MUSEO_SANS_11PT_REGULAR
        row.root.opConfig:ClearOpCursors()
        row.root.cursorConfig.mouseOverCursor = -1
        if folderKeyOf(entry.id) ~= nil then
            local objectID = self.settings().showTagSprites
                and self.store:GetFolderSprite(folderKeyOf(entry.id)) or nil
            local labelLeft = FOLDER_LABEL_LEFT
            if objectID ~= nil then
                parts[#parts + 1] = SidebarRows.AddRowIcon(row, objectID, TAG_ROW_LEFT)
                labelLeft = TAG_ROW_LEFT + 28
            end
            row.label.rgba = Theme.HEADING_TEXT
            row.label:SetPos(labelLeft, 0)
            local chevronLeft = -FOLDER_CHEVRON_RIGHT - FOLDER_CHEVRON_SIZE
            row.label:SetSize(chevronLeft - labelLeft - 4, ROW_HEIGHT, 1.0, 0)
            row.label.content = entry.label .. " (" .. entry.memberCount .. ")"
            row.label:MoveToFront()
            -- Sprites turn anticlockwise from the up-facing bank arrow
            local chevron = ui.Sprite.new(row.root)
            chevron:SetPos(chevronLeft, math.floor((ROW_HEIGHT - FOLDER_CHEVRON_SIZE) / 2), 1.0, 0)
            chevron:SetSize(FOLDER_CHEVRON_SIZE, FOLDER_CHEVRON_SIZE)
            chevron.spriteID = id.Sprite.BANK_ARROW_UP_0
            if entry.expanded then
                NativeUi.setSpriteRotation(chevron, math.pi, 180)
            else
                NativeUi.setSpriteRotation(chevron, math.pi * 1.5, 270)
            end
            chevron.clickthrough = true
            chevron:MoveToFront()
            parts[#parts + 1] = chevron
            parts[#parts + 1] = addFolderAccent(row.root, accentHeight(index))
        else
            local inFolder = entry.folder ~= nil
            local indent = inFolder and FOLDER_INDENT or 0
            if inFolder then parts[#parts + 1] = addFolderAccent(row.root, accentHeight(index)) end
            local objectID = self.settings().showTagSprites and self.store:GetTagSprite(entry.id) or nil
            local labelLeft = TAG_ROW_LEFT + indent
            if objectID ~= nil then
                parts[#parts + 1] = SidebarRows.AddRowIcon(row, objectID, TAG_ROW_LEFT + indent)
                labelLeft = TAG_ROW_LEFT + 28 + indent
            end
            row.label:SetPos(labelLeft, 0)
            row.label:SetSize(-labelLeft - 6, ROW_HEIGHT, 1.0, 0)
            row.label:MoveToFront()
        end
        if entry.selected then
            row.selectionFrame = SidebarRows.AddSelectedFrame(row.root, ROW_HEIGHT)
            for _, edge in ipairs(row.selectionFrame) do parts[#parts + 1] = edge end
        end
    end
end

-- Follow a pressed row's holds and releases
-- PrettyUI's row click reports the press itself, through Press
function TagList:BindRow(row)
    local root = row.root
    -- The client may report a held pointer as a hold or as its own drag
    -- Leaving the row is checked too, since holds may stop off it
    local function move()
        self:MoveGesture(row)
        return true
    end
    root:Subscribe(ui.Hook.ONHOLD, DRAG_HOOK, move)
    root:Subscribe(ui.Hook.ONDRAG, DRAG_HOOK, move)
    root:Subscribe(ui.Hook.ONMOUSELEAVE, DRAG_HOOK, move)
    -- Finish the same gesture for either release event the client sends
    local function release()
        self:Release(row)
        return true
    end
    root:Subscribe(ui.Hook.ONRELEASE, DRAG_HOOK, release)
    root:Subscribe(ui.Hook.ONDRAGCOMPLETE, DRAG_HOOK, release)
end

-- Find the pointer in the list's visible area, or nil without a mouse
-- Native drag start and end positions are not used; they are wrong under Windows scaling
function TagList:Pointer()
    local x, y = Geometry.interfaceMousePosition()
    if x == nil then return nil, nil end
    local originX, originY = Geometry.absolutePosition(self.list.viewport)
    return x - originX, y - originY
end

-- Check whether a visible-area point is inside the list
function TagList:Contains(x, y)
    local viewport = self.list.viewport
    return x ~= nil and x >= 0 and x < viewport.width and y >= 0 and y < viewport.height
end

-- Begin a press; a press on a stuck drag only ends that drag
function TagList:Press(entryID)
    self.clicks = self.clicks + 1
    debugLog("Bank Tags row press ", tostring(entryID), ", clicks ", self.clicks)
    if self:CancelGesture() then return end
    local x, y = self:Pointer()
    self.gesture = { row = self:RowFor(entryID), id = entryID, x = x, y = y, dragging = false }
end

-- Follow the held pointer, turning a press into a drag once it moves far enough
-- Searches show only some rows, so a filtered list never drags
function TagList:MoveGesture(row)
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

-- Find the rows an entry spans: a folder spans its shown tags
-- A tag inside a folder spans only its own row
function TagList:Span(rows, index, withinFolder)
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

-- Make the pressed row an invisible cover over the list, with a ghost and drop line
-- The press stays with that row, so its holds and release follow the pointer anywhere in the list
function TagList:BeginDrag()
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

-- Keep the cover over the visible rows as the list scrolls
function TagList:PlaceCover()
    local gesture, list = self.gesture, self.list
    gesture.row.root:SetPos(0, list.scrollY)
    gesture.row.root:SetSize(gesture.width, list.viewport.height)
end

-- Find where the dragged entry would go at a height in the rows
-- Returns the entry it goes beside, whether after it, and the line's height, or nil where nothing would move
function TagList:DropTarget(y)
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

-- Move the cover, ghost, and drop line to a height in the visible list
-- Each arrival at the list's top or bottom edge scrolls one row
function TagList:UpdateDrag(y)
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

-- Select or open a pressed row, or drop a dragged one where its line shows
-- Releases from bank item drags reach rows that were never pressed, so they do nothing
function TagList:Release(row)
    local gesture = self.gesture
    if gesture == nil or gesture.row ~= row then return end
    if not gesture.dragging then
        self.gesture = nil
        local folderKey = folderKeyOf(gesture.id)
        if folderKey ~= nil then
            self:ToggleFolder(folderKey)
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

-- Forget the press or drag in progress, reporting whether a drag was showing
function TagList:StopGesture()
    local gesture = self.gesture
    self.gesture = nil
    if gesture == nil or not gesture.dragging then return false end
    for _, part in ipairs({ gesture.ghost, gesture.line, gesture.row.root }) do
        pcall(function() part:Destroy() end)
    end
    return true
end

-- End a drag without moving anything and redraw the rows
function TagList:CancelGesture()
    if not self:StopGesture() then return false end
    self:Refresh()
    return true
end

-- Collapse or expand a folder
function TagList:ToggleFolder(folderKey)
    local folder = self.store:GetFolder(folderKey)
    if folder == nil then return false end
    self.store:SetFolderCollapsed(folderKey, not folder.collapsed)
    self.onChanged()
    return true
end

-- Find the row the client currently highlights
-- A dragged row is not listed, since it covers the whole list
function TagList:HoveredEntry()
    if self.list.root.hidden then return nil end
    for _, row in ipairs(self.list.rows or {}) do
        if row.root.isMouseOver == true then return sidebarEntry(row.entry.id) end
    end
    return nil
end

-- Find the drawn row for a tag
function TagList:RowFor(tag)
    for _, row in ipairs(self.list.rows or {}) do
        if row.entry.id == tag then return row end
    end
    return nil
end

-- Resize the row list
function TagList:SetListHeight(height)
    self.list:SetSize(SidebarRows.ContentWidth(self.width), height)
end

-- Destroy the controls this list created
function TagList:Destroy()
    self:StopGesture()
    for _, control in ipairs({ self.search, self.list, self.emptyLabel }) do
        pcall(function() control:Destroy() end)
    end
end

return TagList
