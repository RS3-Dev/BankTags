-- Name Bank Utilities' own sidebar tabs in order and decide which ones a sidebar can show.
-- The bank controller lists these before other plugins' tabs

local SidebarTabs = {}

SidebarTabs.TAGS = "tags"
SidebarTabs.CLEANUP = "cleanup"
SidebarTabs.QUERIES = "runesql"

-- Built-in tabs in rail order; icons are PrettyUI sprite-button names
local TAGS_TAB = { id = SidebarTabs.TAGS, label = "Tags", tooltip = "Bank tags",
    icon = "LIST_LAYOUT" }
local LOCKED_TAGS_TAB = { id = SidebarTabs.TAGS, label = "Tags",
    tooltip = "The layout editor shows tags only", icon = "LIST_LAYOUT" }
local CLEANUP_TAB = { id = SidebarTabs.CLEANUP, label = "Cleanup",
    tooltip = "Cleanup categories", icon = "ERASER" }
local QUERIES_TAB = { id = SidebarTabs.QUERIES, label = "Queries",
    tooltip = "Saved RuneQL queries", icon = "SEARCH" }

local OWN_TABS = {
    [SidebarTabs.TAGS] = true,
    [SidebarTabs.CLEANUP] = true,
    [SidebarTabs.QUERIES] = true,
}

-- List the tabs a sidebar owner can show now: Tags, Cleanup, and Queries when enabled.
-- A locked sidebar, as in the layout editor, shows only Tags
function SidebarTabs.Available(owner)
    if owner.sidebarLocksMode == true then return { LOCKED_TAGS_TAB } end
    local tabs = { TAGS_TAB, CLEANUP_TAB }
    if owner.settings ~= nil and owner.settings.enableRuneSQL == true then
        tabs[#tabs + 1] = QUERIES_TAB
    end
    return tabs
end

-- Find an available tab by ID
function SidebarTabs.Find(owner, tabID)
    for _, tab in ipairs(SidebarTabs.Available(owner)) do
        if tab.id == tabID then return tab end
    end
    return nil
end

-- Recognize one of these tabs' IDs, whether or not it is available now
function SidebarTabs.IsOwnTab(tabID)
    return OWN_TABS[tabID] == true
end

return SidebarTabs
