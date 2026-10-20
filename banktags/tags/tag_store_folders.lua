-- Group tags into folders and keep the sidebar order for TagStore

local TagRules = require("banktags/tags/tag_rules")
local copyTable = TagRules.copy
local folderName = TagRules.folderName

local TagStoreFolders = {}

-- Turn the folder tree back into a flat tag order
local function treeTagOrder(nodes)
    local order = {}
    for _, node in ipairs(nodes) do
        if node.kind == "tag" then
            order[#order + 1] = node.tag
        else
            for _, tag in ipairs(node.tags) do order[#order + 1] = tag end
        end
    end
    return order
end

-- Return the key of the folder a tag is in, if any
function TagStoreFolders:GetTagFolder(tag)
    local record = self.data.tags[tag]
    return record ~= nil and record.folder or nil
end

-- Return a copy of one folder's display name and collapse state
function TagStoreFolders:GetFolder(key)
    local folder = type(key) == "string" and self.data.folders[key] or nil
    if type(folder) ~= "table" then return nil end
    return { key = key, name = folder.name, collapsed = folder.collapsed == true }
end

-- Group the ordered tags so each folder sits where its first member appears
function TagStoreFolders:TagTree()
    local nodes = {}
    local folderNodes = {}
    for _, tag in ipairs(self:AllTags()) do
        local key = self:GetTagFolder(tag)
        if key == nil then
            nodes[#nodes + 1] = { kind = "tag", tag = tag }
        else
            local node = folderNodes[key]
            if node == nil then
                local folder = self.data.folders[key]
                node = {
                    kind = "folder",
                    key = key,
                    name = folder.name,
                    collapsed = folder.collapsed == true,
                    tags = {},
                }
                folderNodes[key] = node
                nodes[#nodes + 1] = node
            end
            node.tags[#node.tags + 1] = tag
        end
    end
    return nodes
end

-- Move a tag or folder one place, keeping folder members together
function TagStoreFolders:MoveSidebarEntry(tag, folderKey, offset)
    if offset ~= -1 and offset ~= 1 then return false, "Choose up or down." end
    local tree = self:TagTree()
    local siblings, source
    for index, node in ipairs(tree) do
        if folderKey ~= nil and node.kind == "folder" and node.key == folderKey then
            siblings, source = tree, index
            break
        elseif folderKey == nil then
            if node.kind == "tag" and node.tag == tag then
                siblings, source = tree, index
                break
            elseif node.kind == "folder" then
                for memberIndex, member in ipairs(node.tags) do
                    if member == tag then
                        siblings, source = node.tags, memberIndex
                        break
                    end
                end
                if source ~= nil then break end
            end
        end
    end
    if source == nil then return false, "The sidebar entry no longer exists." end
    local destination = source + offset
    if destination < 1 or destination > #siblings then return false, nil end
    siblings[source], siblings[destination] = siblings[destination], siblings[source]
    return self:SaveTagOrder(treeTagOrder(tree))
end

-- Work out the tag order after filing a tag, leaving the rest in place
function TagStoreFolders:FolderTagOrder(tag, folderKey)
    local tree = self:TagTree()
    local destination, source
    for index, node in ipairs(tree) do
        if node.kind == "folder" and node.key == folderKey then destination = node end
        if node.kind == "tag" and node.tag == tag then
            source = index
            node.tag = nil
        elseif node.kind == "folder" then
            for memberIndex, member in ipairs(node.tags) do
                if member == tag then
                    source = index + 1
                    table.remove(node.tags, memberIndex)
                    break
                end
            end
        end
    end
    if destination ~= nil then
        destination.tags[#destination.tags + 1] = tag
    else
        local node = folderKey ~= nil
            and { kind = "folder", key = folderKey, tags = { tag } }
            or { kind = "tag", tag = tag }
        table.insert(tree, source or (#tree + 1), node)
    end
    return treeTagOrder(tree)
end

-- List folders in sidebar order for menus
function TagStoreFolders:GetFolders()
    local folders = {}
    for _, node in ipairs(self:TagTree()) do
        if node.kind == "folder" then
            folders[#folders + 1] = { key = node.key, name = node.name }
        end
    end
    return folders
end

-- Move a tag into a folder, or out of every folder when the key is nil
function TagStoreFolders:SetTagFolder(tag, folderKey)
    if self.data.tags[tag] == nil then return false, "The tag is invalid." end
    if folderKey ~= nil and type(self.data.folders[folderKey]) ~= "table" then
        return false, "The folder no longer exists."
    end
    if self:GetTagFolder(tag) == folderKey then return true, nil end
    local nextData = copyTable(self.data)
    nextData.order = self:FolderTagOrder(tag, folderKey)
    nextData.tags[tag].folder = folderKey
    return self:Commit(nextData, "Could not save the folder.")
end

-- Create a folder holding the tag, joining an existing folder with the same name
function TagStoreFolders:CreateFolder(folder, tag)
    local key, display = folderName(folder)
    if key == nil then
        return false, nil, "Enter a folder name of up to "
            .. TagRules.MAX_FOLDER_NAME .. " characters."
    end
    if self.data.tags[tag] == nil then return false, nil, "The tag is invalid." end
    if self:GetTagFolder(tag) == key then return true, key, nil end
    local nextData = copyTable(self.data)
    nextData.order = self:FolderTagOrder(tag, key)
    if type(nextData.folders[key]) ~= "table" then
        nextData.folders[key] = { name = display, collapsed = false }
    end
    nextData.tags[tag].folder = key
    local saved, reason = self:Commit(nextData, "Could not save the folder.")
    if not saved then return false, nil, reason end
    return true, key, nil
end

-- Rename a folder, moving its tags to the new name's key
function TagStoreFolders:RenameFolder(key, folder)
    local current = type(key) == "string" and self.data.folders[key] or nil
    if type(current) ~= "table" then return false, nil, "The folder no longer exists." end
    local nextKey, display = folderName(folder)
    if nextKey == nil then
        return false, nil, "Enter a folder name of up to "
            .. TagRules.MAX_FOLDER_NAME .. " characters."
    end
    if nextKey ~= key and type(self.data.folders[nextKey]) == "table" then
        return false, nil, "A folder with that name already exists."
    end
    local nextData = copyTable(self.data)
    local value = nextData.folders[key]
    value.name = display
    if nextKey ~= key then
        nextData.folders[key] = nil
        nextData.folders[nextKey] = value
        for _, record in pairs(nextData.tags) do
            if record.folder == key then record.folder = nextKey end
        end
    end
    local saved, reason = self:Commit(nextData, "Could not save the folder.")
    if not saved then return false, nil, reason end
    return true, nextKey, nil
end

-- Remove a folder while keeping every tag it contained
function TagStoreFolders:DeleteFolder(key)
    if type(key) ~= "string" or type(self.data.folders[key]) ~= "table" then
        return false, "The folder no longer exists."
    end
    local nextData = copyTable(self.data)
    nextData.order = treeTagOrder(self:TagTree())
    nextData.folders[key] = nil
    for _, record in pairs(nextData.tags) do
        if record.folder == key then record.folder = nil end
    end
    return self:Commit(nextData, "Could not delete the folder.")
end

-- Toggle the flag in place rather than copying every tag
function TagStoreFolders:SetFolderCollapsed(key, collapsed)
    local folder = type(key) == "string" and self.data.folders[key] or nil
    if type(folder) ~= "table" then return false end
    local previous = folder.collapsed
    folder.collapsed = collapsed == true
    if previous == folder.collapsed then return true end
    if not self:Save() then
        folder.collapsed = previous
        return false
    end
    return true
end

-- Attach these methods to TagStore
function TagStoreFolders.install(target)
    for name, method in pairs(TagStoreFolders) do
        if name ~= "install" then target[name] = method end
    end
end

return TagStoreFolders
