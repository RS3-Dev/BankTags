-- Hold the saved tags; layouts and folders have their own files

local Config = require("resources/core/config")
local ChunkedStringStore = require("resources/core/chunked_string_store")
local TagData = require("resources/tags/tag_data")
local TagRules = require("resources/tags/tag_rules")
local TagLayouts = require("resources/tags/tag_layouts")
local ItemIdentity = require("resources/tags/item_identity")
local copy = TagRules.copy
local normalizeTag = TagRules.normalizeTag
local folderName = TagRules.folderName

local TagStore = {}
TagStore.__index = TagStore
require("resources/tags/tag_store_layouts").install(TagStore)
require("resources/tags/tag_store_labels").install(TagStore)
require("resources/tags/tag_store_folders").install(TagStore)

local TEXT_STORE = {
    manifestKey = Config.TAGS_TEXT_MANIFEST_KEY,
    chunkPrefix = Config.TAGS_TEXT_CHUNK_PREFIX,
}
local INVALID_TAG_NAME = "Enter one tag name without commas (up to "
    .. TagRules.MAX_TAG_NAME .. " characters)."

TagStore.MAX_TAG_NAME = TagRules.MAX_TAG_NAME

-- Find the saved reference for an optional item icon
local function iconReference(spriteObjectID)
    if spriteObjectID == nil then return true, nil end
    local objectID = math.tointeger(tonumber(spriteObjectID))
    if objectID == nil or objectID < 0 then return false, nil end
    return true, ItemIdentity.Reference(objectID)
end

-- Load tags and protect unreadable saves
function TagStore.new()
    local saved, reason = ChunkedStringStore.Read(TEXT_STORE)
    local data, migrated
    if saved ~= nil then data, reason, migrated = TagData.Decode(saved, true) end
    local store = setmetatable({ data = data or TagData.Empty() }, TagStore)
    if reason ~= nil then
        store.loadError = "The saved tags could not be read (" .. tostring(reason)
            .. "). Nothing will be saved until they are fixed or removed."
    elseif migrated and PersistentDB ~= nil and PersistentDB.SetString ~= nil then
        -- Persist legacy name-keyed tags under their new UUIDs
        store:Save()
    end
    return store
end

-- Apply the placement preference for newly tagged items
function TagStore:SetLayoutPlacement(preserve)
    self.preserveTagLayout = preserve ~= false
end

-- Save changed data, using it only once the save works
function TagStore:Commit(nextData, failureMessage)
    if self.loadError ~= nil then return false, self.loadError end
    if #nextData.order > TagData.MAX_TAGS then
        return false, "You can save at most " .. TagData.MAX_TAGS .. " tags."
    end
    local used = {}
    for name, tag in pairs(nextData.tags) do
        TagLayouts.Trim(tag.rows)
        if tag.folder ~= nil then used[tag.folder] = true end
        local count = TagData.EntryCount(tag)
        local current = self.data.tags[name]
        if count > TagData.EDIT_ENTRY_LIMIT
            and (current == nil or count > TagData.EntryCount(current)) then
            return false, "A tag can hold at most " .. TagData.EDIT_ENTRY_LIMIT
                .. " rows, labels, and items."
        end
    end
    local folderCount = 0
    for key in pairs(nextData.folders) do
        if used[key] then folderCount = folderCount + 1 else nextData.folders[key] = nil end
    end
    if folderCount > TagData.MAX_FOLDERS then
        return false, "You can save at most " .. TagData.MAX_FOLDERS .. " folders."
    end
    -- Edits saved together are written once at the end
    if self.holdSave then
        self.data = nextData
        return true, nil
    end
    if PersistentDB == nil or PersistentDB.SetString == nil then
        return false, "PersistentDB is unavailable."
    end
    local text = TagData.Encode(nextData)
    if #text > TagData.MAX_TEXT_LENGTH then return false, "The saved tags are too large." end
    local saved, failure = ChunkedStringStore.Write(TEXT_STORE, text)
    if not saved then
        if failure.stage == "chunk" then
            return false, "PersistentDB could not save tag chunk "
                .. tostring(failure.index) .. ": " .. tostring(failure.reason)
        end
        return false, failureMessage .. " " .. tostring(failure.reason or "")
    end
    self.data = nextData
    return true, nil
end

-- Save the current data
function TagStore:Save()
    return self:Commit(self.data, "Could not save the tags.")
end

-- Save related edits together or roll them all back
function TagStore:SaveTogether(edit)
    local before = self.data
    local holding = self.holdSave
    self.holdSave = true
    -- An edit that errors must not leave later saves held
    local ran, done, reason = pcall(edit)
    self.holdSave = holding
    if ran and done and self.data ~= before then
        done, reason = self:Commit(self.data, "Could not save the tags.")
    end
    if not (ran and done) then self.data = before end
    if not ran then error(done, 0) end
    return done == true, reason
end

-- Add an item slot, including another copy
function TagStore:AddTag(tag, objectID)
    objectID = math.tointeger(tonumber(objectID))
    if self.data.tags[tag] == nil or objectID == nil or objectID < 0 then
        return false, "The tag or item is invalid.", nil
    end
    local nextData = copy(self.data)
    local record = nextData.tags[tag]
    local slot = TagLayouts.Item(objectID)
    if self.preserveTagLayout == false then
        local index, position = TagLayouts.FirstOpenSlot(record.rows)
        if index ~= nil then
            record.rows[index].slots[position] = slot
        else
            TagLayouts.AppendToLastRow(record.rows, slot)
        end
    else
        record.unsorted[#record.unsorted + 1] = slot
    end
    local saved, reason = self:Commit(nextData, "Could not save the tag.")
    return saved, reason, saved and slot.layoutKey or nil
end

-- Take selected items out in reading order
function TagStore.TakeSlots(record, layoutKeys, onlyRows)
    local wanted, taken = {}, {}
    for _, layoutKey in ipairs(layoutKeys) do wanted[layoutKey] = true end
    for _, entry in ipairs(record.rows) do
        for position, slot in ipairs(entry.slots or {}) do
            if slot.kind == "item" and wanted[slot.layoutKey] then
                entry.slots[position] = { kind = "blank" }
                taken[#taken + 1] = slot
            end
        end
    end
    if not onlyRows then
        local kept = {}
        for _, slot in ipairs(record.unsorted) do
            if slot.kind == "item" and wanted[slot.layoutKey] then
                taken[#taken + 1] = slot
            else
                kept[#kept + 1] = slot
            end
        end
        record.unsorted = kept
    end
    return taken
end

-- Remove selected items in one save
function TagStore:RemoveTags(tag, layoutKeys)
    if self.data.tags[tag] == nil then return true, nil, false end
    local nextData = copy(self.data)
    if #TagStore.TakeSlots(nextData.tags[tag], layoutKeys) == 0 then return true, nil, false end
    local saved, reason = self:Commit(nextData, "Could not remove the tag.")
    return saved, reason, saved
end

-- Remove one item from a tag
function TagStore:RemoveTag(tag, layoutKey)
    return self:RemoveTags(tag, { layoutKey })
end

-- Add a new empty tag to copied data
local function addTag(data, id, name, icon)
    data.tags[id] = { name = name, icon = icon, rows = {}, unsorted = {} }
    data.order[#data.order + 1] = id
end

-- Read a tag's display name
function TagStore:GetTagName(tag)
    local record = self.data.tags[tag]
    if record ~= nil and type(record.name) == "string" and record.name ~= "" then
        return record.name
    end
    return type(tag) == "string" and tag or ""
end

-- Suggest an unused default name without saving anything
function TagStore:NextPlaceholderTagName()
    local used = {}
    for _, record in pairs(self.data.tags) do
        if type(record.name) == "string" then used[record.name] = true end
    end
    local index = 1
    while used["placeholder " .. index] do index = index + 1 end
    return "placeholder " .. index
end

-- Create an empty tag with an optional icon
function TagStore:CreateTag(requestedName, spriteObjectID)
    local name = normalizeTag(requestedName)
    if name == nil then return false, nil, INVALID_TAG_NAME end
    local valid, icon = iconReference(spriteObjectID)
    if not valid then return false, nil, "The selected sprite is invalid." end
    local nextData = copy(self.data)
    local id = TagRules.newUUID(nextData.tags)
    addTag(nextData, id, name, icon)
    local saved, reason = self:Commit(nextData, "Could not create the tag.")
    if not saved then return false, nil, reason end
    return true, id, nil
end

-- Read the object ID of a tag's sidebar icon
function TagStore:GetTagSprite(tag)
    local record = self.data.tags[tag]
    return record ~= nil and ItemIdentity.ObjectID(record.icon) or nil
end

-- Rename a tag and keep or replace its icon without changing its ID
function TagStore:UpdateTag(tagID, newName, spriteObjectID)
    local name = normalizeTag(newName)
    if self.data.tags[tagID] == nil then return false, nil, "The existing tag is invalid." end
    if name == nil then return false, nil, INVALID_TAG_NAME end
    local valid, icon = iconReference(spriteObjectID)
    if not valid then return false, nil, "The selected sprite is invalid." end
    local nextData = copy(self.data)
    local record = nextData.tags[tagID]
    record.name = name
    record.icon = icon or record.icon
    local saved, reason = self:Commit(nextData, "Could not save the tag.")
    if not saved then return false, nil, reason end
    return true, tagID, nil
end

-- Delete a tag and its saved layout
function TagStore:DeleteTag(tag)
    if self.data.tags[tag] == nil then return false, "The tag is invalid." end
    local nextData = copy(self.data)
    nextData.tags[tag] = nil
    for index, name in ipairs(nextData.order) do
        if name == tag then table.remove(nextData.order, index) break end
    end
    return self:Commit(nextData, "Could not delete the tag.")
end

-- List tag names in sidebar order
function TagStore:AllTags()
    return copy(self.data.order)
end

-- Save the listed order, keeping unlisted tags afterward
function TagStore:SaveTagOrder(requestedOrder)
    local order, seen = {}, {}
    for _, list in ipairs({ requestedOrder or {}, self.data.order }) do
        for _, tag in ipairs(list) do
            if self.data.tags[tag] ~= nil and not seen[tag] then
                seen[tag] = true
                order[#order + 1] = tag
            end
        end
    end
    local nextData = copy(self.data)
    nextData.order = order
    return self:Commit(nextData, "Could not save the tag order.")
end

-- List every tag with the text that shares it
function TagStore:TagExports()
    local exports = {}
    for _, tag in ipairs(self.data.order) do
        local value = TagData.Encode(self.data, tag)
        exports[#exports + 1] = { tag = tag, name = self:GetTagName(tag), value = value, length = #value }
    end
    return exports
end

-- Apply a single shared tag's chosen name, icon, and folder
local function customizeImport(imported, options, current)
    if #imported.order ~= 1 then return false, "Import customization requires a single shared tag." end
    local tag = imported.tags[imported.order[1]]
    local name = normalizeTag(options.name or tag.name)
    if name == nil then return false, INVALID_TAG_NAME end
    tag.name = name
    if options.spriteObjectID ~= nil then
        local valid, icon = iconReference(options.spriteObjectID)
        if not valid then return false, "The selected sprite is invalid." end
        tag.icon = icon
    end
    if options.newFolderName ~= nil then
        local key, display = folderName(options.newFolderName)
        if key == nil then
            return false, "Enter a folder name of up to " .. TagRules.MAX_FOLDER_NAME .. " characters."
        end
        imported.folders[key] = imported.folders[key] or { name = display, collapsed = false }
        tag.folder = key
    elseif options.folderKey == false then
        tag.folder = nil
    elseif options.folderKey ~= nil then
        if current.folders[options.folderKey] == nil and imported.folders[options.folderKey] == nil then
            return false, "The selected folder no longer exists."
        end
        tag.folder = options.folderKey
    end
    return true, nil
end

-- Import shared tags or a backup under fresh unique IDs
function TagStore:ImportText(source, options)
    local imported, reason = TagData.Decode(source)
    if imported == nil then return false, nil, reason end
    if options ~= nil then
        local customized, customizeReason = customizeImport(imported, options, self.data)
        if not customized then return false, nil, customizeReason end
    end
    local nextData = copy(self.data)
    local importedOrder = {}
    for _, sourceID in ipairs(imported.order) do
        local tag = imported.tags[sourceID]
        local id = TagRules.newUUID(nextData.tags)
        nextData.tags[id] = tag
        importedOrder[#importedOrder + 1] = id
        if tag.folder ~= nil and nextData.folders[tag.folder] == nil then
            nextData.folders[tag.folder] = imported.folders[tag.folder]
        end
    end
    -- Imported tags go first unless a folder places them
    if options ~= nil and (options.folderKey ~= nil or options.newFolderName ~= nil) then
        nextData.order = self:FolderTagOrder(importedOrder[1], nextData.tags[importedOrder[1]].folder)
    else
        local order, seen = {}, {}
        for _, list in ipairs({ importedOrder, nextData.order }) do
            for _, tag in ipairs(list) do
                if not seen[tag] then
                    seen[tag] = true
                    order[#order + 1] = tag
                end
            end
        end
        nextData.order = order
    end
    local saved, saveReason = self:Commit(nextData, "Could not save the imported bank tags.")
    if not saved then return false, nil, saveReason end
    return true, { tags = #importedOrder }, nil
end

return TagStore
