-- Edit a tag's name and icon

local objectFromID = require("banktags/core/object_config").FromID
local TagRules = require("banktags/tags/tag_rules")

local TagSettingsEditor = {}
TagSettingsEditor.__index = TagSettingsEditor

local WIDTH = 360
local HEIGHT = 176
local MARGIN = 16
local CONTENT_WIDTH = WIDTH - 16
local CONTROL_WIDTH = CONTENT_WIDTH - MARGIN * 2
local BUTTON_GAP = 8
local BUTTON_WIDTH = math.floor((CONTROL_WIDTH - BUTTON_GAP) / 2)
local SLOT_SIZE = 40
local SLOT_GAP = 8
local FIELD_WIDTH = CONTROL_WIDTH - SLOT_SIZE - SLOT_GAP
local SLOT_X = MARGIN + FIELD_WIDTH + SLOT_GAP

-- Create the tag name and icon editor
function TagSettingsEditor.new(parent, options)
    local self = setmetatable({
        spriteObjectID = options.spriteObjectID,
        onChooseSprite = options.onChooseSprite,
        onSave = options.onSave,
    }, TagSettingsEditor)

    self.window = prettyui.Window.new(parent, {
        title = options.title or "Rename Bank Tag",
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
    })

    local content = self.window.content
    self.nameLabel = prettyui.Text.new(content, {
        text = options.nameLabel or "Tag name",
        x = MARGIN,
        y = 10,
        width = FIELD_WIDTH,
        height = 20,
        colour = 0xF2C66DFF,
    })
    self.field = prettyui.TextField.new(content, {
        x = MARGIN,
        y = 31,
        width = FIELD_WIDTH,
        height = 30,
        text = options.tag or "",
        placeholder = options.nameLabel or "Tag name",
        maxLength = options.maxLength or TagRules.MAX_TAG_NAME,
        onSubmit = function(_, value) self:Save(value) end,
    })
    local selectedObject = objectFromID(self.spriteObjectID)
    self.spriteSlot = prettyui.ItemSlot.new(content, selectedObject, {
        x = SLOT_X,
        y = 26,
        clickthrough = false,
        tooltip = "Click to edit",
    })
    -- Open the item icon picker
    self.spriteSlot.root:Subscribe(ui.Hook.ONCLICK, function()
        if self.onChooseSprite ~= nil then self.onChooseSprite() end
        return false
    end)
    self.status = prettyui.Text.new(content, {
        text = "",
        x = MARGIN,
        y = 70,
        width = CONTROL_WIDTH,
        height = 18,
        colour = 0xE57373FF,
        alignHorizontal = ui.AlignMode.CENTRE,
    })
    self.status.hidden = true
    -- Close the editor without saving its draft
    self.cancelButton = prettyui.SimpleButton.new(content, "Cancel", function()
        self.window:Close()
    end, {
        x = MARGIN,
        y = 96,
        width = BUTTON_WIDTH,
        height = 28,
    })
    -- Save the current name and chosen icon
    self.saveButton = prettyui.SimpleButton.new(content, "Save", function()
        self:Save(self.field:GetText())
    end, {
        x = MARGIN + BUTTON_WIDTH + BUTTON_GAP,
        y = 96,
        width = BUTTON_WIDTH,
        height = 28,
    })
    return self
end

-- Show the chosen icon without saving it yet
function TagSettingsEditor:SetSprite(objectID)
    self.spriteObjectID = math.tointeger(tonumber(objectID))
    self.spriteSlot:SetObject(objectFromID(self.spriteObjectID))
    self.spriteSlot:SetTooltip("Click to edit")
    self.status.hidden = true
end

-- Save the name and icon, showing any problem
function TagSettingsEditor:Save(value)
    if self.onSave == nil then return end
    local success, reason = self.onSave(value, self.spriteObjectID)
    if success then
        self.window:Close()
    else
        self.status.content = tostring(reason or "Could not save the tag.")
        self.status.rgba = 0xE57373FF
        self.status.hidden = false
    end
end

-- Show the editor window
function TagSettingsEditor:Show()
    self.window:Show()
end

-- Destroy the editor controls and window
function TagSettingsEditor:Destroy()
    for _, control in ipairs({
        self.saveButton,
        self.cancelButton,
        self.spriteSlot,
        self.field,
        self.nameLabel,
        self.status,
        self.window,
    }) do
        if control ~= nil then pcall(function() control:Destroy() end) end
    end
    self.saveButton = nil
    self.cancelButton = nil
    self.spriteSlot = nil
    self.field = nil
    self.nameLabel = nil
    self.status = nil
    self.window = nil
    self.onChooseSprite = nil
    self.onSave = nil
end

return TagSettingsEditor
