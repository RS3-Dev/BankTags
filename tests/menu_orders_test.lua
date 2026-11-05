package.path = "./?.lua;./?/init.lua;" .. package.path

-- Check item and sidebar actions across menu insertion orders
-- FAKE HOST: stand-in components, loader, and menus

local Harness = require("tools/test_support/tags_harness")
local h = Harness.new("menu_orders")
local host = h.bankHost
host:SetItems({ { 4151, 1, "Abyssal whip" }, { 4151, 1, "Abyssal whip" }, { 385, 20, "Shark" } })
host.itemLayer.interfaceID = 517
h:LoadCore()
h:LoadTags()
local app = h:App()
local session, layout = h:OpenBank()
h:Tick(2)
assert(h.menuSubscriptions.banktags_menu ~= nil and h.menuSubscriptions.bankcore_menu ~= nil)

local TagLayouts = h:TagsModule("banktags/tags/tag_layouts")
assert(session.publicAPI.Register({ id = "other", name = "Other", icon = "STAR",
    column = { mount = function() end } }))
h:Tick(2)
-- Select mode's left click names the clicked item
local NAMES = { "Abyssal whip", "Abyssal whip", "Shark" }
-- Read an item's Add to menu label
local function addLabel(slot)
    return "Add to Ranged <col=f2c66d>" .. NAMES[slot] .. "</col>"
end
-- Point at a tag row in the Tags tab
local function pointAtRow(tag)
    local row = app.tab:RowFor(tag)
    app.tab.controls.list.list.scrollY = row.root.y
    h:PointAt(row.root, 20, 10 - row.root.y)
end
-- Restore test tags with duplicate and absent bank items
local function resetTags()
    for _, tag in ipairs({ "melee", "ranged" }) do
        if app.store.data.tags[tag] ~= nil then assert(app.store:DeleteTag(tag)) end
        assert(app.store:CreateTag(tag))
    end
    app.store.data.tags.melee.rows = { { kind = "row", slots = {
        TagLayouts.Item(4151), TagLayouts.Item(4151), TagLayouts.Item(4151), TagLayouts.Item(999) } } }
    assert(app.store:Save())
    app:Changed()
    h:Tick(2)
end
-- Run the menu's default action without native withdrawal
local function leftClick(menu)
    return Harness.LeftClick(menu)
end

for _, order in ipairs({ "core_first", "tags_first" }) do
    for _, placement in ipairs({ "documented", "above_cancel", "below_default" }) do
        local where = " (" .. order .. ", " .. placement .. ")"
        h.menuOrder, h.placement = order, placement
        resetTags()

        -- Rows show their actions top down above Cancel; chosen entries run next tick
        assert(app.store:CreateFolder("Combat", "melee"))
        app:Changed()
        -- Check a tag's Add to menu label
        local function shows(id, expected)
            pointAtRow(id)
            local menu = h:ContentMenu()
            local shown = table.concat(Harness.DisplayedLabels(menu), "|")
            assert(shown == table.concat(expected, "|") .. "|Cancel", shown .. where)
            return menu
        end
        -- Check whether a menu contains a named entry
        local function named(labels, name)
            local out = {}
            for index, label in ipairs(labels) do out[index] = label .. " <col=f2c66d>" .. name .. "</col>" end
            return out
        end
        local ARROW = " <col=ffffff><gt></col>"
        local addRanged = "Add to folder <col=f2c66d>Ranged</col>" .. ARROW
        local moveMelee = "Move to folder <col=f2c66d>Melee</col>" .. ARROW
        local labels = named({ "Select", "Edit", "Rename", "Select items", "Remove" }, "Ranged")
        table.insert(labels, 5, addRanged)
        local menu = shows("ranged", labels)
        assert(#Harness.Submenus(menu) == 1 and Harness.Submenu(menu, addRanged).options.title == "Add to folder", where)
        labels = named({ "Select", "Edit", "Rename", "Select items", "Remove from folder", "Remove" }, "Melee")
        labels[5] = "Remove from folder <col=f2c66d>Combat</col>"
        table.insert(labels, 5, moveMelee)
        menu = shows("melee", labels)
        assert(Harness.Submenu(menu, moveMelee).options.title == "Move to folder", where)

        -- The folder submenu lists other folders, then Create new folder and Cancel
        if app.store.data.tags.magic ~= nil then assert(app.store:DeleteTag("magic")) end
        assert(app.store:CreateTag("magic") and app.store:CreateFolder("Archery", "magic"))
        app:Changed()
        -- Read the actions in the named submenu
        local function children(id, label)
            pointAtRow(id)
            menu = h:ContentMenu()
            return table.concat(Harness.ChildLabels(Harness.Submenu(menu, label)), "|")
        end
        local folders = children("ranged", addRanged)
        assert(folders == "Combat|Archery|Create new folder|Cancel", folders .. where)
        folders = children("melee", moveMelee)
        assert(folders == "Archery|Create new folder|Cancel", folders .. where)
        -- A child moves the tag on the next tick, once, and expands the folder
        app.store:SetFolderCollapsed("archery", true)
        pointAtRow("melee")
        menu = h:ContentMenu()
        Harness.ChooseChild(menu, moveMelee, "Archery")
        assert(app.store:GetTagFolder("melee") == "combat", where)
        Harness.ChooseChild(menu, moveMelee, "Archery")
        Harness.Choose(menu, "Remove <col=f2c66d>Melee</col>")
        h:Tick(2)
        assert(app.store:GetTagFolder("melee") == "archery" and not app.store:GetFolder("archery").collapsed, where)
        assert(app.windows.tagDeleteConfirm == nil, where)
        pointAtRow("ranged")
        Harness.ChooseChild(h:ContentMenu(), addRanged, "Archery")
        h:Tick(2)
        assert(app.store:GetTagFolder("ranged") == "archery" and app.store:CreateFolder("Combat", "melee"), where)
        -- Cancel, and a menu that was never opened, move nothing
        local moveRanged = "Move to folder <col=f2c66d>Ranged</col>" .. ARROW
        pointAtRow("ranged")
        Harness.ChooseChild(h:ContentMenu(), moveRanged, "Cancel")
        pointAtRow("ranged")
        menu = h:ContentMenu()
        for _, child in ipairs(Harness.Submenu(menu, moveRanged).children) do
            if child.label == "Combat" then child.action() end
        end
        h:Tick(2)
        assert(app.store:GetTagFolder("ranged") == "archery", where)
        -- A child chosen after a row click, a removed folder, or a rebuilt tab moves nothing
        pointAtRow("ranged")
        menu = h:ContentMenu()
        h:ClickRow("ranged")
        Harness.ChooseChild(menu, moveRanged, "Combat")
        h:Tick(2)
        assert(app.store:GetTagFolder("ranged") == "archery" and app:ToggleTag("ranged"), where)
        h:Tick(2)
        assert(app:ShownTag() == nil, where)
        pointAtRow("ranged")
        menu = h:ContentMenu()
        Harness.ChooseChild(menu, moveRanged, "Combat")
        assert(app:DeleteFolder("combat"))
        h:Tick(2)
        assert(app.store:GetTagFolder("ranged") == "archery" and app.store:GetFolder("combat") == nil, where)
        assert(app.store:CreateFolder("Combat", "melee"))
        pointAtRow("ranged")
        menu = h:ContentMenu()
        layout:SetSidebarMode("__bankutils_ext_tab:other")
        h:Tick(2)
        layout:SetSidebarMode("__bankutils_ext_tab:banktags")
        h:Tick(2)
        Harness.ChooseChild(menu, moveRanged, "Combat")
        h:Tick(2)
        assert(app.store:GetTagFolder("ranged") == "archery", where)
        -- A removed tag's child moves nothing
        pointAtRow("magic")
        menu = h:ContentMenu()
        Harness.ChooseChild(menu, "Move to folder <col=f2c66d>Magic</col>" .. ARROW, "Combat")
        assert(app.store:DeleteTag("magic"))
        h:Tick(2)
        assert(app.store.data.tags.magic == nil and app.store:GetTagFolder("ranged") == "archery", where)
        -- Create new folder opens the naming prompt, which files the tag under the new folder
        pointAtRow("ranged")
        Harness.ChooseChild(h:ContentMenu(), moveRanged, "Create new folder")
        assert(app.windows.textPrompt == nil, where)
        h:Tick(2)
        assert(app.windows.textPrompt ~= nil, where)
        app.windows.textPrompt:Save("Bows")
        assert(app.store:GetTagFolder("ranged") == "bows", where)
        app.windows:Close("textPrompt")
        assert(app:MoveTagToFolder("ranged", nil) and app.store:GetTagFolder("melee") == "combat", where)
        app:Changed()
        h:Tick(2)
        -- A folder name made of markup brackets still leaves a usable submenu
        assert(app.store:CreateFolder("<>", "ranged"))
        app:Changed()
        h:Tick(2)
        pointAtRow("melee")
        menu = h:ContentMenu()
        assert(table.concat(Harness.ChildLabels(Harness.Submenu(menu, moveMelee)), "|")
            == "Folder|Create new folder|Cancel", where)
        assert(app:MoveTagToFolder("ranged", nil))
        h:Tick(2)
        local folderRow = "__banktags_folder:combat"
        menu = shows(folderRow, named({ "Collapse", "Rename folder", "Ungroup folder" }, "Combat"))
        assert(#Harness.Submenus(menu) == 0, where)
        -- Chosen from the open menu, the default runs once
        Harness.Choose(menu, "Collapse <col=f2c66d>Combat</col>")
        h:Tick(2)
        assert(app.store:GetFolder("combat").collapsed, where)
        menu = shows(folderRow, named({ "Expand", "Rename folder", "Ungroup folder" }, "Combat"))
        -- Deliver both the menu default and row click
        local function click(id) h:ClickRow(id) end
        -- Deliver the row's native press and release
        local function leftClickRow(id)
            pointAtRow(id)
            local default = leftClick(h:ContentMenu())
            click(id)
            h:Tick(2)
            return default
        end
        assert(leftClickRow(folderRow) == "Expand <col=f2c66d>Combat</col>"
            and not app.store:GetFolder("combat").collapsed, where)
        assert(leftClickRow(folderRow) == "Collapse <col=f2c66d>Combat</col>"
            and app.store:GetFolder("combat").collapsed, where)
        assert(leftClickRow(folderRow) == "Expand <col=f2c66d>Combat</col>", where)
        assert(leftClickRow("ranged") == "Select <col=f2c66d>Ranged</col>" and app:ShownTag() == "ranged", where)
        assert(leftClickRow("ranged") == "Select <col=f2c66d>Ranged</col>" and app:ShownTag() == nil, where)
        -- Deliver the row click before its menu action
        local function rowThenMenu(id, rebuilt)
            pointAtRow(id)
            local menu = h:ContentMenu()
            click(id)
            if rebuilt then
                h:Tick()
                pointAtRow(id)
                menu = h:ContentMenu()
            end
            leftClick(menu)
            h:Tick(2)
        end
        for _, rebuilt in ipairs({ false, true }) do
            rowThenMenu("ranged", rebuilt)
            assert(app:ShownTag() == "ranged", where)
            rowThenMenu("ranged", rebuilt)
            assert(app:ShownTag() == nil, where)
            rowThenMenu(folderRow, rebuilt)
            assert(app.store:GetFolder("combat").collapsed, where)
            rowThenMenu(folderRow, rebuilt)
            assert(not app.store:GetFolder("combat").collapsed, where)
        end
        -- Deliver the menu action before the row click
        local function menuThenLateRow(id, repeats)
            pointAtRow(id)
            local menu = h:ContentMenu()
            for _ = 1, repeats do
                leftClick(menu)
                h:Tick(2)
            end
            click(id)
            h:Tick(2)
        end
        menuThenLateRow("ranged", 1)
        assert(app:ShownTag() == "ranged", where)
        menuThenLateRow("ranged", 2)
        assert(app:ShownTag() == nil, where)
        menuThenLateRow(folderRow, 2)
        assert(app.store:GetFolder("combat").collapsed, where)
        menuThenLateRow(folderRow, 1)
        assert(not app.store:GetFolder("combat").collapsed, where)
        -- Repeated left clicks each toggle once, whenever their menus were built
        for count = 1, 4 do
            pointAtRow("ranged")
            local before = h:ContentMenu()
            click("ranged")
            leftClick(before)
            h:Tick()
            pointAtRow("ranged")
            leftClick(h:ContentMenu())
            h:Tick()
            assert(app:ShownTag() == (count % 2 == 1 and "ranged" or nil), count .. where)
        end
        -- The row answers the left click, so the default alone does nothing
        local pages = session.pluginPages
        local leave, leaves = pages.ClosePage, 0
        pages.ClosePage = function(...)
            leaves = leaves + 1
            return leave(...)
        end
        pointAtRow("ranged")
        assert(leftClick(h:ContentMenu()) == "Select <col=f2c66d>Ranged</col>", where)
        h:Tick(4)
        assert(app:ShownTag() == nil and leaves == 0, where)
        -- Check that an explicit Select choice runs once
        local function chooseSelect(id, label)
            pointAtRow(id)
            local menu = h:ContentMenu()
            Harness.Choose(menu, label)
            Harness.Choose(menu, label)
            h:Tick(4)
        end
        chooseSelect("ranged", "Select <col=f2c66d>Ranged</col>")
        assert(app:ShownTag() == "ranged" and leaves == 0, where)
        chooseSelect("ranged", "Select <col=f2c66d>Ranged</col>")
        assert(app:ShownTag() == nil and layout.shownPage == nil and leaves == 1, where)
        chooseSelect(folderRow, "Collapse <col=f2c66d>Combat</col>")
        assert(app.store:GetFolder("combat").collapsed, where)
        chooseSelect(folderRow, "Expand <col=f2c66d>Combat</col>")
        assert(not app.store:GetFolder("combat").collapsed, where)
        pages.ClosePage = nil
        -- Row clicks alone still toggle
        click("melee")
        assert(app:ShownTag() == "melee", where)
        click("melee")
        assert(app:ShownTag() == nil, where)
        click("melee")
        assert(app:ShownTag() == "melee", where)
        click("melee")
        assert(app:ShownTag() == nil, where)
        h:Tick(2)
        -- An entry chosen after a row click, or from a rebuilt tab, does nothing
        pointAtRow("ranged")
        menu = h:ContentMenu()
        h:ClickRow("melee")
        Harness.Choose(menu, "Edit <col=f2c66d>Ranged</col>")
        h:Tick(2)
        assert(app:ShownTag() == "melee" and app.windows.tagSettingsEditor == nil, where)
        assert(app:ToggleTag("melee") and app:ShownTag() == nil)
        h:Tick(2)
        pointAtRow("ranged")
        menu = h:ContentMenu()
        layout:SetSidebarMode("__bankutils_ext_tab:other")
        h:Tick(2)
        layout:SetSidebarMode("__bankutils_ext_tab:banktags")
        h:Tick(2)
        Harness.Choose(menu, "Select <col=f2c66d>Ranged</col>")
        h:Tick(2)
        assert(app:ShownTag() == nil and app.tab.controls ~= nil, where)
        -- An unreported entry cannot be placed, so Cancel is the left click
        pointAtRow("ranged")
        assert(leftClick(h:ContentMenu(true)) == "Cancel", where)

        -- Remove takes the clicked slot; Withdraw stays a stack's left click and Cancel a ghost's
        assert(app:ShowTag("melee"))
        h:Tick(2)
        h:PointAtSlot(3)
        menu = h:SlotMenu()
        assert(leftClick(menu) == "Cancel", table.concat(Harness.Labels(menu), "|") .. where)
        Harness.Choose(menu, "Remove from <col=f2c66d>Melee</col>")
        h:Tick(2)
        assert(h:Saved("melee") == "4151 4151 0 999", h:Saved("melee") .. where)
        h:PointAtSlot(2)
        assert(layout.itemHover:HasHoveredBankStack(), where)
        menu = h:SlotMenu()
        assert(leftClick(menu) == "Withdraw-1", table.concat(Harness.Labels(menu), "|") .. where)
        Harness.Choose(menu, "Remove from <col=f2c66d>Melee</col>")
        h:Tick(2)
        assert(h:Saved("melee") == "4151 0 0 999", h:Saved("melee") .. where)
        h:PointAtSlot(4)
        menu = h:SlotMenu()
        assert(leftClick(menu) == "Cancel", table.concat(Harness.Labels(menu), "|") .. where)
        Harness.Choose(menu, "Remove from <col=f2c66d>Melee</col>")
        h:Tick(2)
        assert(h:Saved("melee") == "4151", h:Saved("melee") .. where)

        -- A Remove chosen before the tag was shown again writes nothing
        h:PointAtSlot(1)
        menu = h:SlotMenu()
        Harness.Choose(menu, "Remove from <col=f2c66d>Melee</col>")
        assert(app.ext:Close() and app:ShowTag("melee"))
        h:Tick(2)
        assert(h:Saved("melee") == "4151", "stale after reopening" .. where)

        -- Select mode leaves the shown tag; left clicks tag, never withdraw
        pointAtRow("ranged")
        Harness.Choose(h:ContentMenu(), "Select items <col=f2c66d>Ranged</col>")
        h:Tick(2)
        assert(app.select:Tag() == "ranged" and app:ShownTag() == nil and layout.shownPage == nil, where)
        for slot = 1, 3 do
            menu = h:MenuFor(host.items[slot])
            assert(leftClick(menu) == addLabel(slot), table.concat(Harness.Labels(menu), "|") .. where)
            h:Tick(2)
        end
        assert(h:Saved("ranged") == "4151 4151 385", h:Saved("ranged") .. where)
        -- An entry the host does not report leaves Cancel the left click
        assert(leftClick(h:MenuFor(host.items[1], true)) == "Cancel", where)
        -- Done returns the left click to the bank
        Harness.Find(h:TabParent(), "Done").hooks.pressed()
        h:Tick(2)
        assert(app.select:Tag() == nil and leftClick(h:MenuFor(host.items[1])) == "Withdraw-1", where)
    end
end

-- Select mode keeps adding objects in a numbered tab
h.menuOrder, h.placement = "core_first", "above_cancel"
resetTags()
local detect = layout.DetectNativeViewAll
layout.DetectNativeViewAll = function() return false end
layout:SetNativeViewAll(false)
h:Tick(2)
assert(app.select:Toggle("ranged"))
assert(leftClick(h:MenuFor(host.items[3])) == addLabel(3))
h:Tick(2)
assert(h:Saved("ranged") == "385" and app.select:Stop())
layout.DetectNativeViewAll = detect
layout:SetNativeViewAll(true)
h:Tick(2)

-- The layout editor covers the bank, so rows and items beneath it get no entries
resetTags()
local removeRanged = "Remove <col=f2c66d>Ranged</col>"
local addItem = addLabel(1)
pointAtRow("ranged")
local before = h:ContentMenu()
Harness.Open(before)
assert(app.select:Toggle("ranged"))
h:Tick(2)
local itemBefore = h:MenuFor(host.items[1])
assert(Harness.Has(itemBefore, addItem))
app.windows:OpenLayoutEditor("ranged")
assert(app.windows.layoutEditor ~= nil)
pointAtRow("ranged")
local covered = h:ContentMenu()
assert(table.concat(Harness.DisplayedLabels(covered), "|") == "Cancel")
Harness.Open(covered)
assert(not Harness.Has(h:MenuFor(host.items[1]), addItem))
-- Entries from menus built before the editor opened do nothing
Harness.Choose(before, removeRanged)
leftClick(itemBefore)
h:Tick(2)
assert(app.windows.tagDeleteConfirm == nil and h:Saved("ranged") == "")
-- Closing the editor brings the entries back at once
app.windows.layoutEditor.window:Close()
assert(app.windows.layoutEditor == nil)
assert(Harness.Has(h:MenuFor(host.items[1]), addItem))
assert(app.select:Stop())
h:Tick(2)
pointAtRow("ranged")
local menu = h:ContentMenu()
assert(Harness.Has(menu, removeRanged))
-- An entry chosen just before the editor opens does not run after it
Harness.Choose(menu, removeRanged)
app.windows:OpenLayoutEditor("ranged")
h:Tick(2)
assert(app.windows.tagDeleteConfirm == nil)
app.windows.layoutEditor.window:Close()
pointAtRow("ranged")
Harness.Choose(h:ContentMenu(), removeRanged)
h:Tick(2)
assert(app.windows.tagDeleteConfirm ~= nil)
app.windows:Close("tagDeleteConfirm")

-- Disconnecting drops the menu subscription
app:Disconnect()
assert(h.menuSubscriptions.banktags_menu == nil)

print("menu_orders_test: ok")
