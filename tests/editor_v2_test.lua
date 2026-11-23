-- Platform fixes: virtualized grid pooling, Classic UI bounds, Bank Core keybind holds, and newline-free row removal confirmation.
local suite = { tests = {} }

local function component(parent)
    local value = { parent = parent, hooks = {}, x = 0, y = 0, width = 0, height = 0, hidden = false }
    function value:SetPos(x, y) self.x, self.y = x, y end
    function value:SetSize(w, h) self.width, self.height = w, h end
    function value:SetAssociatedObject(objectID) self.objectID = objectID end
    function value:MoveToFront() end
    function value:Destroy() self.destroyed = true end
    function value:Subscribe(hook, name, fn) self.hooks[hook] = fn or name end
    return value
end

function suite.setup()
    require("tests/editor_fixture")()
    id.Font = { MUSEO_SANS_11PT_REGULAR = 1 }
    ui.AlignMode = { CENTRE = 1, TOPLEFT = 2 }
    ui.ObjectQuantityDisplayMode.NEVER = 0
    ui.ObjectQuantityDisplayMode.MULTIPLE = 2
    ui.Sprite = { new = component }
    prettyui = {
        Text = { new = function(_, options)
            local t = component()
            t.content = options.text or ""
            t.rgba = options.colour
            return t
        end },
        SimpleView = { new = function(_, options)
            local view = { content = component(), scrollY = 0, contentWidth = options.width - 18, options = options }
            function view:SetContentHeight(h) self.contentHeight = h; if self.onLayout then self:onLayout() end end
            function view:SetScrollPosition(y) self.scrollY = math.max(0, y); if self.onLayout then self:onLayout() end end
            function view:ScrollBy(d) self:SetScrollPosition(self.scrollY + d) end
            return view
        end },
    }
    for _, module in ipairs({ "rows" }) do
        for key, value in pairs(require("resources/windows/layout_editor_" .. module)) do e[key] = value end
    end
    e.styles = {}
end

suite.tests.layout_editor_suspends_and_releases_bank_core_keybinds = function()
    local suspendedLabel, released = nil, 0
    local hold = { Release = function() released = released + 1; return true end }
    local ext = {
        GetBankBounds = function() return { x = 0, y = 0, width = 998, height = 650, columns = 10 } end,
        SuspendKeybinds = function(_, label) suspendedLabel = label; return hold end,
    }
    id.Component = { TOPLEVEL_V2__BANK_LAYER = 1 }
    ui.Interfaces = { GetComponent = function() return {} end }
    package.loaded["resources/windows/windows"] = nil
    for _, dep in ipairs({
        "windows/confirm_window", "core/debug_log", "windows/import_share",
        "windows/sprite_picker", "tags/tag_rules",
        "windows/tag_settings_editor", "ui/text_prompt",
    }) do
        package.loaded["resources/" .. dep] = { Write = function() end }
    end
    local editorOnClose
    package.loaded["resources/windows/layout_editor_window"] = {
        new = function(_, options)
            editorOnClose = options.onClose
            return {
                Show = function() end,
                SetOverlays = function() end,
                Destroy = function(self) if editorOnClose then editorOnClose(self) end end,
            }
        end,
    }
    local Windows = require("resources/windows/windows")
    local windows = Windows.new({
        ext = ext,
        settings = {},
        store = {},
        BankItems = function() return {} end,
    })

    windows:OpenLayoutEditor("tag-1")
    assert(suspendedLabel == "layout editor" and windows.editorKeybindHold == hold and released == 0)

    -- Closing the editor releases the Bank Core keybind hold
    windows:Close("layoutEditor")
    assert(windows.editorKeybindHold == nil and released == 1)

    -- Older Bank Core handles without SuspendKeybinds stay safe
    ext.SuspendKeybinds = nil
    windows:OpenLayoutEditor("tag-1")
    assert(windows.layoutEditor ~= nil and windows.editorKeybindHold == nil)
    windows:Close("layoutEditor")
end

suite.tests.pane_grid_virtualizes_large_grids_and_uses_prettyui_new_component = function()
    local newComponentCalls, rawLayerCalls = 0, 0
    local origLayerNew = ui.Layer.new
    ui.Layer.new = function(parent)
        rawLayerCalls = rawLayerCalls + 1
        return origLayerNew(parent)
    end
    prettyui.NewComponent = function(nativeType, parent)
        newComponentCalls = newComponentCalls + 1
        return nativeType.new(parent)
    end

    local pane = e:CreatePane("sorted", e.content, 0, 0, 466, 10)
    assert(pane.view.options.categoryID == "auto")
    pane.slots = {}
    for index = 1, 2000 do
        pane.slots[index] = { kind = "item", objectID = 10000 + index }
    end

    local beforeDraw = newComponentCalls
    e:DrawPane(pane, 200, {})
    local allocated = newComponentCalls - beforeDraw
    assert(allocated > 0 and allocated < 400,
        "expected windowed pool under 400 components for 2000 items, got " .. tostring(allocated))
    assert(pane.sprites[1] ~= nil and pane.sprites[1].objectID == 10001)
    assert(pane.sprites[1999] == nil, "offscreen rows must not be rendered at scrollY=0")

    local poolBefore = #pane.itemPool
    pane.view:SetScrollPosition(pane.contentHeight - pane.height)
    assert(pane.sprites[2000] ~= nil and pane.sprites[2000].objectID == 12000)
    assert(pane.sprites[1] == nil)
    assert(#pane.itemPool <= poolBefore + pane.columns * 2,
        "scrolling should reuse pooled sprites instead of growing unboundedly")

    -- Parts.contentLayer keeps category-0 raw Layer while Parts.layer routes through NewComponent
    local Parts = require("resources/windows/layout_editor_parts")
    local beforeRaw, beforeManaged = rawLayerCalls, newComponentCalls
    Parts.contentLayer(e.content, 0, 0, 100, 100)
    assert(rawLayerCalls == beforeRaw + 1 and newComponentCalls == beforeManaged)
    Parts.layer(e.content, 0, 0, 100, 100)
    assert(newComponentCalls == beforeManaged + 1)
    ui.Layer.new = origLayerNew
end

suite.tests.classic_ui_aligns_layout_editor_to_detached_sidebar = function()
    local Parts = require("resources/windows/layout_editor_parts")
    local Windows = require("resources/windows/windows")
    local border = Parts.size.WINDOW_BORDER

    -- Modern UI: sidebarRoot sits inside the bank frame, so bounds stay unchanged
    local modernRoot = { x = 100, y = 50, width = 998, height = 650 }
    local modernRail = { x = 40, y = 40, parent = modernRoot }
    local modernCol = { x = 1, y = 1, parent = modernRail }
    prettyui.IsClassicUI = function() return false end
    local modernWin = Windows.new({
        ext = { GetBankBounds = function() return { x = 100, y = 50, width = 998, height = 650, columns = 10 } end },
        tab = { ctx = { parent = modernCol } },
    })
    local mb = modernWin:BankBounds()
    assert(mb.x == 100 and mb.width == 998)

    -- Classic UI with detached left sidebar: outer left edge aligns to sidebarRoot.x (100)
    local classicRoot = { x = 100, y = 50, width = 300, height = 650 }
    local classicRail = { x = 56, y = 40, parent = classicRoot }
    local classicCol = { x = 1, y = 1, parent = classicRail }
    prettyui.IsClassicUI = function() return true end
    local classicWin = Windows.new({
        ext = { GetBankBounds = function() return { x = 400, y = 50, width = 714, height = 650, columns = 10 } end },
        tab = { ctx = { parent = classicCol } },
    })
    local cb = classicWin:BankBounds()
    assert(cb.x - border == 100, "editor outer left should align with sidebar left edge 100, got " .. tostring(cb.x - border))
    assert(cb.width == 998, "combined width minus border should be 998, got " .. tostring(cb.width))
    Parts.SizeToBank(cb.columns, cb.width, cb.height)
    assert((cb.x - border) + Parts.size.WIDTH == 400 + 714,
        "editor outer right edge should align with bank right edge")

    -- Classic UI fallback when sidebar tab ctx is temporarily nil
    local fallbackWin = Windows.new({
        ext = { GetBankBounds = function() return { x = 400, y = 50, width = 714, height = 650, columns = 10 } end },
        tab = { ctx = nil },
    })
    local fb = fallbackWin:BankBounds()
    assert(fb.x - border == 100 and fb.width == 998)
end

suite.tests.remove_row_confirm_avoids_newlines_and_uses_message_lines = function()
    local prompted = nil
    e.selectedTag = "tag-1"
    e.store = {
        data = {},
        GetTagName = function(_, id) return id == "tag-1" and "clue rewards" or id end,
        LayoutLineContents = function() return { empty = false, items = 10, reserved = 0 } end,
    }
    e.onConfirmRemoveRow = function(options) prompted = options end
    assert(e:RemoveRow(0))
    assert(prompted ~= nil)
    assert(not string.find(prompted.message, "\n", 1, true), "message must not contain newline characters")
    assert(prompted.messageLines ~= nil and #prompted.messageLines == 2)
    assert(string.find(prompted.messageLines[1], "clue rewards", 1, true))
    assert(string.find(prompted.messageLines[2], "bank keeps every item", 1, true))
end

return suite
