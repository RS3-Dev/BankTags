"""Editor item names follow the bank's centered below-item tooltip placement."""

from pathlib import Path
import unittest

from lupa.lua54 import LuaRuntime
from test_marquee import HARNESS

ROOT = Path(__file__).resolve().parents[1]


class EditorNameTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime()
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute(HARNESS)
        self.lua.execute('''
            package.loaded['resources/core/object_config']={DisplayName=function() return 'Item<img=-1>' end}
            for k,v in pairs(require('resources/windows/layout_editor_names')) do e[k]=v end
            prettyui={Tooltip={attach=function(anchor,parent,options)
                assert(options.parent==parent and options.placement=='below')
                local t={width=120,height=28,options=options}
                function t:SetText(text) self.text=text end
                function t:Show() self.shown=true end
                function t:Hide() self.shown=false end
                return t
            end}}
            e.content.width,e.content.height=1000,650
            e.unsortedNames={[10]='Shark'}
            e.panes.sorted.slots[1].objectID=10
            e.panes.unsorted.slots[1].objectID=10
            e:CreateItemNames()
            function hover(x,y)
                e.pointerSurface=e.panes.sorted.surface
                e.pointerX,e.pointerY=x,y
                e:UpdateItemName()
            end
        ''')

    def test_layout_and_unsorted_items_center_name_below_cell(self):
        self.lua.execute('''
            for _,name in ipairs({'sorted','unsorted'}) do
                local p=e.panes[name]
                hover(p.x+p.gridLeft+8,p.y+12)
                assert(e.nameTooltip.shown)
                assert(e.nameTooltipOptions.x==math.floor(p.x+p.gridLeft+(40-120)/2))
                assert(e.nameTooltipOptions.y==p.y+4+40+6)
                assert(e.nameTooltip.text==(name=='unsorted' and 'Shark' or 'Item'))
            end
        ''')

    def test_search_tooltip_appears_even_when_name_fits(self):
        self.lua.execute('''
            local s=require('resources/windows/layout_editor_parts').size
            e.searchList={scrollY=0}; e.searchResults={{objectId=10,displayName='Shark'}}
            hover(s.SEARCH_X+s.SEARCH_INSET+8,s.PANEL_TOP+s.SEARCH_LIST_TOP+8)
            assert(e.nameTooltip.shown and e.nameTooltip.text=='Shark')
            assert(e.nameAnchor.width==24)
            assert(e.nameTooltipOptions.x==s.SEARCH_X+s.SEARCH_INSET+7+(24-120)//2)
            assert(e.nameTooltipOptions.y==s.PANEL_TOP+s.SEARCH_LIST_TOP+4+24+6)
        ''')

    def test_above_fallback_matches_bank_near_bottom(self):
        self.lua.execute('''
            e:PlaceItemName({x=300,y=600,size=40})
            assert(e.nameTooltipOptions.x==260)
            assert(e.nameTooltipOptions.y==600-28-6)
        ''')

    def test_gaps_and_drag_hide_tooltip(self):
        self.lua.execute('''
            hover(212,62); assert(e.nameTooltip.shown)
            hover(244,62); assert(not e.nameTooltip.shown)
            hover(212,62); e.drag={}; e:UpdateItemName()
            assert(not e.nameTooltip.shown)
        ''')


if __name__ == '__main__':
    unittest.main()
