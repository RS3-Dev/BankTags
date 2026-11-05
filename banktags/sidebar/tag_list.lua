-- Draw selectable, draggable tags and folders in the sidebar

local Geometry = require("banktags/ui/geometry")
local SidebarRows = require("banktags/ui/sidebar_rows")
local Text = require("banktags/core/text")
local Theme = require("banktags/ui/theme")

local Parts = require("banktags/sidebar/tag_list_parts")
local folderKeyOf, sidebarEntry = Parts.folderKeyOf, Parts.sidebarEntry

local TagList = {}
TagList.__index = TagList
for name, method in pairs(require("banktags/sidebar/tag_list_drag")) do TagList[name] = method end

local HELP_BUTTON_SIZE = 26
local HELP_BUTTON_GAP = 6
local FOLDER_ENTRY_PREFIX = Parts.FOLDER_ENTRY_PREFIX
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
local ROW_HEIGHT = Parts.ROW_HEIGHT
local ENTRY_HEIGHT = Parts.ENTRY_HEIGHT
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
        onToggleFolder = options.onToggleFolder,
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
        -- Keep the search text while refreshing visible rows
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

-- List visible tags and folders in sidebar order
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

-- Add folder arrows, icons, and selection outlines
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
                chevron.rotationDegrees = 180
            else
                chevron.rotationDegrees = 270
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

-- Find the visible row under the pointer
function TagList:HoveredEntry()
    if self.list.root.hidden or self.list.root.visibleGlobal == false then return nil end
    for _, row in ipairs(self.list.rows or {}) do
        if row.entry.enabled ~= false and not row.root.hidden and row.root.visibleGlobal ~= false
            and row.root.isMouseOver == true then return sidebarEntry(row.entry.id) end
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

-- Destroy the controls this list created
function TagList:Destroy()
    self:StopGesture()
    for _, control in ipairs({ self.search, self.list, self.emptyLabel }) do
        pcall(function() control:Destroy() end)
    end
end

return TagList
