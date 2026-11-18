"""Tag page restrictions and Core failures keep feedback and page identity correct."""
from pathlib import Path
import unittest
from lupa.lua54 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]

class BankStateTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime()
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path = root .. '/?.lua;' .. package.path
            for _,name in ipairs({'core/config','core/debug_log','tags/native_items',
                'sidebar/select_mode','core/settings','windows/settings_section',
                'sidebar/tag_menus','tags/tag_page','tags/tag_store','sidebar/tag_tab',
                'windows/windows','windows/tutorial'}) do
                package.loaded['resources/'..name] = {PLUGIN_REF='banktags',Write=function() end}
            end
            local App=require('resources/app')
            state={bankOpen=true,viewAll=true}
            opened=false
            ext={GetBankState=function() return state end,
                IsOpen=function() return opened end,
                Close=function() opened=false; return true end,
                Open=function() if refusal then return false,refusal end; opened=true; return true end}
            app=setmetatable({ext=ext,store={data={tags={gear={},other={}}}},
                tab={Refresh=function() end,RefreshStatus=function() end},
                nativeItems={RestoreHighlights=function() end,Refresh=function() end},
                select={Stop=function() end},pageTag='other',pageKeys={42},revision=3},App)
            function app:SetTagPage(tag) self.pageTag=tag;self.pageKeys={99};self.revision=4;return true end
        ''')

    def test_restrictions_refuse_and_clear_notice(self):
        for field, value, message in [('bankOpen',False,'Open your bank'),
            ('viewAll',False,'All Items'),('presetOpen',True,'preset selector'),
            ('searchActive',True,'bank search'),('filterActive',True,'bank filter')]:
            with self.subTest(field=field):
                self.lua.globals().field=field
                self.lua.globals().value=value
                self.lua.globals().message=message
                self.lua.execute('''
                    state={bankOpen=true,viewAll=true};state[field]=value
                    local ok,reason=app:ShowTag('gear')
                    assert(not ok and reason and string.find(app.status,message,1,true))
                    assert(app.pageTag=='other')
                    app:OnBankStateChanged({bankOpen=true,viewAll=true})
                    assert(app.status==nil)
                ''')

    def test_core_refusals_preserve_previous_page(self):
        for reason in ['not_all_items','preset_open','bank_closed','busy','stale','no_page','failed','unknown']:
            with self.subTest(reason=reason):
                self.lua.globals().refusal=reason
                self.lua.execute('''
                    local ok,reason=app:ShowTag('gear')
                    assert(not ok and reason==refusal and app.status)
                    assert(app.pageTag=='other' and app.pageKeys[1]==42 and app.revision==3)
                ''')

    def test_state_change_closes_with_notice_without_reopening(self):
        self.lua.execute('''
            opened=true
            app:OnBankStateChanged({bankOpen=true,viewAll=true,presetOpen=true})
            assert(not opened and string.find(app.status,'preset selector',1,true))
            app:OnBankStateChanged({bankOpen=true,viewAll=true})
            assert(not opened and app.status==nil)
            app:ShowStateNotice('not_all_items')
            app:ShowStatus('An unrelated save error')
            app:OnBankStateChanged({bankOpen=true,viewAll=true})
            assert(app.status=='An unrelated save error')
        ''')

    def test_close_failure_is_reported(self):
        self.lua.execute('''
            opened=true
            ext.Close=function() return false,'busy' end
            assert(not app:ToggleTag('other'))
            assert(string.find(app.status,'updating',1,true))
            app:OnBankStateChanged({bankOpen=true,viewAll=false})
            assert(opened and string.find(app.status,'updating',1,true))
        ''')
