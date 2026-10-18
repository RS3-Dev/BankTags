-- Present the import-source host and tag sharing controls
-- Sources supply drafts; this window owns preview, destination choices, and the explicit import

local CodeImportSource = require("banktags/windows/code_import_source")
local Config = require("banktags/core/config")
local TagData = require("banktags/tags/tag_data")
local TagRules = require("banktags/tags/tag_rules")
local ItemIdentity = require("banktags/tags/item_identity")

local ImportShare = {}
ImportShare.__index = ImportShare

local WIDTH = 520
local HEIGHT = 520
local CONTENT_WIDTH = WIDTH - 16
-- The tabs fill the window now that the title-bar X is the only close control
local TABS_HEIGHT = 466
local SHARE_PAGE_MIN_HEIGHT = TABS_HEIGHT - 42
local IMPORT_NO_FOLDER = "none"
local IMPORT_NEW_FOLDER = "new"
local IMPORT_FOLDER_PREFIX = "folder:"
-- The source picker leaves room for the selected source's 30px icon
local SOURCE_WIDTH = 414
local INPUT_Y = 122
local FOLDER_NAME_Y = 302
local STATUS_SUCCESS = 0x78C47CFF
local STATUS_ERROR = 0xE57373FF
local STATUS_NEUTRAL = 0xC9BEA4FF

-- Look up an imported tag's icon, allowing unavailable object definitions
local function objectFromID(objectID)
    if objectID == nil then return nil end
    local ok, object = pcall(function() return config.Obj.FromID(objectID) end)
    return ok and object or nil
end

-- Create a settings label with the requested bounds and appearance
local function text(parent, value, y, options)
    options = options or {}
    return prettyui.Text.new(parent, {
        text = value,
        x = options.x or 18,
        y = y,
        width = options.width or 452,
        height = options.height or 24,
        colour = options.colour or 0xC9BEA4FF,
        font = options.font,
        maxLines = options.maxLines or 2,
        alignHorizontal = options.alignHorizontal,
    })
end

-- Count a single tag's items, and those this client cannot resolve
local function countItems(tag)
    local items, unknown = 0, 0
    -- Count one list of slots
    local function count(slots)
        for _, slot in ipairs(slots) do
            if slot.kind == "item" then items = items + 1 end
            if slot.dormant ~= nil then unknown = unknown + 1 end
        end
    end
    for _, entry in ipairs(tag.rows) do
        if entry.kind == "row" then count(entry.slots) end
    end
    count(tag.unsorted)
    return items, unknown
end

-- Describe a readable draft before anything is saved
local function previewMessage(source, imported)
    local tagCount = #imported.order
    if tagCount ~= 1 then
        local message = tostring(tagCount) .. " tags. Original names and sprites kept."
        return source.builtin and ("Backup: " .. message) or message
    end
    local items, unknown = countItems(imported.tags[imported.order[1]])
    local message = "Preview: " .. tostring(items) .. (items == 1 and " item" or " items")
    if unknown > 0 then message = message .. ", " .. tostring(unknown) .. " not recognized" end
    return message .. ". Not saved until you import."
end

-- Create the standalone import and sharing pages
function ImportShare.new(parent, options)
    options = options or {}
    local self = setmetatable({
        options = options,
        controls = {},
        source = CodeImportSource,
        sources = { CodeImportSource },
        closed = false,
    }, ImportShare)

    self.window = prettyui.Window.new(parent, {
        title = "Bank Tag Import / Share",
        x = -math.floor(WIDTH / 2),
        y = -math.floor(HEIGHT / 2),
        xAnchor = 0.5,
        yAnchor = 0.5,
        width = WIDTH,
        height = HEIGHT,
        minWidth = WIDTH,
        maxWidth = WIDTH,
        minHeight = HEIGHT,
        maxHeight = HEIGHT,
        scrollable = false,
        -- A closed window takes no further answers from import sources
        onClose = function()
            self:CancelImportRequest()
            self.closed = true
            if options.onClose ~= nil then options.onClose() end
        end,
    })

    self.tabs = prettyui.Tabs.new(self.window.content, {
        { kind = "text", text = "Import", value = "import" },
        { kind = "text", text = "Share", value = "share", scrollable = true },
    }, {
        x = 0,
        y = 0,
        width = CONTENT_WIDTH,
        height = TABS_HEIGHT,
        scrollable = false,
        tabInset = 4,
    })

    local importPage = self.tabs:GetPage(1)
    self.importPage = importPage
    self.controls.importTitle = text(importPage.content, "Import bank tags", 0, {
        colour = 0xF2C66DFF,
        font = id.Font.CINZEL_13PT_BOLD,
    })
    -- The source comes first because it decides what the input below it means
    self.controls.importSourceLabel = text(importPage.content, "Source", 32, {
        height = 20, maxLines = 1,
    })
    self.importSourcePicker = prettyui.ComboBox.new(importPage.content, {
        x = 18, y = 56, width = SOURCE_WIDTH, height = 30,
        entries = { { id = CodeImportSource.key, label = CodeImportSource.label, order = 1 } },
        selectedID = CodeImportSource.key,
        maxVisibleEntries = 6,
        -- Replacing the entries can report the same selection again, which keeps the input
        onChange = function()
            local key = self.importSourcePicker:GetSelectedID()
            if key ~= self.source.key then self:SelectSource(key) end
        end,
    })
    -- The input comes next because it fills in the name, sprite, and folder below it
    self.controls.importCodeLabel = text(importPage.content, CodeImportSource.prompt, 98, {
        height = 20, maxLines = 1,
    })
    self.importField = prettyui.TextField.new(importPage.content, {
        x = 18,
        y = INPUT_Y,
        width = 452,
        height = 30,
        maxLength = Config.LONG_INPUT_LIMIT,
        maxLines = 1,
        placeholder = CodeImportSource.placeholder,
        font = id.Font.MUSEO_SANS_11PT_REGULAR,
        onChange = function(_, _, content) self:RefreshImportPreview(content) end,
    })
    self.controls.importNameLabel = text(importPage.content, "Tag name", 164, {
        width = 404, height = 20, maxLines = 1,
    })
    self.controls.importSpriteLabel = text(importPage.content, "Sprite", 164, {
        x = 422, width = 48, height = 20, maxLines = 1,
        font = id.Font.MUSEO_SANS_11PT_REGULAR,
        alignHorizontal = ui.AlignMode.CENTRE,
    })
    self.importNameField = prettyui.TextField.new(importPage.content, {
        x = 18, y = 193, width = 404, height = 30,
        placeholder = "Tag name", maxLength = 80, maxLines = 1,
        disabled = true,
    })
    self.importSpriteSlot = prettyui.ItemSlot.new(importPage.content, nil, {
        x = 430, y = 188, clickthrough = false, disabled = true,
        tooltip = "Choose tag sprite",
    })
    self.importSpriteSlot.root:Subscribe(ui.Hook.ONCLICK, function()
        self:ChooseImportSprite()
        return false
    end)
    self.controls.importFolderLabel = text(importPage.content, "Folder", 236, {
        height = 20, maxLines = 1,
    })
    self.importFolder = prettyui.ComboBox.new(importPage.content, {
        x = 18, y = 260, width = 452, height = 30,
        entries = {
            { id = IMPORT_NO_FOLDER, label = "No folder", order = 1 },
            { id = IMPORT_NEW_FOLDER, label = "New folder...", order = 2 },
        },
        selectedID = IMPORT_NO_FOLDER,
        disabled = true,
        maxVisibleEntries = 6,
        onChange = function() self:UpdateImportFolderControls() end,
    })
    self.importFolderName = prettyui.TextField.new(importPage.content, {
        x = 18, y = FOLDER_NAME_Y, width = 452, height = 30,
        placeholder = "New folder name", maxLength = TagRules.MAX_FOLDER_NAME,
        maxLines = 1, disabled = true,
    })
    self.importFolderName.root.hidden = true
    self.importButton = prettyui.SimpleButton.new(importPage.content, "Import tags", function()
        self:Import()
    end, {
        x = 18,
        y = FOLDER_NAME_Y,
        width = 452,
        height = 28,
    })
    self.importStatus = text(importPage.content, "", FOLDER_NAME_Y + 36, {
        width = 452,
        height = 36,
        maxLines = 2,
        alignHorizontal = ui.AlignMode.CENTRE,
    })
    self.importStatus.hidden = true

    local sharePage = self.tabs:GetPage(2)
    self.sharePage = sharePage
    self.shareRows = {}
    self.controls.shareTitle = text(sharePage.content, "Share tag layouts", 12, {
        colour = 0xF2C66DFF,
        font = id.Font.CINZEL_13PT_BOLD,
    })
    self.controls.shareCopy = text(sharePage.content,
        "Each field contains one compact tag group. Click a field, then press Ctrl+A and Ctrl+C.",
        38, { height = 32, maxLines = 2 })
    self:RebuildShareRows(options.tagExports or {})
    self:RefreshSources()
    self:SelectSource(CodeImportSource.key)
    return self
end

-- Find a listed import source by key
function ImportShare:FindSource(key)
    for _, source in ipairs(self.sources) do
        if source.key == key then return source end
    end
    return nil
end

-- List the share code first, then registered sources, keeping the selection when it remains
function ImportShare:RefreshSources()
    if self.closed or self.window == nil then return end
    local sources = { CodeImportSource }
    local providers = self.options.importProviders
    for _, source in ipairs(providers ~= nil and providers:Sources() or {}) do
        sources[#sources + 1] = source
    end
    -- The picker needs distinct labels, so a repeated label names its owner
    local entries, used = {}, {}
    for index, source in ipairs(sources) do
        local label = source.label
        if used[label] then label = label .. " (" .. source.ownerLabel .. ")" end
        if used[label] then label = label .. " " .. source.key end
        used[label] = true
        entries[index] = { id = source.key, label = label, order = index }
    end
    self.sources = sources
    local current = self.source
    local listed = self:FindSource(current.key)
    self.importSourcePicker:SetEntries(entries, listed ~= nil and current.key or CodeImportSource.key)
    -- A removed source falls back to the share code; a changed one asks again
    if listed == nil then
        self:SelectSource(CodeImportSource.key)
    elseif listed.revision ~= current.revision then
        self:SelectSource(listed.key, self.importSource)
    end
end

-- Show one source's input, dropping any outstanding request and the previous draft
function ImportShare:SelectSource(key, input)
    if self.closed then return end
    local source = self:FindSource(key) or CodeImportSource
    self:CancelImportRequest()
    self.source = source
    if self.importSourcePicker:GetSelectedID() ~= source.key then
        self.importSourcePicker:Select(source.key, false)
    end
    local content = self.importPage.content
    if self.importSourceIcon ~= nil then pcall(function() self.importSourceIcon:Destroy() end) end
    self.importSourceIcon = nil
    if source.icon ~= nil then
        self.importSourceIcon = prettyui.SpriteButton.new(content, source.icon, nil, {
            x = SOURCE_WIDTH + 26, y = 56, size = 30, tooltip = source.label,
        })
    end
    if self.importActionButton ~= nil then pcall(function() self.importActionButton:Destroy() end) end
    self.importActionButton = nil
    self.controls.importCodeLabel.content = source.prompt or source.label
    local usable = source.unavailable == nil
    self.importField.root.hidden = source.input ~= "text"
    self.importField:SetDisabled(not usable)
    self.importField:SetPlaceholder(source.placeholder or "")
    input = source.input == "text" and tostring(input or "") or ""
    self.importField:SetText(input, false)
    if source.input == "action" then
        self.importActionButton = prettyui.SimpleButton.new(content, source.actionLabel or "Choose...",
            function() self:RequestImport() end, { x = 18, y = INPUT_Y, width = 452, height = 28 })
        self.importActionButton:SetDisabled(not usable)
    end
    self.importSource = nil
    self:RefreshImportPreview(input)
end

-- Read the current input through the selected source without saving anything
function ImportShare:RefreshImportPreview(input)
    input = tostring(input or "")
    if self.closed or input == self.importSource then return end
    self.importSource = input
    self:CancelImportRequest()
    local source = self.source
    if source.unavailable ~= nil then
        self:ShowImportResult("unavailable", source.unavailable)
    elseif source.input ~= "text" or string.match(input, "%S") == nil then
        self:ShowImportResult("empty")
    elseif source.builtin then
        self:ShowImportResult("ready", source.Read(input))
    else
        self:BeginImportRequest(input)
    end
end

-- Ask an action source to run its own flow and answer with a draft
function ImportShare:RequestImport()
    if self.closed or self.source.input ~= "action" or self.source.unavailable ~= nil then return end
    self:CancelImportRequest()
    self:BeginImportRequest(nil)
end

-- Ask the selected registered source for a draft. Every change of source or input and
-- closing the window cancel it, and a cancelled request never answers
function ImportShare:BeginImportRequest(input)
    local token = self.options.importProviders:Begin(self.source.key, input, function(state, value)
        self.importRequest = nil
        self:ShowImportResult(state, value)
    end)
    if token == nil then
        self:ShowImportResult("unavailable", "This source is unavailable right now.")
        return
    end
    self.importRequest = token
    self:ShowImportResult("loading")
end

-- Drop the outstanding source request so its answer is ignored
function ImportShare:CancelImportRequest()
    local token = self.importRequest
    self.importRequest = nil
    if token ~= nil then self.options.importProviders:Cancel(token) end
end

-- Show one import state; only a readable draft fills the destination and enables Import
function ImportShare:ShowImportResult(state, value)
    local imported, reason = nil, value
    if state == "ready" then
        imported, reason = TagData.Decode(value)
        if imported == nil then state = "invalid" end
    end
    self.importState = state
    self.importRevision = (self.importRevision or 0) + 1
    self.importText = imported ~= nil and value or nil
    self.importData = imported
    local tag = imported ~= nil and #imported.order == 1 and imported.order[1] or nil
    self.importSingleTag = tag
    self.importNameField:SetText(tag or "", false)
    self.importNameField:SetDisabled(tag == nil)
    self.importSpriteSlot:SetDisabled(tag == nil)
    self:SetImportSprite(tag ~= nil and ItemIdentity.ObjectID(imported.tags[tag].icon) or nil)
    self.importFolderName:SetText("", false)
    local folderKey = tag ~= nil and imported.tags[tag].folder or nil
    self:RefreshImportFolders(folderKey ~= nil and IMPORT_FOLDER_PREFIX .. folderKey or IMPORT_NO_FOLDER)
    self.importButton:SetDisabled(imported == nil)
    if state == "empty" then
        self:SetPageStatus(self.importStatus, nil, true)
    elseif state == "loading" then
        self:SetPageStatus(self.importStatus, "Loading from " .. self.source.label .. "...", STATUS_NEUTRAL)
    elseif state == "unavailable" then
        self:SetPageStatus(self.importStatus, reason, STATUS_NEUTRAL)
    elseif imported == nil then
        self:SetPageStatus(self.importStatus, reason, false)
    else
        self:SetPageStatus(self.importStatus, previewMessage(self.source, imported), true)
    end
end

-- List saved folders and any folder supplied by the single-tag import
function ImportShare:RefreshImportFolders(selectedID)
    selectedID = selectedID or self.importFolder:GetSelectedID() or IMPORT_NO_FOLDER
    local entries = { { id = IMPORT_NO_FOLDER, label = "No folder", order = 1 } }
    local available = { [IMPORT_NO_FOLDER] = true, [IMPORT_NEW_FOLDER] = true }
    local folders = self.options.onGetFolders ~= nil and self.options.onGetFolders() or {}
    local function addFolder(key, name)
        local entryID = IMPORT_FOLDER_PREFIX .. key
        if available[entryID] then return end
        available[entryID] = true
        entries[#entries + 1] = { id = entryID, label = name, order = #entries + 1 }
    end
    for _, folder in ipairs(folders) do addFolder(folder.key, folder.name) end
    if self.importSingleTag ~= nil then
        local key = self.importData.tags[self.importSingleTag].folder
        local folder = key ~= nil and self.importData.folders[key] or nil
        if folder ~= nil then addFolder(key, folder.name) end
    end
    entries[#entries + 1] = { id = IMPORT_NEW_FOLDER, label = "New folder...", order = #entries + 1 }
    self.importFolder:SetEntries(entries, available[selectedID] and selectedID or IMPORT_NO_FOLDER)
    self.importFolder:SetDisabled(self.importSingleTag == nil)
    self:UpdateImportFolderControls()
end

-- Show a new-folder draft only when requested and keep the import action below it
function ImportShare:UpdateImportFolderControls()
    if self.importFolderName == nil then return end
    local creating = self.importSingleTag ~= nil
        and self.importFolder:GetSelectedID() == IMPORT_NEW_FOLDER
    self.importFolderName.root.hidden = not creating
    self.importFolderName:SetDisabled(not creating)
    local buttonY = creating and FOLDER_NAME_Y + 42 or FOLDER_NAME_Y
    self.importButton.root:SetPos(18, buttonY)
    self.importStatus:SetPos(18, buttonY + 36)
end

-- Change only the imported draft's icon and its preview
function ImportShare:SetImportSprite(objectID)
    self.importSpriteObjectID = math.tointeger(tonumber(objectID))
    self.importSpriteSlot:SetObject(objectFromID(self.importSpriteObjectID))
end

-- Ignore picker results when the draft has changed since the picker opened
function ImportShare:ChooseImportSprite()
    if self.closed or self.importSingleTag == nil or self.options.onChooseImportSprite == nil then return end
    local revision = self.importRevision
    self.options.onChooseImportSprite(function(objectID)
        if self.importRevision == revision then self:SetImportSprite(objectID) end
    end)
end

-- Display feedback in green for success, red for failure, or a given colour
function ImportShare:SetPageStatus(control, value, success)
    control.content = tostring(value or "")
    control.rgba = success == true and STATUS_SUCCESS or success == false and STATUS_ERROR or success
    control.hidden = value == nil or value == ""
end

-- Remove export-row controls before rebuilding the sharing list
function ImportShare:DestroyShareRows()
    for index = #self.shareRows, 1, -1 do
        local row = self.shareRows[index]
        if row.field ~= nil then pcall(function() row.field:Destroy() end) end
        if row.root ~= nil then pcall(function() row.root:Destroy() end) end
    end
    self.shareRows = {}
end

-- Create rows that let the user copy each tag's export text
function ImportShare:RebuildShareRows(exports)
    self:DestroyShareRows()
    local startY = 74
    local rowHeight = 34
    for index, export in ipairs(exports or {}) do
        local root = ui.Layer.new(self.sharePage.content)
        root:SetPos(18, startY + (index - 1) * rowHeight)
        root:SetSize(452, 30)
        root.clickthrough = true
        local label = prettyui.Text.new(root, {
            text = export.tag,
            x = 0,
            y = 0,
            width = 202,
            height = 28,
            colour = export.value ~= nil and 0xD8CCAEFF or 0xE57373FF,
            maxLines = 1,
            alignVertical = ui.AlignMode.CENTRE,
            tooltip = export.reason,
        })
        local value = export.value or tostring(export.reason or "Unavailable")
        local tooLarge = #value > Config.LONG_INPUT_LIMIT
        if tooLarge then
            value = "Too large for the game field (" .. tostring(#value) .. " characters)"
            label.rgba = 0xE57373FF
        end
        local field = prettyui.TextField.new(root, {
            x = 210,
            y = 1,
            width = 242,
            height = 27,
            maxLength = Config.LONG_INPUT_LIMIT,
            maxLines = 1,
            font = id.Font.MUSEO_SANS_11PT_REGULAR,
            text = value,
        })
        self.shareRows[#self.shareRows + 1] = {
            root = root,
            label = label,
            field = field,
        }
    end
    if #self.shareRows == 0 then
        local empty = text(self.sharePage.content, "No bank tags to share.", startY + 10, {
            x = 18,
            width = 452,
            height = 28,
            alignHorizontal = ui.AlignMode.CENTRE,
            colour = 0x9F947BFF,
        })
        self.shareRows[1] = { root = empty }
    end
    self.sharePage:SetContentHeight(math.max(SHARE_PAGE_MIN_HEIGHT,
        startY + #self.shareRows * rowHeight + 8))
end

-- Reload export text and refresh the sharing controls
function ImportShare:RefreshExports()
    if self.options.onGetTagExports == nil then return end
    self:RebuildShareRows(self.options.onGetTagExports())
end

-- Save the current readable draft with the chosen destination and display the result
function ImportShare:Import()
    if self.closed or self.options.onImport == nil then return end
    if self.source.builtin then
        local source = self.importField:GetText()
        if source ~= self.importSource then self:RefreshImportPreview(source) end
    end
    -- Only a readable draft from the current source and input can be saved
    if self.importState ~= "ready" then return end
    local overrides = self.importSingleTag ~= nil and {
        name = self.importNameField:GetText(),
        spriteObjectID = self.importSpriteObjectID,
    } or nil
    if overrides ~= nil then
        local selected = self.importFolder:GetSelectedID()
        if selected == IMPORT_NEW_FOLDER then
            overrides.newFolderName = self.importFolderName:GetText()
        elseif selected == IMPORT_NO_FOLDER then
            overrides.folderKey = false
        elseif selected ~= nil then
            overrides.folderKey = string.sub(selected, #IMPORT_FOLDER_PREFIX + 1)
        end
    end
    local saved, summary, reason = self.options.onImport(self.importText, overrides)
    if not saved then
        self:SetPageStatus(self.importStatus, reason or "Could not import the tags.", false)
        return
    end
    self:RefreshExports()
    self:RefreshImportFolders()
    local count = summary.tags or 0
    local message = "Imported " .. tostring(count) .. (count == 1 and " tag." or " tags.")
    self:SetPageStatus(self.importStatus, message, true)
end

-- Retain the previous save entry point as a close action; imports commit independently
function ImportShare:Save()
    self.window:Close()
end

-- Show the existing editor window
function ImportShare:Show()
    self.window:Show()
end

-- Destroy settings pages and controls before releasing the window
function ImportShare:Destroy()
    self:CancelImportRequest()
    self.closed = true
    self.importRevision = (self.importRevision or 0) + 1
    self.importData = nil
    self.importText = nil
    self:DestroyShareRows()
    for _, control in pairs(self.controls) do
        if control ~= nil then pcall(function() control:Destroy() end) end
    end
    for _, control in ipairs({
        self.importSourcePicker,
        self.importSourceIcon,
        self.importActionButton,
        self.importField,
        self.importNameField,
        self.importSpriteSlot,
        self.importFolder,
        self.importFolderName,
        self.importButton,
        self.importStatus,
        self.tabs,
        self.window,
    }) do
        if control ~= nil then pcall(function() control:Destroy() end) end
    end
    self.controls = {}
    self.window = nil
end

return ImportShare
