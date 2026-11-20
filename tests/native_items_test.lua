-- Native selection outlines must cover bank, backpack, and equipped items.
local suite = { tests = {} }
function suite.setup()
    id = { Component = { BANK__BANK_INV = 1, TOPLEVEL_V2__BANK_WINDOW = 2,
        BANK__INVENTORY_SLOTS = 3, BANK__WORN_CONTENT_LAYER = 4 } }
    ui = { Hook = { ONDRAG = 1, ONDRAGCOMPLETE = 2 } }
    function component(objectID, children)
        local value = { associatedObjectID = objectID, associatedObjectQuantity = 1,
            outlineWidth = 0, shadowRGBA = 123, x = 0, y = 0, dynamicID = 0,
            children = children or {}, hooks = {} }
        function value:IterateDynamicComponents(callback)
            for _, child in ipairs(self.children) do callback(child) end
        end
        function value:IterateStaticComponents(callback)
            for _, child in ipairs(self.staticChildren or {}) do callback(child) end
        end
        function value:Subscribe(hook, _, callback) self.hooks[hook] = callback end
        function value:Unsubscribe(hook) self.hooks[hook] = nil end
        return value
    end
    bankItem, inventoryItem, wornItem = component(42), component(42), component(42)
    otherItem = component(99)
    local slot = component(-1, { wornItem })
    wornLayer = component(-1)
    wornLayer.staticChildren = { slot }
    inventoryLayer = component(-1, { inventoryItem, otherItem })
    layers = { [1] = component(-1, { bankItem }), [2] = {},
        [3] = inventoryLayer, [4] = wornLayer }
    ui.Interfaces = { GetComponent = function(_, key) return layers[key] end }
    selected = "gear"
    tagged = { { objectID = 42 } }
    native = require("resources/tags/native_items").new({
        select = { Tag = function() return selected end },
        store = { GetTaggedItems = function() return tagged end },
    })
end

suite.tests.same_outline_in_all_panels_and_restore = function()
    native:Refresh()
    for _, item in ipairs({ bankItem, inventoryItem, wornItem }) do
        assert(item.outlineWidth == 2 and item.shadowRGBA == 0xF2C66DFF)
    end
    assert(otherItem.outlineWidth == 0 and otherItem.shadowRGBA == 123)
    assert(inventoryItem.hooks[1] == nil and wornItem.hooks[1] == nil)
    selected = nil
    native:RefreshHighlights()
    for _, item in ipairs({ bankItem, inventoryItem, wornItem }) do
        assert(item.outlineWidth == 0 and item.shadowRGBA == 123)
    end
end

suite.tests.replaced_and_removed_items_restore_original_appearance = function()
    inventoryItem.outlineWidth = 4
    native:Refresh()
    assert(inventoryItem.outlineWidth == 4)
    local replacement = component(42)
    inventoryLayer.children = { replacement }
    layers[4] = nil
    native:Refresh()
    assert(inventoryItem.outlineWidth == 4 and inventoryItem.shadowRGBA == 123)
    assert(wornItem.outlineWidth == 0 and wornItem.shadowRGBA == 123)
    assert(replacement.shadowRGBA == 0xF2C66DFF)
    tagged = {}
    native:Refresh()
    assert(bankItem.outlineWidth == 0 and replacement.outlineWidth == 0)
end

suite.tests.bank_closure_and_missing_panel_names_are_safe = function()
    native:Refresh()
    layers[2] = nil
    native:Refresh()
    assert(#native.visuals == 0 and inventoryItem.outlineWidth == 0)
    layers[2] = {}
    id.Component.BANK__INVENTORY_SLOTS = nil
    id.Component.BANK__WORN_CONTENT_LAYER = nil
    native:Refresh()
    assert(bankItem.outlineWidth == 2 and #native.visuals == 1)
end
return suite
