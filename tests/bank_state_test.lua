-- Tag page restrictions and Core failures keep feedback and page identity correct.
local suite = { setup = require("tests/app_fixture"), tests = {} }

suite.tests.restrictions_refuse_and_clear_notice = function()
    for _, case in ipairs({
        {"bankOpen",false,"Open your bank"},
        {"viewAll",false,"All Items"},
        {"presetOpen",true,"preset selector"},
        {"searchActive",true,"bank search"},
        {"filterActive",true,"bank filter"},
    }) do
        local field,value,message=table.unpack(case)
        state={bankOpen=true,viewAll=true};state[field]=value
        local beforeRefreshes=tabRefreshes
        local ok,reason=app:ShowTag('gear')
        assert(not ok and reason and string.find(app.status,message,1,true))
        assert(tabRefreshes>beforeRefreshes,'refused tag click must refresh sidebar selection')
        assert(app.pageTag=='other')
        app:OnBankStateChanged({bankOpen=true,viewAll=true})
        assert(app.status==nil)
    end
end

suite.tests.core_refusals_preserve_previous_page = function()
    for _, reason in ipairs({"not_all_items","preset_open","bank_closed","busy","stale","no_page","failed","unknown"}) do
        refusal = reason
        local ok,reason=app:ShowTag('gear')
        assert(not ok and reason==refusal and app.status)
        assert(app.pageTag=='other' and app.pageKeys[1]==42 and app.revision==3)
    end
end

suite.tests.navigating_away_closes_quietly_without_notice_or_reopening = function()
    opened=true
    app:OnBankStateChanged({bankOpen=true,viewAll=false})
    assert(not opened and app.status==nil)
    app:OnPageClosed()
    assert(app.status==nil)
    app:OnBankStateChanged({bankOpen=true,viewAll=true})
    assert(not opened and app.status==nil)

    opened=true
    app:OnBankStateChanged({bankOpen=true,viewAll=true,presetOpen=true})
    assert(not opened and app.status==nil)
    app:OnBankStateChanged({bankOpen=true,viewAll=true})
    assert(not opened and app.status==nil)

    app:ShowStateNotice('not_all_items')
    app:ShowStatus('An unrelated save error')
    app:OnBankStateChanged({bankOpen=true,viewAll=true})
    assert(app.status=='An unrelated save error')
end

suite.tests.press_resets_prettyui_row_selection_before_tag_opens = function()
    package.loaded['resources/sidebar/tag_list_parts'] = {
        FOLDER_ENTRY_PREFIX='__folder:', ROW_HEIGHT=30, ENTRY_HEIGHT=32,
        folderKeyOf=function() return nil end, sidebarEntry=function(id) return {kind='tag',tag=id} end,
    }
    package.loaded['resources/ui/geometry'] = { interfaceMousePosition=function() return 10,10 end,
        absolutePosition=function() return 0,0 end }
    package.loaded['resources/ui/sidebar_rows'] = { AddSelectedFrame=function() end }
    package.loaded['resources/ui/theme'] = { SELECTED_BORDER=1 }
    local drag = require('resources/sidebar/tag_list_drag')
    local refreshed = false
    local row = { root={}, entry={ id='gear', selected=true } }
    local list = setmetatable({
        clicks=0,
        entriesByID={ gear={ id='gear', selected=false } },
        list={ rows={ row }, viewport={ width=200, height=200 },
            _RefreshRows=function() refreshed=true end },
        RowFor=function() return row end,
    }, { __index=drag })
    list:Press('gear')
    assert(row.entry.selected==false and refreshed)
end

suite.tests.close_failure_is_reported = function()
    opened=true
    ext.Close=function() return false,'busy' end
    assert(not app:ToggleTag('other'))
    assert(string.find(app.status,'updating',1,true))
    app:OnBankStateChanged({bankOpen=true,viewAll=false})
    assert(opened and string.find(app.status,'updating',1,true))
end

suite.tests.bank_close_closes_all_additional_windows_including_import_share = function()
    package.loaded['resources/windows/windows'] = nil
    for _, dep in ipairs({
        'windows/confirm_window', 'core/debug_log', 'windows/import_share',
        'windows/layout_editor_window', 'windows/sprite_picker', 'tags/tag_rules',
        'windows/tag_settings_editor', 'ui/text_prompt',
    }) do
        package.loaded['resources/' .. dep] = { Write = function() end }
    end
    local Windows = require('resources/windows/windows')
    local windows = Windows.new(app)
    local names = { 'textPrompt', 'layoutEditor', 'tagSettingsEditor', 'tagDeleteConfirm',
        'rowRemoveConfirm', 'importShare', 'spritePicker' }
    local destroyed = {}
    for _, name in ipairs(names) do
        windows[name] = { Destroy = function() destroyed[name] = true end, SetOverlays = function() end }
    end
    windows.spritePickerOwner = windows.importShare
    windows:CloseBankWindows()
    for _, name in ipairs(names) do
        assert(windows[name] == nil and destroyed[name], name .. ' should close on bank close')
    end
    assert(windows.spritePickerOwner == nil)
end

suite.tests.sidebar_scroll_persists_across_rebuilds_and_flushes_on_bank_close = function()
    package.loaded['resources/sidebar/tag_list'] = nil
    package.loaded['resources/sidebar/tag_list_drag'] = { StopGesture = function() end, BindRow = function() end }
    package.loaded['resources/sidebar/tag_list_parts'] = {
        FOLDER_ENTRY_PREFIX = '__folder:', ROW_HEIGHT = 30, ENTRY_HEIGHT = 32,
        folderKeyOf = function() return nil end, sidebarEntry = function(id) return { kind = 'tag', tag = id } end,
    }
    package.loaded['resources/ui/geometry'] = { trackPointer = function() end }
    package.loaded['resources/ui/theme'] = { ROW_ODD = 1, ROW_EVEN = 2, ROW_HOVER = 3, ROW_SELECTED = 4, HEADING_TEXT = 5, HEADING_LINE = 6 }
    package.loaded['resources/core/text'] = { titleCase = function(s) return s end, plain = function(s) return s end }
    local createdLists = {}
    package.loaded['resources/ui/sidebar_rows'] = {
        ROW_LEFT = 6, ROW_TEXT = 1, ENTRY_HEIGHT = 32,
        ContentWidth = function(w) return w end,
        CreateSearch = function() return { Destroy = function() end } end,
        CreateEmptyLabel = function() return { hidden = false, Destroy = function() end } end,
        CreateList = function()
            local list = {
                root = { hidden = false },
                rows = {},
                scrollY = 0,
                SetEntries = function() end,
                SetScrollPosition = function(self, y) self.scrollY = y end,
                Destroy = function() end,
            }
            createdLists[#createdLists + 1] = list
            return list
        end,
    }
    local TagList = require('resources/sidebar/tag_list')
    local listState = { searchQuery = '', scrollY = 0 }
    local store = {
        TagTree = function() return { { kind = 'tag', tag = 'gear' }, { kind = 'tag', tag = 'pvm' } } end,
        AllTags = function() return { 'gear', 'pvm' } end,
        GetTagName = function(_, tag) return tag end,
    }
    local opts = {
        store = store,
        settings = function() return { showTagSprites = false } end,
        state = listState,
        width = 220,
        listHeight = 200,
        isSelected = function() return false end,
    }
    local first = TagList.new({}, opts)
    first.list:SetScrollPosition(96)
    first:Destroy()
    assert(listState.scrollY == 96)

    -- Rebuilding TagList within the same bank session restores scrollY
    local second = TagList.new({}, opts)
    assert(second.list.scrollY == 96)
    second:Destroy()

    -- Bank close flushes scrollY back to 0
    local resetCalled = false
    app.tab.ResetScroll = function() resetCalled = true; listState.scrollY = 0 end
    app.nativeItems.Stop = function() end
    app.tutorial = { Stop = function() end }
    app.windows = { CloseBankWindows = function() end }
    app:OnBankClose()
    assert(resetCalled and listState.scrollY == 0)

    local third = TagList.new({}, opts)
    assert(third.list.scrollY == 0)
    third:Destroy()
end

return suite
