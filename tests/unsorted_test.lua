-- Filtered Unsorted grid cells retain their saved identities and editor actions.
local suite = { setup = function()
    require("tests/editor_fixture")()
    nameCalls=0
    package.loaded['resources/core/object_config']={DisplayName=function(id)
        nameCalls=nameCalls+1
        return ({[10]='Shark',[20]='Super restore<img=-1>'})[id]
    end}
    for _,module in ipairs({'unsorted','search','rows','names'}) do
        for k,v in pairs(require('resources/windows/layout_editor_'..module)) do e[k]=v end
    end
    local function component()
        local v={}
        function v:SetPos(x,y) self.x,self.y=x,y end
        function v:SetSize(w,h) self.width,self.height=w,h end
        function v:SetAssociatedObject(id) self.objectID=id end
        function v:MoveToFront() end
        function v:Destroy() end
        return v
    end
    ui.Sprite={new=component}
    ui.AlignMode={TOPLEFT=1}
    ui.ObjectQuantityDisplayMode.NEVER=0
    prettyui={TextField={new=function(parent,options)
        fieldOptions=options; return {root=e.panes.sorted.surface}
    end}, Text={new=function(parent,options) return options end},
    SimpleView={new=function(parent,options)
        local view={content=component(),scrollY=0,contentWidth=options.width-18,options=options}
        function view:SetContentHeight(h) self.contentHeight=h end
        function view:SetScrollPosition(y) self.scrollY=math.max(0,y) end
        function view:ScrollBy(d) self:SetScrollPosition(self.scrollY+d) end
        return view
    end}}
    e.HideItemName=function() end
    e.StyleItem=function() end
    e.CreateItemList=function(self,panel,width)
        local list={rows={},scrollY=0}
        function list:SetEntries(entries)
            self.entries,self.rows=entries,{}
            for _,entry in ipairs(entries) do
                self.rows[#self.rows+1]={root=component(),label=component()}
            end
        end
        function list:SetScrollPosition(y) self.scrollY=math.max(0,y) end
        function list:UnselectAll() self.selected=nil end
        function list:SetSelected(index,selected,notify) self.selected=index end
        return list
    end
    e:CreateUnsorted()
    left=e.panes.unsorted
    local a={kind='item',objectID=10,layoutKey='shark1'}
    local b={kind='item',objectID=20,layoutKey='restore'}
    local c={kind='item',objectID=10,layoutKey='shark2'}
    local d={kind='item',objectID=999,layoutKey='unknown'}
    e.layout.unsorted={a,b,c,d}
    e.layout.unsortedIndex={shark1=1,restore=2,shark2=3,unknown=4}
    e:RefreshUnsorted()
end, tests = {} }

suite.tests.filter_is_case_insensitive_and_preserves_duplicates = function()
    e:FilterUnsorted(' SHARK ')
    assert(#left.slots==2 and left.slots[1].layoutKey=='shark1' and left.slots[2].layoutKey=='shark2')
    assert(#e.layout.unsorted==4 and e.layout.unsorted[2].layoutKey=='restore')
    e:FilterUnsorted('restore')
    assert(#left.slots==1 and left.slots[1].layoutKey=='restore')
    assert(e.unsortedNames[20]=='Super restore')
end

suite.tests.filter_does_not_call_runeql_and_names_are_cached = function()
    local calls=nameCalls
    runeql={Catalog={Find=function() error('Local filter must not query catalog') end}}
    e:FilterUnsorted('s'); e:FilterUnsorted('sh'); e:FilterUnsorted('shark')
    assert(nameCalls==calls)
    e:FilterUnsorted('Item 999'); assert(left.slots[1].layoutKey=='unknown')
end

suite.tests.filtered_grid_hits_and_context_menu_use_correct_key = function()
    e:FilterUnsorted('shark')
    local x=e:GridCellX(left,1)+8
    assert(e:SlotIndexAt(left,x,8)==2)
    e.pointerSurface=e.panes.sorted.surface
    e.pointerX,e.pointerY=left.x+x,left.y+8
    e.selectedTag='test'; e.store={data={}}; e.drag=nil
    local target=e:RowMenuTarget()
    assert(target.pane=='unsorted' and target.layoutKey=='shark2')
    local item=e:GridItemAt(left.x+x,left.y+8)
    assert(item.objectID==10 and item.name=='Shark')
end

suite.tests.drag_uses_filtered_slot_key = function()
    e:FilterUnsorted('restore'); shiftDown=false
    e.StartItemDrag=function(self,drag) self.started=drag; return false end
    e:BeginCenterDrag(left,1)
    assert(e.started.layoutKey=='restore' and e.started.sourceKind=='unsorted')
end

suite.tests.selection_is_tied_to_visible_slot_identity = function()
    e:SelectOnly('shark2'); e:FilterUnsorted('shark')
    assert(not left.outlines[1].hidden and left.outlines[1].x==e:GridCellX(left,1))
    e:FilterUnsorted('restore'); assert(left.outlines[1].hidden)
    e:FilterUnsorted('')
    assert(not left.outlines[1].hidden and left.outlines[1].x==e:GridCellX(left,2))
end

suite.tests.scroll_uses_grid_rows_and_filter_resets_scroll = function()
    for i=1,12 do
        e.layout.unsorted[i]={kind='item',objectID=10,layoutKey='item'..i}
    end
    e:RefreshUnsorted()
    e:ScrollWheel(1,'unsorted'); assert(left.view.scrollY==44)
    local index=e:SlotIndexAt(left,left.gridLeft+8,8)
    assert(left.slots[index].layoutKey=='item'..(left.columns+1))
    e:FilterUnsorted('shark'); assert(left.view.scrollY==0)
    assert(e:SlotIndexAt(left,left.gridLeft+8,left.rowCount*44+8)==nil)
end

suite.tests.empty_filter_does_not_change_saved_items = function()
    e:FilterUnsorted('nothing'); assert(#left.slots==0 and not e.unsortedHint.hidden)
    assert(e.unsortedHint.text=='' and e.unsortedHint.content=='No unsorted items match that search.')
    e:FilterUnsorted(''); assert(#left.slots==4 and e.unsortedHint.hidden)
    e.layout.unsorted={}; e:RefreshUnsorted()
    assert(e.unsortedHint.content=='No unsorted items.')
end

suite.tests.typing_releases_grid_keys = function()
    e.keysOnGrid=true
    local field={SetText=function(self,text,notify) assert(not notify) end}
    fieldOptions.onChange(field,nil,'Shark<img=-1>')
    assert(not e.keysOnGrid and e.unsortedQuery=='Shark' and #left.slots==2)
end

suite.tests.cells_fill_usable_width_with_equal_edge_padding_and_even_gaps = function()
    for _,width in ipairs({206,224,225}) do
        left.view.contentWidth=width; e:RefreshUnsorted()
        assert(left.gridLeft==4)
        assert(e:GridCellX(left,left.columns-1)+40==width-4)
        local smallest,largest=math.huge,0
        for column=1,left.columns-1 do
            local gap=e:GridCellX(left,column)-e:GridCellX(left,column-1)-40
            smallest,largest=math.min(smallest,gap),math.max(largest,gap)
            assert(e:SlotIndexAt(left,e:GridCellX(left,column-1)+41,8)==nil)
        end
        assert(largest-smallest<=1)
    end
    assert(e:GridCellX(e.panes.sorted,1)-e:GridCellX(e.panes.sorted,0)==44)
end

suite.tests.full_rightmost_cell_remains_clickable_and_tooltip_matches = function()
    left.view.contentWidth=left.width; e:RefreshUnsorted()
    left.surface=e:CreateDragSurface('unsorted')
    assert(e.surfaceClips[left.surface].width==left.view.contentWidth)
    e.panes.sorted.x=500
    local lastX=e:GridCellX(left,3)
    e.pointerSurface=left.surface
    e.pointerX,e.pointerY=left.x+lastX+39,left.y+8
    e.selectedTag='test'; e.store={data={}}
    local target=e:RowMenuTarget()
    assert(target.layoutKey=='unknown')
    local item=e:GridItemAt(e.pointerX,e.pointerY)
    assert(item.objectID==999 and item.x==left.x+lastX)
end

suite.tests.grid_stays_inside_shared_border_at_larger_bank_sizes = function()
    local Parts=require('resources/windows/layout_editor_parts')
    for _,size in ipairs({{10,998,650},{14,1174,850}}) do
        Parts.SizeToBank(table.unpack(size))
        local s=Parts.size
        assert(math.abs(s.UNSORTED_VIEW_WIDTH-s.SEARCH_VIEW_WIDTH)<=1)
        e:CreateUnsorted(); e:RefreshUnsorted()
        local pane=e.panes.unsorted
        assert(pane.x==s.UNSORTED_X+s.SEARCH_INSET+1)
        assert(pane.y==s.PANEL_TOP+s.SEARCH_LIST_TOP+1)
        assert(pane.width==s.UNSORTED_VIEW_WIDTH-2 and pane.height==s.SEARCH_LIST_HEIGHT-2)
        local right=e:GridCellX(pane,pane.columns-1)+s.GRID_SLOT_SIZE
        assert(right<=pane.view.contentWidth and pane.gridLeft>=0)
    end
end

return suite
