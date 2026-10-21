-- Own Bank Tags' standalone windows, closing most with the bank

local ConfirmWindow = require("banktags/windows/confirm_window")
local debugLog = require("banktags/core/debug_log").Write
local ImportShare = require("banktags/windows/import_share")
local LayoutEditorWindow = require("banktags/windows/layout_editor_window")
local SpritePicker = require("banktags/windows/sprite_picker")
local TagRules = require("banktags/tags/tag_rules")
local TagSettingsEditor = require("banktags/windows/tag_settings_editor")
local TextPrompt = require("banktags/ui/text_prompt")

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

-- Keep prompts, tag settings, and the sprite picker in front of the layout editor
function Windows:SyncEditorOverlays()
    if self.layoutEditor == nil then return end
    local overlays = {}
    for _, name in ipairs(EDITOR_OVERLAYS) do
        if self[name] ~= nil then overlays[#overlays + 1] = self[name].window end
    end
    self.layoutEditor:SetOverlays(overlays)
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

-- Ask for a folder name and file the tag under it
function Windows:OpenCreateFolderPrompt(tag)
    local app = self.app
    self:OpenTextPrompt({
        title = "Create Folder",
        heading = "Folder name",
        placeholder = "Folder name",
        maxLength = TagRules.MAX_FOLDER_NAME,
        saveLabel = "Create",
        onSave = function(value)
            local saved, folderKey, reason = app.store:CreateFolder(value, tag)
            if not saved then return false, reason end
            app.store:SetFolderCollapsed(folderKey, false)
            app:Changed()
            return true, nil
        end,
    })
end

-- Ask for a folder's new name
function Windows:OpenRenameFolderPrompt(folderKey)
    local app = self.app
    local folder = app.store:GetFolder(folderKey)
    if folder == nil then return end
    self:OpenTextPrompt({
        title = "Rename Folder",
        heading = "Folder name",
        text = folder.name,
        placeholder = "Folder name",
        maxLength = TagRules.MAX_FOLDER_NAME,
        onSave = function(value)
            local saved, _, reason = app.store:RenameFolder(folderKey, value)
            if not saved then return false, reason end
            app:Changed()
            return true, nil
        end,
    })
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
        onSave = function(value)
            if string.match(value, "%S") == nil then return false, "Enter the label text." end
            return options.onSave(value)
        end,
        onDelete = options.onDelete,
    })
    self:SyncEditorOverlays()
end

-- Open the layout editor sized to the bank
function Windows:OpenLayoutEditor(tag)
    local app = self.app
    local state = app.state
    if type(tag) ~= "string" or tag == "" or state == nil or state.bounds == nil then return end
    self:Close("layoutEditor")
    local parent = parentFor("the layout editor")
    if parent == nil then return end
    local editor
    editor = LayoutEditorWindow.new(parent, {
        store = app.store,
        settings = function() return app.settings end,
        tag = tag,
        columns = state.columns,
        bounds = state.bounds,
        bankItems = app:BankItems(),
        onChanged = function() app:Changed() end,
        onPromptLabel = function(options) self:OpenPageLabelPrompt(options) end,
        onConfirmRemoveRow = function(options) self:OpenRowRemoveConfirm(options) end,
        onClose = function(value)
            if self.layoutEditor == value then
                self.layoutEditor = nil
                -- A label prompt or row removal edits this editor's tag, so it closes too
                self:Close("textPrompt")
                self:Close("rowRemoveConfirm")
            end
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

-- Move the editor with the bank, reopening it after a resize
function Windows:BankStateChanged(state)
    local editor = self.layoutEditor
    if editor == nil or state.bounds == nil then return end
    if editor:FitsBank(state.columns, state.bounds) then
        editor:MoveTo(state.bounds)
    else
        self:OpenLayoutEditor(editor.selectedTag)
    end
end

-- Give an open layout editor the bank's latest items
function Windows:BankItemsChanged()
    if self.layoutEditor ~= nil then self.layoutEditor:SetBankItems(self.app:BankItems()) end
end

-- Show store changes in the open editor and Import/Share
function Windows:StoreChanged()
    if self.layoutEditor ~= nil then self.layoutEditor:StoreChanged() end
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
        message = "Delete <col=ffcb05>\"" .. tostring(tag)
            .. "\"</col> from every tagged item?<br><br>Do you wish to continue?",
        confirmLabel = "Delete",
        failureText = "Could not delete the tag.",
        onConfirm = function()
            local saved, reason = app.store:DeleteTag(tag)
            if not saved then return false, reason end
            app:Changed()
            return true, nil
        end,
    })
    self.tagDeleteConfirm:Show()
end

-- Ask before removing a layout editor row, in front of the editor
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
        onChooseSprite = function()
            if self.tagSettingsEditor ~= editor then return end
            self:OpenSpritePicker(editor, function(result) editor:SetSprite(result.objectId) end)
        end,
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

-- Show current import sources in an open Import/Share window
function Windows:RefreshImportSources()
    if self.importShare ~= nil then self.importShare:RefreshSources() end
end

-- Open Import/Share
function Windows:OpenImportShare()
    local app = self.app
    self:Close("importShare")
    local parent = parentFor("Import/Share")
    if parent == nil then return end
    local window
    window = ImportShare.new(parent, {
        tagExports = app.store:TagExports(),
        onGetTagExports = function() return app.store:TagExports() end,
        onGetFolders = function() return app.store:GetFolders() end,
        importProviders = app.imports.providers,
        onChooseImportSprite = function(onSelected)
            if self.importShare ~= window then return end
            self:OpenSpritePicker(window, function(result) onSelected(result.objectId) end)
        end,
        onClose = function()
            if self.spritePickerOwner == window then self:Close("spritePicker") end
        end,
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
