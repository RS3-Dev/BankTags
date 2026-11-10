"""Editor gesture checks. Run with: python -m unittest discover -s tests

Requires lupa (pip install lupa). Native UI objects are replaced with event stubs.
"""

from pathlib import Path
import unittest

from lupa.lua54 import LuaRuntime


ROOT = Path(__file__).resolve().parents[1]
HARNESS = r'''
package.path = root .. '/?.lua;' .. package.path
shiftDown = true
Keyboard = {IsShiftDown = function() return shiftDown end}
ModifierKey = {SHIFT=1, CONTROL=2, ALT=4, ANY=7}
GameKey = {ESCAPE=27}
MiniMenu = {IsOpen=function() return false end}
id = {Sprite={RS3_ICON_SLOT_40PX_1=1}}
ui = {Hook={}, ObjectQuantityDisplayMode={ALWAYS=1}}
for _, name in ipairs({'ONCLICK','ONHOLD','ONMOUSEOVER','ONMOUSEREPEAT','ONMOUSELEAVE',
    'ONDRAG','ONRELEASE','ONDRAGCOMPLETE','ONSCROLLWHEEL'}) do ui.Hook[name] = name end
local function component(parent)
    local value = {parent=parent, hooks={}, x=0, y=0}
    function value:SetPos(x,y) self.x,self.y=x,y end
    function value:SetSize(w,h) self.width,self.height=w,h end
    function value:MoveToFront() end
    function value:Destroy() self.destroyed=true end
    function value:Subscribe(hook, name, fn) self.hooks[hook]=fn or name end
    return value
end
ui.Layer = {new=component}; ui.Rectangle = {new=component}
package.loaded['resources/ui/sidebar_rows'] = {
    CONTENT_X=8, SEARCH_TOP=8, SEARCH_HEIGHT=24, LIST_TOP=40,
    ContentWidth=function(w) return w-16 end,
}
package.loaded['resources/ui/bank_controls'] = {}
package.loaded['resources/windows/layout_editor_tabs'] = {}
local Parts = require('resources/windows/layout_editor_parts')
Parts.SizeToBank(3, 1000, 650)
e = {content=component(), window={root={hidden=false}}, overlayWindows={}, searchResults={},
    layout={sortedIndex={a=1,b=2,c=7,d=30}, unsortedIndex={u=1}, labels={{row=1,text='Label'}}}}
for _, module in ipairs({'view','drag','group','marquee','keys'}) do
    for key, value in pairs(require('resources/windows/layout_editor_' .. module)) do e[key]=value end
end
local function pane(name,x)
    local view={scrollY=0, content=component()}
    function view:ScrollBy(d) self.scrollY=math.max(0, math.min(500,self.scrollY+d)) end
    return {name=name,x=x,y=50,width=180,height=120,columns=3,gridLeft=4,
        labels=e.layout.labels,rowCount=12,slots={},view=view,outlines={},marks=component()}
end
e.panes={sorted=pane('sorted',200),unsorted=pane('unsorted',0)}
for key,index in pairs(e.layout.sortedIndex) do
    e.panes.sorted.slots[index]={kind='item',layoutKey=key}
end
e.panes.unsorted.slots[1]={kind='item',layoutKey='u'}
e:CreateDragSurfaces()
s=e.panes.sorted.surface
function press(x,y) return s.hooks.ONCLICK(s,200+x,50+y) end
function hold(x,y) return s.hooks.ONHOLD(s,200+x,50+y) end
function release(x,y) return s.hooks.ONRELEASE(s,200+x,50+y) end
function selected(...)
    local expected={}
    for _,key in ipairs({...}) do expected[key]=true; assert(e:IsSelected(key), 'missing '..key) end
    for _,key in ipairs({'a','b','c','d','u'}) do assert(e:IsSelected(key)==(expected[key]==true),'extra '..key) end
end
'''


class MarqueeTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime()
        self.lua.globals().root = ROOT.as_posix()
        self.lua.execute(HARNESS)

    def check(self, code):
        self.lua.execute(code)

    def test_box_adds_items_and_uses_existing_group_drag(self):
        self.check('''
            e:SelectOnly('d'); press(0,0); hold(85,110)
            selected('a','b','c','d'); assert(e.drag.kind=='box' and not e.drag.fill.hidden)
            local fill=e.drag.fill; release(85,110)
            assert(e.drag==nil and fill.destroyed); selected('a','b','c','d')
            shiftDown=false
            e.BeginGroupDrag=function(self,slot) self.grabbed=slot.layoutKey; return false end
            press(24,24); assert(e.grabbed=='a')
        ''')

    def test_reverse_box_and_center_hit_testing(self):
        self.check('''
            press(85,110); hold(23,23); selected('a','b','c')
            hold(25,23); selected('b'); release(25,23)
        ''')

    def test_shrinking_box_removes_only_new_hits(self):
        self.check('''
            e:SelectOnly('d'); press(0,0); hold(85,110); selected('a','b','c','d')
            hold(30,30); selected('a','d'); release(30,30)
        ''')

    def test_shift_click_toggle_and_empty_click_threshold(self):
        self.check('''
            press(24,24); assert(e.drag==nil); selected('a')
            press(24,24); selected()
            e:SelectOnly('d'); e.pasteCell=5
            press(0,0); hold(2,2); assert(not e.drag.active); release(2,2)
            selected('d'); assert(e.pasteCell==5)
        ''')

    def test_shift_release_restores_unsorted_selection_and_paste(self):
        self.check('''
            e:SelectOnly('u'); e.pasteCell=5
            press(0,0); hold(85,110); selected('a','b','c')
            shiftDown=false; e:TickBoxSelection()
            assert(e.drag==nil and e.pasteCell==5); selected('u')
        ''')

    def test_escape_restores_group(self):
        self.check('''
            e:SelectItems({'b','d'}); press(0,0); hold(85,110)
            e:KeyPressed({gameKey=GameKey.ESCAPE}); selected('b','d'); assert(e.drag==nil)
        ''')

    def test_label_press_starts_box_and_scroll_preserves_anchor(self):
        self.check('''
            press(0,0); hold(30,25); selected('a')
            s.hooks.ONSCROLLWHEEL(s,1); selected('a')
            s.hooks.ONSCROLLWHEEL(s,1); selected('a','c')
            release(30,25); selected('a','c')
            e.panes.sorted.view.scrollY=0
            press(24,55); assert(e.drag.kind=='box'); hold(30,110)
            release(30,110); selected('a','c')
        ''')

    def test_edge_scroll_and_hold_timeout(self):
        self.check('''
            press(0,0); hold(85,119)
            for i=1,9 do e:TickBoxSelection() end
            assert(e.drag and e.panes.sorted.view.scrollY==45)
            local border=e.drag.border; e:TickBoxSelection()
            assert(e.drag==nil and border.destroyed); selected('a','b','c')
        ''')

    def test_real_holds_renew_capture_and_new_press_has_fresh_anchor(self):
        self.check('''
            press(0,0); hold(85,110)
            for i=1,15 do hold(85,110); e:TickBoxSelection(); assert(e.drag) end
            press(100,0); assert(e.drag.kind=='box' and e.drag.anchorX==100)
            release(100,0)
            assert(e.drag==nil and e.surfaceClips[s].x==200 and s.x==-200)
        ''')

    def test_final_release_point_is_applied_and_outside_pointer_clamps(self):
        self.check('''
            press(0,0); release(85,110); selected('a','b','c')
            press(0,0); hold(1000,1000); release(1000,1000)
            selected('a','b','c')
        ''')

    def test_cancel_cleans_up_without_changing_layout(self):
        self.check('''
            local slots=e.panes.sorted.slots
            press(0,0); hold(85,110); local fill=e.drag.fill
            e:CancelDrag(); selected(); assert(fill.destroyed and slots==e.panes.sorted.slots)
            assert(slots[1].layoutKey=='a' and slots[7].layoutKey=='c')
        ''')

    def test_drag_complete_keeps_selection_and_overlay_cancels(self):
        self.check('''
            press(0,0); hold(85,110); s.hooks.ONDRAGCOMPLETE(s)
            selected('a','b','c'); assert(e.drag==nil)
            e:SelectOnly('d'); press(0,0); hold(85,110)
            e.overlayWindows={{root={hidden=false}}}; e:TickBoxSelection()
            selected('d'); assert(e.drag==nil)
        ''')

    def test_window_focus_change_cancels(self):
        self.check('''
            local function event()
                return {Subscribe=function(_, fn) return fn end}
            end
            Event={KeyDown=event(),MiniMenuOpened=event(),WindowFocusChanged=event()}
            Event.WindowFocusChanged.Subscribe=function(_,fn) lostFocus=fn end
            e.itemSearch={root=s}
            e:StartShortcuts(); e:SelectOnly('d'); press(0,0); hold(85,110)
            lostFocus(); selected('d'); assert(e.drag==nil and not e.keysOnGrid)
        ''')


if __name__ == '__main__':
    unittest.main()
