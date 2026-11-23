-- Local connection regressions for dependency load order and Core reloads.
local suite = { setup = require("tests/app_fixture"), tests = {} }

suite.tests.core_is_a_required_dependency = function()
    local file=assert(io.open(root .. "/plugin.json", "r"))
    local contents=file:read("*a"); file:close()
    local manifest=require("resources/core/json").decode(contents)
    assert(manifest.requiredDependencies.bankcore==6464293)
    assert(manifest.optionalDependencies.bankcore==nil)
end

suite.tests.missing_core_then_late_load = function()
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
        assert(type(spec.onSelect)=='function' and type(spec.onDeselect)=='function')
        count=count+1; return handle
    end}
    app:CheckConnection()
    assert(app.ext==handle and count==1)
    app:CheckConnection()
    assert(count==1,'a healthy connection must not register again')
end

suite.tests.older_core_without_selection_hooks_falls_back = function()
    app.Disconnect=function(self) self.ext=nil end
    app.OnBankStateChanged=function() end
    app.nativeItems.Start=function() end
    app.menus={Start=function() end}
    local calls=0
    local handle={GetBankState=function() return {bankOpen=false} end}
    bankcore={Register=function(spec)
        calls=calls+1
        if spec.onSelect~=nil or spec.onDeselect~=nil then return nil,'invalid','unknown field' end
        return handle
    end}
    assert(app:Connect() and app.ext==handle and calls==2)
end

suite.tests.stale_export_falls_back_to_replacement = function()
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
end

suite.tests.retry_waits_and_stops_after_shutdown = function()
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
end

return suite
