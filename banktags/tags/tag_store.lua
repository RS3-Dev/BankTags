-- Own the saved tags; layouts and folders live in companion modules

local Config = require("banktags/core/config")
local ChunkedStringStore = require("banktags/core/chunked_string_store")
local TagData = require("banktags/tags/tag_data")
local TagRules = require("banktags/tags/tag_rules")
local TagLayouts = require("banktags/tags/tag_layouts")
local ItemIdentity = require("banktags/tags/item_identity")
local copy = TagRules.copy
local normalizeTag = TagRules.normalizeTag
local folderName = TagRules.folderName

local TagStore = {}
TagStore.__index = TagStore
require("banktags/tags/tag_store_layouts").install(TagStore)
require("banktags/tags/tag_store_folders").install(TagStore)

local TEXT_STORE = {
    manifestKey = Config.TAGS_TEXT_MANIFEST_KEY,
    chunkPrefix = Config.TAGS_TEXT_CHUNK_PREFIX,
}
local INVALID_TAG_NAME = "Enter one tag name without commas (up to "
    .. TagRules.MAX_TAG_NAME .. " characters)."

TagStore.MAX_FOLDER_NAME = TagRules.MAX_FOLDER_NAME
TagStore.MAX_TAG_NAME = TagRules.MAX_TAG_NAME
TagStore.MAX_LABEL_TEXT = TagRules.MAX_LABEL_TEXT

-- Read an icon's saved reference from an object ID, or nil for no icon
local function iconReference(spriteObjectID)
    if spriteObjectID == nil then return true, nil end
    local objectID = math.tointeger(tonumber(spriteObjectID))
    if objectID == nil or objectID < 0 then return false, nil end
    return true, ItemIdentity.Reference(objectID)
end

-- Load saved tags, refusing changes when the save cannot be read
function TagStore.new()
    local saved = ChunkedStringStore.Read(TEXT_STORE)
    local data, reason = nil, nil
    if saved ~= nil then data, reason = TagData.Decode(saved, true) end
    local store = setmetatable({ data = data or TagData.Empty(), members = {} }, TagStore)
    if saved ~= nil and data == nil then
        store.loadError = "The saved tags could not be read (" .. tostring(reason)
            .. "). Nothing will be saved until they are fixed or removed."
    end
    return store
end

-- Apply the placement preference for newly tagged items
function TagStore:SetLayoutPlacement(preserve)
    self.preserveTagLayout = preserve ~= false
end

-- Save changed data and adopt it only once the save succeeds
function TagStore:Commit(nextData, failureMessage)
    if self.loadError ~= nil then return false, self.loadError end
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
    for key in pairs(nextData.folders) do
        if not used[key] then nextData.folders[key] = nil end
    end
    if PersistentDB == nil or PersistentDB.SetString == nil then
        return false, "PersistentDB is unavailable."
    end
    local saved, failure = ChunkedStringStore.Write(TEXT_STORE, TagData.Encode(nextData))
    if not saved then
        if failure.stage == "chunk" then
            return false, "PersistentDB could not save tag chunk "
                .. tostring(failure.index) .. ": " .. tostring(failure.reason)
        end
        return false, failureMessage .. " " .. tostring(failure.reason or "")
    end
    self.data, self.members = nextData, {}
    return true, nil
end

-- Save the current data
function TagStore:Save()
    return self:Commit(self.data, "Could not save the tags.")
end

-- Return the set of item copies in a tag, or nil when the tag does not exist
function TagStore:Members(tag)
    local record = self.data.tags[tag]
    if record == nil then return nil end
    local members = self.members[tag]
    if members == nil then
        members = {}
        for _, slots in ipairs({ TagLayouts.RowSlots(record.rows), record.unsorted }) do
            for _, slot in ipairs(slots) do
                if slot.kind == "item" then members[slot.layoutKey] = true end
            end
        end
        self.members[tag] = members
    end
    return members
end

-- Report whether a tag lists an item copy
function TagStore:HasTag(tag, layoutKey)
    local members = self:Members(tag)
    return members ~= nil and members[layoutKey] == true
end

-- Add an item copy to a tag's layout or Unsorted list
function TagStore:AddTag(tag, objectID, layoutKey)
    objectID = math.tointeger(tonumber(objectID))
    layoutKey = layoutKey or ItemIdentity.LayoutKey(objectID, 1)
    if self.data.tags[tag] == nil or objectID == nil or layoutKey == nil then
        return false, "The tag or item is invalid.", false
    end
    if self:HasTag(tag, layoutKey) then return true, nil, false end
    local nextData = copy(self.data)
    local record = nextData.tags[tag]
    local slot = { kind = "item", objectID = objectID, layoutKey = layoutKey }
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
    return saved, reason, saved
end

-- Take a copy out of a tag, leaving a blank in its row
function TagStore.TakeSlot(record, layoutKey)
    for _, entry in ipairs(record.rows) do
        for position, slot in ipairs(entry.slots or {}) do
            if slot.kind == "item" and slot.layoutKey == layoutKey then
                entry.slots[position] = { kind = "blank" }
                return slot
            end
        end
    end
    for index, slot in ipairs(record.unsorted) do
        if slot.kind == "item" and slot.layoutKey == layoutKey then
            return table.remove(record.unsorted, index)
        end
    end
    return nil
end

-- Remove one item copy from a tag
function TagStore:RemoveTag(tag, layoutKey)
    if not self:HasTag(tag, layoutKey) then return true, nil, false end
    local nextData = copy(self.data)
    TagStore.TakeSlot(nextData.tags[tag], layoutKey)
    local saved, reason = self:Commit(nextData, "Could not remove the tag.")
    return saved, reason, saved
end

-- Add a new empty tag to copied data
local function addTag(data, name, icon)
    data.tags[name] = { icon = icon, rows = {}, unsorted = {} }
    data.order[#data.order + 1] = name
end

-- Suggest an unused default name without saving anything
function TagStore:NextPlaceholderTagName()
    local index = 1
    while self.data.tags["placeholder " .. index] ~= nil do index = index + 1 end
    return "placeholder " .. index
end

-- Create an empty tag with an optional icon
function TagStore:CreateTag(requestedName, spriteObjectID)
    local name = normalizeTag(requestedName)
    if name == nil then return false, nil, INVALID_TAG_NAME end
    if self.data.tags[name] ~= nil then return false, nil, "A tag with that name already exists." end
    local valid, icon = iconReference(spriteObjectID)
    if not valid then return false, nil, "The selected sprite is invalid." end
    local nextData = copy(self.data)
    addTag(nextData, name, icon)
    local saved, reason = self:Commit(nextData, "Could not create the tag.")
    if not saved then return false, nil, reason end
    return true, name, nil
end

-- Create an empty tag with the next available default name
function TagStore:CreatePlaceholderTag()
    return self:CreateTag(self:NextPlaceholderTagName())
end

-- Read the object ID of a tag's sidebar icon
function TagStore:GetTagSprite(tag)
    local record = self.data.tags[tag]
    return record ~= nil and ItemIdentity.ObjectID(record.icon) or nil
end

-- Rename a tag and set its icon, keeping the icon when none is given
function TagStore:UpdateTag(oldTag, newTag, spriteObjectID)
    local name = normalizeTag(newTag)
    if self.data.tags[oldTag] == nil then return false, nil, "The existing tag is invalid." end
    if name == nil then return false, nil, INVALID_TAG_NAME end
    if name ~= oldTag and self.data.tags[name] ~= nil then
        return false, nil, "A tag with that name already exists."
    end
    local valid, icon = iconReference(spriteObjectID)
    if not valid then return false, nil, "The selected sprite is invalid." end
    local nextData = copy(self.data)
    local record = nextData.tags[oldTag]
    record.icon = icon or record.icon
    nextData.tags[oldTag] = nil
    nextData.tags[name] = record
    for index, tag in ipairs(nextData.order) do
        if tag == oldTag then nextData.order[index] = name end
    end
    local saved, reason = self:Commit(nextData, "Could not save the tag.")
    if not saved then return false, nil, reason end
    return true, name, nil
end

-- Delete a tag, its layout, and its place in the sidebar
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

-- Save a sidebar order, keeping any tag it leaves out after the listed ones
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
        exports[#exports + 1] = { tag = tag, value = value, length = #value }
    end
    return exports
end

-- Apply a single shared tag's chosen name, icon, and folder
local function customizeImport(imported, options, current)
    if #imported.order ~= 1 then return false, "Import customization requires a single shared tag." end
    local original = imported.order[1]
    local tag = imported.tags[original]
    local name = normalizeTag(options.name or original)
    if name == nil then return false, INVALID_TAG_NAME end
    imported.tags[original] = nil
    imported.tags[name], imported.order[1] = tag, name
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

-- Import shared tags or a backup, replacing same-named tags
function TagStore:ImportText(source, options)
    local imported, reason = TagData.Decode(source)
    if imported == nil then return false, nil, reason end
    if options ~= nil then
        local customized, customizeReason = customizeImport(imported, options, self.data)
        if not customized then return false, nil, customizeReason end
    end
    local nextData = copy(self.data)
    for _, name in ipairs(imported.order) do
        local tag = imported.tags[name]
        nextData.tags[name] = tag
        if tag.folder ~= nil and nextData.folders[tag.folder] == nil then
            nextData.folders[tag.folder] = imported.folders[tag.folder]
        end
    end
    -- Imported tags go first unless a folder places them
    if options ~= nil and (options.folderKey ~= nil or options.newFolderName ~= nil) then
        nextData.order = self:FolderTagOrder(imported.order[1], nextData.tags[imported.order[1]].folder)
    else
        local order, seen = {}, {}
        for _, list in ipairs({ imported.order, nextData.order }) do
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
    return true, { tags = #imported.order }, nil
end

return TagStore
