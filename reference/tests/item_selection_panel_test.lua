package.path = "./?.lua;./?/init.lua;" .. package.path

-- Return a host component stand-in that records positions and accepts other calls
local created = {}
local function node()
    local value = setmetatable({ x = 0, y = 0, width = 0, height = 0 }, {
        __index = function() return function() end end,
    })
    function value:SetPos(x, y, xAnchor) self.x, self.y, self.xAnchor = x, y, xAnchor end
    function value:SetSize(width, height) self.width, self.height = width, height end
    function value:Destroy() self.destroyed = true end
    function value:Subscribe(hook, callback) self[hook] = callback end
    created[#created + 1] = value
    return value
end

local subscriptions = {}
Event = { Logic = {
    Subscribe = function(name, callback) subscriptions[name] = callback end,
    Unsubscribe = function(name) subscriptions[name] = nil end,
} }
id = { Font = { MUSEO_SANS_11PT_REGULAR = 1 } }
ui = {
    AlignMode = { CENTRE = 1 },
    ObjectQuantityDisplayMode = { NEVER = 0 },
    Hook = { ONBUTTONPRESSED = "press", ONMOUSEOVER = "over", ONMOUSELEAVE = "leave" },
    Layer = { new = node },
    Sprite = { new = node },
    Rectangle = { new = node },
    Text = { new = node },
    Button = { new = function()
        local button = node()
        button.text = {}
        return button
    end },
    Interfaces = { GetComponent = function() return nil end },
}
prettyui = { Tooltip = { bind = function() end, unbind = function() end } }

local NativeTagSelect = require("lib/features/tags/native_tag_select")

-- An owner with the shared state select mode reads from the bank layout
local all, content = node(), node()
content.height = 594
local owner = {
    active = true,
    expanded = true,
    components = { all = all, content = content },
    cleanupCategories = { IsGenerated = function() return false end },
    store = { GetTagSprite = function() return 15332 end },
    selectedTag = nil,
    IsPresetViewOpen = function() return false end,
    UpdateLayoutControls = function() end,
    RefreshTags = function() end,
    DisplayTagName = function(_, tag) return tag:gsub("^%l", string.upper) end,
}
NativeTagSelect.install(owner)

-- Starting selection covers the right column and names the tag
assert(owner:SetItemSelectionTag("overloads"))
local panel = owner.itemSelectionPanel
-- Measured from the right edge: 225px in lands on x = 773 in a default 998px window
assert(panel ~= nil and panel.root.x == -225 and panel.root.xAnchor == 1.0 and panel.root.y == 44)
assert(panel.root.width == 213 and panel.root.height == 594)
assert(panel.root.clickthrough == false, "the panel blocks the inventory beneath it")
local texts = {}
for _, value in ipairs(created) do
    if type(rawget(value, "content")) == "string" then texts[value.content] = true end
end
assert(texts["Select mode"] and texts["Overloads"])

-- Done ends selection and uncovers the right column
panel.done.root.press()
assert(owner.itemSelectionTag == nil and owner.itemSelectionPanel == nil)
assert(panel.root.destroyed)

-- Every other way out of select mode removes the panel too
assert(owner:SetItemSelectionTag("overloads"))
panel = owner.itemSelectionPanel
owner:StopItemSelection(false)
assert(owner.itemSelectionPanel == nil and panel.root.destroyed)

print("item_selection_panel_test: ok")
