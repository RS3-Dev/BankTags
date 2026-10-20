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
-- Give melee a stack, a borrowed copy 3 slot, copy 2, and a ghost
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
        shows("ranged", named({ "Select", "Edit", "Select items", "Remove", "Move to folder..." }, "Ranged"))
        local labels = named({ "Select", "Edit", "Select items", "Remove", "Remove from folder", "Move to folder..." },
            "Melee")
        labels[5] = "Remove from folder <col=f2c66d>Combat</col>"
        shows("melee", labels)
        local folderRow = "__banktags_folder:combat"
        local menu = shows(folderRow, named({ "Collapse", "Rename folder", "Ungroup folder" }, "Combat"))
        -- Chosen from the open menu, the default runs once
        Harness.Choose(menu, "Collapse <col=f2c66d>Combat</col>")
        h:Tick(2)
        assert(app.store:GetFolder("combat").collapsed, where)
        menu = shows(folderRow, named({ "Expand", "Rename folder", "Ungroup folder" }, "Combat"))
        -- A left click runs the default and the row's own click; the row answers it once
        local function leftClickRow(id)
            pointAtRow(id)
            local default = leftClick(h:ContentMenu())
            app.tab.controls.list.list:Click(id)
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
        -- The row answering first leaves the menu's left click nothing to do
        local function rowThenMenu(id)
            pointAtRow(id)
            local menu = h:ContentMenu()
            app.tab.controls.list.list:Click(id)
            leftClick(menu)
            h:Tick(2)
        end
        rowThenMenu("ranged")
        assert(app.shownTag == "ranged", where)
        rowThenMenu("ranged")
        assert(app.shownTag == nil, where)
        -- A left click only the menu hears toggles too: open, close, open
        local pages = session.extensionPages
        local leave, leaves = pages.LeavePage, 0
        pages.LeavePage = function(...)
            leaves = leaves + 1
            return leave(...)
        end
        local function menuOnly(id)
            pointAtRow(id)
            local default = leftClick(h:ContentMenu())
            h:Tick(4)
            return default
        end
        assert(menuOnly("ranged") == "Select <col=f2c66d>Ranged</col>" and app.shownTag == "ranged", where)
        assert(menuOnly("ranged") == "Select <col=f2c66d>Ranged</col>", where)
        assert(leaves == 1 and app.shownTag == nil and layout.selectedTag == nil, where)
        h:Tick(4)
        assert(app.shownTag == nil and layout.selectedTag == nil, where)
        assert(menuOnly("ranged") == "Select <col=f2c66d>Ranged</col>" and app.shownTag == "ranged", where)
        -- A Select built under another shown tag leaves the current page alone
        pointAtRow("ranged")
        menu = h:ContentMenu()
        assert(app:ShowTag("melee"))
        leftClick(menu)
        h:Tick(2)
        assert(app.shownTag == "melee" and leaves == 1, where)
        pages.LeavePage = nil
        -- Row clicks alone still toggle
        app.tab.controls.list.list:Click("melee")
        assert(app.shownTag == nil, where)
        app.tab.controls.list.list:Click("melee")
        assert(app.shownTag == "melee", where)
        app.tab.controls.list.list:Click("melee")
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
        -- A preset view ends select mode, pausing native clicks until heard
        presetOpen = true
        layout:Changed(false)
        assert((host.items[2].outlineWidth or 0) == 0 and leftClick(h:MenuFor(host.items[1])) == "Cancel", where)
        h:Tick(2)
        assert(app.select:Tag() == nil and app.status == 'Select "Return to Bank" before choosing items for a tag.', where)
        presetOpen = false
        layout:Changed(false)
        assert(leftClick(h:MenuFor(host.items[1])) == "Withdraw-1", where)
        -- An Add offered across a preset view opening writes nothing
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

-- Disconnecting drops the menu subscription
app:Disconnect()
assert(h.menuSubscriptions.banktags_menu == nil)

print("menu_orders_test: ok")
