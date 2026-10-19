-- Choose a tag's folder: another folder, a new folder, or none
-- Bank Core menus have no submenus, so folders are listed here

local Text = require("banktags/core/text")
local Theme = require("banktags/ui/theme")

local FolderChooser = {}
FolderChooser.__index = FolderChooser

local WIDTH = 300
local HEIGHT = 380
local MARGIN = 14
local CONTENT_WIDTH = WIDTH - 16
local LIST_TOP = 40
local CREATE_ENTRY = "__banktags_create_folder"
local REMOVE_ENTRY = "__banktags_no_folder"
local FOLDER_PREFIX = "folder:"

-- Create the folder chooser
function FolderChooser.new(parent, options)
    local self = setmetatable({ options = options }, FolderChooser)
    self.window = prettyui.Window.new(parent, {
        title = "Move to Folder",
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
        destroyOnClose = true,
        onClose = function()
            if options.onClose ~= nil then options.onClose() end
        end,
    })
    local content = self.window.content
    self.heading = prettyui.Text.new(content, {
        text = Text.titleCase(options.tag),
        x = MARGIN, y = 8, width = CONTENT_WIDTH - MARGIN * 2, height = 24,
        colour = Theme.HEADING_TEXT, maxLines = 1,
    })
    local entries = {}
    -- Add one choice row
    local function add(entryID, label, colour)
        entries[#entries + 1] = {
            id = entryID, label = label, enabled = true,
            backgroundColour = #entries % 2 == 0 and Theme.ROW_ODD or Theme.ROW_EVEN,
            hoverColour = Theme.ROW_HOVER, selectedColour = Theme.ROW_SELECTED,
            textColour = colour or Theme.TEXT,
        }
    end
    add(CREATE_ENTRY, "Create New Folder...", Theme.HEADING_TEXT)
    if options.current ~= nil then add(REMOVE_ENTRY, "Remove from folder", Theme.HEADING_TEXT) end
    for _, folder in ipairs(options.folders) do
        if folder.key ~= options.current then add(FOLDER_PREFIX .. folder.key, folder.name) end
    end
    self.list = prettyui.List.new(content, {
        x = MARGIN, y = LIST_TOP, width = CONTENT_WIDTH - MARGIN * 2,
        height = HEIGHT - LIST_TOP - 52,
        entryHeight = 30, maxSelected = 1,
        backgroundColour = 0x00000000, borderColour = Theme.INNER_FRAME,
        selectedColour = Theme.ROW_SELECTED,
        _onEntryClick = function(_, entryID) self:Choose(entryID) end,
    })
    self.list:SetEntries(entries)
    return self
end

-- Act on one choice and close the chooser
function FolderChooser:Choose(entryID)
    local options = self.options
    if entryID == CREATE_ENTRY then
        self.window:Close()
        options.onCreate()
    elseif entryID == REMOVE_ENTRY then
        options.onMove(nil)
        self.window:Close()
    elseif string.sub(tostring(entryID), 1, #FOLDER_PREFIX) == FOLDER_PREFIX then
        options.onMove(string.sub(entryID, #FOLDER_PREFIX + 1))
        self.window:Close()
    end
end

-- Show the chooser window
function FolderChooser:Show()
    self.window:Show()
end

-- Destroy the chooser's controls and window
function FolderChooser:Destroy()
    for _, control in ipairs({ self.list, self.heading, self.window }) do
        if control ~= nil then pcall(function() control:Destroy() end) end
    end
    self.list, self.heading, self.window = nil, nil, nil
    self.options = nil
end

return FolderChooser
