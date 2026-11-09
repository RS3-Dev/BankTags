-- Preview imported tags and display share codes

local Config = require("resources/core/config")
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
    self.controls.importTitle = text(importPage.content, "Import bank tags", 0, {
        colour = 0xF2C66DFF,
        font = id.Font.CINZEL_13PT_BOLD,
    })
    -- The input fills in the name, sprite, and folder below
    self.controls.importCodeLabel = text(importPage.content, "Import code", 32, {
        height = 20, maxLines = 1,
    })
    self.importField = prettyui.TextField.new(importPage.content, {
        x = 18,
        y = 56,
        width = 452,
        height = 30,
        maxLength = Config.LONG_INPUT_LIMIT,
        maxLines = 1,
        placeholder = "Paste a shared tag code or backup...",
        font = id.Font.MUSEO_SANS_11PT_REGULAR,
        onChange = function(_, _, content) self:RefreshImportPreview(content) end,
    })
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
        "Each field contains one compact tag group. Click a field, then press Ctrl+A and Ctrl+C.",
        38, { height = 32, maxLines = 2 })
    self:RefreshExports()
    self:RefreshImportPreview("")
    return self
end

-- Show feedback in green, red, or a given colour
function ImportShare:SetPageStatus(control, value, success)
    control.content = tostring(value or "")
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
    local startY = 74
    local rowHeight = 34
    for index, export in ipairs(exports) do
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
            tag = export.tag,
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
    for _, control in ipairs({
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
