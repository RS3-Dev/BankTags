-- Preview imported tags and display share codes

local Config = require("resources/core/config")
local Text = require("resources/core/text")
local TagRules = require("resources/tags/tag_rules")

local Draft = require("resources/windows/import_share_draft")

local ImportShare = {}
ImportShare.__index = ImportShare
for name, method in pairs(Draft.methods) do ImportShare[name] = method end

local WIDTH = 520
local HEIGHT = 520
local CONTENT_WIDTH = WIDTH - 16
-- The tabs fill the window below the title bar
local TABS_HEIGHT = 466
local SHARE_PAGE_MIN_HEIGHT = TABS_HEIGHT - 42
local IMPORT_NO_FOLDER, IMPORT_NEW_FOLDER = Draft.NO_FOLDER, Draft.NEW_FOLDER
local FOLDER_NAME_Y = Draft.FOLDER_NAME_Y
local STATUS_SUCCESS = 0x78C47CFF
local STATUS_ERROR = 0xE57373FF

-- Create a settings label
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

-- Create the import and sharing pages
function ImportShare.new(parent, options)
    local self = setmetatable({
        options = options,
        controls = {},
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
        -- Mark the window closed and notify its owner
        onClose = function()
            self.closed = true
            options.onClose()
        end,
    })

    self.tabs = prettyui.Tabs.new(self.window.content, {
        { kind = "text", text = "Import", value = "import", scrollable = true },
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
    self.controls.importTitle = text(importPage.content, "Import bank tags", 0, {
        colour = 0xF2C66DFF,
        font = id.Font.CINZEL_13PT_BOLD,
    })
    -- The input fills in the name, sprite, and folder below
    self.controls.importCodeLabel = text(importPage.content, "Import code", 32, {
        height = 20, maxLines = 1,
    })
    self.importPage = importPage
    self.importFields = {}
    self:AddImportField()
    self.controls.importNameLabel = text(importPage.content, "Tag name", 98, {
        width = 404, height = 20, maxLines = 1,
    })
    self.controls.importSpriteLabel = text(importPage.content, "Sprite", 98, {
        x = 422, width = 48, height = 20, maxLines = 1,
        font = id.Font.MUSEO_SANS_11PT_REGULAR,
        alignHorizontal = ui.AlignMode.CENTRE,
    })
    self.importNameField = prettyui.TextField.new(importPage.content, {
        x = 18, y = 127, width = 404, height = 30,
        placeholder = "Tag name", maxLength = 80, maxLines = 1,
        disabled = true,
        onChange = function(field, _, value) Text.cleanField(field, value) end,
    })
    self.importSpriteSlot = prettyui.ItemSlot.new(importPage.content, nil, {
        x = 430, y = 122, clickthrough = false, disabled = true,
        tooltip = "Choose tag sprite",
    })
    -- Choose an icon for the current import draft
    self.importSpriteSlot.root:Subscribe(ui.Hook.ONCLICK, function()
        self:ChooseImportSprite()
        return false
    end)
    self.controls.importFolderLabel = text(importPage.content, "Folder", 170, {
        height = 20, maxLines = 1,
    })
    self.importFolder = prettyui.ComboBox.new(importPage.content, {
        x = 18, y = 194, width = 452, height = 30,
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
        onChange = function(field, _, value) Text.cleanField(field, value) end,
    })
    self.importFolderName.root.hidden = true
    -- Import the preview after the player's explicit choice
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
        "Click a code field.",
        38, { height = 18, maxLines = 1, font = id.Font.MUSEO_SANS_11PT_REGULAR })
    self.controls.shareCopyShortcut = text(sharePage.content,
        "Ctrl+A, Ctrl+C to copy. Copy numbered parts in order.",
        56, { height = 18, maxLines = 1, font = id.Font.MUSEO_SANS_11PT_REGULAR })
    self:RefreshExports()
    self:RefreshImportInputs()
    return self
end

-- Add a continuation field when the previous input reaches the game limit.
function ImportShare:AddImportField()
    local index = #self.importFields + 1
    local field = prettyui.TextField.new(self.importPage.content, {
        x = 18, y = 56 + (index - 1) * 38, width = 452, height = 30,
        maxLength = Config.LONG_INPUT_LIMIT, maxLines = 1,
        placeholder = index == 1 and "Paste a shared tag code or backup..."
            or "Paste the next part of the import code...",
        font = id.Font.MUSEO_SANS_11PT_REGULAR,
        onChange = function(field, _, content)
            Text.cleanField(field, content)
            self:RefreshImportInputs()
        end,
    })
    self.importFields[index] = field
end

-- Join the input parts without inserting separators or trimming their contents.
function ImportShare:GetImportText()
    local parts = {}
    for index, field in ipairs(self.importFields) do
        parts[index] = Text.cleanField(field, field:GetText())
    end
    return table.concat(parts)
end

-- Keep a spare input after a full field and move the draft below all parts.
function ImportShare:RefreshImportInputs()
    if self.closed then return end
    local input = self:GetImportText()
    local fields = self.importFields
    while #fields > 1 and fields[#fields]:GetText() == ""
        and #fields[#fields - 1]:GetText() < Config.LONG_INPUT_LIMIT do
        fields[#fields]:Destroy()
        table.remove(fields)
    end
    if #fields[#fields]:GetText() >= Config.LONG_INPUT_LIMIT then self:AddImportField() end
    self.importInputOffset = (#fields - 1) * 38
    local offset = self.importInputOffset
    self.controls.importNameLabel:SetPos(18, 98 + offset)
    self.controls.importSpriteLabel:SetPos(422, 98 + offset)
    self.importNameField.root:SetPos(18, 127 + offset)
    self.importSpriteSlot.root:SetPos(430, 122 + offset)
    self.controls.importFolderLabel:SetPos(18, 170 + offset)
    self.importFolder.root:SetPos(18, 194 + offset)
    self.importFolderName.root:SetPos(18, FOLDER_NAME_Y + offset)
    self:UpdateImportFolderControls()
    self:RefreshImportPreview(input)
end

-- Show feedback in green, red, or a given colour
function ImportShare:SetPageStatus(control, value, success)
    control.content = Text.plain(value)
    control.rgba = success and STATUS_SUCCESS or STATUS_ERROR
    control.hidden = value == nil or value == ""
end

-- Remove the share rows before rebuilding them
function ImportShare:DestroyShareRows()
    for index = #self.shareRows, 1, -1 do
        local row = self.shareRows[index]
        if row.field ~= nil then pcall(function() row.field:Destroy() end) end
        if row.root ~= nil then pcall(function() row.root:Destroy() end) end
    end
    self.shareRows = {}
end

-- Create a row to copy each tag's share code
function ImportShare:RebuildShareRows(exports)
    self:DestroyShareRows()
    local startY = 82
    local rowHeight = 34
    for _, export in ipairs(exports) do
        local value = Text.sanitize(export.value or tostring(export.reason or "Unavailable"))
        local partCount = math.max(1, math.ceil(#value / Config.LONG_INPUT_LIMIT))
        for part = 1, partCount do
            local root = ui.Layer.new(self.sharePage.content)
            root:SetPos(18, startY + #self.shareRows * rowHeight)
            root:SetSize(452, 30)
            root.clickthrough = true
            local name = Text.plain(export.name or export.tag)
            if partCount > 1 then name = name .. " (" .. part .. "/" .. partCount .. ")" end
            local label = prettyui.Text.new(root, {
                text = name,
                x = 0,
                y = 0,
                width = 202,
                height = 28,
                colour = export.value ~= nil and 0xD8CCAEFF or 0xE57373FF,
                maxLines = 1,
                alignVertical = ui.AlignMode.CENTRE,
                tooltip = export.reason ~= nil and Text.plain(export.reason) or name,
            })
            -- Keep each copyable part within the game field's limit.
            local start = (part - 1) * Config.LONG_INPUT_LIMIT + 1
            local field = prettyui.TextField.new(root, {
                x = 210,
                y = 1,
                width = 242,
                height = 27,
                maxLength = Config.LONG_INPUT_LIMIT,
                maxLines = 1,
                font = id.Font.MUSEO_SANS_11PT_REGULAR,
                text = string.sub(value, start, start + Config.LONG_INPUT_LIMIT - 1),
            })
            self.shareRows[#self.shareRows + 1] = {
                tag = export.tag,
                root = root,
                label = label,
                field = field,
            }
        end
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

-- Reload share codes and refresh the sharing rows
function ImportShare:RefreshExports()
    self:RebuildShareRows(self.options.onGetTagExports())
end

-- Show the window
function ImportShare:Show()
    self.window:Show()
end

-- Destroy the pages and controls before the window
function ImportShare:Destroy()
    self.closed = true
    self.importRevision = (self.importRevision or 0) + 1
    self.importData = nil
    self.importText = nil
    self:DestroyShareRows()
    for _, control in pairs(self.controls) do
        if control ~= nil then pcall(function() control:Destroy() end) end
    end
    for _, field in ipairs(self.importFields) do field:Destroy() end
    self.importFields = {}
    for _, control in ipairs({
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
