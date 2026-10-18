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
id = { Font = { MUSEO_SANS_11PT_REGULAR = 1 },
    Sprite = { BANK_ARROW_UP_0 = 3, RS3_ICON_SLOT_40PX_1 = 4 } }
ui = {
    AlignMode = { CENTRE = 1, BOTTOMRIGHT = 2 },
    ObjectQuantityDisplayMode = { NEVER = 0, ALWAYS = 2 },
    Hook = {},
    Text = { new = node },
    Rectangle = { new = node },
    Sprite = { new = node },
    Layer = { new = node },
}
prettyui = { Tooltip = { attach = function() return node() end,
    registerContext = function() end, unregisterContext = function() end } }
PersistentDB = {
    GetString = function() return nil end,
    SetString = function() return true end,
}

-- Return a sidebar control stand-in that records its state
local function control(options)
    local value = { root = node(), options = options or {} }
    for _, name in ipairs({ "Active", "Hidden", "Disabled", "Selected", "Tooltip" }) do
        value["Set" .. name] = function(self, state) self[string.lower(name)] = state end
    end
    function value:SetSize() end
    function value:SetBounds() end
    function value:Destroy() self.destroyed = true end
    return value
end
local BankControls = require("lib/ui/bank_controls")
BankControls.button = function(_, label, action, options)
    local value = control(options)
    value.label, value.action = label, action
    return value
end
BankControls.tab = function(_, label, action)
    local value = control()
    value.label, value.action = label, action
    return value
end
prettyui.SpriteButton = { new = function(_, _, action, options)
    local value = control(options)
    value.action = action
    return value
end }
prettyui.TextField = { new = function(_, options)
    local value = { root = node(), onChange = options.onChange }
    function value:SetText(text) self.text = text end
    function value:SetPlaceholder(text) self.placeholder = text end
    function value:Destroy() end
    return value
end }
prettyui.Text = { new = node }
prettyui.List = { new = function(_, options)
    local list = { root = node(), viewport = node(), entryHeight = 32, options = options }
    function list:SetEntries(entries)
        self.rows = {}
        for _, entry in ipairs(entries) do
            self.rows[#self.rows + 1] = { entry = entry, root = node(), label = node(),
                background = node() }
        end
    end
    function list:SetSize() end
    function list:Destroy() end
    return list
end }

local TagStore = require("lib/features/tags/tag_store")
local LayoutEditorWindow = require("lib/features/tags/layout_editor_window")
local store = TagStore.new()
assert(store:CreateTag("food") and store:AddTag("food", 1))
assert(store:CreateTag("melee") and store:AddTag("melee", 2))
assert(store:CreateFolder("Combat", "melee"))

-- A stand-in editor that records what the sidebar asks of it
local changes = {}
local editor = {
    selectedTag = "food",
    window = { Close = function(self) self.closed = true end },
    onChanged = function(tag) changes[#changes + 1] = tag or "none" end,
}
function editor:SelectTag(tag) self.selectedTag = tag end
function editor:CreateNewTag() self.creating = true end

local sidebar = LayoutEditorWindow.EditorSidebar.new(editor, { store = store, settings = {} })
sidebar:CreateRail(node(), 594, 4, 12)

-- The editor uses the bank sidebar itself, placed in its own left column: the tab
-- rail at the column's edge and the tag column 40px in, as in the bank
assert(sidebar.tabRail.root.x == 4 and sidebar.tabRail.root.y == 12)
assert(sidebar.rail.x == 44 and sidebar.rail.y == 12)
-- The rail shows only the selected Tags tab; Cleanup and Queries are not drawn
local tabButtons = sidebar.tabRail.buttons
assert(#tabButtons == 1 and tabButtons[1].tabID == "tags" and tabButtons[1].options.active)
assert(tabButtons[1].options.tooltip == "The layout editor shows tags only")
assert(sidebar.tabRail.selectionFrame ~= nil)
assert(not sidebar.sortButton.hidden, "sorting stays available in the editor")
assert(sidebar.editButton.options.spriteName == "CROSS")
assert(sidebar.editButton.tooltip == "Close layout editor" and not sidebar.editButton.hidden)

-- The rows include folders, and the open tag is selected
local ids = {}
for _, row in ipairs(sidebar.list.rows) do ids[#ids + 1] = row.entry.id end
assert(table.concat(ids, ","):find("__bankutils_folder:combat", 1, true))
for _, row in ipairs(sidebar.list.rows) do
    if row.entry.id == "food" then assert(row.entry.selected) end
end

-- Footer actions: New Tag opens the editor's draft, the cross closes the editor
sidebar.newTagButton.action()
assert(editor.creating)
sidebar.editButton.action()
assert(editor.window.closed)

-- Choosing a tag loads it; choosing the open tag again keeps it open
sidebar.list.options._onEntryClick(sidebar.list, "melee", true)
assert(editor.selectedTag == "melee")
sidebar.list.options._onEntryClick(sidebar.list, "melee", false)
assert(editor.selectedTag == "melee")

-- Search filters the rows by tag name
sidebar.search.onChange(nil, nil, "foo")
assert(#sidebar.list.rows == 1 and sidebar.list.rows[1].entry.id == "food")
sidebar.search.onChange(nil, nil, "")

-- Folder and order changes made here also refresh the bank's sidebar
sidebar.list.options._onEntryClick(sidebar.list, "__bankutils_folder:combat", true)
assert(store:GetFolder("combat").collapsed and #changes == 1)

-- Clicking the Tags tab keeps the Tags view
tabButtons[1].action()
assert(sidebar:IsTagsMode() and sidebar:ActiveSidebarTab() == "tags")
assert(#sidebar.tabRail.buttons == 1)

sidebar:DestroyRail()
assert(sidebar.rail == nil and sidebar.list == nil and sidebar.tabRail == nil)

print("editor_sidebar_test: ok")
