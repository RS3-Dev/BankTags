-- Own standalone plugin windows and dialogs

local debugLog = require("lib/core/debug_log").Write

local StandaloneWindows = {}
StandaloneWindows.__index = StandaloneWindows

-- Load production window dependencies
local function defaultDependencies()
    return {
        BankSettings = require("lib/features/settings/bank_settings"),
        DebugConsole = require("lib/features/settings/debug_console"),
        LayoutEditorWindow = require("lib/features/tags/layout_editor_window"),
        QueryEditor = require("lib/features/runesql/query_editor"),
        QueryStore = require("lib/features/runesql/query_store"),
        SpritePicker = require("lib/features/tags/sprite_picker"),
        TagDeleteConfirm = require("lib/features/tags/tag_delete_confirm"),
        TagSettingsEditor = require("lib/features/tags/tag_settings_editor"),
        TagStore = require("lib/features/tags/tag_store"),
        TextPrompt = require("lib/ui/text_prompt"),
    }
end

-- Find a layer for standalone windows
local function editorParent()
    return ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__BANK_LAYER)
        or ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__GAME_AREA)
end

-- Create an empty window collection
function StandaloneWindows.new(app, dependencies)
    return setmetatable({
        app = app,
        dependencies = dependencies or defaultDependencies(),
        layoutEditor = nil,
        tagSettingsEditor = nil,
        bankSettings = nil,
        debugConsole = nil,
        runeQueryEditor = nil,
        tagDeleteConfirm = nil,
        spritePicker = nil,
        textPrompt = nil,
    }, StandaloneWindows)
end

-- Stop layout editor input listeners
function StandaloneWindows:StopGlobalEvents()
    self.dependencies.LayoutEditorWindow.StopGlobalEvents()
end

-- Check the active query editor
function StandaloneWindows:IsEditingRuneQuery(queryID)
    return self.runeQueryEditor ~= nil
        and tostring(self.runeQueryEditor.queryID) == tostring(queryID)
end

-- Close one window by its field name, with the sprite picker it owns
function StandaloneWindows:Close(name)
    local window = self[name]
    if window == nil then return end
    self[name] = nil
    if name == "spritePicker" then
        self.spritePickerOwner = nil
    elseif self.spritePickerOwner == window then
        self:Close("spritePicker")
    end
    pcall(function() window:Destroy() end)
    -- A label prompt covers the layout editor while it is open
    if name == "textPrompt" and self.layoutEditor ~= nil then self.layoutEditor:SetOverlay(nil) end
end

-- Close every window; settings can also open from the plugin panel, so leaving
-- the bank may keep it open
function StandaloneWindows:CloseAll(keepSettings)
    for _, name in ipairs({ "textPrompt", "layoutEditor", "tagSettingsEditor",
        "debugConsole", "runeQueryEditor", "tagDeleteConfirm" }) do
        self:Close(name)
    end
    if not keepSettings then self:Close("bankSettings") end
end

-- Open a single-field prompt, replacing any prompt that is already open
function StandaloneWindows:OpenTextPrompt(options)
    local app = self.app
    if not app.inGame then return end
    self:Close("textPrompt")
    local parent = editorParent()
    if parent == nil then
        debugLog("BankUtils could not find a UI layer for its prompt")
        return
    end
    self.textPrompt = self.dependencies.TextPrompt.new(parent, options)
    self.textPrompt:Show()
end

-- Ask for a folder name and file the tag under it
function StandaloneWindows:OpenCreateFolderPrompt(tag)
    local app = self.app
    self:OpenTextPrompt({
        title = "Create Folder",
        heading = "Folder name",
        placeholder = "Folder name",
        maxLength = self.dependencies.TagStore.MAX_FOLDER_NAME,
        saveLabel = "Create",
        onSave = function(value)
            local saved, folderKey, reason = app.store:CreateFolder(value, tag)
            if not saved then return false, reason end
            app.store:SetFolderCollapsed(folderKey, false)
            app:RefreshFolders()
            debugLog("BankUtils added tag ", tag, " to folder ", value)
            return true, nil
        end,
    })
end

-- Ask for a folder's new name
function StandaloneWindows:OpenRenameFolderPrompt(folderKey)
    local app = self.app
    local folder = app.store:GetFolder(folderKey)
    if folder == nil then return end
    self:OpenTextPrompt({
        title = "Rename Folder",
        heading = "Folder name",
        text = folder.name,
        placeholder = "Folder name",
        maxLength = self.dependencies.TagStore.MAX_FOLDER_NAME,
        onSave = function(value)
            local saved, _, reason = app.store:RenameFolder(folderKey, value)
            if not saved then return false, reason end
            app:RefreshFolders()
            return true, nil
        end,
    })
end

-- Ask for a label's text over the layout editor that requested it
-- The editor supplies the save and delete actions for the row being edited
function StandaloneWindows:OpenPageLabelPrompt(options)
    self:OpenTextPrompt({
        title = options.text ~= nil and "Edit Label" or "Add Label",
        heading = "Label text",
        text = options.text or "",
        placeholder = "e.g. Weapons",
        maxLength = self.dependencies.TagStore.MAX_LABEL_TEXT,
        saveLabel = options.text ~= nil and "Save" or "Add",
        onSave = function(value)
            if string.match(value, "%S") == nil then
                return false, "Enter the label text."
            end
            return options.onSave(value)
        end,
        onDelete = options.onDelete,
    })
    if self.layoutEditor ~= nil and self.textPrompt ~= nil then
        self.layoutEditor:SetOverlay(self.textPrompt.window)
    end
end

-- Open the query editor
function StandaloneWindows:OpenRuneQueryEditor(selection)
    local app = self.app
    if not app.inGame then return end
    self:Close("runeQueryEditor")
    local parent = editorParent()
    if parent == nil then
        debugLog("BankUtils could not find a UI layer for its RuneQL editor")
        return
    end

    local record = selection ~= nil
        and app.queryStore:GetBySelection(selection) or nil
    if selection ~= nil and record == nil then
        debugLog("BankUtils could not find the selected RuneQL query")
        app.features:RefreshTags()
        return
    end

    local editor
    editor = self.dependencies.QueryEditor.new(parent, {
        record = record,
        onSave = function(queryID, name, query)
            local plan, queryReason = runeql.Compile(query)
            if plan == nil then return false, queryReason end
            local saved, savedRecord, reason = app.queryStore:Save(
                queryID,
                name,
                query
            )
            if not saved then return false, reason end
            local savedSelection = self.dependencies.QueryStore.SelectionID(savedRecord.id)
            app.features.runeQueryCounts[tostring(savedRecord.id)] = nil
            if app.features.selectedTag == savedSelection then
                app.features:ReapplySelectedTag(true)
            end
            app.features:RefreshTags()
            debugLog("BankUtils saved RuneQL query ", savedRecord.name)
            return true, nil
        end,
        onClose = function()
            if self.runeQueryEditor == editor then self.runeQueryEditor = nil end
        end,
    })
    self.runeQueryEditor = editor
    editor:Show()
end

-- Open the debug console
function StandaloneWindows:OpenDebugConsole()
    local app = self.app
    if not app.inGame then return end
    self:Close("debugConsole")
    local parent = editorParent()
    if parent == nil then
        debugLog("Bank Utilities could not find a UI layer for its debug console")
        return
    end
    local console
    console = self.dependencies.DebugConsole.new(parent, {
        onClose = function()
            if self.debugConsole == console then self.debugConsole = nil end
        end,
    })
    self.debugConsole = console
    console:Show()
end

-- Open the tag layout editor
function StandaloneWindows:OpenLayoutEditor(tag)
    local app = self.app
    if not app.inGame or type(tag) ~= "string" or tag == "" then return end
    self:Close("layoutEditor")
    local parent = editorParent()
    if parent == nil then
        debugLog("Bank Utilities could not find a UI layer for the layout editor")
        return
    end

    local editor
    editor = self.dependencies.LayoutEditorWindow.new(parent, {
        store = app.store,
        settings = app.settings,
        tag = tag,
        onChanged = function(changedTag)
            app.features:RefreshTags()
            if app.features.selectedTag == changedTag then
                app.features:ReapplySelectedTag(true)
            end
        end,
        onOpenSettings = function() self:OpenBankSettings() end,
        onCreateTag = function(onCreated)
            self:OpenTagSettings(app.store:NextPlaceholderTagName(), true, function(newTag)
                if self.layoutEditor == editor then onCreated(newTag) end
            end)
        end,
        onPromptLabel = function(options)
            self:OpenPageLabelPrompt(options)
        end,
        onClose = function(value)
            if self.layoutEditor == value then
                self.layoutEditor = nil
                -- A label prompt edits this editor's tag, so it closes with it
                self:Close("textPrompt")
            end
        end,
    })
    self.layoutEditor = editor
    editor:Show()
end

-- Open the tag deletion dialog
function StandaloneWindows:OpenTagDeleteConfirm(tag)
    local app = self.app
    if not app.inGame then return end
    self:Close("tagDeleteConfirm")
    local parent = editorParent()
    if parent == nil then
        debugLog("Bank Utilities could not find a UI layer for delete confirmation")
        return
    end

    self.tagDeleteConfirm = self.dependencies.TagDeleteConfirm.new(parent, {
        tag = tag,
        onDelete = function()
            local saved, reason = app.store:DeleteTag(tag)
            if not saved then return false, reason end
            if app.features.selectedTag == tag then app.features:SetSelectedTag(nil) end
            if app.features:IsSelectingItemsForTag(tag) then
                app.features:StopItemSelection(false)
            end
            app.features:RefreshTags()
            debugLog("Bank Utilities deleted tag ", tag)
            return true, nil
        end,
    })
    self.tagDeleteConfirm:Show()
end

-- Open the sprite picker
function StandaloneWindows:OpenSpritePicker(editor)
    local app = self.app
    if not app.inGame or editor ~= self.tagSettingsEditor then return end
    self:Close("spritePicker")
    local parent = editorParent()
    if parent == nil then return end
    self.spritePickerOwner = editor
    self.spritePicker = self.dependencies.SpritePicker.new(parent, {
        onSelect = function(result)
            if self.tagSettingsEditor == editor then
                editor:SetSprite(result.objectId, result.displayName)
            end
        end,
    })
    self.spritePicker:Show()
end

-- Open tag settings
function StandaloneWindows:OpenTagSettings(tag, isNew, onSaved)
    local app = self.app
    if not app.inGame then return end
    self:Close("tagSettingsEditor")
    local parent = editorParent()
    if parent == nil then
        debugLog("Bank Utilities could not find a UI layer for the tag settings editor")
        return
    end

    local editor
    editor = self.dependencies.TagSettingsEditor.new(parent, {
        title = isNew and "Create Bank Tag" or "Edit Bank Tag",
        tag = tag,
        spriteObjectID = not isNew and app.store:GetTagSprite(tag) or nil,
        onChooseSprite = function() self:OpenSpritePicker(editor) end,
        onSave = function(newName, spriteObjectID)
            local saved, finalName, reason
            if isNew then
                saved, finalName, reason = app.store:CreateTag(newName, spriteObjectID)
            else
                saved, finalName, reason = app.store:UpdateTag(tag, newName, spriteObjectID)
            end
            if not saved then return false, reason end
            if not isNew and app.features.selectedTag == tag then
                app.features:SetSelectedTag(finalName)
            end
            if not isNew and app.features:IsSelectingItemsForTag(tag) then
                app.features:SetItemSelectionTag(finalName)
            end
            app.features:RefreshTags()
            debugLog("Bank Utilities ", isNew and "created" or "renamed",
                " tag ", tag, " as ", finalName)
            if onSaved ~= nil then onSaved(finalName) end
            return true, nil
        end,
    })
    self.tagSettingsEditor = editor
    editor:Show()
end

-- Show the current import sources in an open Import/Share window
function StandaloneWindows:RefreshImportSources()
    if self.bankSettings ~= nil then self.bankSettings:RefreshSources() end
end

-- Open bank settings
function StandaloneWindows:OpenBankSettings()
    local app = self.app
    if not app.inGame then return end
    self:Close("bankSettings")
    local parent = editorParent()
    if parent == nil then
        debugLog("Bank Utilities could not find a UI layer for its settings")
        return
    end

    local settingsWindow
    settingsWindow = self.dependencies.BankSettings.new(parent, {
        tagExports = app.store:TagExports(),
        onGetTagExports = function() return app.store:TagExports() end,
        onGetFolders = function() return app.store:GetFolders() end,
        importProviders = app.importProviders,
        onChooseImportSprite = function(onSelected)
            if self.bankSettings ~= settingsWindow then return end
            self:Close("spritePicker")
            self.spritePickerOwner = settingsWindow
            self.spritePicker = self.dependencies.SpritePicker.new(parent, {
                onSelect = function(result)
                    if self.bankSettings == settingsWindow then onSelected(result.objectId) end
                end,
            })
            self.spritePicker:Show()
        end,
        onClose = function()
            if self.spritePickerOwner == settingsWindow then self:Close("spritePicker") end
        end,
        onImport = function(source, overrides)
            local saved, summary, reason = app.store:ImportText(source, overrides)
            if not saved then return false, nil, reason end
            app.features:RefreshTags()
            if app.features.selectedTag ~= nil then app.features:ReapplySelectedTag(true) end
            debugLog("Bank Utilities imported ", summary.tags, " tag(s)")
            return true, summary, nil
        end,
    })
    self.bankSettings = settingsWindow
    settingsWindow:Show()
end

return StandaloneWindows
