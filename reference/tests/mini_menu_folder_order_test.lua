package.path = "./?.lua;./?/init.lua;" .. package.path

Event = { Logic = { Subscribe = function() end, Unsubscribe = function() end } }

-- Model the host menu as observed in game: index 1 is the bottom row and each
-- Add lands in that lowest slot, so actions read top to bottom in add order
-- until Cancel is moved down
local function newMenu()
    local menu = { entries = { { verbText = "Cancel" } } }
    menu.entryCount = 1
    function menu:Add(text)
        table.insert(self.entries, 1, { fullText = text })
        self.entryCount = #self.entries
    end
    function menu:Swap(left, right)
        self.entries[left], self.entries[right] = self.entries[right], self.entries[left]
    end
    return menu
end

-- Read rows top to bottom as the player sees them
local function visibleRows(menu)
    local rows = {}
    for index = #menu.entries, 1, -1 do
        local entry = menu.entries[index]
        rows[#rows + 1] = (entry.fullText or entry.verbText):gsub("<[^>]->", "")
    end
    return rows
end

local function normalizeMenuText(value)
    return string.lower(tostring(value or ""):gsub("<[^>]->", ""):match("^%s*(.-)%s*$"))
end

-- Mirror the observed PrettyUI behaviour: the parent lands in the lowest slot
prettyui = {
    MiniMenu = {
        AddSubmenu = function(menu, label)
            local entry = { fullText = label .. " >" }
            table.insert(menu.entries, 1, entry)
            menu.entryCount = #menu.entries
            return entry
        end,
    },
}

local TagMenu = require("lib/features/tags/tag_menu")
local app = {
    inGame = true,
    store = {
        GetTagFolder = function() return nil end,
        GetFolders = function() return {} end,
    },
    features = {
        HoveredRuneQuery = function() return nil end,
        HoveredFolder = function() return nil end,
        HoveredTag = function() return "overloads" end,
        DisplayTagName = function() return "Overloads" end,
        IsSelectingItemsForTag = function() return false end,
    },
}
local router = TagMenu.new(app, { normalizeMenuText = normalizeMenuText })
local menu = newMenu()
assert(router:AddSidebarMenuEntries(menu))

local rows = visibleRows(menu)
assert(rows[#rows] == "Cancel", "Cancel must be the bottom row: " .. table.concat(rows, " | "))
assert(rows[#rows - 1] == "Add To Folder >", "submenu must sit above Cancel: " .. table.concat(rows, " | "))
assert(rows[#rows - 2]:find("^Remove"), "Remove must keep its place: " .. table.concat(rows, " | "))

-- A placeholder has no native item in its menu, so the page entry under the
-- pointer supplies the item; Cancel stays the default for left clicks
local queued = nil
local placeholderApp = {
    inGame = true,
    store = {},
    features = {
        selectedTag = "overloads",
        ItemSelectionTag = function() return nil end,
        SelectionPage = function() return require("lib/features/tags/tag_page") end,
        DisplayTagName = function() return "Overloads" end,
        PlaceholderAtPointer = function()
            return { objectID = 15332, layoutKey = "object:15332:1" }
        end,
    },
}
local placeholderRouter = TagMenu.new(placeholderApp, { normalizeMenuText = normalizeMenuText })
function placeholderRouter:QueueTagRemoval(pending) queued = pending end
menu = newMenu()
local originalAdd = menu.Add
function menu:Add(text, action)
    originalAdd(self, text)
    self.entries[1].action = action
end
placeholderRouter:AddPlaceholderMenuEntries(menu)
rows = visibleRows(menu)
assert(rows[1] == "Cancel" and rows[2] == "Remove from Overloads",
    "placeholder menu: " .. table.concat(rows, " | "))
menu.entries[1].action()
assert(queued.objectID == 15332 and queued.tag == "overloads"
    and queued.itemKey == "object:15332:1")

-- Nothing is added away from a placeholder
placeholderApp.features.PlaceholderAtPointer = function() return nil end
menu = newMenu()
placeholderRouter:AddPlaceholderMenuEntries(menu)
assert(#menu.entries == 1)

print("mini_menu_folder_order_test: ok")
