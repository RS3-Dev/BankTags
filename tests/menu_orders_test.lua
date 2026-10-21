package.path = "./?.lua;./?/init.lua;" .. package.path

-- Drive Bank Tags' menus beside Bank Core's guard under every entry placement
-- Covers select mode, Remove on each slot kind, rows, and stale entries
-- FAKE HOST: stand-in loader, components, and menus, not the game client

local Harness = require("tools/test_support/tags_harness")
local Geometry = require("banktags/ui/geometry")
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

local key = require("banktags/tags/item_identity").LayoutKey
local presetOpen = false
local other = assert(session.publicAPI.RegisterExtension("other", "Other"))
assert(other:RegisterTab("notes", { label = "Notes", icon = "STAR", rows = {} }))
h:Tick(2)
layout.IsPresetViewOpen = function() return presetOpen end

-- Point at a content position in the bank's item area
local function pointAt(x, y)
    local left, top = Geometry.absolutePosition(host.viewport)
    host.mouse = { x = left + x + 5, y = top + y + 5 }
end
-- Point at a tag row in the Tags tab
local function pointAtRow(tag)
    local row = app.tab:RowFor(tag)
    app.tab.controls.list.list.scrollY = row.root.y
    h:PointAt(row.root, 20, 10 - row.root.y)
end
-- Give melee two bank stacks, a reused stack, and an item missing from the bank
local function resetTags()
    for _, tag in ipairs({ "melee", "ranged" }) do
        if app.store.data.tags[tag] ~= nil then assert(app.store:DeleteTag(tag)) end
        assert(app.store:CreateTag(tag))
    end
    local function item(objectID, copy, source)
        return { kind = "item", objectID = objectID, layoutKey = key(objectID, copy),
            sourceLayoutKey = source ~= nil and key(objectID, source) or nil }
    end
    app.store.data.tags.melee.rows = { { kind = "row", slots = {
        item(4151, 1), item(4151, 3, 1), item(4151, 2), item(999, 1) } } }
    assert(app.store:Save())
    app:Changed()
    h:Tick(2)
end
-- Report the menu's left click, which must not be a native withdraw
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
        local function shows(id, expected)
            pointAtRow(id)
            local menu = h:ContentMenu()
            local shown = table.concat(Harness.DisplayedLabels(menu), "|")
            assert(shown == table.concat(expected, "|") .. "|Cancel", shown .. where)
            return menu
        end
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
        app.tab.controls.list.list:Click("ranged")
        Harness.ChooseChild(menu, moveRanged, "Combat")
        h:Tick(2)
        assert(app.store:GetTagFolder("ranged") == "archery" and app:ToggleTag("ranged"), where)
        h:Tick(2)
        assert(app.shownTag == nil, where)
        pointAtRow("ranged")
        menu = h:ContentMenu()
        Harness.ChooseChild(menu, moveRanged, "Combat")
        assert(app:DeleteFolder("combat"))
        h:Tick(2)
        assert(app.store:GetTagFolder("ranged") == "archery" and app.store:GetFolder("combat") == nil, where)
        assert(app.store:CreateFolder("Combat", "melee"))
        pointAtRow("ranged")
        menu = h:ContentMenu()
        layout:SetSidebarMode("__bankutils_ext_tab:other/notes")
        h:Tick(2)
        layout:SetSidebarMode("__bankutils_ext_tab:banktags/tags")
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
        -- A left click runs the default and the row's own click; the row answers it once
        local function click(id) app.tab.controls.list.list:Click(id) end
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
        assert(leftClickRow("ranged") == "Select <col=f2c66d>Ranged</col>" and app.shownTag == "ranged", where)
        assert(leftClickRow("ranged") == "Select <col=f2c66d>Ranged</col>" and app.shownTag == nil, where)
        -- The row may hear the click first, with the default from that menu or one rebuilt after it
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
            assert(app.shownTag == "ranged", where)
            rowThenMenu("ranged", rebuilt)
            assert(app.shownTag == nil, where)
            rowThenMenu(folderRow, rebuilt)
            assert(app.store:GetFolder("combat").collapsed, where)
            rowThenMenu(folderRow, rebuilt)
            assert(not app.store:GetFolder("combat").collapsed, where)
        end
        -- The default may run ticks before the row hears the click, or more than once
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
        assert(app.shownTag == "ranged", where)
        menuThenLateRow("ranged", 2)
        assert(app.shownTag == nil, where)
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
            assert(app.shownTag == (count % 2 == 1 and "ranged" or nil), count .. where)
        end
        -- The row answers the left click, so the default alone does nothing
        local pages = session.extensionPages
        local leave, leaves = pages.LeavePage, 0
        pages.LeavePage = function(...)
            leaves = leaves + 1
            return leave(...)
        end
        pointAtRow("ranged")
        assert(leftClick(h:ContentMenu()) == "Select <col=f2c66d>Ranged</col>", where)
        h:Tick(4)
        assert(app.shownTag == nil and leaves == 0, where)
        -- Select chosen from the opened menu toggles once, even if heard twice
        local function chooseSelect(id, label)
            pointAtRow(id)
            local menu = h:ContentMenu()
            Harness.Choose(menu, label)
            Harness.Choose(menu, label)
            h:Tick(4)
        end
        chooseSelect("ranged", "Select <col=f2c66d>Ranged</col>")
        assert(app.shownTag == "ranged" and leaves == 0, where)
        chooseSelect("ranged", "Select <col=f2c66d>Ranged</col>")
        assert(app.shownTag == nil and layout.selectedTag == nil and leaves == 1, where)
        chooseSelect(folderRow, "Collapse <col=f2c66d>Combat</col>")
        assert(app.store:GetFolder("combat").collapsed, where)
        chooseSelect(folderRow, "Expand <col=f2c66d>Combat</col>")
        assert(not app.store:GetFolder("combat").collapsed, where)
        pages.LeavePage = nil
        -- Row clicks alone still toggle
        click("melee")
        assert(app.shownTag == "melee", where)
        click("melee")
        assert(app.shownTag == nil, where)
        click("melee")
        assert(app.shownTag == "melee", where)
        click("melee")
        assert(app.shownTag == nil, where)
        h:Tick(2)
        -- An entry chosen after a row click, or from a rebuilt tab, does nothing
        pointAtRow("ranged")
        menu = h:ContentMenu()
        app.tab.controls.list.list:Click("melee")
        Harness.Choose(menu, "Edit <col=f2c66d>Ranged</col>")
        h:Tick(2)
        assert(app.shownTag == "melee" and app.windows.tagSettingsEditor == nil, where)
        assert(app:ToggleTag("melee") and app.shownTag == nil)
        h:Tick(2)
        pointAtRow("ranged")
        menu = h:ContentMenu()
        layout:SetSidebarMode("__bankutils_ext_tab:other/notes")
        h:Tick(2)
        layout:SetSidebarMode("__bankutils_ext_tab:banktags/tags")
        h:Tick(2)
        Harness.Choose(menu, "Select <col=f2c66d>Ranged</col>")
        h:Tick(2)
        assert(app.shownTag == nil and app.tab.controls ~= nil, where)
        -- An unreported entry cannot be placed, so Cancel is the left click
        pointAtRow("ranged")
        assert(leftClick(h:ContentMenu(true)) == "Cancel", where)

        -- Remove targets each slot's own copy; Withdraw stays a stack's left click
        assert(app:ShowTag("melee"))
        h:Tick(2)
        pointAt(52, 4)
        h:Tick()
        assert(layout.nativeLease:HasInteractionLease(), where)
        menu = h:MenuFor(host.items[1])
        assert(leftClick(menu) == "Withdraw-1", table.concat(Harness.Labels(menu), "|") .. where)
        Harness.Choose(menu, "Remove from <col=f2c66d>Melee</col>")
        h:Tick(2)
        assert(not app.store:HasTag("melee", key(4151, 3)) and app.store:HasTag("melee", key(4151, 1)), where)
        pointAt(96, 4)
        h:Tick()
        Harness.Choose(h:MenuFor(host.items[2]), "Remove from <col=f2c66d>Melee</col>")
        h:Tick(2)
        assert(not app.store:HasTag("melee", key(4151, 2)) and app.store:HasTag("melee", key(4151, 1)), where)
        pointAt(140, 4)
        h:Tick()
        menu = h:ContentMenu()
        assert(leftClick(menu) == "Cancel", table.concat(Harness.Labels(menu), "|") .. where)
        Harness.Choose(menu, "Remove from <col=f2c66d>Melee</col>")
        h:Tick(2)
        assert(not app.store:HasTag("melee", key(999, 1)), where)

        -- A Remove offered, or chosen, before the bank view changed writes nothing
        pointAt(8, 4)
        h:Tick()
        menu = h:MenuFor(host.items[1])
        host:Rebuild()
        layout:HandleInventoryUpdate()
        Harness.Choose(menu, "Remove from <col=f2c66d>Melee</col>")
        h:Tick(4)
        assert(app.store:HasTag("melee", key(4151, 1)), "stale after rebuild" .. where)
        pointAt(8, 4)
        h:Tick()
        menu = h:MenuFor(host.items[1])
        Harness.Choose(menu, "Remove from <col=f2c66d>Melee</col>")
        assert(app.handle:LeavePage() and app:ShowTag("melee"))
        h:Tick(2)
        assert(app.store:HasTag("melee", key(4151, 1)), "stale after reopening" .. where)

        -- Select mode leaves the shown tag; left clicks tag, never withdraw
        pointAtRow("ranged")
        Harness.Choose(h:ContentMenu(), "Select items <col=f2c66d>Ranged</col>")
        h:Tick(2)
        assert(app.select:Tag() == "ranged" and app.shownTag == nil and layout.selectedTag == nil, where)
        for slot = 1, 3 do
            menu = h:MenuFor(host.items[slot])
            assert(leftClick(menu) == "Add to Ranged <col=f2c66d>Item</col>",
                table.concat(Harness.Labels(menu), "|") .. where)
            h:Tick(2)
        end
        assert(app.store:HasTag("ranged", key(4151, 1)) and app.store:HasTag("ranged", key(4151, 2))
            and app.store:HasTag("ranged", key(385, 1)), where)
        -- An entry the host does not report leaves Cancel the left click
        assert(leftClick(h:MenuFor(host.items[1], true)) == "Cancel", where)
        -- A preset view ends select mode; native clicks pause until Bank Tags notices
        presetOpen = true
        layout:Changed(false)
        assert((host.items[2].outlineWidth or 0) == 0 and leftClick(h:MenuFor(host.items[1])) == "Cancel", where)
        h:Tick(2)
        assert(app.select:Tag() == nil and app.status == 'Select "Return to Bank" before choosing items for a tag.', where)
        presetOpen = false
        layout:Changed(false)
        assert(leftClick(h:MenuFor(host.items[1])) == "Withdraw-1", where)
        -- An Add offered before a preset view opens writes nothing
        assert(app.store:RemoveTag("ranged", key(4151, 1)) and app.select:Toggle("ranged"))
        h:Tick(2)
        assert(host.items[2].outlineWidth == 2, where)
        menu = h:MenuFor(host.items[1])
        presetOpen = true
        layout:Changed(false)
        presetOpen = false
        layout:Changed(false)
        leftClick(menu)
        h:Tick(2)
        assert(not app.store:HasTag("ranged", key(4151, 1)) and app.select:Tag() == nil, "stale add after preset" .. where)
        assert((host.items[2].outlineWidth or 0) == 0, where)
        assert(app.select:Toggle("ranged"))
        h:Tick(2)
        -- An Add chosen before the bank rebuilt writes nothing
        assert(app.store:RemoveTag("ranged", key(4151, 1)))
        menu = h:MenuFor(host.items[1])
        leftClick(menu)
        host:Rebuild()
        layout:HandleInventoryUpdate()
        h:Tick(2)
        assert(not app.store:HasTag("ranged", key(4151, 1)), "stale add" .. where)
        -- Done returns the left click to the bank
        Harness.Find(h:TabParent(), "Done").hooks.pressed()
        h:Tick(2)
        assert(app.select:Tag() == nil and leftClick(h:MenuFor(host.items[1])) == "Withdraw-1", where)
    end
end

-- Start select mode before Core records All Items, then switch tabs
h.menuOrder, h.placement = "core_first", "above_cancel"
resetTags()
layout.nativeViewAll = false
local detect = layout.DetectNativeViewAll
layout.DetectNativeViewAll = function() return true end
assert(app.select:Toggle("ranged") and layout.nativeViewAll)
h:Tick(2)
assert(app.select:Tag() == "ranged" and leftClick(h:MenuFor(host.items[3])) == "Add to Ranged <col=f2c66d>Item</col>")
h:Tick(2)
assert(app.store:HasTag("ranged", key(385, 1)))
layout.DetectNativeViewAll = function() return false end
layout:SetNativeViewAll(false)
-- Until Bank Tags hears the change, a native click is paused
assert(leftClick(h:MenuFor(host.items[1])) == "Cancel")
h:Tick(2)
assert(app.select:Tag() == nil and app.status == 'Select "All Items" before choosing items for a tag.')
assert(leftClick(h:MenuFor(host.items[1])) == "Withdraw-1")
layout.DetectNativeViewAll = function() return true end
layout:SetNativeViewAll(true)
h:Tick(2)
assert(app.select:Toggle("ranged"))
h:Tick(2)
assert(leftClick(h:MenuFor(host.items[2])) == "Add to Ranged <col=f2c66d>Item</col>")
h:Tick(2)
assert(app.store:HasTag("ranged", key(4151, 2)) and app.select:Stop())
layout.DetectNativeViewAll = detect

-- The layout editor covers the bank, so rows and items beneath it get no entries
resetTags()
local removeRanged = "Remove <col=f2c66d>Ranged</col>"
local addItem = "Add to Ranged <col=f2c66d>Item</col>"
pointAtRow("ranged")
local before = h:ContentMenu()
Harness.Open(before)
assert(app.select:Toggle("ranged"))
h:Tick(2)
assert(app.store:RemoveTag("ranged", key(4151, 1)))
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
assert(app.windows.tagDeleteConfirm == nil and not app.store:HasTag("ranged", key(4151, 1)))
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
