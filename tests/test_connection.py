"""Local connection regressions for dependency load order and Core reloads."""
import unittest
import json
import test_bank_state

class ConnectionTests(unittest.TestCase):
    setUp = test_bank_state.BankStateTests.setUp

    def test_core_is_a_required_dependency(self):
        manifest = json.loads((test_bank_state.ROOT / 'plugin.json').read_text())
        self.assertEqual(manifest['requiredDependencies']['bankcore'], 6464293)
        self.assertNotIn('bankcore', manifest['optionalDependencies'])
    def test_missing_core_then_late_load(self):
        self.lua.execute('''
            local App=getmetatable(app)
            app.Disconnect=function(self) self.ext=nil end
            app.OnBankStateChanged=function() end
            app.nativeItems.Start=function() end
            app.menus={Start=function() end}
            bankcore=nil
            assert(not app:Connect() and app.ext==nil)
            local count=0
            local handle={GetBankState=function() return {bankOpen=false} end}
            bankcore={Register=function(spec)
                assert(spec.id=='banktags' and spec.icon=='LIST_LAYOUT')
                count=count+1; return handle
            end}
            app:CheckConnection()
            assert(app.ext==handle and count==1)
            app:CheckConnection()
            assert(count==1,'a healthy connection must not register again')
        ''')

    def test_stale_export_falls_back_to_replacement(self):
        self.lua.execute('''
            local config=require('resources/core/config')
            config.CORE_API_KEY='__bankcore_api'
            app.Disconnect=function(self) self.ext=nil end
            app.OnBankStateChanged=function() end
            app.nativeItems.Start=function() end
            app.menus={Start=function() end}
            app.ext={GetBankState=function() return nil,'stale' end}
            bankcore={Register=function() return nil,'stopped' end}
            local count=0
            local handle={GetBankState=function() return {bankOpen=false} end}
            _G.__bankcore_api={Register=function() count=count+1;return handle end}
            app:CheckConnection()
            assert(app.ext==handle and count==1)
            app:CheckConnection()
            assert(count==1)
        ''')

    def test_retry_waits_and_stops_after_shutdown(self):
        self.lua.execute('''
            local callbacks={}
            Event={Logic={Subscribe=function(key,callback) callbacks[key]=callback end},
                SettingsLayerReady={Subscribe=function() end}}
            local attempts=0
            app.Connect=function() attempts=attempts+1 end
            app.ext=nil
            app:Start()
            assert(attempts==1)
            local tick=assert(callbacks.banktags_core_connection)
            for i=1,49 do tick() end
            assert(attempts==1)
            tick()
            assert(attempts==2)
            app.shutDown=true
            for i=1,50 do tick() end
            assert(attempts==2)
        ''')
