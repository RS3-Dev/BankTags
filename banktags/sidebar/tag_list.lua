-- Build the tag list shown in the Tags tab and layout editor

local BankControls = require("banktags/ui/bank_controls")
local Geometry = require("banktags/ui/geometry")
local NativeUi = require("banktags/ui/native_ui")
local SidebarRows = require("banktags/ui/sidebar_rows")
local Text = require("banktags/core/text")
local Theme = require("banktags/ui/theme")
local debugLog = require("banktags/core/debug_log").Write

local TagList = {}
TagList.__index = TagList

local SORT_BUTTON_SIZE = 26
local SORT_BUTTON_GAP = 6
local SORT_ARROW_SIZE = 20
local SORT_ARROW_GAP = 2
local SORT_CONTROLS_WIDTH = SORT_ARROW_SIZE * 2 + SORT_ARROW_GAP + 8
local FOLDER_ENTRY_PREFIX = "__banktags_folder:"
local TAG_ROW_LEFT = SidebarRows.ROW_LEFT
local FOLDER_CHEVRON_RIGHT = 8
local FOLDER_CHEVRON_SIZE = 14
local FOLDER_LABEL_LEFT = 26
-- Indent folder members to line up with the folder name
local FOLDER_INDENT = FOLDER_LABEL_LEFT - TAG_ROW_LEFT
local FOLDER_ROW = 0x302A21FF
-- Folder members use warmer striped rows, darker than the header
local FOLDER_ROW_ODD = 0x27231DFF
local FOLDER_ROW_EVEN = 0x2D2823FF
local FOLDER_ACCENT_WIDTH = 2
local ROW_HEIGHT = 30

-- Return the folder key behind a folder header row, or nil for a tag row
local function folderKeyOf(entryID)
    entryID = tostring(entryID or "")
    if string.sub(entryID, 1, #FOLDER_ENTRY_PREFIX) ~= FOLDER_ENTRY_PREFIX then return nil end
    return string.sub(entryID, #FOLDER_ENTRY_PREFIX + 1)
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
        sortMode = false,
        sortButtons = {},
        entries = {},
        entriesByID = {},
        sortPositions = {},
        -- Row clicks so far, so a menu can tell one happened after it was built
        clicks = 0,
    }, TagList)
    local contentWidth = SidebarRows.ContentWidth(self.width)
    self.search = SidebarRows.CreateSearch(parent, contentWidth - SORT_BUTTON_SIZE - SORT_BUTTON_GAP, {
        placeholder = "Search tags...",
        text = self.state.searchQuery,
        onChange = function(_, _, content)
            self.state.searchQuery = tostring(content or "")
            if self.state.searchQuery ~= "" and self.sortMode then self:SetSortMode(false) end
            self:Refresh()
        end,
    })
    self.sortButton = BankControls.button(parent, nil, function()
        self:SetSortMode(not self.sortMode)
    end, {
        x = SidebarRows.CONTENT_X + contentWidth - SORT_BUTTON_SIZE,
        y = SidebarRows.SEARCH_TOP,
        size = SORT_BUTTON_SIZE,
        iconSize = 18,
        spriteName = "SWAP",
        tooltip = "Sort tags and folders",
    })
    self.emptyLabel = SidebarRows.CreateEmptyLabel(parent, contentWidth,
        "Create a tag, then drag bank items onto it.")
    self.list = SidebarRows.CreateList(parent, contentWidth, options.listHeight, function(_, entryID)
        self.clicks = self.clicks + 1
        debugLog("Bank Tags row click ", tostring(entryID), ", clicks ", self.clicks)
        local folderKey = folderKeyOf(entryID)
        if folderKey ~= nil then
            self:ToggleFolder(folderKey)
        else
            self.onSelect(entryID)
        end
    end)
    self:Refresh()
    return self
end

-- Describe the rows in sidebar order, with folders where they start
function TagList:Entries()
    local query = string.lower(self.state.searchQuery or "")
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
    local function addTag(tag, inFolder)
        entries[#entries + 1] = {
            id = tag,
            label = Text.titleCase(tag),
            selected = self.isSelected(tag),
            enabled = true,
            backgroundColour = rowColour(inFolder),
            hoverColour = Theme.ROW_HOVER,
            selectedColour = Theme.ROW_SELECTED,
            textColour = SidebarRows.ROW_TEXT,
            inFolder = inFolder,
        }
    end
    local tree = self.store:TagTree()
    self.sortPositions = {}
    for index, node in ipairs(tree) do
        local entryID = node.kind == "tag" and node.tag or FOLDER_ENTRY_PREFIX .. node.key
        self.sortPositions[entryID] = { index = index, count = #tree }
        for memberIndex, tag in ipairs(node.tags or {}) do
            self.sortPositions[tag] = { index = memberIndex, count = #node.tags }
        end
    end
    for _, node in ipairs(tree) do
        if node.kind == "tag" then
            if matches(node.tag) then addTag(node.tag, false) end
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
                    for _, tag in ipairs(visible) do addTag(tag, true) end
                end
            end
        end
    end
    return entries
end

-- Rebuild the rows from the store, keeping the search text
function TagList:Refresh()
    self:DestroySortButtons()
    self.entries = self:Entries()
    self.entriesByID = {}
    for _, entry in ipairs(self.entries) do self.entriesByID[entry.id] = entry end
    self.sortButton:SetActive(self.sortMode)
    self.sortButton:SetTooltip(self.sortMode and "Finish sorting tags and folders" or "Sort tags and folders")
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

-- Decorate rows with chevrons, accents, icons, frames, and arrows
function TagList:DecorateRows()
    local rows = self.list.rows or {}
    -- Extend the folder bar across gaps until its last member
    local function accentHeight(index)
        local nextRow = rows[index + 1]
        if nextRow == nil then return ROW_HEIGHT end
        local nextEntry = self.entriesByID[nextRow.entry.id] or nextRow.entry
        return nextEntry.inFolder and SidebarRows.ENTRY_HEIGHT or ROW_HEIGHT
    end
    for index, row in ipairs(rows) do
        Geometry.trackPointer(row.root)
        -- PrettyUI may keep only the entry fields it knows, so read our own entry
        local entry = self.entriesByID[row.entry.id] or row.entry
        row.background:SetSize(0, ROW_HEIGHT, 1.0, 0)
        row.label.font = id.Font.MUSEO_SANS_11PT_REGULAR
        row.root.opConfig:ClearOpCursors()
        row.root.cursorConfig.mouseOverCursor = -1
        local rightInset = self.sortMode and SORT_CONTROLS_WIDTH or 0
        if folderKeyOf(entry.id) ~= nil then
            row.label.rgba = Theme.HEADING_TEXT
            row.label:SetPos(FOLDER_LABEL_LEFT, 0)
            local chevronLeft = -FOLDER_CHEVRON_RIGHT - FOLDER_CHEVRON_SIZE - rightInset
            row.label:SetSize(chevronLeft - FOLDER_LABEL_LEFT - 4, ROW_HEIGHT, 1.0, 0)
            row.label.content = tostring(entry.label or "") .. " (" .. tostring(entry.memberCount or 0) .. ")"
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
            addFolderAccent(row.root, accentHeight(index))
        else
            local indent = entry.inFolder and FOLDER_INDENT or 0
            if entry.inFolder then addFolderAccent(row.root, accentHeight(index)) end
            local objectID = self.settings().showTagSprites and self.store:GetTagSprite(entry.id) or nil
            local labelLeft = TAG_ROW_LEFT + indent
            if objectID ~= nil then
                SidebarRows.AddRowIcon(row, objectID, TAG_ROW_LEFT + indent)
                labelLeft = TAG_ROW_LEFT + 28 + indent
            end
            row.label:SetPos(labelLeft, 0)
            row.label:SetSize(-labelLeft - math.max(6, rightInset), ROW_HEIGHT, 1.0, 0)
            row.label:MoveToFront()
        end
        if entry.selected then row.selectionFrame = SidebarRows.AddSelectedFrame(row.root, ROW_HEIGHT) end
        if self.sortMode then self:AddSortArrows(row) end
    end
end

-- Remove the sort arrows before their rows are replaced
function TagList:DestroySortButtons()
    for _, button in ipairs(self.sortButtons) do pcall(function() button:Destroy() end) end
    self.sortButtons = {}
end

-- Add arrows that move an entry within its own group
function TagList:AddSortArrows(row)
    local position = self.sortPositions[row.entry.id]
    if position == nil then return end
    for _, offset in ipairs({ -1, 1 }) do
        local up = offset == -1
        local button = prettyui.SpriteButton.new(row.root, up and "ARROW_UP" or "ARROW_DOWN", function()
            self:MoveEntry(row.entry.id, offset)
        end, {
            x = up and -SORT_CONTROLS_WIDTH or -SORT_ARROW_SIZE - 8,
            xAnchor = 1.0,
            y = math.floor((ROW_HEIGHT - SORT_ARROW_SIZE) / 2),
            size = SORT_ARROW_SIZE,
            disabled = up and position.index == 1 or not up and position.index == position.count,
            _onScrollWheel = function(component, delta)
                return self.list:_OnScrollWheel(component, delta)
            end,
        })
        self.sortButtons[#self.sortButtons + 1] = button
    end
end

-- Toggle sort mode, clearing the search so moves stay visible
function TagList:SetSortMode(enabled)
    self.sortMode = enabled == true
    if self.sortMode and (self.state.searchQuery or "") ~= "" then
        self.state.searchQuery = ""
        self.search:SetText("", false)
    end
    self:Refresh()
end

-- Save one sibling move and rebuild the rows
function TagList:MoveEntry(entryID, offset)
    if not self.sortMode then return false end
    local key = folderKeyOf(entryID)
    local saved, reason = self.store:MoveSidebarEntry(key == nil and entryID or nil, key, offset)
    if not saved then
        if reason ~= nil then debugLog("Bank Tags could not reorder: ", reason) end
        return false
    end
    self.onChanged()
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
function TagList:HoveredEntry()
    if self.list.root.hidden then return nil end
    for _, row in ipairs(self.list.rows or {}) do
        if row.root.isMouseOver == true then
            local folderKey = folderKeyOf(row.entry.id)
            if folderKey ~= nil then return { kind = "folder", key = folderKey } end
            return { kind = "tag", tag = row.entry.id }
        end
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
    self:DestroySortButtons()
    for _, control in ipairs({ self.sortButton, self.search, self.list, self.emptyLabel }) do
        pcall(function() control:Destroy() end)
    end
end

return TagList
