"""Blank-cell menu actions must be explicit right-click choices."""

from pathlib import Path
import unittest

from lupa.lua54 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


class EditorMenuTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime()
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute('''
            package.path=root..'/?.lua;'..package.path
            MiniMenuActionType={CANCEL=0}
            pendingTick=nil
            Event={Logic={Subscribe=function(_,fn) pendingTick=fn end, Unsubscribe=function() end}}
            prettyui={MiniMenu={AddSubmenu=function(menu,label,children,options)
                menu.children=children
                menu:Add(label..' <col=ffffff><gt></col>',function() end)
            end}}
            editor={RowMenuTarget=function() return target end,
                RowTargetCurrent=function() return true end,
                InsertEmptyRow=function(_,row) inserted=row end}
            menus=require('resources/sidebar/tag_menus').new({windows={layoutEditor=editor}})
            function build(pane,key,usedRows)
                inserted=nil; pendingTick=nil
                target={pane=pane,layoutKey=key,usedRows=usedRows,row=0}
                local menu={entries={{actionType=0,fullText='Cancel'}},entryCount=1}
                function menu:Add(text,callback)
                    table.insert(self.entries,1,{actionType=1,fullText=text,callback=callback})
                    self.entryCount=#self.entries
                end
                function menu:Swap(a,b) self.entries[a],self.entries[b]=self.entries[b],self.entries[a] end
                menus:AddEditorEntries(menu)
                return menu
            end
        ''')

    def test_blank_cell_defaults_to_cancel_and_retains_row_submenu(self):
        self.lua.execute('''
            local menu=build('sorted',nil,1)
            assert(menu.entries[menu.entryCount].actionType==MiniMenuActionType.CANCEL)
            assert(#menu.children==6)
            menu.children[1].action(); assert(pendingTick==nil and inserted==nil)
            menus.rowMenu.opened=true
            menu.children[1].action(); assert(pendingTick); pendingTick()
            assert(inserted==0)
        ''')

    def test_empty_layout_keeps_add_row_as_explicit_choice(self):
        self.lua.execute('''
            local menu=build('sorted',nil,0)
            assert(menu.entries[menu.entryCount].actionType==MiniMenuActionType.CANCEL)
            local add
            for _,entry in ipairs(menu.entries) do if entry.fullText=='Add row' then add=entry end end
            assert(add)
            add.callback(); assert(pendingTick==nil and inserted==nil)
            menus.rowMenu.opened=true; add.callback(); pendingTick(); assert(inserted==0)
        ''')

    def test_item_menus_keep_existing_default_actions(self):
        self.lua.execute('''
            local sorted=build('sorted','item1',1)
            assert(sorted.entries[sorted.entryCount].fullText=='Move to Unsorted')
            local unsorted=build('unsorted','item2',1)
            assert(unsorted.entries[unsorted.entryCount].fullText=='Move to Layout')
        ''')


if __name__ == '__main__':
    unittest.main()
