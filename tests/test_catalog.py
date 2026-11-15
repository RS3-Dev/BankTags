"""Check the editor's bankable search without changing icon-picker searches."""

from pathlib import Path
import unittest

from lupa.lua54 import LuaRuntime


ROOT = Path(__file__).resolve().parents[1]


class CatalogTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime()
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root .. '/?.lua;' .. package.path
            package.loaded['resources/core/object_config']={
                ObjectID=function(name) return ({bank_item=10,other_item=20,CERT_bank_item=30,bank_CERT_item=40})[name] end,
                ConfigName=function(id) return ({[10]='bank_item',[20]='other_item',[30]='CERT_bank_item',[40]='bank_CERT_item'})[id] end,
                DisplayName=function(id) return ({[10]='Bank item',[20]='Other item',[30]='Bank item',[40]='Bank certificate'})[id] end,
            }
            Catalog=require('resources/tags/catalog')
            bank={{objectID=10}}
        ''')

    def test_bankable_search_passes_query_limit_and_options(self):
        self.lua.execute('''
            runeql={Catalog={Find=function(query,limit,options)
                assert(query=='shark' and limit==100 and options.bankableOnly==true)
                return {{configName='bank_item',displayName='Bank item'}}, 12
            end,Search=function() error('Must not scan query attributes') end}}
            local items,total,limited=Catalog.Find('shark',100,bank,{bankableOnly=true})
            assert(#items==1 and items[1].objectId==10 and total==12 and not limited)
            assert(Catalog.IsFull({bankableOnly=true}))
        ''')

    def test_icon_picker_keeps_unfiltered_find(self):
        self.lua.execute('''
            runeql={Catalog={Find=function(query,limit,options)
                assert(query=='Other' and limit==40 and options==nil)
                return {{configName='other_item'}},1
            end,Search=function() error('Unexpected Search call') end}}
            local items=Catalog.Find('Other',40,bank)
            assert(#items==1 and items[1].objectId==20)
        ''')

    def test_noted_configs_are_excluded_only_from_bankable_results(self):
        self.lua.execute('''
            runeql={Catalog={Find=function()
                return {{configName='CERT_bank_item'},{configName='bank_item'},
                    {configName='bank_CERT_item'}},3
            end}}
            local items=Catalog.Find('Bank',100,bank,{bankableOnly=true})
            assert(#items==2 and items[1].objectId==10 and items[2].objectId==40)
            local icons=Catalog.Find('Bank',40,bank)
            assert(#icons==3 and icons[1].objectId==30)
        ''')

    def test_noted_configs_are_excluded_from_fallback_names_and_exact_references(self):
        self.lua.execute('''
            bank={{objectID=30},{objectID=10},{objectID=40}}
            for _,query in ipairs({'30','#30','CERT_bank_item'}) do
                local items=Catalog.Find(query,100,bank,{bankableOnly=true})
                assert(#items==0)
            end
            local items=Catalog.Find('Bank',100,bank,{bankableOnly=true})
            assert(#items==2 and items[1].objectId==10 and items[2].objectId==40)
            assert(#Catalog.Find('30',40,bank)==1)
        ''')

    def test_limited_bankable_search_rejects_nonbank_exact_references(self):
        self.lua.execute('''
            for _,query in ipairs({'20','#20','other_item','Other'}) do
                local items,total,limited=Catalog.Find(query,100,bank,{bankableOnly=true})
                assert(#items==0 and total==0 and limited)
            end
            for _,query in ipairs({'10','#10','bank_item','Bank'}) do
                local items=Catalog.Find(query,100,bank,{bankableOnly=true})
                assert(#items==1 and items[1].objectId==10)
            end
            assert(#Catalog.Find('20',40,bank)==1)
        ''')

    def test_missing_find_does_not_fall_back_to_query_search(self):
        self.lua.execute('''
            runeql={Catalog={Search=function() error('Must not use query Search') end}}
            assert(not Catalog.IsFull({bankableOnly=true}))
            local items,_,limited=Catalog.Find('Other',100,bank,{bankableOnly=true})
            assert(#items==0 and limited)
        ''')

    def test_global_api_and_disabled_plugin(self):
        self.lua.execute('''
            __runeql_api={Catalog={Find=function() return {{configName='bank_item'}},1 end}}
            assert(Catalog.IsFull({bankableOnly=true}))
            Catalog.SetRuneQLEnabled(false)
            assert(not Catalog.IsFull({bankableOnly=true}))
            local items,_,limited=Catalog.Find('tier:90',100,bank,{bankableOnly=true})
            assert(#items==0 and limited)
        ''')

    def test_query_errors_reach_editor_error_handler(self):
        self.lua.execute('''
            runeql={Catalog={Find=function() return nil,0,'Invalid query' end}}
            local ok,reason=pcall(Catalog.Find,'bad query',100,bank,{bankableOnly=true})
            assert(not ok and string.find(reason,'Invalid query',1,true))
        ''')

    def test_sidebar_requests_bankable_options(self):
        self.lua.execute('''
            package.loaded['resources/windows/layout_editor_parts']={size={SEARCH_ROW_HEIGHT=32}}
            local search=require('resources/windows/layout_editor_search')
            local called=false
            Catalog.Find=function(query,limit,items,options)
                assert(query=='shark' and limit==100 and items==bank and options.bankableOnly==true)
                assert(options.includeFields==false, 'Name search must not load attribute shards')
                called=true; return {},0,false
            end
            local editor={bankItemList=bank,searchList={rows={},SetEntries=function() end},
                searchHint={},searchDragSurface={MoveToFront=function() end}}
            for key,value in pairs(search) do editor[key]=value end
            editor:RunSearch(' shark ')
            assert(called and #editor.searchResults==0)
        ''')

    def test_typing_only_searches_latest_value_after_pause(self):
        self.lua.execute('''
            package.loaded['resources/windows/layout_editor_parts']={size={SEARCH_ROW_HEIGHT=32}}
            local search=require('resources/windows/layout_editor_search')
            local calls={}
            Catalog.Find=function(query)
                calls[#calls+1]=query; return {},0,false
            end
            local editor={bankItemList=bank,searchList={rows={},SetEntries=function() end},
                searchHint={},searchDragSurface={MoveToFront=function() end}}
            for key,value in pairs(search) do editor[key]=value end
            editor:QueueSearch('s'); editor:TickSearch()
            editor:QueueSearch('sh'); editor:TickSearch()
            editor:QueueSearch('shark'); editor:TickSearch(); editor:TickSearch()
            assert(#calls==0)
            editor:TickSearch(); assert(#calls==1 and calls[1]=='shark')
            editor:TickSearch(); assert(#calls==1)
            editor:QueueSearch('sharks'); editor:RunSearch('sharks')
            editor:TickSearch(); assert(#calls==2 and calls[2]=='sharks')
            editor:QueueSearch('sh'); editor:QueueSearch(' ')
            editor:TickSearch(); assert(#calls==2 and #editor.searchResults==0)
        ''')


if __name__ == '__main__':
    unittest.main()
