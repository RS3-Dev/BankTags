package.path = "./?.lua;./?/init.lua;" .. package.path

-- Drive the vertical sidebar tab host through a mounted fake bank window and the public
-- API: expanded geometry, built-in tabs and their content, extension tab validation,
-- host-drawn rows that open pages through the API's arbitration, overflow paging, short
-- heights, reopening at a new size, disposal and replacement fallback, and shutdown.
-- FAKE HOST: geometry here is what the code asks of stand-in components, not the client
-- Run all tests with Lua 5.4: lua54 tools/check.lua (toolchain notes in STAGE0_BASELINE.md)

local FakeBankHost = require("tools/test_support/fake_bank_host")
local host = FakeBankHost.install()
host:InstallSidebarWidgets()
local Config = require("lib/core/config")
local TagStore = require("lib/features/tags/tag_store")
local QueryStore = require("lib/features/runesql/query_store")
local Composition = require("tools/test_support/composition")
local ExtensionPages = require("lib/features/extensions/extension_pages")
local PublicAPI = require("lib/core/public_api")
local ImportProviders = require("lib/features/extensions/import_providers")
local HeaderLaunchers = require("lib/features/extensions/header_launchers")
local LauncherPreferences = require("lib/features/extensions/launcher_preferences")

-- Build the public table over a page service and its own import-source registry
local function publicAPI(pages)
    local isLive = function(owner) return pages:IsLive(owner) end
    return PublicAPI.new(pages, ImportProviders.new({ isLive = isLive }), HeaderLaunchers.new({
        isLive = isLive,
        pageExists = function(owner, pageID) return pages:HasPage(owner, pageID) end,
        preferences = LauncherPreferences.new(),
    }))
end
local SidebarTabRail = require("lib/ui/sidebar_tab_rail")
local SidebarTabs = require("lib/features/tags/sidebar_tabs")

config.Obj.iron_bar = { id = 101 }
host:SetItems({
    { 101, 5, "Iron bar" },
    { 102, 5, "Iron ore" },
    { 103, 5, "Lobster" },
})

local store = TagStore.new()
store:SetLayoutPlacement(false)
assert(store:CreateTag("ores") and store:AddTag("ores", 102))
assert(store:CreateTag("food") and store:AddTag("food", 103))
assert(store:CreateFolder("Supplies", "food"))
local queryStore = QueryStore.new()
assert(queryStore:Save(nil, "Bars", "bar"))

local settings = { enableRuneSQL = true }
local layout, features = Composition.NewLayout(store, { settings = settings, queryStore = queryStore })
local service = ExtensionPages.new(layout, {
    isInGame = function() return true end,
    bankIsOpen = function() return host.window ~= nil end,
})
local api = publicAPI(service)

-- Open the bank at a size and attach the sidebar the way the app does
local function openBank(width, height)
    local window = host:MountBankWindow(width, height)
    assert(layout:IsReady() and layout:Apply())
    layout.nativeViewAll = true
    return window
end

-- Close the bank and remove the sidebar
local function closeBank()
    layout:Restore()
    host:UnmountBankWindow()
end

-- List the drawn tab IDs from top to bottom, with the active one starred
local function drawnTabs()
    local ids = {}
    for _, button in ipairs(layout.tabRail.buttons) do
        ids[#ids + 1] = button.tabID .. (button.active and "*" or "")
    end
    return table.concat(ids, " ")
end

-- Press a drawn tab as the player does
local function pressTab(tabID)
    for _, button in ipairs(layout.tabRail.buttons) do
        if button.tabID == tabID then
            button.root.hooks.pressed()
            return
        end
    end
    error("tab " .. tabID .. " is not drawn")
end

-- List the sidebar's row IDs in order: Bank Utilities' rows on its own tabs, the
-- bank's page rows on an extension tab
local function rowIDs()
    local ids = {}
    for _, row in ipairs((layout.list or features.list).rows) do ids[#ids + 1] = row.entry.id end
    return table.concat(ids, " ")
end

-- Expanding the default bank adds the tab rail, its gap, the tag column, and the
-- gutter, and moves the native content over without narrowing it
local window = openBank(714, 650)
assert(window.all.width == 998 and Config.SIDEBAR_WIDTH == 284)
assert(window.content.x == 12 + 284 and window.content.width == 690)
assert(window.host.x == 100 - 142 and window.host.width == 998)
local rail, tabs = layout.rail, layout.tabRail.root
assert(tabs.parent == window.all and rail.parent == window.all)
assert(tabs.x == 12 and tabs.y == 44 and tabs.width == 32 and tabs.height == 594)
assert(rail.x == 52 and rail.y == 44 and rail.width == 236 and rail.height == 594)
-- 8px gaps: tab rail to tag column, and tag column to the native content
assert(tabs.x + tabs.width + 8 == rail.x and rail.x + rail.width + 8 == window.content.x)
-- The rail's tile is an ordinary first child, so the tabs above it keep their order
assert(tabs.children[1] == layout.tabRail.background and layout.tabRail.background.isTiling)
assert(layout.tabRail.background.options == nil)
-- The content starts at the top with room for search, the list, and the footer; on
-- Bank Utilities' own tabs that content belongs to its features, in the bank's column
assert(layout.list == nil and features.search.root.parent == rail)
assert(features.search.root.x == 8 and features.search.root.y == 8)
assert(features.list.root.x == 8 and features.list.root.y == 42)
assert(features.list.root.height == 594 - 42 - 44)

-- Built-in tabs are vertical sprite tabs in order, with Tags selected and framed
assert(drawnTabs() == "tags* cleanup runesql", drawnTabs())
local buttons = layout.tabRail.buttons
for index, expected in ipairs({ { "LIST_LAYOUT", "Bank tags" },
    { "ERASER", "Cleanup categories" }, { "SEARCH", "Saved RuneQL queries" } }) do
    assert(buttons[index].spriteName == expected[1] and buttons[index].tooltipText == expected[2])
    assert(buttons[index].root.x == 0 and buttons[index].root.y == (index - 1) * 36)
    assert(buttons[index].root.width == 32 and buttons[index].root.height == 32)
    -- The icon is a sibling of the button, not its child
    assert(buttons[index].icon.parent == tabs and buttons[index].root.parent == tabs)
end
assert(buttons[1].icon.spriteID == prettyui.Sprites.SPRITE_BUTTONS.LIST_LAYOUT.active)
assert(buttons[2].icon.spriteID == prettyui.Sprites.SPRITE_BUTTONS.ERASER.neutral)
local frame = layout.tabRail.selectionFrame
assert(#frame == 4 and frame[1].y == 0 and frame[2].y == 31 and frame[4].x == 31)
assert(layout.railFrame[1].y == 0 and layout.railFrame[3].height == layout.rail.height)
assert(not layout.tabRail.upArrow and not layout.tabRail.downArrow)

-- Button tooltips use the full window and follow the tab rail's position
local tooltipContext = tabs.tooltipContext
assert(tooltipContext.parent == rail.parent and tooltipContext.parent.width > tabs.width)
local tooltipX, tooltipY = tooltipContext.position(buttons[2].root)
assert(tooltipX == tabs.x and tooltipY == tabs.y + buttons[2].root.y)
assert(rail.tooltipContext.parent == rail.parent)
assert(buttons[1].selection == nil)

-- Tags keep folders, search, sorting, and the New Tag footer
assert(rowIDs() == "ores __bankutils_folder:supplies food", rowIDs())
assert(not features.sortButton.hidden and not features.newTagButton.hidden)
assert(features.search.placeholder == "Search tags...")
features.search:Type("ore")
assert(rowIDs() == "ores")
features.search:Type("")
assert(layout:SetSelectedTag("ores") and layout.selectedTag == "ores")
assert(not features.editButton.hidden)

-- Cleanup: switching tabs leaves the page, as the horizontal tabs did, and scans the bank
pressTab("cleanup")
assert(layout.sidebarMode == "cleanup" and layout.selectedTag == nil)
assert(drawnTabs() == "tags cleanup* runesql" and layout.tabRail.selectionFrame[1].y == 36)
assert(features.search.placeholder == "Search categories...")
assert(features.newTagButton.hidden and features.editButton.hidden and features.sortButton.hidden)
assert(host:Listener("_cleanup_build") ~= nil)
for _ = 1, 4 do host:Tick() end
assert(host:Listener("_cleanup_build") == nil)

-- Queries list saved queries with the New Query footer
pressTab("runesql")
assert(features.search.placeholder == "Search queries...")
assert(rowIDs() == QueryStore.SelectionID(queryStore:All()[1].id))
assert(not features.newQueryButton.hidden and features.newTagButton.hidden)
-- Turning queries off removes the tab and returns to Tags
settings.enableRuneSQL = false
layout:ApplySettings(settings)
assert(layout.sidebarMode == "tags" and drawnTabs() == "tags* cleanup")
settings.enableRuneSQL = true
layout:ApplySettings(settings)
assert(drawnTabs() == "tags* cleanup runesql")

-- Extension tabs are plain data; registering one never selects it or the page
assert(api.LIMITS.tabs == 16 and api.LIMITS.tabsPerOwner == 4 and api.LIMITS.rows == 64)
assert(api.LIMITS.detailLength == 6)
local quest = assert(api.RegisterExtension("example.quest", "Quest"))
assert(quest:RegisterPage("smithing", { title = "Smithing", items = { "iron_bar", 102 } }))
assert(quest:RegisterPage("cooking", { title = "Cooking", items = { 103 } }))
local questTab = {
    label = "Quest Helper",
    icon = "STAR",
    tooltip = "Quest item checklists",
    emptyText = "No quests tracked.",
    rows = {
        { heading = "Skills" },
        { page = "smithing", detail = "2", item = "iron_bar" },
        { page = "cooking", label = "Cook's food" },
    },
}
assert(layout:SetSelectedTag("ores"))
assert(quest:RegisterTab("quests", questTab))
assert(layout.sidebarMode == "tags" and layout.selectedTag == "ores")
local questTabID = "__bankutils_ext_tab:example.quest/quests"
assert(drawnTabs() == "tags* cleanup runesql " .. questTabID, drawnTabs())
assert(layout.tabRail.buttons[4].spriteName == "STAR")
assert(layout.tabRail.buttons[4].tooltipText == "Quest item checklists")
local state = quest:GetState()
assert(state.tabs[1] == "quests" and state.activeTab == nil and #state.tabs == 1)

-- Tab input is checked in full and refused with a reason
local function refuses(expected, tabID, input)
    local ok, reason, detail = quest:RegisterTab(tabID, input)
    assert(not ok and reason == expected, tostring(reason) .. " " .. tostring(detail))
end
refuses("invalid_tab_id", "bad id", questTab)
refuses("duplicate_tab", "quests", questTab)
refuses("invalid_tab", "t", nil)
refuses("invalid_tab", "t", { icon = "STAR" })
refuses("invalid_tab", "t", { label = "T", icon = "NOT_A_SPRITE" })
refuses("invalid_tab", "t", { label = "T", icon = 4 })
refuses("invalid_tab", "t", { label = "T", icon = "STAR", onClick = function() end })
refuses("invalid_tab", "t", { label = "T", icon = "STAR", tooltip = "" })
refuses("unknown_page", "t", { label = "T", icon = "STAR", rows = { { page = "missing" } } })
refuses("invalid_tab", "t", { label = "T", icon = "STAR", rows = { { page = "smithing" },
    { page = "smithing" } } })
refuses("invalid_tab", "t", { label = "T", icon = "STAR", rows = { { heading = "H", page = "smithing" } } })
refuses("invalid_tab", "t", { label = "T", icon = "STAR", rows = { { page = "smithing", detail = "1234567" } } })
refuses("unknown_item", "t", { label = "T", icon = "STAR", rows = { { page = "smithing", item = "nope" } } })
refuses("invalid_tab", "t", { label = "T", icon = "STAR", rows = { { page = "smithing", x = 1, y = 2 } } })
refuses("invalid_tab", "t", { label = "T", icon = "STAR", rows = { function() end } })
local tooManyRows = {}
for index = 1, 65 do tooManyRows[index] = { heading = "H" .. index } end
refuses("invalid_tab", "t", { label = "T", icon = "STAR", rows = tooManyRows })
-- Reading a tab never runs the caller's metamethods
refuses("invalid_tab", "t", setmetatable({}, { __index = function() error("metamethod ran") end }))
assert(#quest:GetState().tabs == 1)
-- An invalid update keeps the last good tab
local rejected, reason = quest:UpdateTab("quests", { label = "", icon = "STAR" })
assert(not rejected and reason == "invalid_tab")
assert(select(2, quest:UpdateTab("other", questTab)) == "unknown_tab")
assert(layout.extensionTabs[1].label == "Quest Helper" and #layout.extensionTabs[1].rows == 3)
-- The caller's table is copied
questTab.rows[2].detail = "99"
assert(layout.extensionTabs[1].rows[2].detail == "2")

-- Selecting the extension tab shows its host-drawn rows: a heading, then page rows
-- titled from the page or the row, with the row's detail and item icon
pressTab(questTabID)
assert(layout.sidebarMode == questTabID and layout.selectedTag == nil)
assert(quest:GetState().activeTab == "quests")
assert(drawnTabs() == "tags cleanup runesql " .. questTabID .. "*")
assert(layout.search.placeholder == "Search pages...")
local smithing = "__bankutils_ext:example.quest/smithing"
local cooking = "__bankutils_ext:example.quest/cooking"
assert(rowIDs() == "__bankutils_group:tab:1 " .. smithing .. " " .. cooking, rowIDs())
assert(layout.list.rows[2].entry.label == "Smithing" and layout.list.rows[3].entry.label == "Cook's food")
assert(layout.rowStatus[smithing] == "2" and layout.rowStatus[cooking] == nil)
assert(#layout.rowIcons == 1 and layout.rowIcons[1].associatedObjectID == 101)
-- Extension tabs carry no tag actions: Bank Utilities' content is gone, its footer keeps
-- only Import/Share, and nothing accepts tag drops
assert(features.list == nil and features.search == nil and features.sortButton == nil)
assert(layout.search.root.parent == layout.rail)
assert(features.newTagButton.hidden and features.editButton.hidden)
assert(not features.settingsButton.hidden and not features:IsTagsMode())
assert(features:NativeTagDropTarget() == nil and features:HoveredTag() == nil)
-- Searching filters rows, keeping a heading only above a matching row
layout.search:Type("cook")
assert(rowIDs() == "__bankutils_group:tab:1 " .. cooking)
layout.search:Type("zzz")
assert(layout.list.root.hidden and layout.emptyLabel.content == "No matching pages.")
layout.search:Type("")

-- A row opens its page through the API's page path, and pressing it again leaves it
assert(layout.list:Click(smithing))
assert(layout.selectedTag == smithing and quest:GetState().openPage == "smithing")
assert(#layout:VisibleMirrorEntries() == 2)
assert(layout.list.rows[2].entry.selected)
assert(layout.list:Click(smithing))
assert(layout.selectedTag == nil and quest:GetState().openPage == nil)
-- A refused open leaves the bank as it was and shows the native guidance
layout.nativeViewAll = false
assert(layout.list:Click(cooking))
assert(layout.selectedTag == nil and layout.viewAllWarningPanel ~= nil)
assert(not layout.list.rows[3].entry.selected)
layout:StopViewAllWarning()
layout.nativeViewAll = true
-- Rows use the API's arbitration, so a row pressed during a page change is refused
layout.pageTransitions = 1
assert(layout.list:Click(cooking) and layout.selectedTag == nil)
layout.pageTransitions = 0
assert(select(2, service:OpenSelection("__bankutils_ext:example.quest/none")) == "unknown_page")

-- Updating a page retitles its row; removing it drops the row and leaves the page
assert(layout.list:Click(cooking) and layout.selectedTag == cooking)
assert(quest:UpdatePage("smithing", { title = "Smithing list", items = { 101 } }))
assert(layout.list.rows[2].entry.label == "Smithing list")
assert(quest:RemovePage("cooking"))
assert(layout.selectedTag == nil and rowIDs() == "__bankutils_group:tab:1 " .. smithing)
-- Registering the page again brings its row back
assert(quest:RegisterPage("cooking", { title = "Cooking", items = { 103 } }))
assert(rowIDs() == "__bankutils_group:tab:1 " .. smithing .. " " .. cooking)
assert(quest:RemovePage("cooking"))
-- An emptied tab says so in its own words
assert(quest:UpdateTab("quests", { label = "Quest Helper", icon = "STAR",
    emptyText = "No quests tracked." }))
assert(layout.list.root.hidden and layout.emptyLabel.content == "No quests tracked.")
assert(quest:UpdateTab("quests", { label = "Quest Helper", icon = "STAR",
    rows = { { page = "smithing" } } }))

-- Opening a page from the API leaves the selected tab alone
pressTab("tags")
assert(quest:OpenPage("smithing") and layout.sidebarMode == "tags")
assert(layout.selectedTag == smithing)
assert(layout:SetSelectedTag(nil))

-- Many tabs overflow into paging arrows, and the active tab is always brought into view
local owners = { quest }
for index = 1, 3 do
    local owner = assert(api.RegisterExtension("example.extra" .. index, "Extra " .. index))
    assert(owner:RegisterPage("p", { title = "Page " .. index, items = { 101 } }))
    owners[#owners + 1] = owner
end
for _, owner in ipairs(owners) do
    for index = 1, 4 do
        if owner ~= quest or index > 1 then
            assert(owner:RegisterTab("t" .. index, { label = "Tab " .. index, icon = "PIN",
                rows = owner == quest and {} or { { page = "p" } } }))
        end
    end
end
-- 4 tabs per owner and 16 extension tabs in all
assert(select(2, quest:RegisterTab("t5", { label = "T", icon = "PIN" })) == "too_many_tabs")
local fifth = assert(api.RegisterExtension("example.fifth", "Fifth"))
assert(select(2, fifth:RegisterTab("t", { label = "T", icon = "PIN" })) == "too_many_tabs")
assert(#layout.extensionTabs == 16 and layout.sidebarMode == "tags")
-- Ordered by owner ID, then registration: extra1..3 sort before quest
assert(layout.extensionTabs[1].id == "__bankutils_ext_tab:example.extra1/t1")
assert(layout.extensionTabs[13].id == questTabID)
-- 19 tabs in 594px: arrows top and bottom with 15 tabs between them
local view = layout.tabRail.view
assert(view.arrows and view.first == 1 and view.shown == 15 and #layout.tabRail.buttons == 15)
assert(layout.tabRail.buttons[1].root.y == 24 and layout.tabRail.buttons[15].root.y == 24 + 14 * 36)
assert(layout.tabRail.upArrow.root.y == 0 and layout.tabRail.upArrow.disabled)
assert(layout.tabRail.downArrow.root.y == 594 - 20 and not layout.tabRail.downArrow.disabled)
assert(layout.tabRail.buttons[15].root.y + 32 <= layout.tabRail.downArrow.root.y)
-- Selecting the last tab pages it into view
local lastTabID = "__bankutils_ext_tab:example.quest/t4"
layout:SetSidebarMode(lastTabID)
view = layout.tabRail.view
assert(view.first == 5 and layout.tabRail.buttons[15].tabID == lastTabID)
assert(layout.tabRail.buttons[15].active and layout.tabRail.selectionFrame[1].y == 24 + 14 * 36)
assert(layout.tabRail.downArrow.disabled and not layout.tabRail.upArrow.disabled)
-- The arrows page without changing the selected tab
layout.tabRail.upArrow.root.hooks.pressed()
assert(layout.tabRail.view.first == 4 and layout.sidebarMode == lastTabID)
assert(layout.tabRail.selectionFrame == nil)
for _ = 1, 10 do layout.tabRail.upArrow.root.hooks.pressed() end
assert(layout.tabRail.view.first == 1 and layout.tabRail.upArrow.disabled)
-- Any later change brings the active tab back
layout:UpdateLayoutControls()
assert(layout.tabRail.view.first == 5 and layout.tabRail.selectionFrame ~= nil)

-- Closing and reopening a shorter bank keeps the active tab reachable
closeBank()
assert(layout.tabRail == nil and layout.rail == nil and layout.sidebarMode == lastTabID)
window = openBank(714, 300)
assert(window.content.height == 244 and layout.tabRail.root.height == 244)
view = layout.tabRail.view
assert(view.arrows and view.shown == 5 and view.first == 15)
assert(layout.tabRail.buttons[5].tabID == lastTabID and layout.tabRail.buttons[5].active)
assert(layout.tabRail.downArrow.root.y == 224)
for _, button in ipairs(layout.tabRail.buttons) do
    assert(button.root.y >= 24 and button.root.y + 32 <= 224 - 4)
end
assert(layout.list.root.height == 244 - 42 - 44)
-- Too short for arrows: only the active tab is drawn
local short = SidebarTabRail.Layout(19, 7, 1, 60)
assert(short.first == 7 and short.shown == 1 and not short.arrows)
local fits = SidebarTabRail.Layout(3, 2, 1, 104)
assert(fits.first == 1 and fits.shown == 3 and not fits.arrows)
closeBank()

-- Registrations made while the bank is closed appear when it opens
assert(fifth:Dispose())
assert(quest:RemoveTab("t4"))
assert(layout.sidebarMode == "tags", "removing the selected tab returns to Tags")
assert(layout.selectedTag == nil)
window = openBank(714, 650)
assert(#layout.extensionTabs == 15 and layout.tabRail.view.first == 1)

-- Disposing the owner of the selected tab returns the sidebar to Tags, leaving another
-- owner's shown page in place
local extraTabID = "__bankutils_ext_tab:example.extra1/t1"
pressTab(extraTabID)
assert(layout.sidebarMode == extraTabID)
assert(owners[2]:OpenPage("p"))
assert(layout.selectedTag == "__bankutils_ext:example.extra1/p")
assert(owners[3]:OpenPage("p") and layout.selectedTag == "__bankutils_ext:example.extra2/p")
assert(owners[2]:Dispose())
assert(layout.sidebarMode == "tags" and drawnTabs():sub(1, 5) == "tags*")
assert(layout.selectedTag == "__bankutils_ext:example.extra2/p")
assert(owners[2]:Dispose(), "disposing again changes nothing")
assert(select(2, owners[2]:RegisterTab("t9", { label = "T", icon = "PIN" })) == "stale_handle")

-- Re-registering an owner replaces its tabs and leaves its shown page; the new owner's
-- tabs are not selected
local extraTwoTabID = "__bankutils_ext_tab:example.extra2/t1"
pressTab(extraTwoTabID)
assert(owners[3]:OpenPage("p"))
local replaced = assert(api.RegisterExtension("example.extra2", "Extra 2"))
assert(layout.sidebarMode == "tags" and layout.selectedTag == nil)
assert(select(2, owners[3]:UpdateTab("t1", { label = "T", icon = "PIN" })) == "stale_handle")
assert(replaced:RegisterPage("p", { title = "Again", items = { 101 } }))
assert(replaced:RegisterTab("t1", { label = "Again", icon = "PIN", rows = { { page = "p" } } }))
assert(layout.sidebarMode == "tags" and #layout.extensionTabs == 8)

-- The editor's locked sidebar lists only Tags, whatever extensions are registered
local locked = SidebarTabs.Available({ sidebarLocksMode = true, extensionTabs = layout.extensionTabs,
    settings = { enableRuneSQL = true } })
assert(#locked == 1 and locked[1].id == "tags")

-- Shutting the API down drops every extension tab and returns to Tags
pressTab(extraTwoTabID)
service:Close()
assert(layout.sidebarMode == "tags" and #layout.extensionTabs == 0)
assert(drawnTabs() == "tags* cleanup runesql")
assert(select(2, replaced:RegisterTab("t2", { label = "T", icon = "PIN" })) == "stale_handle")
assert(select(2, service:OpenSelection("__bankutils_ext:example.extra2/p")) == "stale_api")

-- Closing the bank removes the rail and restores the native window
local tabRail = layout.tabRail
closeBank()
assert(tabRail.root == nil and layout.tabRail == nil)
assert(window.all.width == 714 and window.content.x == 12)

print("sidebar_tabs_test: ok")
