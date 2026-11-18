-- Editor gesture checks with native UI event stubs.
local suite = { setup = function()
    require("tests/editor_fixture")()
end, tests = {} }

suite.tests.box_adds_items_and_uses_existing_group_drag = function()
    e:SelectOnly('d'); press(0,0); hold(85,110)
    selected('a','b','c','d'); assert(e.drag.kind=='box' and not e.drag.fill.hidden)
    local fill=e.drag.fill; release(85,110)
    assert(e.drag==nil and fill.destroyed); selected('a','b','c','d')
    shiftDown=false
    e.BeginGroupDrag=function(self,slot) self.grabbed=slot.layoutKey; return false end
    press(24,24); assert(e.grabbed=='a')
end

suite.tests.reverse_box_and_center_hit_testing = function()
    press(85,110); hold(23,23); selected('a','b','c')
    hold(25,23); selected('b'); release(25,23)
end

suite.tests.shrinking_box_removes_only_new_hits = function()
    e:SelectOnly('d'); press(0,0); hold(85,110); selected('a','b','c','d')
    hold(30,30); selected('a','d'); release(30,30)
end

suite.tests.shift_click_toggle_and_empty_click_threshold = function()
    press(24,24); assert(e.drag==nil); selected('a')
    press(24,24); selected()
    e:SelectOnly('d'); e.pasteCell=5
    press(0,0); hold(2,2); assert(not e.drag.active); release(2,2)
    selected('d'); assert(e.pasteCell==5)
end

suite.tests.shift_release_restores_unsorted_selection_and_paste = function()
    e:SelectOnly('u'); e.pasteCell=5
    press(0,0); hold(85,110); selected('a','b','c')
    shiftDown=false; e:TickBoxSelection()
    assert(e.drag==nil and e.pasteCell==5); selected('u')
end

suite.tests.escape_restores_group = function()
    e:SelectItems({'b','d'}); press(0,0); hold(85,110)
    e:KeyPressed({gameKey=GameKey.ESCAPE}); selected('b','d'); assert(e.drag==nil)
end

suite.tests.label_press_starts_box_and_scroll_preserves_anchor = function()
    press(0,0); hold(30,25); selected('a')
    s.hooks.ONSCROLLWHEEL(s,1); selected('a')
    s.hooks.ONSCROLLWHEEL(s,1); selected('a','c')
    release(30,25); selected('a','c')
    e.panes.sorted.view.scrollY=0
    press(24,55); assert(e.drag.kind=='box'); hold(30,110)
    release(30,110); selected('a','c')
end

suite.tests.edge_scroll_and_hold_timeout = function()
    press(0,0); hold(85,119)
    for i=1,9 do e:TickBoxSelection() end
    assert(e.drag and e.panes.sorted.view.scrollY==45)
    local border=e.drag.border; e:TickBoxSelection()
    assert(e.drag==nil and border.destroyed); selected('a','b','c')
end

suite.tests.real_holds_renew_capture_and_new_press_has_fresh_anchor = function()
    press(0,0); hold(85,110)
    for i=1,15 do hold(85,110); e:TickBoxSelection(); assert(e.drag) end
    press(100,0); assert(e.drag.kind=='box' and e.drag.anchorX==100)
    release(100,0)
    assert(e.drag==nil and e.surfaceClips[s].x==200 and s.x==-200)
end

suite.tests.final_release_point_is_applied_and_outside_pointer_clamps = function()
    press(0,0); release(85,110); selected('a','b','c')
    press(0,0); hold(1000,1000); release(1000,1000)
    selected('a','b','c')
end

suite.tests.cancel_cleans_up_without_changing_layout = function()
    local slots=e.panes.sorted.slots
    press(0,0); hold(85,110); local fill=e.drag.fill
    e:CancelDrag(); selected(); assert(fill.destroyed and slots==e.panes.sorted.slots)
    assert(slots[1].layoutKey=='a' and slots[7].layoutKey=='c')
end

suite.tests.drag_complete_keeps_selection_and_overlay_cancels = function()
    press(0,0); hold(85,110); s.hooks.ONDRAGCOMPLETE(s)
    selected('a','b','c'); assert(e.drag==nil)
    e:SelectOnly('d'); press(0,0); hold(85,110)
    e.overlayWindows={{root={hidden=false}}}; e:TickBoxSelection()
    selected('d'); assert(e.drag==nil)
end

suite.tests.window_focus_change_cancels = function()
    local function event()
        return {Subscribe=function(_, fn) return fn end}
    end
    Event={KeyDown=event(),MiniMenuOpened=event(),WindowFocusChanged=event()}
    Event.WindowFocusChanged.Subscribe=function(_,fn) lostFocus=fn end
    e.itemSearch={root=s}
    e:StartShortcuts(); e:SelectOnly('d'); press(0,0); hold(85,110)
    lostFocus(); selected('d'); assert(e.drag==nil and not e.keysOnGrid)
end

return suite
