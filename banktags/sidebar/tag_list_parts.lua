-- Share sidebar row identities and measurements between rendering and drag handling.

local SidebarRows = require("banktags/ui/sidebar_rows")
local Parts = {
    FOLDER_ENTRY_PREFIX = "__banktags_folder:",
    ROW_HEIGHT = 30,
    ENTRY_HEIGHT = SidebarRows.ENTRY_HEIGHT,
}
local FOLDER_ENTRY_PREFIX = Parts.FOLDER_ENTRY_PREFIX

-- Return the folder key behind a folder header row, or nil for a tag row
local function folderKeyOf(entryID)
    entryID = tostring(entryID or "")
    if string.sub(entryID, 1, #FOLDER_ENTRY_PREFIX) ~= FOLDER_ENTRY_PREFIX then return nil end
    return string.sub(entryID, #FOLDER_ENTRY_PREFIX + 1)
end

-- Name a row's tag or folder the way the store does
local function sidebarEntry(entryID)
    local folderKey = folderKeyOf(entryID)
    if folderKey ~= nil then return { kind = "folder", key = folderKey } end
    return { kind = "tag", tag = entryID }
end

Parts.folderKeyOf = folderKeyOf
Parts.sidebarEntry = sidebarEntry

return Parts
