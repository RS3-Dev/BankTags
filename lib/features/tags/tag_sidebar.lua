-- Build the Tags, Cleanup, and Queries sidebar content: search, sorting, rows, and footer.
-- The frame around it is SidebarFrame. In the bank, the bank controller draws the frame and
-- other plugins' rows; the layout editor draws its own frame through CreateRail

local Config = require("lib/core/config")
local StorageKeys = require("lib/features/storage_keys")
local NativeUi = require("lib/ui/native_ui")
local BankControls = require("lib/ui/bank_controls")
local debugLog = require("lib/core/debug_log").Write
local Text = require("lib/core/text")
local Theme = require("lib/ui/theme")
local SidebarFrame = require("lib/ui/sidebar_frame")
local SidebarRows = require("lib/ui/sidebar_rows")
local SidebarTabs = require("lib/features/tags/sidebar_tabs")
local titleCase = Text.titleCase

local TagSidebar = {}

local SEARCH_TOP = SidebarRows.SEARCH_TOP
local SEARCH_HEIGHT = SidebarRows.SEARCH_HEIGHT
local SORT_BUTTON_SIZE = 26
local SORT_BUTTON_GAP = 6
local SORT_ARROW_SIZE = 20
local SORT_ARROW_GAP = 2
local SORT_CONTROLS_WIDTH = SORT_ARROW_SIZE * 2 + SORT_ARROW_GAP + 8
local FOOTER_X = 8
local FOOTER_WIDTH = Config.TAG_RAIL_WIDTH - 24
local FOOTER_BUTTON_HEIGHT = 28
local FOOTER_BUTTON_GAP = 8
local SETTINGS_BUTTON_SIZE = 28
local EDIT_BUTTON_SIZE = 28
local NEW_TAG_X = FOOTER_X + SETTINGS_BUTTON_SIZE + FOOTER_BUTTON_GAP
local NEW_TAG_FULL_WIDTH = FOOTER_WIDTH - SETTINGS_BUTTON_SIZE - FOOTER_BUTTON_GAP
local NEW_TAG_SELECTED_WIDTH = NEW_TAG_FULL_WIDTH
    - EDIT_BUTTON_SIZE - FOOTER_BUTTON_GAP
local EDIT_BUTTON_X = NEW_TAG_X + NEW_TAG_SELECTED_WIDTH + FOOTER_BUTTON_GAP
local VIEW_ALL_WARNING_HOOK = StorageKeys.PLUGIN_REF .. "_view_all_warning_click"
local CLEANUP_GROUP_ORDER = { "Review", "Utility storage", "Player-owned house" }
local FOLDER_ENTRY_PREFIX = "__bankutils_folder:"
local TAG_ROW_LEFT = SidebarRows.ROW_LEFT
local FOLDER_CHEVRON_RIGHT = 8
local FOLDER_CHEVRON_SIZE = 14
local FOLDER_LABEL_LEFT = 26
-- Folder members start where the folder name does, so their icons line up beneath it
local FOLDER_INDENT = FOLDER_LABEL_LEFT - TAG_ROW_LEFT
local SIDEBAR_FOLDER_ROW = 0x302A21FF
local SIDEBAR_FOLDER_TEXT = Theme.HEADING_TEXT
local SIDEBAR_ROW_ODD = Theme.ROW_ODD
local SIDEBAR_ROW_EVEN = Theme.ROW_EVEN
-- Folder members take a warmer zebra that stays darker than the folder header
local SIDEBAR_FOLDER_ROW_ODD = 0x27231DFF
local SIDEBAR_FOLDER_ROW_EVEN = 0x2D2823FF
local FOLDER_ACCENT_COLOUR = Theme.HEADING_LINE
local FOLDER_ACCENT_WIDTH = 2
local SIDEBAR_ROW_HOVER = Theme.ROW_HOVER
local SIDEBAR_ROW_SELECTED = Theme.ROW_SELECTED
local ROW_TEXT = SidebarRows.ROW_TEXT
local STATUS_TEXT = SidebarRows.STATUS_TEXT

local componentIsMouseOver = SidebarRows.IsMouseOver
local isGroupEntry = SidebarRows.IsGroupEntry
local headerEntry = SidebarRows.HeaderEntry
local addSelectedFrame = SidebarRows.AddSelectedFrame

-- Return the folder key behind a collapsible folder header row
local function folderKeyOf(entry)
    local entryID = tostring(type(entry) == "table" and entry.id or entry or "")
    if string.sub(entryID, 1, #FOLDER_ENTRY_PREFIX) ~= FOLDER_ENTRY_PREFIX then return nil end
    return string.sub(entryID, #FOLDER_ENTRY_PREFIX + 1)
end

TagSidebar.FOLDER_ENTRY_PREFIX = FOLDER_ENTRY_PREFIX

-- Mark a folder header or member with a left bar that runs the folder's length
local function addFolderAccent(root, rowHeight)
    local accent = ui.Rectangle.new(root)
    accent:SetPos(0, 0)
    accent:SetSize(FOLDER_ACCENT_WIDTH, rowHeight)
    accent.fill = true
    accent.rgba = FOLDER_ACCENT_COLOUR
    accent.clickthrough = true
    accent:MoveToFront()
    return accent
end

-- Build sidebar rows for tags, cleanup categories, or saved queries
function TagSidebar:TagEntries()
    local query = string.lower(self.searchQuery or "")
    local entries = {}
    self.sidebarRowStatus = {}
    local rowNumber = 0
    -- A native category tab cannot display a plugin-filtered tag view, but its
    -- visible items must still be draggable onto tags. Keep the rows active so
    -- clicks can show the existing View All guidance and drops can assign the
    -- item. The full preset selector is the only state that disables them
    local tagsAvailable = not self:IsPresetViewOpen()
    -- Choose alternating row colours for ordinary sidebar entries
    local function rowStyle(inFolder)
        rowNumber = rowNumber + 1
        if inFolder then
            return rowNumber % 2 == 1 and SIDEBAR_FOLDER_ROW_ODD or SIDEBAR_FOLDER_ROW_EVEN
        end
        return rowNumber % 2 == 1 and SIDEBAR_ROW_ODD or SIDEBAR_ROW_EVEN
    end
    if self:IsRuneSQLMode() then
        local queries = self.queryStore ~= nil and self.queryStore:All() or {}
        for _, record in ipairs(queries) do
            local selectionID = self.queryStore.SelectionID(record.id)
            local searchable = string.lower(record.name .. " " .. record.query)
            if query == "" or string.find(searchable, query, 1, true) ~= nil then
                local count = self.runeQueryCounts and self.runeQueryCounts[record.id] or nil
                entries[#entries + 1] = {
                    id = selectionID,
                    label = record.name,
                    selected = selectionID == self.selectedTag,
                    enabled = tagsAvailable,
                    backgroundColour = rowStyle(),
                    hoverColour = SIDEBAR_ROW_HOVER,
                    selectedColour = SIDEBAR_ROW_SELECTED,
                    textColour = ROW_TEXT,
                    rightText = count ~= nil and ("(" .. tostring(count) .. ")") or nil,
                    rightTextWidth = 34,
                    rightTextFont = id.Font.MUSEO_SANS_11PT_REGULAR,
                    rightTextColour = STATUS_TEXT,
                }
                if count ~= nil then
                    self.sidebarRowStatus[selectionID] = "(" .. tostring(count) .. ")"
                end
            end
        end
        return entries
    end
    if self:IsCleanupMode() then
        local categories = self.cleanupCategories:Entries()
        for _, group in ipairs(CLEANUP_GROUP_ORDER) do
            local groupAdded = false
            for _, category in ipairs(categories) do
                local label = category.displayLabel or category.label
                if category.group == group and (query == ""
                    or string.find(string.lower(label), query, 1, true) ~= nil) then
                    if not groupAdded then
                        groupAdded = true
                        entries[#entries + 1] = headerEntry(tostring(group), group)
                    end
                    entries[#entries + 1] = {
                        id = category.id,
                        label = label,
                        selected = category.id == self.selectedTag,
                        enabled = tagsAvailable and not category.refreshing,
                        refreshing = category.refreshing,
                        backgroundColour = rowStyle(),
                        hoverColour = SIDEBAR_ROW_HOVER,
                        rightText = category.refreshing and "..."
                            or ("(" .. tostring(category.count) .. ")"),
                        rightTextWidth = 34,
                        rightTextFont = id.Font.MUSEO_SANS_11PT_REGULAR,
                        rightTextColour = STATUS_TEXT,
                        selectedColour = SIDEBAR_ROW_SELECTED,
                        textColour = ROW_TEXT,
                    }
                    self.sidebarRowStatus[category.id] = category.refreshing and "..."
                        or ("(" .. tostring(category.count) .. ")")
                end
            end
        end
        return entries
    end
    -- Check a tag or folder name against the sidebar search
    local function matches(value)
        return query == "" or string.find(string.lower(value), query, 1, true) ~= nil
    end
    -- Append one tag row, indenting it when it sits inside a folder
    local function addTag(tag, inFolder)
        entries[#entries + 1] = {
            id = tag,
            label = titleCase(tag),
            selected = tag == self.selectedTag
                or tag == self.itemSelectionTag,
            enabled = tagsAvailable,
            backgroundColour = rowStyle(inFolder),
            hoverColour = SIDEBAR_ROW_HOVER,
            selectedColour = SIDEBAR_ROW_SELECTED,
            textColour = ROW_TEXT,
            inFolder = inFolder,
        }
    end
    local tree = self.store:TagTree()
    self.sidebarSortPositions = {}
    for index, node in ipairs(tree) do
        local entryID = node.kind == "tag" and node.tag or FOLDER_ENTRY_PREFIX .. node.key
        self.sidebarSortPositions[entryID] = { index = index, count = #tree }
        if node.kind == "folder" then
            for memberIndex, tag in ipairs(node.tags) do
                self.sidebarSortPositions[tag] = { index = memberIndex, count = #node.tags }
            end
        end
    end
    for _, node in ipairs(tree) do
        if node.kind == "tag" then
            if matches(node.tag) then addTag(node.tag, false) end
        else
            -- A folder-name match lists every member; searches always expand folders
            local folderMatches = query ~= "" and matches(node.name)
            local visible = {}
            local containsSelected = false
            for _, tag in ipairs(node.tags) do
                if folderMatches or matches(tag) then visible[#visible + 1] = tag end
                if tag == self.selectedTag or tag == self.itemSelectionTag then
                    containsSelected = true
                end
            end
            if #visible > 0 then
                local expanded = query ~= "" or not node.collapsed
                entries[#entries + 1] = {
                    id = FOLDER_ENTRY_PREFIX .. node.key,
                    label = node.name,
                    enabled = true,
                    expanded = expanded,
                    memberCount = #node.tags,
                    -- A collapsed folder carries the outline of its hidden selected tag
                    selected = containsSelected and not expanded,
                    backgroundColour = SIDEBAR_FOLDER_ROW,
                    hoverColour = SIDEBAR_ROW_HOVER,
                    selectedColour = SIDEBAR_ROW_SELECTED,
                    textColour = SIDEBAR_FOLDER_TEXT,
                }
                if expanded then
                    for _, tag in ipairs(visible) do addTag(tag, true) end
                end
            end
        end
    end
    return entries
end

-- Unbind tooltips before sidebar rows are replaced
function TagSidebar:DestroyTagTooltips()
    for index = #self.tagTooltips, 1, -1 do
        pcall(function() self.tagTooltips[index]:Destroy() end)
    end
    self.tagTooltips = {}
end

-- Add native item icons, counts, and selection frames to sidebar rows
function TagSidebar:AttachTagSprites()
    self.tagIcons = {}
    if self.list == nil then return end
    local rows = self.list.rows or {}
    -- The folder bar bridges the gap between rows until the folder's last member
    local function accentHeight(index, rowHeight)
        local nextRow = rows[index + 1]
        if nextRow == nil then return rowHeight end
        local nextEntry = (self.sidebarEntriesByID or {})[nextRow.entry.id] or nextRow.entry
        return nextEntry.inFolder and self.list.entryHeight or rowHeight
    end
    for rowIndex, row in ipairs(rows) do
        -- PrettyUI versions may copy only known entry fields into their rows
        local entry = (self.sidebarEntriesByID or {})[row.entry.id] or row.entry
        if isGroupEntry(row.entry) then
            SidebarRows.StyleHeaderRow(row)
        elseif folderKeyOf(row.entry) ~= nil then
            local rowHeight = math.min(30, self.list.entryHeight)
            row.background:SetSize(0, rowHeight, 1.0, 0)
            row.root.opConfig:ClearOpCursors()
            row.root.cursorConfig.mouseOverCursor = -1
            row.label.font = id.Font.MUSEO_SANS_11PT_REGULAR
            row.label.rgba = SIDEBAR_FOLDER_TEXT
            row.label:SetPos(FOLDER_LABEL_LEFT, 0)
            local rightInset = self:IsTagSortMode() and SORT_CONTROLS_WIDTH or 0
            local chevronLeft = -FOLDER_CHEVRON_RIGHT - FOLDER_CHEVRON_SIZE - rightInset
            row.label:SetSize(chevronLeft - FOLDER_LABEL_LEFT - 4, rowHeight, 1.0, 0)
            row.label.content = tostring(entry.label or "")
                .. " (" .. tostring(entry.memberCount or 0) .. ")"
            row.label:MoveToFront()
            -- The bank arrow faces up and the host turns sprites anticlockwise:
            -- a half turn faces down for an open folder, three quarters faces right
            local chevron = ui.Sprite.new(row.root)
            chevron:SetPos(chevronLeft, math.floor((rowHeight - FOLDER_CHEVRON_SIZE) / 2), 1.0, 0)
            chevron:SetSize(FOLDER_CHEVRON_SIZE, FOLDER_CHEVRON_SIZE)
            chevron.spriteID = id.Sprite.BANK_ARROW_UP_0
            if entry.expanded then
                NativeUi.setSpriteRotation(chevron, math.pi, 180)
            else
                NativeUi.setSpriteRotation(chevron, math.pi * 1.5, 270)
            end
            chevron.clickthrough = true
            chevron:MoveToFront()
            row.bankUtilitiesFolderAccent = addFolderAccent(row.root, accentHeight(rowIndex, rowHeight))
            if row.entry.selected then
                row.bankUtilitiesSelectionFrame = addSelectedFrame(row.root, rowHeight)
            end
        else
            local tag = row.entry.id
            local rowHeight = math.min(30, self.list.entryHeight)
            row.background:SetSize(0, rowHeight, 1.0, 0)
            row.label.font = id.Font.MUSEO_SANS_11PT_REGULAR
            row.root.opConfig:ClearOpCursors()
            row.root.cursorConfig.mouseOverCursor = -1
            local presetOpen = self:IsPresetViewOpen()
            if presetOpen and not row.entry.enabled then
                row.root.clickthrough = false
                local tooltip = prettyui.Tooltip.attach(row.root, self.list.viewport, {
                    text = 'Select "Return to Bank" before using bank tags.',
                    placement = "right",
                })
                if tooltip ~= nil then self.tagTooltips[#self.tagTooltips + 1] = tooltip end
                row.root:Subscribe(ui.Hook.ONCLICK, VIEW_ALL_WARNING_HOOK, function()
                    self:ShowPresetWarning()
                    return false
                end)
            elseif self:IsCleanupMode() and self.cleanupCategories:IsRefreshing(tag) then
                row.root.clickthrough = false
                local tooltip = prettyui.Tooltip.attach(row.root, self.list.viewport, {
                    text = "Scanning the current bank safely in small batches.",
                    placement = "right",
                })
                if tooltip ~= nil then self.tagTooltips[#self.tagTooltips + 1] = tooltip end
            elseif not row.entry.enabled then
                row.root.clickthrough = false
                local tooltip = prettyui.Tooltip.attach(row.root, self.list.viewport, {
                    text = 'Select "All Items" to use bank tags.',
                    placement = "right",
                })
                if tooltip ~= nil then self.tagTooltips[#self.tagTooltips + 1] = tooltip end
                row.root:Subscribe(ui.Hook.ONCLICK, VIEW_ALL_WARNING_HOOK, function()
                    if self:IsPresetViewOpen() then
                        self:ShowPresetWarning()
                    else
                        self:ShowViewAllWarning()
                    end
                    return false
                end)
            end

            local indent = entry.inFolder and FOLDER_INDENT or 0
            if entry.inFolder then
                row.bankUtilitiesFolderAccent = addFolderAccent(row.root, accentHeight(rowIndex, rowHeight))
            end

            local status = (self.sidebarRowStatus or {})[tag]
            if status ~= nil then SidebarRows.AddRowStatus(row, status, rowHeight) end
            local objectID = not self:IsGeneratedSelection(tag)
                and self.settings.showTagSprites ~= false
                and self.store:GetTagSprite(tag) or nil
            local labelLeft = TAG_ROW_LEFT + indent
            if objectID ~= nil then
                local icon = SidebarRows.AddRowIcon(row, objectID, TAG_ROW_LEFT + indent)
                labelLeft = TAG_ROW_LEFT + 28 + indent
                self.tagIcons[#self.tagIcons + 1] = icon
            end
            local labelRight = status ~= nil and 49 or 6
            if self:IsTagSortMode() then labelRight = SORT_CONTROLS_WIDTH end
            row.label:SetPos(labelLeft, 0)
            row.label:SetSize(-labelLeft - labelRight, rowHeight, 1.0, 0)
            row.label:MoveToFront()

            if row.entry.selected then
                row.bankUtilitiesSelectionFrame = addSelectedFrame(row.root, rowHeight)
            end
        end
        if self:IsTagSortMode() then self:AttachTagSortArrows(row) end
    end
end

-- Return the selected sidebar tab's ID; a sidebar without tabs shows Tags
function TagSidebar:ActiveSidebarTab()
    return self.sidebarMode or SidebarTabs.TAGS
end

-- Report whether another plugin's tab is selected, so none of these rows are shown
function TagSidebar:IsExtensionTabMode()
    return not SidebarTabs.IsOwnTab(self:ActiveSidebarTab())
end

-- Report whether the Tags tab is selected
function TagSidebar:IsTagsMode()
    return not self:IsCleanupMode() and not self:IsRuneSQLMode()
        and not self:IsExtensionTabMode()
end

-- Check whether sibling sorting is active in the custom-tag sidebar
function TagSidebar:IsTagSortMode()
    return self.tagSortMode == true and self:IsTagsMode()
end

-- Destroy row arrow controls before their parent list rows are replaced
function TagSidebar:DestroyTagSortButtons()
    for _, button in ipairs(self.tagSortButtons or {}) do button:Destroy() end
    self.tagSortButtons = {}
end

-- Attach move controls with bounds calculated from the full sibling tier
function TagSidebar:AttachTagSortArrows(row)
    local position = (self.sidebarSortPositions or {})[row.entry.id]
    if position == nil then return end
    local rowHeight = math.min(30, self.list.entryHeight)
    self.tagSortButtons = self.tagSortButtons or {}
    for _, offset in ipairs({ -1, 1 }) do
        local up = offset == -1
        local button = prettyui.SpriteButton.new(row.root,
            up and "ARROW_UP" or "ARROW_DOWN", function()
                self:MoveTagSidebarEntry(row.entry.id, offset)
            end, {
                x = up and -SORT_CONTROLS_WIDTH or -SORT_ARROW_SIZE - 8,
                xAnchor = 1.0,
                y = math.floor((rowHeight - SORT_ARROW_SIZE) / 2),
                size = SORT_ARROW_SIZE,
                disabled = up and position.index == 1
                    or not up and position.index == position.count,
                _onScrollWheel = function(component, delta)
                    return self.list:_OnScrollWheel(component, delta)
                end,
            })
        self.tagSortButtons[#self.tagSortButtons + 1] = button
    end
end

-- Save one sibling move and rebuild only the sidebar, retaining the bank selection
function TagSidebar:MoveTagSidebarEntry(entryID, offset)
    if not self:IsTagSortMode() or (self.searchQuery or "") ~= "" then return false end
    local key = folderKeyOf(entryID)
    local saved, reason = self.store:MoveSidebarEntry(key == nil and entryID or nil, key, offset)
    if self.sortButton ~= nil then
        self.sortButton:SetTooltip(saved and "Finish sorting tags and folders"
            or (reason or "This entry is already at the end of its tier."))
    end
    if not saved then
        if reason ~= nil then debugLog("Bank Utilities could not reorder: ", reason) end
        return false
    end
    self:RefreshTags()
    return true
end

-- Toggle inline sorting and clear filtering so every move has a visible neighbour
function TagSidebar:SetTagSortMode(enabled)
    self.tagSortMode = enabled == true and self:IsTagsMode()
    if self.tagSortMode then
        self.searchQuery = ""
        if self.search ~= nil then self.search:SetText("", false) end
    end
    self:UpdateTagSortControl()
    self:RefreshTags()
end

-- Reserve search space for the tag-only sort toggle and update its active marker
function TagSidebar:UpdateTagSortControl()
    local tagsMode = self:IsTagsMode() and self.sidebarSortable ~= false
    if not tagsMode then self.tagSortMode = false end
    if self.sortButton ~= nil then
        self.sortButton:SetHidden(not tagsMode)
        self.sortButton:SetActive(self:IsTagSortMode())
        self.sortButton:SetTooltip(self:IsTagSortMode()
            and "Finish sorting tags and folders" or "Sort tags and folders")
    end
    if self.search ~= nil then
        self.search.root:SetSize(FOOTER_WIDTH - (tagsMode and SORT_BUTTON_SIZE + SORT_BUTTON_GAP or 0),
            SEARCH_HEIGHT)
    end
end

-- Rebuild sidebar entries and their appearance while preserving selection
function TagSidebar:RefreshTags()
    if self.list == nil then return end
    self:DestroyTagSortButtons()
    self:DestroyTagTooltips()
    local entries = self:TagEntries()
    self.sidebarEntriesByID = {}
    for _, entry in ipairs(entries) do self.sidebarEntriesByID[entry.id] = entry end
    if #entries == 0 then
        if self:IsCleanupMode() then
            self.emptyLabel.content = "No matching cleanup categories."
        elseif self:IsRuneSQLMode() then
            local queries = self.queryStore ~= nil and self.queryStore:All() or {}
            self.emptyLabel.content = #queries == 0
                and "Create a RuneQL query to save a reusable bank search."
                or "No matching RuneQL queries."
        elseif #self.store:AllTags() == 0 then
            self.emptyLabel.content = "Create a tag, then drag bank items onto it."
        else
            self.emptyLabel.content = "No matching tags."
        end
        self.emptyLabel.hidden = false
        self.list.root.hidden = true
    else
        self.emptyLabel.hidden = true
        self.list.root.hidden = false
        self.list:SetEntries(entries)
        self:AttachTagSprites()
        if self.itemSelectionTag ~= nil then
            self:RefreshItemSelectionVisuals()
        end
    end
end

-- Match the tabs, labels, and available edit actions to the selected view
function TagSidebar:UpdateLayoutControls()
    self:UpdateContentControls()
    self:UpdateSidebarTabs()
end

-- Match the search, list, and footer actions to the selected tab and page
function TagSidebar:UpdateContentControls()
    self:UpdateTagSortControl()
    local cleanupMode = self:IsCleanupMode()
    local runeSQLMode = self:IsRuneSQLMode()
    local tagsMode = self:IsTagsMode()
    local editableTag = tagsMode
        and self.selectedTag ~= nil and not self:IsGeneratedSelection()
    local editableQuery = runeSQLMode and self:IsRuneQuerySelection()
    -- A sidebar with its own footer action keeps that button available
    local fixedEditButton = self.sidebarEditButton ~= nil
    local enabled = editableTag or editableQuery or fixedEditButton
    if self.search ~= nil then
        self.search:SetPlaceholder(cleanupMode and "Search categories..."
            or (runeSQLMode and "Search queries...") or "Search tags...")
    end
    if self.list ~= nil and self.sidebarHeight ~= nil then
        self.list:SetSize(Config.TAG_RAIL_WIDTH - 24, SidebarRows.ListHeight(self.sidebarHeight))
    end
    if self.newTagButton ~= nil and self.newTagButton.root ~= nil then
        self.newTagButton:SetHidden(not tagsMode)
        self.newTagButton:SetSize(
            (editableTag or fixedEditButton) and NEW_TAG_SELECTED_WIDTH or NEW_TAG_FULL_WIDTH,
            FOOTER_BUTTON_HEIGHT
        )
    end
    if self.newQueryButton ~= nil and self.newQueryButton.root ~= nil then
        self.newQueryButton:SetHidden(not runeSQLMode)
        self.newQueryButton:SetSize(
            editableQuery and NEW_TAG_SELECTED_WIDTH or NEW_TAG_FULL_WIDTH,
            FOOTER_BUTTON_HEIGHT
        )
    end
    if self.editButton ~= nil then
        self.editButton:SetHidden(not enabled)
        self.editButton:SetDisabled(not enabled)
        self.editButton:SetSelected(false)
        self.editButton:SetTooltip(fixedEditButton and self.sidebarEditButton.tooltip
            or (editableQuery and "Edit RuneQL query" or "Open layout editor"))
    end
end

-- The sidebar reads these optional fields on its owner:
--   sidebarMode       the selected tab's ID; without it the sidebar shows Tags
--   sidebarLocksMode  show only the Tags tab
--   sidebarSortable   false hides the sort button
--   sidebarEditButton { spriteName, tooltip } replaces the layout pencil with
--                     an always-available footer action that calls onEditLayout

-- Show this sidebar's tabs with the selected one active, and name it above the content
function TagSidebar:UpdateSidebarTabs()
    SidebarFrame.ShowTabs(self, SidebarTabs.Available(self), self:ActiveSidebarTab())
end

-- Build the search, sort control, and rows in a content column of the given height.
-- Row tooltips are placed relative to tooltipParent, the column's own parent
function TagSidebar:CreateSidebarContent(parent, height, tooltipParent)
    self.sidebarHeight = height
    self.search = SidebarRows.CreateSearch(parent, {
        placeholder = "Search tags...",
        text = self.searchQuery,
        onChange = function(_, _, content)
            self.searchQuery = tostring(content or "")
            if self.searchQuery ~= "" and self.tagSortMode then
                self.tagSortMode = false
                self:UpdateTagSortControl()
            end
            self:RefreshTags()
        end,
    })
    self.sortButton = BankControls.button(parent, nil, function()
        self:SetTagSortMode(not self:IsTagSortMode())
    end, {
        x = FOOTER_X + FOOTER_WIDTH - SORT_BUTTON_SIZE,
        y = SEARCH_TOP,
        size = SORT_BUTTON_SIZE,
        iconSize = 18,
        spriteName = "SWAP",
        tooltip = "Sort tags and folders",
    })
    self.emptyLabel = SidebarRows.CreateEmptyLabel(parent,
        "Create a tag, then drag bank items onto it.")
    self.list = SidebarRows.CreateList(parent, height, function(_, tag, selected)
        local folderKey = folderKeyOf(tag)
        if folderKey ~= nil then
            self:ToggleFolder(folderKey)
            return
        end
        if self:IsCleanupMode() and self.cleanupCategories:IsGenerated(tag)
            and self.cleanupCategories:IsRefreshing(tag) then return end
        local nextTag = selected and tag or nil
        if tag == self.selectedTag then nextTag = nil end
        self:SetSelectedTag(nextTag)
    end)
    self.tagTooltipContext = SidebarRows.RegisterTooltips(self.list, tooltipParent)
end

-- Build the footer: Import/Share, New Tag or New Query, and the edit action
function TagSidebar:CreateSidebarFooter(parent, height)
    self.settingsButton = BankControls.button(parent, nil, function()
        if self.onOpenSettings ~= nil then self.onOpenSettings() end
    end, {
        x = FOOTER_X,
        y = height - 36,
        size = SETTINGS_BUTTON_SIZE,
        iconSize = 18,
        spriteName = "EXPORT",
        tooltip = "Import and share bank tags",
    })
    self.newTagButton = BankControls.button(parent, "New Tag", function()
        self:CreatePlaceholderTag(nil, true)
    end, {
        x = NEW_TAG_X,
        y = height - 36,
        width = NEW_TAG_FULL_WIDTH,
        height = FOOTER_BUTTON_HEIGHT,
        tooltip = "Create a new bank tag",
    })
    self.newQueryButton = BankControls.button(parent, "New Query", function()
        if self.onCreateRuneQuery ~= nil then self.onCreateRuneQuery() end
    end, {
        x = NEW_TAG_X,
        y = height - 36,
        width = NEW_TAG_FULL_WIDTH,
        height = FOOTER_BUTTON_HEIGHT,
        tooltip = "Create a RuneQL query",
    })
    self.editButton = BankControls.button(parent, nil, function()
        if self:IsRuneSQLMode() and self:IsRuneQuerySelection() then
            if self.onEditRuneQuery ~= nil then self.onEditRuneQuery(self.selectedTag) end
        elseif self.onEditLayout ~= nil
            and (self.selectedTag ~= nil or self.sidebarEditButton ~= nil) then
            self.onEditLayout(self.selectedTag)
        end
    end, {
        x = EDIT_BUTTON_X,
        y = height - 36,
        size = EDIT_BUTTON_SIZE,
        iconSize = 18,
        spriteName = self.sidebarEditButton ~= nil and self.sidebarEditButton.spriteName or "PENCIL",
        tooltip = self.sidebarEditButton ~= nil and self.sidebarEditButton.tooltip
            or "Edit tag layout",
    })
end

-- Build a framed sidebar of its own at a position in its parent, as the layout editor does
function TagSidebar:CreateRail(parent, height, x, y)
    x = x or 12
    y = y or 44
    SidebarFrame.Create(self, parent, height, x, y, function(tabID) self:SetSidebarMode(tabID) end)
    self:CreateSidebarContent(self.rail, height, parent)
    self:CreateSidebarFooter(self.rail, height)
    self:UpdateLayoutControls()
    if self:IsCleanupMode() then
        self:BeginCleanupRefresh()
    else
        self:RefreshTags()
    end
    SidebarFrame.RaiseEdges(self)
end

-- Destroy the search, sort control, and rows
function TagSidebar:DestroySidebarContent()
    if self.sortButton ~= nil then pcall(function() self.sortButton:Destroy() end) end
    if self.search ~= nil then pcall(function() self.search:Destroy() end) end
    self:DestroyTagSortButtons()
    self:DestroyTagTooltips()
    SidebarRows.UnregisterTooltips(self.list)
    self.tagTooltipContext = nil
    if self.list ~= nil then pcall(function() self.list:Destroy() end) end
    if self.emptyLabel ~= nil then pcall(function() self.emptyLabel:Destroy() end) end
    self.search = nil
    self.list = nil
    self.emptyLabel = nil
    self.tagIcons = nil
    self.sidebarRowStatus = nil
    self.sortButton = nil
    self.tagSortMode = false
    self.sidebarSortPositions = nil
    self.sidebarEntriesByID = nil
    self.sidebarHeight = nil
end

-- Destroy the footer actions
function TagSidebar:DestroySidebarFooter()
    if self.newTagButton ~= nil then pcall(function() self.newTagButton:Destroy() end) end
    if self.newQueryButton ~= nil then pcall(function() self.newQueryButton:Destroy() end) end
    if self.editButton ~= nil then pcall(function() self.editButton:Destroy() end) end
    if self.settingsButton ~= nil then pcall(function() self.settingsButton:Destroy() end) end
    self.newTagButton = nil
    self.newQueryButton = nil
    self.editButton = nil
    self.settingsButton = nil
end

-- Destroy a framed sidebar built by CreateRail
function TagSidebar:DestroyRail()
    self:DestroySidebarFooter()
    self:DestroySidebarContent()
    SidebarFrame.Destroy(self)
end

-- Find the tag-mode row entry currently beneath the pointer
function TagSidebar:HoveredTagRow()
    if not self:IsTagsMode() or not self.expanded or self.list == nil then return nil end
    for _, row in ipairs(self.list.rows or {}) do
        if not isGroupEntry(row.entry) and componentIsMouseOver(row.root) then
            return row.entry
        end
    end
    return nil
end

-- Find the editable tag row currently beneath the pointer
function TagSidebar:HoveredTag()
    local entry = self:HoveredTagRow()
    if entry == nil or folderKeyOf(entry) ~= nil then return nil end
    return entry.id
end

-- Find the folder header currently beneath the pointer
function TagSidebar:HoveredFolder()
    local entry = self:HoveredTagRow()
    return entry ~= nil and folderKeyOf(entry) or nil
end

-- Collapse or expand a folder and rebuild the rows
function TagSidebar:ToggleFolder(folderKey)
    local folder = self.store:GetFolder(folderKey)
    if folder == nil then return false end
    self.store:SetFolderCollapsed(folderKey, not folder.collapsed)
    self:RefreshTags()
    return true
end

-- Find the saved-query row currently beneath the pointer
function TagSidebar:HoveredRuneQuery()
    if not self:IsRuneSQLMode() or not self.expanded or self.list == nil then
        return nil
    end
    for _, row in ipairs(self.list.rows or {}) do
        if not isGroupEntry(row.entry) and row.entry.enabled ~= false
            and componentIsMouseOver(row.root)
            and self:IsRuneQuerySelection(row.entry.id) then
            return row.entry.id
        end
    end
    return nil
end

-- Attach this module's methods to the owner that holds their shared state
function TagSidebar.install(target)
    for name, method in pairs(TagSidebar) do
        if name ~= "install" then target[name] = method end
    end
end

return TagSidebar
