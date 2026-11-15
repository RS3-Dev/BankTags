-- Own Bank Tags' standalone windows, closing most with the bank

local ConfirmWindow = require("resources/windows/confirm_window")
local debugLog = require("resources/core/debug_log").Write
local ImportShare = require("resources/windows/import_share")
local LayoutEditorWindow = require("resources/windows/layout_editor_window")
local SpritePicker = require("resources/windows/sprite_picker")
local TagRules = require("resources/tags/tag_rules")
local TagSettingsEditor = require("resources/windows/tag_settings_editor")
local TextPrompt = require("resources/ui/text_prompt")

local Windows = {}
Windows.__index = Windows

-- Windows that close with the bank
local BANK_WINDOWS = { "textPrompt", "layoutEditor", "tagSettingsEditor", "tagDeleteConfirm", "rowRemoveConfirm" }
-- Windows kept in front of the layout editor, the last frontmost
local EDITOR_OVERLAYS = { "tagSettingsEditor", "spritePicker", "textPrompt", "rowRemoveConfirm" }

-- Find the layer standalone windows open on
local function windowParent()
    return ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__BANK_LAYER)
        or ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__GAME_AREA)
end

-- Create an empty window collection for an app
function Windows.new(app)
    return setmetatable({ app = app }, Windows)
end

-- Close one window and the sprite picker it owns
function Windows:Close(name)
    local window = self[name]
    if window == nil then return end
    self[name] = nil
    if name == "spritePicker" then
        self.spritePickerOwner = nil
    elseif self.spritePickerOwner == window then
        self:Close("spritePicker")
    end
    pcall(function() window:Destroy() end)
    self:SyncEditorOverlays()
end

-- Keep editor dialogs and the tutorial in front
function Windows:SyncEditorOverlays()
    if self.layoutEditor == nil then return end
    local overlays = {}
    for _, name in ipairs(EDITOR_OVERLAYS) do
        if self[name] ~= nil then overlays[#overlays + 1] = self[name].window end
    end
    local tutorial = self.app.tutorial
    local guideLayer = tutorial ~= nil and tutorial.active and tutorial.root or nil
    self.layoutEditor:SetOverlays(overlays, guideLayer)
end

-- Close every window that needs the open bank; Import/Share stays
function Windows:CloseBankWindows()
    for _, name in ipairs(BANK_WINDOWS) do self:Close(name) end
end

-- Close every window
function Windows:CloseAll()
    self:CloseBankWindows()
    self:Close("importShare")
    self:Close("spritePicker")
end

-- Find the window layer, logging when there is none
local function parentFor(label)
    local parent = windowParent()
    if parent == nil then debugLog("Bank Tags could not find a UI layer for ", label) end
    return parent
end

-- Open a single-field prompt, replacing any open one
function Windows:OpenTextPrompt(options)
    self:Close("textPrompt")
    local parent = parentFor("its prompt")
    if parent == nil then return end
    self.textPrompt = TextPrompt.new(parent, options)
    self.textPrompt:Show()
end

-- Ask for a folder name and file the tag
function Windows:OpenCreateFolderPrompt(tag)
    local app = self.app
    self:OpenTextPrompt({
        title = "Create Folder",
        heading = "Folder name",
        placeholder = "Folder name",
        maxLength = TagRules.MAX_FOLDER_NAME,
        saveLabel = "Create",
        -- Save the entered name only when accepted
        onSave = function(value)
            -- Save folder creation and expansion together
            local saved, reason = app.store:SaveTogether(function()
                local created, folderKey, problem = app.store:CreateFolder(value, tag)
                if not created then return false, problem end
                return app.store:SetFolderCollapsed(folderKey, false)
            end)
            if not saved then return false, reason end
            app:Changed()
            return true, nil
        end,
    })
    if self.textPrompt ~= nil then self.textPrompt.folderTag = tag end
end

-- Edit a folder's name and item icon
function Windows:OpenRenameFolderPrompt(folderKey)
    local app = self.app
    local folder = app.store:GetFolder(folderKey)
    if folder == nil then return end
    self:Close("tagSettingsEditor")
    local parent = parentFor("the folder settings editor")
    if parent == nil then return end
    local editor
    editor = TagSettingsEditor.new(parent, {
        title = "Rename Folder",
        nameLabel = "Folder name",
        tag = folder.name,
        spriteObjectID = app.store:GetFolderSprite(folderKey),
        maxLength = TagRules.MAX_FOLDER_NAME,
        -- Open a picker only for this settings editor
        onChooseSprite = function()
            if self.tagSettingsEditor ~= editor then return end
            self:OpenSpritePicker(editor, function(result) editor:SetSprite(result.objectId) end)
        end,
        -- Save the folder's chosen name and icon
        onSave = function(value, spriteObjectID)
            local saved, _, reason = app.store:RenameFolder(folderKey, value, spriteObjectID)
            if not saved then return false, reason end
            app:Changed()
            return true, nil
        end,
    })
    self.tagSettingsEditor = editor
    editor:Show()
    self:SyncEditorOverlays()
end

-- Ask for a label's text over the layout editor
function Windows:OpenPageLabelPrompt(options)
    self:OpenTextPrompt({
        title = options.text ~= nil and "Edit Label" or "Add Label",
        heading = "Label text",
        text = options.text or "",
        placeholder = "e.g. Weapons",
        maxLength = TagRules.MAX_LABEL_TEXT,
        saveLabel = options.text ~= nil and "Save" or "Add",
        -- Save the entered name only when accepted
        onSave = function(value)
            if string.match(value, "%S") == nil then return false, "Enter the label text." end
            return options.onSave(value)
        end,
        onDelete = options.onDelete,
    })
    self:SyncEditorOverlays()
end

-- Return the open bank's bounds and grid columns, or nil
function Windows:BankBounds()
    local ext = self.app.ext
    return ext ~= nil and ext:GetBankBounds() or nil
end

-- Open the layout editor sized to the bank
function Windows:OpenLayoutEditor(tag)
    local app = self.app
    local bounds = self:BankBounds()
    if type(tag) ~= "string" or tag == "" or bounds == nil then return end
    self:Close("layoutEditor")
    local parent = parentFor("the layout editor")
    if parent == nil then return end
    local editor
    editor = LayoutEditorWindow.new(parent, {
        store = app.store,
        settings = function() return app.settings end,
        tag = tag,
        columns = bounds.columns,
        bounds = bounds,
        bankItems = app:BankItems(),
        onChanged = function(changedTag) app:Changed(changedTag) end,
        onBankCheck = function() self:CheckBankBounds() end,
        onPromptLabel = function(options) self:OpenPageLabelPrompt(options) end,
        onConfirmRemoveRow = function(options) self:OpenRowRemoveConfirm(options) end,
        -- Close pending row and label dialogs with their editor
        onClose = function(value)
            if self.layoutEditor == value then self.layoutEditor = nil end
            self:Close("textPrompt")
            self:Close("rowRemoveConfirm")
        end,
    })
    self.layoutEditor = editor
    editor:Show()
    self:SyncEditorOverlays()
end

-- Keep a renamed tag open in the layout editor
function Windows:TagRenamed(oldTag, newTag)
    if self.layoutEditor ~= nil then self.layoutEditor:TagRenamed(oldTag, newTag) end
end

-- Follow the bank and reopen the editor after resizing
function Windows:CheckBankBounds()
    local editor = self.layoutEditor
    local bounds = editor ~= nil and self:BankBounds() or nil
    if bounds == nil then return end
    if editor:FitsBank(bounds.columns, bounds) then
        editor:MoveTo(bounds)
    else
        self:OpenLayoutEditor(editor.selectedTag)
    end
end

-- Give an open layout editor the bank's latest items
function Windows:BankItemsChanged()
    if self.layoutEditor ~= nil then self.layoutEditor:SetBankItems(self.app:BankItems()) end
end

-- Refresh relevant editor items and share codes
function Windows:StoreChanged(tag)
    if self.layoutEditor ~= nil then self.layoutEditor:StoreChanged(tag) end
    if self.importShare ~= nil then self.importShare:RefreshExports() end
end

-- Open the tag deletion dialog
function Windows:OpenTagDeleteConfirm(tag)
    local app = self.app
    self:Close("tagDeleteConfirm")
    local parent = parentFor("delete confirmation")
    if parent == nil then return end
    self.tagDeleteConfirm = ConfirmWindow.new(parent, {
        title = "Delete Bank Tag",
        messageLines = {
            "You are about to delete " .. tostring(tag) .. ".",
            "Do you want to continue?",
        },
        confirmLabel = "Delete",
        failureText = "Could not delete the tag.",
        -- Delete the tag and refresh its views
        onConfirm = function()
            local saved, reason = app.store:DeleteTag(tag)
            if not saved then return false, reason end
            app:Changed()
            return true, nil
        end,
    })
    self.tagDeleteConfirm:Show()
end

-- Ask before removing a populated editor row
function Windows:OpenRowRemoveConfirm(options)
    self:Close("rowRemoveConfirm")
    local parent = parentFor("row removal confirmation")
    if parent == nil then return end
    self.rowRemoveConfirm = ConfirmWindow.new(parent, {
        title = "Remove Row",
        message = options.message,
        confirmLabel = "Remove",
        failureText = "Could not remove the row.",
        onConfirm = options.onConfirm,
    })
    self.rowRemoveConfirm:Show()
    self:SyncEditorOverlays()
end

-- Open the sprite picker for the window that asked
function Windows:OpenSpritePicker(owner, onSelected)
    self:Close("spritePicker")
    local parent = parentFor("the sprite picker")
    if parent == nil then return end
    self.spritePickerOwner = owner
    self.spritePicker = SpritePicker.new(parent, {
        bankItems = function() return self.app:BankItems() end,
        -- Apply the icon only to the picker owner
        onSelect = function(result)
            if self.spritePickerOwner == owner then onSelected(result) end
        end,
    })
    self.spritePicker:Show()
    self:SyncEditorOverlays()
end

-- Open tag settings for an existing or new tag
function Windows:OpenTagSettings(tag, isNew, onSaved)
    local app = self.app
    self:Close("tagSettingsEditor")
    local parent = parentFor("the tag settings editor")
    if parent == nil then return end
    local editor
    editor = TagSettingsEditor.new(parent, {
        title = isNew and "Create Bank Tag" or "Rename Bank Tag",
        tag = tag,
        spriteObjectID = not isNew and app.store:GetTagSprite(tag) or nil,
        -- Open a picker only for this settings editor
        onChooseSprite = function()
            if self.tagSettingsEditor ~= editor then return end
            self:OpenSpritePicker(editor, function(result) editor:SetSprite(result.objectId) end)
        end,
        -- Create or rename the tag with its chosen icon
        onSave = function(newName, spriteObjectID)
            local saved, finalName, reason
            if isNew then
                saved, finalName, reason = app.store:CreateTag(newName, spriteObjectID)
            else
                saved, finalName, reason = app.store:UpdateTag(tag, newName, spriteObjectID)
            end
            if not saved then return false, reason end
            if isNew then app:Changed() else app:Renamed(tag, finalName) end
            if onSaved ~= nil then onSaved(finalName) end
            return true, nil
        end,
    })
    self.tagSettingsEditor = editor
    editor:Show()
    self:SyncEditorOverlays()
end

-- Open the Import/Share window
function Windows:OpenImportShare()
    local app = self.app
    self:Close("importShare")
    local parent = parentFor("Import/Share")
    if parent == nil then return end
    local window
    window = ImportShare.new(parent, {
        onGetTagExports = function() return app.store:TagExports() end,
        onGetFolders = function() return app.store:GetFolders() end,
        -- Open an icon picker for the current import window
        onChooseImportSprite = function(onSelected)
            if self.importShare ~= window then return end
            self:OpenSpritePicker(window, function(result) onSelected(result.objectId) end)
        end,
        -- Close the picker owned by this import window
        onClose = function()
            if self.spritePickerOwner == window then self:Close("spritePicker") end
        end,
        -- Save the imported tags before refreshing their views
        onImport = function(source, overrides)
            local saved, summary, reason = app.store:ImportText(source, overrides)
            if not saved then return false, nil, reason end
            app:Changed()
            return true, summary, nil
        end,
    })
    self.importShare = window
    window:Show()
end

return Windows
