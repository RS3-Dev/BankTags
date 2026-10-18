package.path = "./?.lua;./?/init.lua;" .. package.path

-- Return a host component stand-in that accepts any method call or field write
local function node()
    local value = setmetatable({ x = 0, y = 0, width = 0, height = 0 }, {
        __index = function(_, key)
            if key == "opConfig" then return { ClearOpCursors = function() end } end
            if key == "cursorConfig" then return {} end
            return function() end
        end,
    })
    function value:SetPos(x, y) self.x, self.y = x, y end
    function value:SetSize(width, height) self.width, self.height = width, height end
    return value
end
id = { Font = { MUSEO_SANS_11PT_REGULAR = 1 }, Sprite = { BANK_ARROW_UP_0 = 3 } }
ui = {
    AlignMode = { CENTRE = 1, BOTTOMRIGHT = 2 },
    ObjectQuantityDisplayMode = { NEVER = 0, ALWAYS = 2 },
    Hook = {},
    Text = { new = node },
    Rectangle = { new = node },
    Sprite = { new = node },
    Layer = { new = node },
}
prettyui = {
    Tooltip = { attach = function() return node() end },
}

local db, writes = {}, 0
PersistentDB = {
    GetString = function(_, key) return db[key] end,
    SetString = function(_, key, value)
        db[key] = value
        if key:find("manifest", 1, true) then writes = writes + 1 end
        return true
    end,
}

local TagStore = require("lib/features/tags/tag_store")
local TagSidebar = require("lib/features/tags/tag_sidebar")

local store = TagStore.new()
for index, tag in ipairs({ "melee", "food", "skilling" }) do
    assert(store:CreateTag(tag) and store:AddTag(tag, index * 100))
end
assert(store:CreateFolder("Combat", "melee"))
assert(store:SetTagFolder("food", "combat"))

local sidebar = {
    store = store,
    settings = {},
    searchQuery = "",
    selectedTag = "food",
    tagTooltips = {},
    cleanupCategories = { IsRefreshing = function() return false end },
    IsPresetViewOpen = function() return false end,
    IsCleanupMode = function() return false end,
    IsRuneSQLMode = function() return false end,
    IsGeneratedSelection = function() return false end,
}
TagSidebar.install(sidebar)

-- Build list rows the way PrettyUI does and decorate them
local function render(entries)
    sidebar.list = { entryHeight = 32, rows = {} }
    for _, entry in ipairs(entries) do
        sidebar.list.rows[#sidebar.list.rows + 1] = {
            entry = entry, root = node(), label = node(), background = node(),
        }
    end
    sidebar:AttachTagSprites()
end

-- An expanded folder lists its members beneath its header
local entries = sidebar:TagEntries()
assert(#entries == 4)
assert(entries[1].id == TagSidebar.FOLDER_ENTRY_PREFIX .. "combat")
assert(entries[1].expanded and entries[1].memberCount == 2)
assert(entries[2].inFolder and entries[3].inFolder)
assert(entries[4].id == "skilling" and not entries[4].inFolder)
render(entries)
assert(sidebar.list.rows[1].label.content == entries[1].label .. " (2)",
    "folder rows show their tag count after the name")
-- Folder members take the warmer zebra, and one bar runs down the whole folder
assert(entries[2].backgroundColour ~= entries[4].backgroundColour
    and entries[3].backgroundColour ~= entries[4].backgroundColour,
    "folder members use their own row colours")
local rows = sidebar.list.rows
assert(rows[1].bankUtilitiesFolderAccent.height == 32
    and rows[2].bankUtilitiesFolderAccent.height == 32
    and rows[3].bankUtilitiesFolderAccent.height == 30
    and rows[4].bankUtilitiesFolderAccent == nil,
    "the folder bar bridges row gaps and stops at the last member")

-- Collapsing hides members and outlines the folder holding the selected tag
sidebar.list = nil
assert(sidebar:ToggleFolder("combat"))
assert(store:GetFolder("combat").collapsed == true)
entries = sidebar:TagEntries()
assert(#entries == 2 and entries[1].selected == true and not entries[1].expanded)
render(entries)

-- Searching expands folders and a folder-name match lists every member
sidebar.searchQuery = "combat"
entries = sidebar:TagEntries()
assert(#entries == 3 and entries[1].expanded)
sidebar.searchQuery = "food"
entries = sidebar:TagEntries()
assert(#entries == 2 and entries[2].id == "food")

-- Hover lookups distinguish folder headers from tags
sidebar.searchQuery = ""
sidebar.expanded = true
store:SetFolderCollapsed("combat", false)
render(sidebar:TagEntries())
sidebar.list.rows[1].root.isMouseOver = true
assert(sidebar:HoveredFolder() == "combat")
assert(sidebar:HoveredTag() == nil)
sidebar.list.rows[1].root.isMouseOver = false
sidebar.list.rows[2].root.isMouseOver = true
assert(sidebar:HoveredTag() == "melee")
assert(sidebar:HoveredFolder() == nil)

-- Exercise the actual rail callbacks with the supported PrettyUI wrapper APIs
local function control()
    local value = { root = node() }
    function value:SetActive(active) self.active = active end
    function value:SetHidden(hidden) self.hidden = hidden end
    function value:SetTooltip(text) self.tooltip = text end
    function value:Destroy() self.destroyed = true end
    return value
end
local BankControls = require("lib/ui/bank_controls")
BankControls.button = function(_, _, action, options)
    local value = control()
    value.action, value.options = action, options
    return value
end
BankControls.tab = function() return control() end
prettyui.SpriteButton = { new = function(_, _, action, options)
    local value = control()
    value.action, value.options = action, options
    return value
end }
prettyui.TextField = { new = function(_, options)
    local value = { root = node(), onChange = options.onChange }
    function value:SetText(text) self.text = text end
    return value
end }
prettyui.Text = { new = node }
prettyui.Tooltip.registerContext = function() end
prettyui.List = { new = function(_, options)
    local list = { root = node(), viewport = node(), entryHeight = 32,
        scrollY = 96, options = options }
    function list:SetEntries(newEntries)
        self.rows = {}
        for _, entry in ipairs(newEntries) do
            -- Mirror versions of PrettyUI that discard custom entry metadata
            self.rows[#self.rows + 1] = {
                entry = { id = entry.id, enabled = entry.enabled, selected = entry.selected },
                root = node(), label = node(), background = node(),
            }
        end
    end
    function list:_OnScrollWheel(_, delta) self.wheelDelta = delta end
    return list
end }
local cleanup, queries = false, false
sidebar.IsCleanupMode = function() return cleanup end
sidebar.IsRuneSQLMode = function() return queries end
sidebar.ConfigureModeTabs = function() end
sidebar.UpdateLayoutControls = sidebar.UpdateTagSortControl
sidebar.BindNativeTagDrops = function() end
sidebar.searchQuery = "melee"
sidebar:CreateRail(node(), 500)
assert(sidebar.sortButton.options.spriteName == "SWAP")
assert(sidebar.settingsButton.options.spriteName == "EXPORT", "import/share uses a share icon, not a gear")
assert(not sidebar.sortButton.active and #sidebar.tagSortButtons == 0)
local searchWidth = sidebar.search.root.width
sidebar.sortButton.action()
assert(sidebar:IsTagSortMode() and sidebar.searchQuery == "" and sidebar.search.text == "")
assert(sidebar.sortButton.active and #sidebar.tagSortButtons == 8)
assert(sidebar.list.rows[2].label.x == sidebar.list.rows[1].label.x
    and sidebar.list.rows[2].label.x > 6, "folder members indent to line up with the folder name")
assert(sidebar.tagSortButtons[1].options.disabled, "first top-level row cannot move up")
assert(not sidebar.tagSortButtons[2].options.disabled)
assert(sidebar.tagSortButtons[3].options.disabled, "first child cannot move up")
assert(sidebar.tagSortButtons[6].options.disabled, "last child cannot move down")
assert(sidebar.tagSortButtons[8].options.disabled, "last top-level row cannot move down")
local oldButtons, selected = sidebar.tagSortButtons, sidebar.selectedTag
-- Move the second child up through the arrow's real callback
sidebar.tagSortButtons[5].action()
assert(store:TagTree()[1].tags[1] == "food")
assert(sidebar.selectedTag == selected and sidebar.list.scrollY == 96)
for _, button in ipairs(oldButtons) do assert(button.destroyed) end
store.Commit = function(_, _, message) return false, message end
local originalOrder = table.concat(store:AllTags(), ",")
assert(not sidebar:MoveTagSidebarEntry("food", 1))
assert(table.concat(store:AllTags(), ",") == originalOrder)
assert(sidebar.sortButton.tooltip == "Could not save the tag order.")
store.Commit = nil
sidebar.tagSortButtons[1].options._onScrollWheel(nil, 2)
assert(sidebar.list.wheelDelta == 2)
-- Collapsed folders retain their top-level sort controls
sidebar.list.options._onEntryClick(nil, TagSidebar.FOLDER_ENTRY_PREFIX .. "combat", true)
assert(store:GetFolder("combat").collapsed and #sidebar.tagSortButtons == 4)
sidebar.tagSortButtons[2].action()
assert(store:TagTree()[1].tag == "skilling")
assert(store:GetFolder("combat").collapsed and sidebar.selectedTag == selected)
oldButtons = sidebar.tagSortButtons
sidebar.sortButton.action()
assert(not sidebar:IsTagSortMode() and #sidebar.tagSortButtons == 0)
for _, button in ipairs(oldButtons) do assert(button.destroyed) end
-- Typing a filter exits sorting; leaving Tags hides the toggle and restores search width
sidebar.sortButton.action()
sidebar.search.onChange(nil, nil, "food")
assert(not sidebar:IsTagSortMode() and not sidebar.sortButton.active)
assert(#sidebar.tagSortButtons == 0 and sidebar.searchQuery == "food")
cleanup = true
sidebar:UpdateTagSortControl()
assert(sidebar.sortButton.hidden and sidebar.search.root.width > searchWidth)
cleanup, queries = false, true
sidebar:UpdateTagSortControl()
assert(sidebar.sortButton.hidden)
queries = false
sidebar:UpdateTagSortControl()
assert(not sidebar.sortButton.hidden and sidebar.search.root.width == searchWidth)

print("tag_sidebar_folders_test: ok")
