-- Shared native UI and editor gesture stubs.
return function()
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
end
