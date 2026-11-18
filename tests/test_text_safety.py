"""Unsafe share text must never reach saved strings or rendered labels."""

from pathlib import Path
import unittest

from lupa.lua54 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
CORE_API = Path('C:/Users/thejo/Documents/RSDevSync/plugins/bankcore/lib/core/public_api.lua')


class TextSafetyTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime()
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
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
        ''')

    def test_complete_and_malformed_tags_without_core(self):
        self.lua.execute('''
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
        ''')

    def test_core_api_used_and_fallback_survives_failures(self):
        self.lua.execute('''
            called=false
            bankcore={SanitizeString=function(text) called=true; return text:gsub('<[^<>]*>',''):gsub('[<>]','') end}
            assert(Text.sanitize('Food<img=-1>')=='Food' and called)
            bankcore={SanitizeString=function() error('unavailable') end}
            assert(Text.sanitize('Food<img=-1>')=='Food')
            bankcore={SanitizeString=function() return nil,'invalid' end}
            assert(Text.sanitize('Food<img=-1>')=='Food')
        ''')

    @unittest.skipUnless(CORE_API.exists(), 'Installed Bank Core API is not available')
    def test_actual_installed_core_api(self):
        self.lua.globals().corePath = CORE_API.as_posix()
        self.lua.execute('''
            bankcore=assert(loadfile(corePath))().new({},nil)
            assert(Text.sanitize('Food<img=-1><sprite=-999>')=='Food')
        ''')

    def test_import_load_save_and_share_are_sanitized(self):
        self.lua.execute('''
            local code=Json.encode(malicious)
            local data=assert(Data.Decode(code)); safe(data)
            assert(data.order[1]=='safe name' and data.tags['safe name'].rows[1].text=='Heading')
            local store=Store.new()
            assert(store:ImportText(code)); safe(store.data)
            for _,value in pairs(savedValues) do safe(value) end
            local loaded=Store.new(); assert(loaded.loadError==nil); safe(loaded.data)
            local shared=Data.Encode(loaded.data); safe(shared); assert(Data.Decode(shared))
        ''')

    def test_old_poisoned_storage_is_safe_before_first_display(self):
        self.lua.execute('''
            local Config=require('resources/core/config')
            local chunks=require('resources/core/chunked_string_store')
            assert(chunks.Write({manifestKey=Config.TAGS_TEXT_MANIFEST_KEY,
                chunkPrefix=Config.TAGS_TEXT_CHUNK_PREFIX},Json.encode(malicious)))
            local loaded=Store.new(); assert(loaded.loadError==nil); safe(loaded.data)
            local page=require('resources/tags/tag_page')
            local rows=page.Rows(loaded.data.tags['safe name']); safe(rows)
            assert(rows[1].label=='Heading')
            assert(loaded:Save())
            local current=assert(chunks.Read({manifestKey=Config.TAGS_TEXT_MANIFEST_KEY,
                chunkPrefix=Config.TAGS_TEXT_CHUNK_PREFIX})); safe(current)
        ''')

    def test_manual_names_and_labels_are_clean_before_storage(self):
        self.lua.execute('''
            local store=Store.new()
            local ok,name=store:CreateTag('Food<img=-1>'); assert(ok and name=='food')
            assert(store:CreateFolder('Gear<sprite=-1>',name))
            assert(store:InsertLabel(name,0,'Supplies<img=-1>',10))
            safe(store.data)
            for _,value in pairs(savedValues) do safe(value) end
        ''')

    def test_encoding_sanitizes_strings_without_crossing_json_fields(self):
        self.lua.execute('''
            local data={order={'start<','>end'},folders={},tags={
                ['start<']={rows={},unsorted={}},['>end']={rows={},unsorted={}}}}
            local code=Data.Encode(data); safe(code)
            local decoded=assert(Data.Decode(code))
            assert(#decoded.order==2 and decoded.tags.start and decoded.tags['end'])
        ''')

    def test_field_cleaning_does_not_recurse_or_strip_safe_text(self):
        self.lua.execute('''
            local field={SetText=function(self,value,notify) self.value=value; assert(not notify) end}
            assert(Text.cleanField(field,'Food<img=-1>')=='Food' and field.value=='Food')
            field.value=nil; Text.cleanField(field,'Food'); assert(field.value==nil)
        ''')

    def test_menu_and_bank_labels_are_sanitized_at_display(self):
        self.lua.execute('''
            local menu=require('resources/ui/menu_entries')
            assert(menu.Text('Open<img=-1>','Food<sprite=-1>')=='Open Food')
            local rows=require('resources/tags/tag_page').Rows({
                rows={{kind='label',text='Food<img=-1>'}},unsorted={}})
            assert(rows[1].label=='Food'); safe(rows)
        ''')


if __name__ == '__main__':
    unittest.main()
