-- Preview imported tags and manage their chosen settings

local TagData = require("banktags/tags/tag_data")
local ItemIdentity = require("banktags/tags/item_identity")
local ObjectConfig = require("banktags/core/object_config")

local ImportDraft = {}

local IMPORT_NO_FOLDER = "none"
local IMPORT_NEW_FOLDER = "new"
local IMPORT_FOLDER_PREFIX = "folder:"
local FOLDER_NAME_Y = 236

-- Count a tag's items and those this client cannot resolve
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

-- Describe a readable draft before saving
local function previewMessage(imported)
    local tagCount = #imported.order
    if tagCount ~= 1 then
        return "Backup: " .. tostring(tagCount) .. " tags. Original names and sprites kept."
    end
    local items, unknown = countItems(imported.tags[imported.order[1]])
    local message = "Preview: " .. tostring(items) .. (items == 1 and " item" or " items")
    if unknown > 0 then message = message .. ", " .. tostring(unknown) .. " not recognized" end
    return message .. ". Not saved until you import."
end

-- Preview the current input without saving
function ImportDraft:RefreshImportPreview(input)
    input = tostring(input or "")
    if self.closed or input == self.importSource then return end
    self.importSource = input
    if string.match(input, "%S") == nil then
        self:ShowImportResult("empty")
    else
        self:ShowImportResult("ready", input)
    end
end

-- Show the preview and enable only valid imports
function ImportDraft:ShowImportResult(state, value)
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
    elseif imported == nil then
        self:SetPageStatus(self.importStatus, reason, false)
    else
        self:SetPageStatus(self.importStatus, previewMessage(imported), true)
    end
end

-- List saved folders plus any folder the import supplies
function ImportDraft:RefreshImportFolders(selectedID)
    selectedID = selectedID or self.importFolder:GetSelectedID() or IMPORT_NO_FOLDER
    local entries = { { id = IMPORT_NO_FOLDER, label = "No folder", order = 1 } }
    local available = { [IMPORT_NO_FOLDER] = true, [IMPORT_NEW_FOLDER] = true }
    local folders = self.options.onGetFolders()
    -- Keep imported and existing folders from appearing twice
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

-- Show the new-folder field only when requested
function ImportDraft:UpdateImportFolderControls()
    if self.importFolderName == nil then return end
    local creating = self.importSingleTag ~= nil
        and self.importFolder:GetSelectedID() == IMPORT_NEW_FOLDER
    self.importFolderName.root.hidden = not creating
    self.importFolderName:SetDisabled(not creating)
    local buttonY = creating and FOLDER_NAME_Y + 42 or FOLDER_NAME_Y
    self.importButton.root:SetPos(18, buttonY)
    self.importStatus:SetPos(18, buttonY + 36)
end

-- Change the imported draft's icon and preview
function ImportDraft:SetImportSprite(objectID)
    self.importSpriteObjectID = math.tointeger(tonumber(objectID))
    self.importSpriteSlot:SetObject(ObjectConfig.FromID(self.importSpriteObjectID))
end

-- Ignore picker results once the draft has changed
function ImportDraft:ChooseImportSprite()
    if self.closed or self.importSingleTag == nil then return end
    local revision = self.importRevision
    -- Ignore icon choices from an older import draft
    self.options.onChooseImportSprite(function(objectID)
        if self.importRevision == revision then self:SetImportSprite(objectID) end
    end)
end

-- Save the readable draft to the chosen destination
function ImportDraft:Import()
    if self.closed then return end
    self:RefreshImportPreview(self.importField:GetText())
    -- Only a readable draft from the current input can be saved
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
    -- The app's change shows the new share codes
    self:RefreshImportFolders()
    local count = summary.tags or 0
    local message = "Imported " .. tostring(count) .. (count == 1 and " tag." or " tags.")
    self:SetPageStatus(self.importStatus, message, true)
end

return {
    methods = ImportDraft,
    NO_FOLDER = IMPORT_NO_FOLDER,
    NEW_FOLDER = IMPORT_NEW_FOLDER,
    FOLDER_NAME_Y = FOLDER_NAME_Y,
}
