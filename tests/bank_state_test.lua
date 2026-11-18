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
        local ok,reason=app:ShowTag('gear')
        assert(not ok and reason and string.find(app.status,message,1,true))
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

suite.tests.state_change_closes_with_notice_without_reopening = function()
    opened=true
    app:OnBankStateChanged({bankOpen=true,viewAll=true,presetOpen=true})
    assert(not opened and string.find(app.status,'preset selector',1,true))
    app:OnBankStateChanged({bankOpen=true,viewAll=true})
    assert(not opened and app.status==nil)
    app:ShowStateNotice('not_all_items')
    app:ShowStatus('An unrelated save error')
    app:OnBankStateChanged({bankOpen=true,viewAll=true})
    assert(app.status=='An unrelated save error')
end

suite.tests.close_failure_is_reported = function()
    opened=true
    ext.Close=function() return false,'busy' end
    assert(not app:ToggleTag('other'))
    assert(string.find(app.status,'updating',1,true))
    app:OnBankStateChanged({bankOpen=true,viewAll=false})
    assert(opened and string.find(app.status,'updating',1,true))
end

return suite
