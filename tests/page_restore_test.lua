-- Session-only tag page restoration when reopening the Bank Tags sidebar.
local suite = {
    setup = function()
        package.path = root .. "/?.lua;" .. package.path
        for _, name in ipairs({
            "core/config", "core/debug_log", "tags/native_items",
            "sidebar/select_mode", "windows/settings_section",
            "sidebar/tag_menus", "tags/tag_page", "tags/tag_store", "sidebar/tag_tab",
            "windows/windows", "windows/tutorial",
        }) do
            package.loaded["resources/" .. name] = { PLUGIN_REF = "banktags", Write = function() end, SetEnabled = function() end }
        end
        Settings = require("resources/core/settings")
        App = require("resources/app")

        savedSettings = nil
        PersistentDB = {
            GetStructuredData = function() return savedSettings end,
            SetStructuredData = function(_, _, value) savedSettings = value; return true end,
        }
        id = { Inv = { BANK = 95 } }
        listeners = { MiniMenuEntrySelected = {}, InventoryUpdated = {} }
        Event = {
            MiniMenuEntrySelected = {
                Subscribe = function(key, fn) listeners.MiniMenuEntrySelected[key] = fn end,
                Unsubscribe = function(key) listeners.MiniMenuEntrySelected[key] = nil end,
            },
            InventoryUpdated = {
                Subscribe = function(key, fn) listeners.InventoryUpdated[key] = fn end,
                Unsubscribe = function(key) listeners.InventoryUpdated[key] = nil end,
            },
        }

        state = { bankOpen = true, viewAll = true, presetOpen = false, searchActive = false, filterActive = false }
        opened = false
        refusal = nil
        selectTag = nil
        ext = {
            GetBankState = function() return state end,
            GetBankItems = function() return {} end,
            IsOpen = function() return opened end,
            Close = function() opened = false; return true end,
            Open = function()
                if refusal ~= nil then return false, refusal end
                opened = true
                return true
            end,
            Dispose = function() end,
        }
        app = setmetatable({
            ext = ext,
            settings = Settings.defaults(),
            store = {
                data = { tags = { gear = {}, pvm = {}, bossing = {} } },
                SetLayoutPlacement = function() end,
                GetFolder = function(_, key) return key == "combat" and { key = "combat", collapsed = false } or nil end,
                SetFolderCollapsed = function() return true end,
            },
            tab = { Refresh = function() end, RefreshStatus = function() end, RowFor = function() end },
            nativeItems = { Start = function() end, Stop = function() end, RestoreHighlights = function() end, Refresh = function() end },
            menus = { Start = function() end, Stop = function() end },
            windows = { CloseBankWindows = function() end, StoreChanged = function() end, TagRenamed = function() end,
                BankItemsChanged = function() end, CheckBankBounds = function() end },
            tutorial = { Stop = function() end, Offer = function() end },
            select = {
                Tag = function() return selectTag end,
                Stop = function() selectTag = nil end,
                Forget = function() selectTag = nil end,
                Rename = function(_, oldTag, newTag) if selectTag == oldTag then selectTag = newTag end end,
            },
            pageTag = nil,
            pageKeys = {},
            revision = 0,
            restoreTag = nil,
            sidebarSelected = false,
            pendingRestore = nil,
        }, App)
        function app:SetTagPage(tag)
            self.pageTag = tag
            self.pageKeys = { 1 }
            self.revision = self.revision + 1
            return true
        end
    end,
    tests = {},
}

local function fireMenu(verb)
    for _, fn in pairs(listeners.MiniMenuEntrySelected) do
        fn({ entry = { verbText = verb } })
    end
end

local function fireBankInventory()
    for _, fn in pairs(listeners.InventoryUpdated) do
        fn({ inv = { id = id.Inv.BANK } })
    end
end

suite.tests.setting_defaults_to_true_and_disabling_cancels_restore = function()
    assert(Settings.defaults().restoreLastTag == true)
    assert(Settings.copy({}).restoreLastTag == true)
    assert(Settings.copy({ restoreLastTag = false }).restoreLastTag == false)

    app:OnSidebarSelected()
    assert(app:ShowTag("gear"))
    opened = false
    app:OnSidebarDeselected()
    app:OnPageClosed()

    state = { bankOpen = true, viewAll = false }
    app:OnSidebarSelected()
    assert(app.pendingRestore == "not_all_items")

    assert(app:SetSetting("restoreLastTag", false))
    assert(app.pendingRestore == nil)
    assert(next(listeners.MiniMenuEntrySelected) == nil)
    assert(next(listeners.InventoryUpdated) == nil)

    state = { bankOpen = true, viewAll = true }
    app:OnBankStateChanged(state)
    assert(not opened)
    app:OnSidebarDeselected()
    app:OnSidebarSelected()
    assert(not opened)
end

suite.tests.reopening_sidebar_restores_last_tag_on_all_items = function()
    app:OnSidebarSelected()
    assert(app:ShowTag("gear"))
    assert(app.restoreTag == "gear")

    -- Simulate collapsing the sidebar in Core: ReturnToBank -> onDeselect -> onClose
    opened = false
    app:OnSidebarDeselected()
    app:OnPageClosed()
    assert(app.restoreTag == "gear")

    -- Reopen the Bank Tags sidebar on All Items
    app:OnSidebarSelected()
    assert(opened and app:ShownTag() == "gear")
    assert(app.status == nil)
end

suite.tests.closing_and_reopening_bank_restores_in_memory_tag = function()
    app:OnSidebarSelected()
    assert(app:ShowTag("pvm"))

    -- Simulate bank close: onDeselect -> onBankClose -> onClose
    opened = false
    state = { bankOpen = false, viewAll = false }
    app:OnSidebarDeselected()
    app:OnBankClose()
    app:OnPageClosed()
    assert(app.restoreTag == "pvm")

    -- Reopen bank on All Items and select Bank Tags
    state = { bankOpen = true, viewAll = true }
    app:OnSidebarSelected()
    assert(opened and app:ShownTag() == "pvm")
    assert(app.status == nil)
end

suite.tests.switching_between_plugins_restores_previous_tag = function()
    app:OnSidebarSelected()
    assert(app:ShowTag("gear"))

    -- User switches to another plugin, which then opens its own page (closing Bank Tags' page)
    app:OnSidebarDeselected()
    opened = false
    app:OnPageClosed()
    assert(app.restoreTag == "gear")

    -- User clicks Bank Tags icon again
    app:OnSidebarSelected()
    assert(opened and app:ShownTag() == "gear")
end

suite.tests.explicit_dismissal_clears_remembered_tag = function()
    app:OnSidebarSelected()
    assert(app:ShowTag("gear"))
    assert(app:ToggleTag("gear"))
    assert(not opened and app.restoreTag == nil)

    app:OnSidebarDeselected()
    app:OnSidebarSelected()
    assert(not opened)

    -- Return to Bank or clicking native View All while selected also forgets the tag
    assert(app:ShowTag("pvm"))
    opened = false
    app:OnPageClosed()
    assert(app.restoreTag == nil)
    app:OnSidebarDeselected()
    app:OnSidebarSelected()
    assert(not opened)
end

suite.tests.not_all_items_restores_when_next_action_is_view_all = function()
    app:OnSidebarSelected()
    assert(app:ShowTag("gear"))
    opened = false
    app:OnSidebarDeselected()
    app:OnPageClosed()

    -- Open bank / sidebar while on native tab 2
    state = { bankOpen = true, viewAll = false }
    app:OnSidebarSelected()
    assert(not opened)
    assert(app.status == nil, "deferred restore must not flash a refusal banner")
    assert(app.pendingRestore == "not_all_items")

    -- Right-click Cancel does not cancel pending restore; clicking View All keeps it armed
    fireMenu("Cancel")
    assert(app.pendingRestore == "not_all_items")
    fireMenu("<col=ffffff>View All</col>")
    assert(app.pendingRestore == "not_all_items")

    -- Core reports viewAll = true
    state = { bankOpen = true, viewAll = true }
    app:OnBankStateChanged(state)
    assert(opened and app:ShownTag() == "gear")
    assert(app.pendingRestore == nil)
    assert(next(listeners.MiniMenuEntrySelected) == nil)
end

suite.tests.other_actions_before_view_all_cancel_pending_restore = function()
    app:OnSidebarSelected()
    assert(app:ShowTag("gear"))
    opened = false
    app:OnSidebarDeselected()
    app:OnPageClosed()

    -- 1. Withdrawing an item on tab 2 cancels pending restore
    state = { bankOpen = true, viewAll = false }
    app:OnSidebarSelected()
    assert(app.pendingRestore == "not_all_items")
    fireMenu("Withdraw-1")
    assert(app.pendingRestore == nil)
    state = { bankOpen = true, viewAll = true }
    app:OnBankStateChanged(state)
    assert(not opened)

    -- 2. Switching to another native tab cancels pending restore
    app:OnSidebarDeselected()
    state = { bankOpen = true, viewAll = false }
    app:OnSidebarSelected()
    fireMenu("View tab 3")
    assert(app.pendingRestore == nil)
    state = { bankOpen = true, viewAll = true }
    app:OnBankStateChanged(state)
    assert(not opened)

    -- 3. Bank inventory change (e.g. dragging on tab 2) cancels pending restore
    app:OnSidebarDeselected()
    state = { bankOpen = true, viewAll = false }
    app:OnSidebarSelected()
    fireBankInventory()
    assert(app.pendingRestore == nil)
    state = { bankOpen = true, viewAll = true }
    app:OnBankStateChanged(state)
    assert(not opened)

    -- 4. Opening search/filter/presets cancels pending restore
    app:OnSidebarDeselected()
    state = { bankOpen = true, viewAll = false }
    app:OnSidebarSelected()
    state = { bankOpen = true, viewAll = false, searchActive = true }
    app:OnBankStateChanged(state)
    assert(app.pendingRestore == nil)
    state = { bankOpen = true, viewAll = true }
    app:OnBankStateChanged(state)
    assert(not opened)

    -- 5. Clicking a sidebar folder cancels pending restore
    app:OnSidebarDeselected()
    state = { bankOpen = true, viewAll = false }
    app:OnSidebarSelected()
    assert(app:ToggleFolder("combat"))
    assert(app.pendingRestore == nil)
    state = { bankOpen = true, viewAll = true }
    app:OnBankStateChanged(state)
    assert(not opened)
end

suite.tests.preset_search_or_filter_on_select_does_not_arm_restore_or_show_notice = function()
    app:OnSidebarSelected()
    assert(app:ShowTag("gear"))
    opened = false
    app:OnSidebarDeselected()
    app:OnPageClosed()

    for _, field in ipairs({ "presetOpen", "searchActive", "filterActive" }) do
        state = { bankOpen = true, viewAll = true }
        state[field] = true
        app:OnSidebarSelected()
        assert(not opened and app.pendingRestore == nil and app.status == nil)
        state = { bankOpen = true, viewAll = true }
        app:OnBankStateChanged(state)
        assert(not opened)
        app:OnSidebarDeselected()
    end
end

suite.tests.early_attach_busy_retries_on_bank_items = function()
    app:OnSidebarSelected()
    assert(app:ShowTag("gear"))
    opened = false
    app:OnSidebarDeselected()
    app:OnPageClosed()

    refusal = "bank_closed"
    app:OnSidebarSelected()
    assert(not opened and app.status == nil and app.pendingRestore == "attaching")

    refusal = nil
    app:OnBankItems()
    assert(opened and app:ShownTag() == "gear" and app.pendingRestore == nil)
end

suite.tests.rename_delete_disconnect_and_select_mode_handling = function()
    app:OnSidebarSelected()
    assert(app:ShowTag("gear"))

    -- Rename keeps restoreTag in sync
    app:Renamed("gear", "bossing")
    assert(app.restoreTag == "bossing")

    -- Core reconnect (Disconnect) keeps session-memory restoreTag
    opened = false
    app:Disconnect()
    assert(app.restoreTag == "bossing" and not app.sidebarSelected and app.pendingRestore == nil)
    app.ext = ext

    -- Select mode prevents automatic restore from interrupting item selection
    selectTag = "pvm"
    app:OnSidebarSelected()
    assert(not opened)
    selectTag = nil

    -- Deleting the remembered tag clears restoreTag
    app.store.data.tags.bossing = nil
    app:Changed()
    assert(app.restoreTag == nil)
    app:OnSidebarDeselected()
    app:OnSidebarSelected()
    assert(not opened)
end

suite.tests.select_mode_start_cancels_pending_restore_and_clears_open_restore_tag = function()
    package.loaded["resources/sidebar/select_mode"] = nil
    Event.Logic = { Subscribe = function() end, Unsubscribe = function() end }
    local SelectMode = require("resources/sidebar/select_mode")
    local selectMode = SelectMode.new(app)
    app.select = selectMode

    app:OnSidebarSelected()
    assert(app:ShowTag("gear"))
    assert(app.restoreTag == "gear")
    assert(selectMode:Start("pvm"))
    assert(not opened and app.restoreTag == nil)
    selectMode:Stop()

    -- Starting select mode while waiting for View All cancels the pending restore
    assert(app:ShowTag("gear"))
    opened = false
    app:OnSidebarDeselected()
    app:OnPageClosed()
    state = { bankOpen = true, viewAll = false }
    app:OnSidebarSelected()
    assert(app.pendingRestore == "not_all_items")
    assert(selectMode:Start("pvm"))
    assert(app.pendingRestore == nil)
    selectMode:Stop()
    state = { bankOpen = true, viewAll = true }
    app:OnBankStateChanged(state)
    assert(not opened)
end

return suite
