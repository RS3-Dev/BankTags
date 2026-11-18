-- Shared app and Bank Core handle stubs.
return function()
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
end
