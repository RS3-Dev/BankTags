-- Editor v2 layout geometry, left tab switching, and searchable Bank tab.
local suite = { tests = {} }

local function component(parent)
    local value = { parent = parent, hooks = {}, x = 0, y = 0, width = 0, height = 0, hidden = false }
    function value:SetPos(x, y) self.x, self.y = x, y end
    function value:SetSize(w, h) self.width, self.height = w, h end
    function value:SetAssociatedObject(objectID) self.objectID = objectID end
    function value:MoveToFront() end
    function value:Destroy() self.destroyed = true end
    function value:Subscribe(hook, name, fn) self.hooks[hook] = fn or name end
    return value
end

function suite.setup()
    require("tests/editor_fixture")()
    id.Sprite.BANK_TABS_HORIZONTAL_0 = 10
    id.Sprite.BANK_TABS_HORIZONTAL_1 = 11
    id.Sprite.BANK_TABS_HORIZONTAL_2 = 12
    id.Font = { MUSEO_SANS_11PT_REGULAR = 1 }
    ui.AlignMode = { CENTRE = 1, TOPLEFT = 2 }
    ui.ObjectQuantityDisplayMode.NEVER = 0
    ui.ObjectQuantityDisplayMode.MULTIPLE = 2
    ui.Sprite = { new = component }
    bankFieldOptions = nil
    prettyui = {
        TextField = { new = function(_, options)
            if options.placeholder == "Search bank items..." then bankFieldOptions = options end
            return { root = component(), options = options }
        end },
        Text = { new = function(_, options)
            local t = component()
            t.content = options.text or ""
            t.rgba = options.colour
            return t
        end },
        SimpleView = { new = function(_, options)
            local view = { content = component(), scrollY = 0, contentWidth = options.width - 18, options = options }
            function view:SetContentHeight(h) self.contentHeight = h; if self.onLayout then self:onLayout() end end
            function view:SetScrollPosition(y) self.scrollY = math.max(0, y); if self.onLayout then self:onLayout() end end
            function view:ScrollBy(d) self:SetScrollPosition(self.scrollY + d) end
            return view
        end },
        Tabs = { new = function(_, entries, options)
            local pages = {}
            for index, entry in ipairs(entries) do
                pages[index] = { root = component(), content = component(), value = entry.value }
            end
            local tabs = { entries = entries, pages = pages, options = options, activeIndex = 1 }
            function tabs:GetPage(index) return pages[index] end
            function tabs:SetActive(index, notify)
                local previous = self.activeIndex
                self.activeIndex = index
                for pageIndex, page in ipairs(pages) do page.root.hidden = pageIndex ~= index end
                if notify ~= false and previous ~= index and options.onChange then
                    options.onChange(self, index, entries[index].value, pages[index])
                end
                return true
            end
            function tabs:Destroy() self.destroyed = true end
            tabs:SetActive(1, false)
            return tabs
        end },
    }
    nameCalls = 0
    package.loaded["resources/core/object_config"] = {
        DisplayName = function(objectID)
            nameCalls = nameCalls + 1
            local fixed = ({ [10] = "Shark", [20] = "Super restore<img=-1>", [30] = "Abyssal whip",
                [6512] = "null", [99] = "" })[objectID]
            if fixed ~= nil then return fixed end
            if objectID >= 10000 then return "Bank item " .. objectID end
            return nil
        end,
        ConfigName = function(objectID)
            return ({ [6512] = "BLANKOBJECT" })[objectID]
        end,
        ObjectID = function() return nil end,
    }
    for _, module in ipairs({ "bank", "unsorted", "search", "rows", "names" }) do
        for key, value in pairs(require("resources/windows/layout_editor_" .. module)) do e[key] = value end
    end
    e.styles = {}
    e.HideItemName = function() end
    e.bankItemList = {
        { objectID = 10, quantity = 50 },
        { objectID = 20, quantity = 0 },
        { objectID = 10, quantity = 5 }, -- duplicate objectID should be deduped
        { objectID = 30, quantity = 1 },
    }
    e:CreateLeftTabs()
    e:CreateSearch()
    e:CreateBank()
    e.panes.bank.surface = e:CreateDragSurface("bank")
    e.panes.search.surface = e:CreateDragSurface("search")
    e:RefreshBank()
end

suite.tests.layout_slides_right_and_left_panel_expands = function()
    local Parts = require("resources/windows/layout_editor_parts")
    for _, size in ipairs({ { 10, 998, 650 }, { 14, 1174, 850 } }) do
        Parts.SizeToBank(table.unpack(size))
        local s = Parts.size
        -- Layout sits flush against the right edge
        assert(s.CENTER_X + s.CENTER_WIDTH == s.WIDTH - s.RIGHT_MARGIN)
        -- Left tabbed panel expands to fill all remaining width to the left of Layout
        assert(s.LEFT_X + s.LEFT_WIDTH + s.COLUMN_GAP == s.CENTER_X)
        assert(s.LEFT_WIDTH > 400, "expanded left panel should absorb the former right column width")
        assert(s.UNSORTED_WIDTH == s.LEFT_WIDTH and s.SEARCH_WIDTH == s.LEFT_WIDTH)
        assert(s.SEARCH_X == s.LEFT_X and s.UNSORTED_X == s.LEFT_X)
        assert(s.LEFT_BODY_TOP == s.PANEL_TOP + s.TAB_HEADER)
        assert(s.STATUS_WIDTH > 300, "footer status keeps ample width")
    end
end

suite.tests.left_tabs_switch_panels_panes_and_drag_surfaces = function()
    e:SelectLeftTab("unsorted")
    assert(e.activeLeftTab == "unsorted" and e.leftTabs.activeIndex == 1)
    assert(not e.leftTabs:GetPage(1).root.hidden and e.leftTabs:GetPage(2).root.hidden and e.leftTabs:GetPage(3).root.hidden)
    assert(not e.panes.unsorted.hidden and e.panes.bank.hidden and e.panes.search.hidden)
    assert(not e.panes.unsorted.surface.hidden and e.panes.bank.surface.hidden and e.panes.search.surface.hidden)

    -- Clicking via PrettyUI Tabs triggers onChange and switches to Bank
    e.leftTabs:SetActive(2)
    assert(e.activeLeftTab == "bank" and e.leftTabs.activeIndex == 2)
    assert(e.leftTabs:GetPage(1).root.hidden and not e.leftTabs:GetPage(2).root.hidden and e.leftTabs:GetPage(3).root.hidden)
    assert(e.panes.unsorted.hidden and not e.panes.bank.hidden and e.panes.search.hidden)
    assert(e.panes.unsorted.surface.hidden and not e.panes.bank.surface.hidden and e.panes.search.surface.hidden)

    e.leftTabs:SetActive(3)
    assert(e.activeLeftTab == "search" and e.leftTabs.activeIndex == 3)
    assert(e.leftTabs:GetPage(1).root.hidden and e.leftTabs:GetPage(2).root.hidden and not e.leftTabs:GetPage(3).root.hidden)
    assert(e.panes.unsorted.hidden and e.panes.bank.hidden and not e.panes.search.hidden)
    assert(e.panes.unsorted.surface.hidden and e.panes.bank.surface.hidden and not e.panes.search.surface.hidden)
end

suite.tests.bank_tab_lists_unique_items_and_filters_locally = function()
    local bank = e.panes.bank
    assert(#bank.slots == 3)
    assert(bank.slots[1].objectID == 10 and bank.slots[2].objectID == 20 and bank.slots[3].objectID == 30)
    assert(e.bankHint.hidden)

    -- Filtering does not query RuneQL and reuses cached names
    local callsBefore = nameCalls
    runeql = { Catalog = { Find = function() error("Bank tab filter must not query catalog") end } }
    e:FilterBank("restore")
    assert(nameCalls == callsBefore)
    assert(#bank.slots == 1 and bank.slots[1].objectID == 20)
    assert(e.bankNames[20] == "Super restore")

    e:FilterBank("nonexistent")
    assert(#bank.slots == 0 and not e.bankHint.hidden)
    assert(e.bankHint.content == "No bank items match that search.")

    e:FilterBank("")
    assert(#bank.slots == 3 and e.bankHint.hidden)

    -- Live SetBankItems refreshes Bank grid and skips RS3 blank/empty bank slots
    e:SetBankItems({
        { objectID = 6512, quantity = 0 },
        { objectID = -1, quantity = 0 },
        { objectID = 99, quantity = 0 },
        { objectID = 30, quantity = 2 },
    })
    assert(#bank.slots == 1 and bank.slots[1].objectID == 30)
end

suite.tests.bank_drag_adds_to_layout_and_layout_drop_on_bank_does_not_unarrange = function()
    shiftDown = false
    e:SelectLeftTab("bank")
    e.selectedTag = "herblore"
    local addedResult, addedDest
    e.AddCatalogResult = function(_, result, destination)
        addedResult, addedDest = result, destination
    end
    local startedDrag
    e.StartItemDrag = function(_, drag, objectID)
        startedDrag = drag
        assert(objectID == 20)
        return false
    end
    e:BeginBankDrag(e.panes.bank, 2)
    assert(startedDrag ~= nil and startedDrag.kind == "search" and startedDrag.result.objectId == 20)
    assert(startedDrag.sourceKind == "bank")

    -- Dropping the bank drag onto a sorted cell adds it via AddCatalogResult
    local sorted = e.panes.sorted
    e:FinishSearchDrag(startedDrag, sorted.x + sorted.gridLeft + 8, sorted.y + 8)
    assert(addedResult ~= nil and addedResult.objectId == 20 and addedDest == 1)

    -- Dropping a sorted item onto the Bank pane must NOT unarrange it
    local unarranged = false
    e.SaveEdit = function() unarranged = true end
    local bank = e.panes.bank
    e:FinishCenterDrag({ kind = "layout", layoutKey = "a", sourceKind = "sorted" }, bank.x + 10, bank.y + 10)
    assert(not unarranged)
end

suite.tests.bank_tab_tooltips_and_context_menu_work = function()
    e:SelectLeftTab("bank")
    local bank = e.panes.bank
    local x = bank.x + e:GridCellX(bank, 1) + 8
    local y = bank.y + 8
    local item = e:GridItemAt(x, y)
    assert(item ~= nil and item.objectID == 20 and item.name == "Super restore")

    e.pointerSurface = bank.surface
    e.pointerX, e.pointerY = x, y
    e.selectedTag = "herblore"
    e.store = { data = {} }
    e.drag = nil
    local target = e:RowMenuTarget()
    assert(target ~= nil and target.pane == "bank" and target.objectID == 20)
end

suite.tests.custom_keybinds_persist_and_dispatch_editor_actions = function()
    local Settings = require("resources/core/settings")
    local defaults = Settings.defaults()
    assert(defaults.editorKeybinds.copy[1] == "CONTROL" and defaults.editorKeybinds.copy[2] == "C")
    assert(defaults.editorKeybinds.remove[1] == "DELETE")

    local copied = Settings.copy({
        editorKeybinds = {
            copy = { "ALT", "K" },
            remove = { "X" },
            undo = {},
        },
    })
    assert(copied.editorKeybinds.copy[1] == "ALT" and copied.editorKeybinds.copy[2] == "K")
    assert(copied.editorKeybinds.remove[1] == "X")
    assert(#copied.editorKeybinds.undo == 0)
    -- Missing keys retain defaults
    assert(copied.editorKeybinds.paste[1] == "CONTROL" and copied.editorKeybinds.paste[2] == "V")

    GameKey.ALT, GameKey.K, GameKey.X, GameKey.Z, GameKey.CONTROL = 100, 101, 102, 103, 104
    local namesByCode = { [100] = "ALT", [101] = "K", [102] = "X", [103] = "Z", [104] = "CONTROL" }
    GameKey.FromID = function(code) return namesByCode[code] end
    Keyboard.IsControlDown = function() return false end
    Keyboard.IsAltDown = function() return false end
    Keyboard.IsShiftDown = function() return false end
    prettyui.KeybindField = { IsCapturing = function() return false end }

    local ran = {}
    e.keysOnGrid = true
    e.settings = function() return copied end
    e.SelectedEntry = function() return { layoutKey = "a" }, "sorted", 1 end
    e.CopySelected = function() ran[#ran + 1] = "copy" end
    e.RemoveSelected = function() ran[#ran + 1] = "remove" end
    e.Undo = function() ran[#ran + 1] = "undo" end

    -- Rebound Alt+K triggers copy
    e:KeyPressed({ gameKey = GameKey.K, modifiers = ModifierKey.ALT })
    assert(#ran == 1 and ran[1] == "copy")
    -- Rebound X triggers remove
    e:KeyPressed({ gameKey = GameKey.X, modifiers = 0 })
    assert(#ran == 2 and ran[2] == "remove")
    -- Unbound undo does nothing on Ctrl+Z
    e:KeyPressed({ gameKey = GameKey.Z, modifiers = ModifierKey.CONTROL })
    assert(#ran == 2)
    assert(e:FormatKeybind("copy") == "Alt+K")
    assert(e:FormatKeybind("undo") == nil)
end

suite.tests.editor_settings_modal_saves_warns_duplicates_and_resets = function()
    local Settings = require("resources/core/settings")
    GameKey.CONTROL, GameKey.SHIFT, GameKey.C, GameKey.V, GameKey.DELETE, GameKey.Z, GameKey.Y = 1, 12, 2, 3, 4, 5, 6
    GameKey.LEFT, GameKey.RIGHT, GameKey.UP, GameKey.DOWN, GameKey.X = 7, 8, 9, 10, 11
    local byID = {}
    for name, code in pairs(GameKey) do
        if type(code) == "number" then byID[code] = name end
    end
    GameKey.FromID = function(code) return byID[code] end
    id.Font.CINZEL_13PT_BOLD = 2

    local state = Settings.defaults()
    prettyui.Window = { new = function(_, options)
        return { content = component(), options = options, Show = function() end, Close = function() end, Destroy = function() end }
    end }
    prettyui.SimpleButton = { new = function(_, _, fn)
        return { click = fn, Destroy = function() end }
    end }
    prettyui.CheckboxButton = { new = function(_, _, options)
        local selected = {}
        for _, v in ipairs(options.selectedValues or {}) do selected[v] = true end
        return {
            items = {},
            IsSelected = function(_, k) return selected[k] == true end,
            SetSelected = function(_, k, v) selected[k] = v end,
            toggle = function(self, k, v) selected[k] = v; options.onChange(self) end,
            Destroy = function() end,
        }
    end }
    prettyui.KeybindField = { new = function(_, options)
        local field = {
            value = options.value,
            defaultValue = options.defaultValue,
            disabled = options.disabled == true,
            onChange = options.onChange,
        }
        function field:SetValue(v, notify)
            self.value = v
            if notify and self.onChange then self.onChange(self, v) end
        end
        function field:SetDisabled(disabled) self.disabled = disabled == true end
        function field:Destroy() self.destroyed = true end
        return field
    end }

    local EditorSettings = require("resources/windows/layout_editor_settings")
    local modal = EditorSettings.new({}, {
        settings = function() return state end,
        onSetKeybind = function(action, names)
            state.editorKeybinds[action] = names
            return true
        end,
        onResetKeybinds = function()
            state.editorKeybinds = Settings.defaultEditorKeybinds()
            return true
        end,
        onSetArrowKeyMovement = function(enabled)
            state.arrowKeyMovement = enabled
            return true
        end,
    })

    -- Directional movement keybinds start disabled until the checkbox is checked
    assert(not modal.fields.copy.disabled)
    assert(modal.fields.moveLeft.disabled and modal.fields.moveRight.disabled)
    assert(modal.fields.moveUp.disabled and modal.fields.moveDown.disabled)

    -- Rebinding Copy to X saves cleanly
    modal.fields.copy:SetValue({ GameKey.X }, true)
    assert(state.editorKeybinds.copy[1] == "X" and modal.status.hidden)

    -- Rebinding Paste to X warns about duplicate with Copy
    modal.fields.paste:SetValue({ GameKey.X }, true)
    assert(not modal.status.hidden and string.find(modal.status.content, "Copy", 1, true))

    -- Toggling directional movement enables the 4 move keybind fields, and unchecking disables them again
    modal.moveToggle:toggle("arrowKeyMovement", true)
    assert(state.arrowKeyMovement == true)
    assert(not modal.fields.moveLeft.disabled and not modal.fields.moveRight.disabled)
    assert(not modal.fields.moveUp.disabled and not modal.fields.moveDown.disabled)
    modal.moveToggle:toggle("arrowKeyMovement", false)
    assert(state.arrowKeyMovement == false)
    assert(modal.fields.moveLeft.disabled and modal.fields.moveDown.disabled)

    -- Reset Defaults restores Copy and Paste
    modal.resetButton.click()
    assert(state.editorKeybinds.copy[1] == "CONTROL" and state.editorKeybinds.copy[2] == "C")
    assert(state.editorKeybinds.paste[1] == "CONTROL" and state.editorKeybinds.paste[2] == "V")
    modal:Destroy()
    assert(modal.fields.copy == nil)
end

suite.tests.layout_editor_suspends_and_releases_bank_core_keybinds = function()
    local suspendedLabel, released = nil, 0
    local hold = { Release = function() released = released + 1; return true end }
    local ext = {
        GetBankBounds = function() return { x = 0, y = 0, width = 998, height = 650, columns = 10 } end,
        SuspendKeybinds = function(_, label) suspendedLabel = label; return hold end,
    }
    id.Component = { TOPLEVEL_V2__BANK_LAYER = 1 }
    ui.Interfaces = { GetComponent = function() return {} end }
    package.loaded["resources/windows/windows"] = nil
    for _, dep in ipairs({
        "windows/confirm_window", "core/debug_log", "windows/import_share",
        "windows/layout_editor_settings", "windows/sprite_picker", "tags/tag_rules",
        "windows/tag_settings_editor", "ui/text_prompt",
    }) do
        package.loaded["resources/" .. dep] = { Write = function() end }
    end
    local editorOnClose
    package.loaded["resources/windows/layout_editor_window"] = {
        new = function(_, options)
            editorOnClose = options.onClose
            return {
                Show = function() end,
                SetOverlays = function() end,
                Destroy = function(self) if editorOnClose then editorOnClose(self) end end,
            }
        end,
    }
    local Windows = require("resources/windows/windows")
    local windows = Windows.new({
        ext = ext,
        settings = {},
        store = {},
        BankItems = function() return {} end,
    })

    windows:OpenLayoutEditor("tag-1")
    assert(suspendedLabel == "layout editor" and windows.editorKeybindHold == hold and released == 0)

    -- Closing the editor releases the Bank Core keybind hold
    windows:Close("layoutEditor")
    assert(windows.editorKeybindHold == nil and released == 1)

    -- Older Bank Core handles without SuspendKeybinds stay safe
    ext.SuspendKeybinds = nil
    windows:OpenLayoutEditor("tag-1")
    assert(windows.layoutEditor ~= nil and windows.editorKeybindHold == nil)
    windows:Close("layoutEditor")
end

suite.tests.shift_multiselect_group_drag_and_copy_paste_across_unsorted_bank_and_search = function()
    local savedValues = {}
    PersistentDB = {
        GetString = function(_, key) return savedValues[key] end,
        SetString = function(_, key, value) savedValues[key] = value; return true end,
    }
    local Store = require("resources/tags/tag_store")
    local store = Store.new()
    local _, tagID = store:CreateTag("herblore")
    local _, _, u1 = store:AddTag(tagID, 10)
    local _, _, u2 = store:AddTag(tagID, 20)
    local _, _, u3 = store:AddTag(tagID, 30)

    for _, module in ipairs({ "clipboard", "history" }) do
        for key, value in pairs(require("resources/windows/layout_editor_" .. module)) do e[key] = value end
    end
    local Parts = require("resources/windows/layout_editor_parts")
    Parts.SizeToBank(10, 998, 650)

    e.store = store
    e.selectedTag = tagID
    e.ShowNotice = function() end
    e.ShowError = function(_, msg) e.lastError = msg end
    e.ClearStatus = function() end
    e.NotifyChanged = function()
        e.layout = store:EditorLayout(tagID, Parts.size.CENTER_COLUMNS)
        e.panes.sorted.slots = e.layout.slots
        e.panes.unsorted.slots = e.layout.unsorted
        e.panes.unsorted.indexes = e.layout.unsortedIndex
    end
    e.SelectedEntry = function(self)
        local key = self.selectedLayoutKey
        if self.layout.sortedIndex[key] ~= nil then return self.layout.slots[self.layout.sortedIndex[key]], "sorted", self.layout.sortedIndex[key] end
        if self.layout.unsortedIndex[key] ~= nil then return self.layout.unsorted[self.layout.unsortedIndex[key]], "unsorted", self.layout.unsortedIndex[key] end
        return nil
    end
    e:NotifyChanged()

    -- 1. Shift-multiselect in Bank + Copy + Paste into Layout
    e:SelectLeftTab("bank")
    shiftDown = true
    e:BeginBankDrag(e.panes.bank, 1) -- Shark (10)
    e:BeginBankDrag(e.panes.bank, 3) -- Whip (30)
    local bankIDs = e:SelectedBankObjectIDs()
    assert(#bankIDs == 2 and bankIDs[1] == 10 and bankIDs[2] == 30)
    assert(e:CopySelected())
    assert(e.clipboard.mode == "flow" and #e.clipboard.objectIDs == 2)
    e.pasteCell = 1
    assert(e:PasteClipboard())
    assert(e.layout.slots[1].objectID == 10 and e.layout.slots[2].objectID == 30)

    -- 2. Undo reverts the entire multi-item Bank paste in one step
    assert(e:Undo())
    assert(#e.layout.slots == 0)

    -- 3. Group drag from Bank onto Layout cell 2 places both items into cells 2 and 3
    e:SelectBankItems({ 10, 20 })
    shiftDown = false
    local sorted = e.panes.sorted
    e.pointerSurface = e.panes.bank.surface
    e.pointerX, e.pointerY = 10, 10
    e:BeginBankDrag(e.panes.bank, 1)
    assert(e.drag ~= nil and e.drag.kind == "bank_group" and #e.drag.items == 2)
    e:FinishMultiDrag(e.drag, sorted.x + sorted.gridLeft + Parts.size.GRID_STEP + 8, sorted.y + 8)
    e:CancelDrag()
    assert(e.layout.slots[2].objectID == 10 and e.layout.slots[3].objectID == 20)

    -- 4. Search grid renders results, supports tooltip/menu + Shift-drag marquee + Copy/Paste into Layout cell 5
    e:SelectLeftTab("search")
    e:ApplySearchResults("s", {
        { objectId = 10, displayName = "Shark" },
        { objectId = 30, displayName = "Abyssal whip" },
    }, nil)
    local searchPane = e.panes.search
    assert(#searchPane.slots == 2 and searchPane.slots[1].objectID == 10 and searchPane.slots[2].objectID == 30)
    local sx = searchPane.x + e:GridCellX(searchPane, 1) + 8
    local sy = searchPane.y + 8
    local hovered = e:GridItemAt(sx, sy)
    assert(hovered ~= nil and hovered.objectID == 30 and hovered.name == "Abyssal whip")
    shiftDown = true
    e.pointerSurface = searchPane.surface
    e.pointerX, e.pointerY = searchPane.x + 1, searchPane.y + 1
    e:BeginBoxSelection(1, 1, searchPane)
    e.pointerX, e.pointerY = searchPane.x + e:GridCellX(searchPane, 1) + 35, searchPane.y + 42
    e:UpdateBoxSelection(e.pointerX, e.pointerY, false)
    e:CommitDrag()
    local searchIDs = e:SelectedSearchObjectIDs()
    assert(#searchIDs == 2 and searchIDs[1] == 10 and searchIDs[2] == 30)
    assert(e:CopySelected())
    e.pasteCell = 5
    assert(e:PasteClipboard())
    assert(e.layout.slots[5].objectID == 10 and e.layout.slots[6].objectID == 30)

    -- 5. Shift-multiselect in Unsorted + group drag onto Layout cell 1 skips occupied cells 2,3
    e:SelectLeftTab("unsorted")
    shiftDown = true
    e:BeginCenterDrag(e.panes.unsorted, 1)
    e:BeginCenterDrag(e.panes.unsorted, 2)
    local uKeys = e:SelectedUnsortedKeys()
    assert(#uKeys == 2 and uKeys[1] == u1 and uKeys[2] == u2)
    shiftDown = false
    e.pointerSurface = e.panes.unsorted.surface
    e:BeginCenterDrag(e.panes.unsorted, 1)
    assert(e.drag ~= nil and e.drag.kind == "unsorted_group" and #e.drag.items == 2)
    e:FinishMultiDrag(e.drag, sorted.x + sorted.gridLeft + 8, sorted.y + 8)
    e:CancelDrag()
    assert(e.layout.slots[1].layoutKey == u1 and e.layout.slots[4].layoutKey == u2)
    assert(#e.layout.unsorted == 1 and e.layout.unsorted[1].layoutKey == u3)
end

suite.tests.bank_grid_virtualizes_large_banks_and_uses_prettyui_new_component = function()
    local newComponentCalls, rawLayerCalls = 0, 0
    local origLayerNew = ui.Layer.new
    ui.Layer.new = function(parent)
        rawLayerCalls = rawLayerCalls + 1
        return origLayerNew(parent)
    end
    prettyui.NewComponent = function(nativeType, parent)
        newComponentCalls = newComponentCalls + 1
        return nativeType.new(parent)
    end
    -- Build 2,000 unique bank items
    local bigBank = {}
    for index = 1, 2000 do
        bigBank[index] = { objectID = 10000 + index, quantity = index }
    end
    -- Hidden Bank tab allocates zero sprites
    e:SelectLeftTab("unsorted")
    e.panes.bank.cells = nil
    e.panes.bank.gridPool = nil
    e.panes.bank.itemPool = nil
    e.panes.bank.itemPoolObjectIDs = nil
    e:SetBankItems(bigBank)
    assert(#e.panes.bank.slots == 2000)
    assert(e.panes.bank.cells == nil, "hidden Bank pane must not allocate sprites")

    -- Switching to Bank renders only the visible viewport + overscan, not all 2,000 items
    local beforeShow = newComponentCalls
    e:SelectLeftTab("bank")
    local allocated = newComponentCalls - beforeShow
    assert(allocated > 0 and allocated < 400,
        "expected windowed pool under 400 components for 2000 items, got " .. tostring(allocated))
    assert(e.panes.bank.sprites[1] ~= nil and e.panes.bank.sprites[1].objectID == 10001)
    assert(e.panes.bank.sprites[1999] == nil, "offscreen rows must not be rendered at scrollY=0")

    -- Scrolling to the bottom reuses the existing pool and renders the last item
    local poolBefore = #e.panes.bank.itemPool
    e.panes.bank.view:SetScrollPosition(e.panes.bank.contentHeight - e.panes.bank.height)
    assert(e.panes.bank.sprites[2000] ~= nil and e.panes.bank.sprites[2000].objectID == 12000)
    assert(e.panes.bank.sprites[1] == nil)
    assert(#e.panes.bank.itemPool <= poolBefore + e.panes.bank.columns * 2,
        "scrolling should reuse pooled sprites instead of growing unboundedly")

    -- Parts.contentLayer keeps category-0 raw Layer while Parts.layer routes through NewComponent
    local Parts = require("resources/windows/layout_editor_parts")
    local beforeRaw, beforeManaged = rawLayerCalls, newComponentCalls
    Parts.contentLayer(e.content, 0, 0, 100, 100)
    assert(rawLayerCalls == beforeRaw + 1 and newComponentCalls == beforeManaged)
    Parts.layer(e.content, 0, 0, 100, 100)
    assert(newComponentCalls == beforeManaged + 1)
    ui.Layer.new = origLayerNew
end

suite.tests.classic_ui_aligns_layout_editor_to_detached_sidebar = function()
    local Parts = require("resources/windows/layout_editor_parts")
    local Windows = require("resources/windows/windows")
    local border = Parts.size.WINDOW_BORDER

    -- Modern UI: sidebarRoot sits inside the bank frame, so bounds stay unchanged
    local modernRoot = { x = 100, y = 50, width = 998, height = 650 }
    local modernRail = { x = 40, y = 40, parent = modernRoot }
    local modernCol = { x = 1, y = 1, parent = modernRail }
    prettyui.IsClassicUI = function() return false end
    local modernWin = Windows.new({
        ext = { GetBankBounds = function() return { x = 100, y = 50, width = 998, height = 650, columns = 10 } end },
        tab = { ctx = { parent = modernCol } },
    })
    local mb = modernWin:BankBounds()
    assert(mb.x == 100 and mb.width == 998)

    -- Classic UI with detached left sidebar: outer left edge aligns to sidebarRoot.x (100)
    local classicRoot = { x = 100, y = 50, width = 300, height = 650 }
    local classicRail = { x = 56, y = 40, parent = classicRoot }
    local classicCol = { x = 1, y = 1, parent = classicRail }
    prettyui.IsClassicUI = function() return true end
    local classicWin = Windows.new({
        ext = { GetBankBounds = function() return { x = 400, y = 50, width = 714, height = 650, columns = 10 } end },
        tab = { ctx = { parent = classicCol } },
    })
    local cb = classicWin:BankBounds()
    assert(cb.x - border == 100, "editor outer left should align with sidebar left edge 100, got " .. tostring(cb.x - border))
    assert(cb.width == 998, "combined width minus border should be 998, got " .. tostring(cb.width))
    Parts.SizeToBank(cb.columns, cb.width, cb.height)
    assert((cb.x - border) + Parts.size.WIDTH == 400 + 714,
        "editor outer right edge should align with bank right edge")

    -- Classic UI fallback when sidebar tab ctx is temporarily nil
    local fallbackWin = Windows.new({
        ext = { GetBankBounds = function() return { x = 400, y = 50, width = 714, height = 650, columns = 10 } end },
        tab = { ctx = nil },
    })
    local fb = fallbackWin:BankBounds()
    assert(fb.x - border == 100 and fb.width == 998)
end

suite.tests.copy_paste_across_tags_remove_row_shortcut_and_meta_modifier = function()
    local Parts = require("resources/windows/layout_editor_parts")
    local Settings = require("resources/core/settings")
    local TagStore = require("resources/tags/tag_store")
    local Window = require("resources/windows/layout_editor_window")
    local Clipboard = require("resources/windows/layout_editor_clipboard")
    for k, v in pairs(Clipboard) do e[k] = v end
    e.SelectTag = Window.SelectTag
    e.RefreshCenter = Window.RefreshCenter
    e.SelectedEntry = Window.SelectedEntry
    e.ClearHistory = function() end
    e.ClearStatus = function() end
    e.ShowChosenTag = function() end
    e.ShowNotice = function() end
    e.ShowError = function() end
    e.NotifyChanged = function() end
    e.SaveEdit = function(self, _, fn)
        local ok, reason = fn()
        if ok then self:RefreshCenter() end
        return ok, reason
    end
    Parts.SizeToBank(3, 1000, 650)

    local savedValues = {}
    PersistentDB = {
        GetString = function(_, key) return savedValues[key] end,
        SetString = function(_, key, value) savedValues[key] = value; return true end,
    }
    local store = TagStore.new()
    assert(store:CreateTag("alpha"))
    assert(store:CreateTag("beta"))
    local alphaID, betaID = store:AllTags()[1], store:AllTags()[2]
    assert(store:PlaceItemsAtCells(alphaID, { 10, 20 }, { 1, 2 }, 3))
    assert(store:InsertLabel(betaID, 0, "Weapons", 3))
    assert(store:InsertLayoutRow(betaID, 1, 3))

    e.store = store
    e.panes.sorted.view.SetContentHeight = function() end
    e.panes.sorted.view.SetScrollPosition = function() end
    e.panes.unsorted.view.SetContentHeight = function() end
    e.panes.unsorted.view.SetScrollPosition = function() end
    e.panes.unsorted.view.contentWidth = 160
    e.panes.sorted.view.contentWidth = 160
    e.unsortedHint = { content = "", hidden = true }
    e.unsortedQuery, e.unsortedNames = "", {}
    e:SelectTag(alphaID)

    -- 1. Copy group from tag alpha, switch to tag beta, paste into empty row 1
    local k1, k2 = e.layout.slots[1].layoutKey, e.layout.slots[2].layoutKey
    e:SelectItems({ k1, k2 })
    assert(e:CopySelected())
    assert(e.clipboard ~= nil)
    e:SelectTag(betaID)
    assert(e.clipboard ~= nil, "clipboard must persist across tag switches")
    e.pasteCell = 4 -- row 1, col 0 (row 0 is label 'Weapons')
    assert(e:PasteClipboard())
    assert(e.layout.slots[4].objectID == 10 and e.layout.slots[5].objectID == 20)

    -- 2. Shift+Delete removes hovered label row, selected item row, or empty paste-cell row
    ModifierKey.META = 8
    package.loaded["resources/windows/layout_editor_keys"] = nil
    for k, v in pairs(require("resources/windows/layout_editor_keys")) do e[k] = v end
    GameKey.CONTROL, GameKey.SHIFT, GameKey.DELETE, GameKey.C, GameKey.V = 1, 2, 3, 4, 5
    GameKey.FromID = function(code)
        return ({ [1] = "CONTROL", [2] = "SHIFT", [3] = "DELETE", [4] = "C", [5] = "V" })[code]
    end
    Keyboard.IsShiftDown = function() return false end
    Keyboard.IsControlDown = function() return false end
    Keyboard.IsAltDown = function() return false end
    Keyboard.IsMetaDown = function() return false end
    prettyui.KeybindField = { IsCapturing = function() return false end }

    local defaults = Settings.defaults()
    assert(defaults.editorKeybinds.removeRow[1] == "SHIFT" and defaults.editorKeybinds.removeRow[2] == "DELETE")
    e.settings = function() return defaults end
    e.keysOnGrid = true

    local confirmPrompted = nil
    e.onConfirmRemoveRow = function(opts) confirmPrompted = opts end

    -- Hover over label row 0 and press Shift+Delete -> prompts to remove label 'Weapons'
    local sorted = e.panes.sorted
    e.pointerSurface = sorted.surface
    e.pointerX, e.pointerY = sorted.x + sorted.gridLeft + 10, sorted.y + 8
    e:KeyPressed({ gameKey = GameKey.DELETE, modifiers = ModifierKey.SHIFT })
    assert(confirmPrompted ~= nil and string.find(confirmPrompted.message, "Weapons", 1, true))
    assert(not string.find(confirmPrompted.message, "\n", 1, true)
        and confirmPrompted.messageLines ~= nil and #confirmPrompted.messageLines == 2)
    confirmPrompted.onConfirm()
    assert(#e.layout.labels == 0, "confirmed Shift+Delete should remove the label row")

    -- Empty row selected via pasteCell -> Shift+Delete removes immediately without confirmation
    assert(store:InsertLayoutRow(betaID, 0, 3))
    e:RefreshCenter()
    e.pointerSurface = nil
    e:SelectOnly(nil)
    e.pasteCell = 1
    confirmPrompted = nil
    local linesBefore = e.layout.lines
    e:KeyPressed({ gameKey = GameKey.DELETE, modifiers = ModifierKey.SHIFT })
    assert(confirmPrompted == nil and e.layout.lines == linesBefore - 1)

    -- 3. macOS Meta / Command matches CONTROL-bound shortcuts (Cmd+C, Cmd+V), without matching Shift+Cmd+C
    e.clipboard = nil
    local copiedKey = e.layout.slots[1].layoutKey
    e:SelectOnly(copiedKey)
    -- Shift+Cmd+C must NOT trigger Copy
    e:KeyPressed({ gameKey = GameKey.C, modifiers = ModifierKey.META | ModifierKey.SHIFT })
    assert(e.clipboard == nil)
    -- Cmd+C triggers Copy
    e:KeyPressed({ gameKey = GameKey.C, modifiers = ModifierKey.META })
    assert(e.clipboard ~= nil)
    -- Cmd+V (via Keyboard.IsMetaDown) pastes into empty cell 3
    e:SelectOnly(nil)
    e.pasteCell = 3
    Keyboard.IsMetaDown = function() return true end
    e:KeyPressed({ gameKey = GameKey.V, modifiers = 0 })
    Keyboard.IsMetaDown = function() return false end
    assert(e.layout.slots[3].objectID == 10)
end

return suite
