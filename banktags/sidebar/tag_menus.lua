-- Add Bank Tags' right-click entries through Bank Core: tag and folder actions over the
-- Tags tab's rows, and Remove from the shown tag over its items. Bank Core places the
-- entries and runs them on a later tick; nothing here edits a menu directly

local ItemIdentity = require("banktags/tags/item_identity")
local TagPage = require("banktags/tags/tag_page")
local Text = require("banktags/core/text")

local TagMenus = {}

-- Show a tag name as a menu subject
local function subject(tag)
    return Text.plain(Text.titleCase(tag))
end

-- Add Expand or Collapse, Rename, and Ungroup for a folder row
local function addFolderEntries(app, menu, folderKey)
    local folder = app.store:GetFolder(folderKey)
    if folder == nil then return end
    local name = Text.plain(folder.name)
    menu:Add(folder.collapsed and "Expand" or "Collapse", function()
        app:ToggleFolder(folderKey)
    end, name)
    menu:Add("Rename folder", function() app.windows:OpenRenameFolderPrompt(folderKey) end, name)
    menu:Add("Ungroup folder", function() app:DeleteFolder(folderKey) end, name)
end

-- Add Select, Edit, select mode, Remove, and folder actions for a tag row
local function addTagEntries(app, menu, tag)
    local name = subject(tag)
    menu:Add("Select", function() app:ShowTag(tag) end, name)
    menu:Add("Edit", function() app.windows:OpenTagSettings(tag, false) end, name)
    menu:Add(app.select:Tag() == tag and "Stop selecting items" or "Select items", function()
        app.select:Toggle(tag)
    end, name)
    menu:Add("Remove", function() app.windows:OpenTagDeleteConfirm(tag) end, name)
    local folderKey = app.store:GetTagFolder(tag)
    if folderKey ~= nil then
        local folder = app.store:GetFolder(folderKey)
        menu:Add("Remove from folder", function() app:MoveTagToFolder(tag, nil) end,
            Text.plain(folder ~= nil and folder.name or folderKey))
    end
    menu:Add("Move to folder...", function() app.windows:OpenFolderChooser(tag) end, name)
end

-- Add the actions for the Tags tab row under the pointer, if any
function TagMenus.AddRowEntries(app, menu, entry)
    if entry == nil then return end
    if entry.kind == "folder" then
        addFolderEntries(app, menu, entry.key)
    elseif app.store.data.tags[entry.tag] ~= nil then
        addTagEntries(app, menu, entry.tag)
    end
end

-- Offer Remove from the shown tag over one of its items or ghosts. The entry removes the
-- copy the slot was drawn for, which a ghost or borrowed slot names, not the stack beneath
function TagMenus.AddItemEntries(app, item, menu)
    local tag = app.shownTag
    if item.view ~= "page" or item.pageID ~= TagPage.PAGE_ID or item.slot == nil or tag == nil then
        return
    end
    local layoutKey = ItemIdentity.LayoutKey(item.objectID, item.slot.copy)
    if not app.store:HasTag(tag, layoutKey) then return end
    menu:Add("Remove from", function() app:RemoveFromTag(tag, layoutKey) end, subject(tag))
end

return TagMenus
