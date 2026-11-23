-- Unsafe share text must never reach saved strings or rendered labels.
local suite = { setup = function()
    package.path=root .. '/?.lua;' .. package.path
    Text=require('resources/core/text')
    Rules=require('resources/tags/tag_rules')
    Json=require('resources/core/json')
    Data=require('resources/tags/tag_data')
    savedValues={}
    PersistentDB={GetString=function(_,key) return savedValues[key] end,
        SetString=function(_,key,value) savedValues[key]=value; return true end}
    Store=require('resources/tags/tag_store')
    function safe(value)
        if type(value)=='string' then assert(not value:find('[<>]'),value)
        elseif type(value)=='table' then for k,v in pairs(value) do safe(k); safe(v) end end
    end
    malicious={format='bankutilities-tags',version=4,
        order={'Safe<img=-1> name'},
        folders={evil={name='Gear<sprite=999999999>',icon='<img=-1>UNKNOWN'}},
        tags={['Safe<img=-1> name']={folder='evil',icon='<sprite=-1>ICON',
            rows={'Heading<img=-1>',{'<img=-1>UNKNOWN'}},unsorted={'<sprite=-1>UNKNOWN'}}}}
end, tests = {} }

suite.tests.complete_and_malformed_tags_without_core = function()
    assert(Text.plain('  Safe<img=-1> name  ')=='Safe name')
    assert(Text.plain('<sprite=999999999>')=='')
    assert(Text.titleCase('gear<img=-1> box')=='Gear Box')
    for _,value in ipairs({'<img=-1','<<img=-1>>','x<>y','a<col=red>b</col>c',
        '<img=<sprite=-1>>','a> <b','<IMG=-1>'}) do safe(Text.sanitize(value)) end
    assert(Rules.normalizeTag('<img=-1>')==nil)
    assert(Rules.normalizeTag('Food<sprite=-1>')=='food')
    local key,name=Rules.folderName(' Gear<img=-1> ')
    assert(key=='gear' and name=='Gear')
    assert(Rules.labelText('Heading<sprite=-1>')=='Heading')
end

suite.tests.core_api_used_and_fallback_survives_failures = function()
    called=false
    bankcore={SanitizeString=function(text) called=true; return text:gsub('<[^<>]*>',''):gsub('[<>]','') end}
    assert(Text.sanitize('Food<img=-1>')=='Food' and called)
    bankcore={SanitizeString=function() error('unavailable') end}
    assert(Text.sanitize('Food<img=-1>')=='Food')
    bankcore={SanitizeString=function() return nil,'invalid' end}
    assert(Text.sanitize('Food<img=-1>')=='Food')
end

suite.tests.actual_installed_core_api = function()
    local coreRoot=os.getenv("BANKCORE_ROOT")
    if not coreRoot or coreRoot=="" then return "skip", "BANKCORE_ROOT is not set" end
    local corePath=coreRoot .. "/lib/core/public_api.lua"
    bankcore=assert(loadfile(corePath))().new({},nil)
    assert(Text.sanitize("Food<img=-1><sprite=-999>")=="Food")
end

suite.tests.import_load_save_and_share_are_sanitized = function()
    local code=Json.encode(malicious)
    local data=assert(Data.Decode(code)); safe(data)
    local id=data.order[1]
    assert(Rules.isUUID(id) and data.tags[id].name=='safe name' and data.tags[id].rows[1].text=='Heading')
    local store=Store.new()
    assert(store:ImportText(code)); safe(store.data)
    for _,value in pairs(savedValues) do safe(value) end
    local loaded=Store.new(); assert(loaded.loadError==nil); safe(loaded.data)
    local shared=Data.Encode(loaded.data); safe(shared); assert(Data.Decode(shared))
end

suite.tests.old_poisoned_storage_is_safe_before_first_display = function()
    local Config=require('resources/core/config')
    local chunks=require('resources/core/chunked_string_store')
    assert(chunks.Write({manifestKey=Config.TAGS_TEXT_MANIFEST_KEY,
        chunkPrefix=Config.TAGS_TEXT_CHUNK_PREFIX},Json.encode(malicious)))
    local loaded=Store.new(); assert(loaded.loadError==nil); safe(loaded.data)
    local id=loaded.data.order[1]
    assert(Rules.isUUID(id) and loaded:GetTagName(id)=='safe name')
    local page=require('resources/tags/tag_page')
    local rows=page.Rows(loaded.data.tags[id]); safe(rows)
    assert(rows[1].label=='Heading')
    assert(loaded:Save())
    local current=assert(chunks.Read({manifestKey=Config.TAGS_TEXT_MANIFEST_KEY,
        chunkPrefix=Config.TAGS_TEXT_CHUNK_PREFIX})); safe(current)
end

suite.tests.manual_names_and_labels_are_clean_before_storage = function()
    local store=Store.new()
    local ok,id=store:CreateTag('Food<img=-1>')
    assert(ok and Rules.isUUID(id) and store:GetTagName(id)=='food')
    assert(store:CreateFolder('Gear<sprite=-1>',id))
    assert(store:InsertLabel(id,0,'Supplies<img=-1>',10))
    safe(store.data)
    for _,value in pairs(savedValues) do safe(value) end
end

suite.tests.encoding_sanitizes_strings_without_crossing_json_fields = function()
    local data={order={'start<','>end'},folders={},tags={
        ['start<']={rows={},unsorted={}},['>end']={rows={},unsorted={}}}}
    local code=Data.Encode(data); safe(code)
    local decoded=assert(Data.Decode(code))
    assert(#decoded.order==2)
    assert(decoded.tags[decoded.order[1]].name=='start' and decoded.tags[decoded.order[2]].name=='end')
end

suite.tests.field_cleaning_does_not_recurse_or_strip_safe_text = function()
    local field={SetText=function(self,value,notify) self.value=value; assert(not notify) end}
    assert(Text.cleanField(field,'Food<img=-1>')=='Food' and field.value=='Food')
    field.value=nil; Text.cleanField(field,'Food'); assert(field.value==nil)
end

suite.tests.menu_and_bank_labels_are_sanitized_at_display = function()
    local menu=require('resources/ui/menu_entries')
    assert(menu.Text('Open<img=-1>','Food<sprite=-1>')=='Open Food')
    local rows=require('resources/tags/tag_page').Rows({
        rows={{kind='label',text='Food<img=-1>'}},unsorted={}})
    assert(rows[1].label=='Food'); safe(rows)
end

return suite
