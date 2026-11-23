-- Editor item names follow the bank's centered below-item tooltip placement.
local suite = { setup = function()
    require("tests/editor_fixture")()
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
end, tests = {} }

suite.tests.layout_and_unsorted_items_center_name_below_cell = function()
    for _,name in ipairs({'sorted','unsorted'}) do
        local p=e.panes[name]
        hover(p.x+p.gridLeft+8,p.y+12)
        assert(e.nameTooltip.shown)
        assert(e.nameTooltipOptions.x==math.floor(p.x+p.gridLeft+(40-120)/2))
        assert(e.nameTooltipOptions.y==p.y+4+40+6)
        assert(e.nameTooltip.text==(name=='unsorted' and 'Shark' or 'Item'))
    end
end

suite.tests.search_grid_tooltip_centers_below_cell = function()
    local searchPane = {
        name = 'search', x = 0, y = 50, width = 180, height = 120, columns = 3, gridLeft = 4,
        labels = {}, rowCount = 1, view = { scrollY = 0 },
        slots = { { kind = 'item', objectID = 10, displayName = 'Shark' } },
    }
    e.panes.unsorted.hidden = true
    e.panes.search = searchPane
    e.activeLeftTab = 'search'
    hover(searchPane.x + searchPane.gridLeft + 8, searchPane.y + 12)
    assert(e.nameTooltip.shown and e.nameTooltip.text == 'Shark')
    assert(e.nameAnchor.width == 40)
    assert(e.nameTooltipOptions.x == math.floor(searchPane.x + searchPane.gridLeft + (40 - 120) / 2))
    assert(e.nameTooltipOptions.y == searchPane.y + 4 + 40 + 6)
end

suite.tests.above_fallback_matches_bank_near_bottom = function()
    e:PlaceItemName({x=300,y=600,size=40})
    assert(e.nameTooltipOptions.x==260)
    assert(e.nameTooltipOptions.y==600-28-6)
end

suite.tests.gaps_and_drag_hide_tooltip = function()
    hover(212,62); assert(e.nameTooltip.shown)
    hover(244,62); assert(not e.nameTooltip.shown)
    hover(212,62); e.drag={}; e:UpdateItemName()
    assert(not e.nameTooltip.shown)
end

return suite
