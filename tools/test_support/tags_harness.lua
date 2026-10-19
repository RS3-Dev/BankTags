-- Load the real Bank Core beside the built Bank Tags in a stand-in host
-- Bank Core is read, never changed, from BANKCORE_ROOT or ../bank-utilities
-- FAKE HOST: stand-in loader, components, and menus, not the game client
-- Kept outside tests/ so tools/check.lua does not count it as a test program

local Harness = {}

-- Report whether a file exists
local function exists(path)
    local file = io.open(path, "rb")
    if file == nil then return false end
    file:close()
    return true
end

-- Read a file's text, or nil when it is missing
local function readText(path)
    local file = io.open(path, "rb")
    if file == nil then return nil end
    local text = file:read("a")
    file:close()
    return text
end

-- Find Bank Core's checkout, refusing one without the needed API
function Harness.CoreRoot()
    local root = os.getenv("BANKCORE_ROOT") or "../bank-utilities"
    root = string.gsub(root, "\\", "/")
    if not exists(root .. "/plugins/bankcore/main.lua") then
        error("Bank Core was not found at " .. root .. "; set BANKCORE_ROOT to a bank-utilities checkout", 0)
    end
    local contract = readText(root .. "/HOST_CONTRACT.md") or ""
    for _, needed in ipairs({ "PluginDependencyUpdate(event)", "GetMenuItem", "SetItemHighlight", "`columns`",
        "the root is a plain table", "SetSettings" }) do
        if not string.find(contract, needed, 1, true) then
            error("Bank Core at " .. root .. " lacks " .. needed .. " in its contract; set BANKCORE_ROOT "
                .. "to a checkout with the extension API Bank Tags uses", 0)
        end
    end
    -- Bank Tags' modules come first; Bank Core's tools fill gaps
    if not string.find(package.path, root .. "/?.lua", 1, true) then
        package.path = package.path .. ";" .. root .. "/?.lua"
    end
    return root
end

-- Give stand-in list rows real positions so tests can point at them
local function placeListRows()
    local newList = prettyui.List.new
    prettyui.List.new = function(parent, options)
        local list = newList(parent, options)
        list.viewport:SetSize(options.width, options.height)
        local setEntries = list.SetEntries
        function list:SetEntries(entries)
            setEntries(self, entries)
            for index, row in ipairs(self.rows) do
                row.root:SetPos(0, (index - 1) * self.entryHeight)
                row.root:SetSize(self.root.width, self.entryHeight)
                row.label.content = row.entry.label
            end
        end
        function list:_OnScrollWheel() return true end
        return list
    end
end

-- Install the stand-in host, build Bank Tags, and create a loader
function Harness.new(name, options)
    options = options or {}
    local coreRoot = Harness.CoreRoot()
    local bankHost = require("tools/test_support/fake_bank_host").install()
    bankHost:InstallSidebarWidgets()
    bankHost:InstallWindowWidgets()
    bankHost:InstallPanelWidgets()
    placeListRows()
    prettyui.ItemGrid = { new = function(parent)
        local grid = { root = ui.Layer.new(parent), slots = {} }
        function grid:SetObjects(objects) self.objects = objects end
        function grid:GetSlot() return nil end
        function grid:Destroy() self.destroyed = true end
        return grid
    end }
    -- PrettyUI's item slot takes a tooltip; the stand-in records it
    local newSlot = prettyui.ItemSlot.new
    prettyui.ItemSlot.new = function(...)
        local slot = newSlot(...)
        function slot:SetTooltip(text) self.tooltipText = text end
        return slot
    end
    ui.ObjectQuantityDisplayMode.MULTIPLE = 1
    local contentSubscriptions = {}
    for _, event in ipairs({ "GameStateChanged", "MiniMenuEntrySelected",
        "InventoryAdded", "InventoryRemoved", "InventoryUpdated" }) do
        Event[event] = { Subscribe = function() end, Unsubscribe = function() end }
    end
    -- MiniMenuReady handlers by subscription ID; tests choose the order
    local menuSubscriptions = {}
    Event.MiniMenuReady = {
        Subscribe = function(key, action) menuSubscriptions[key] = action end,
        Unsubscribe = function(key) menuSubscriptions[key] = nil end,
    }
    Event.ContentLayerReady = {
        Subscribe = function(key, action) contentSubscriptions[key] = action end,
        Unsubscribe = function(key) contentSubscriptions[key] = nil end,
    }
    local Build = require("tools/build")
    local out = "dist/test/" .. name
    local built = Build.Run({ out = out })
    local Loader = require("tools/test_support/fake_plugin_host")
    local globals = { ui = ui, id = id, Event = Event, config = config, Vector4 = Vector4,
        Mouse = Mouse, MiniMenuActionType = MiniMenuActionType,
        Player = { IsAvailable = function() return true end }, GameState = { GAME = 30 },
        log = function() end }
    local databases = {}
    local host = Loader.new(globals, { exports = { prettyui = prettyui }, databases = databases,
        separateGlobals = options.separateGlobals, cloneExports = options.cloneExports,
        recordEvents = true })
    return setmetatable({
        bankHost = bankHost,
        host = host,
        databases = databases,
        contentSubscriptions = contentSubscriptions,
        menuSubscriptions = menuSubscriptions,
        -- Where the host adds a plugin's entry, and who hears a menu first
        placement = "above_cancel",
        menuOrder = "core_first",
        coreRoot = coreRoot,
        out = out,
        coreFolder = coreRoot .. "/plugins/bankcore",
        tagsFolder = built.folder,
        built = built,
    }, { __index = Harness })
end

-- Load Bank Core from its source checkout, as a plugin with its own module cache
function Harness:LoadCore()
    self.core = self.host:Load("bankcore", self.coreFolder, nil, self.coreRoot)
    return self.core
end

-- Load the built Bank Tags folder
function Harness:LoadTags()
    self.tags = self.host:Load("banktags", self.tagsFolder)
    return self.tags
end

-- Read one of Bank Tags' loaded modules from its own module cache
function Harness:TagsModule(moduleName)
    return self.tags.env.package.loaded[moduleName]
end

-- Return the running Bank Tags app
function Harness:App()
    return rawget(self.tags.env._G, "__banktags_session")
end

-- Return the running Bank Core session
function Harness:Session()
    return rawget(self.core.env._G, "__bankcore_session")
end

-- Open the bank in View All for the running Core session
function Harness:OpenBank(width, height)
    if self.bankHost.window == nil then
        local window = self.bankHost:MountBankWindow(width or 714, height or 650)
        self.bankHost.viewport.parent = window.all
    end
    local session = self:Session()
    assert(session.layout:IsReady() and session.layout:Apply())
    session.layout.nativeViewAll = true
    return session, session.layout
end

-- Return the mounted Tags tab parent, if Core mounted it
function Harness:TabParent()
    local layout = self:Session().layout
    return layout.tabMount ~= nil and layout.tabMount.values ~= nil and layout.tabMount.values.parent or nil
end

-- Run logic ticks
function Harness:Tick(count)
    for _ = 1, count or 1 do self.bankHost:Tick() end
end

-- Show the plugin's content panel, as selecting its ribbon icon does
function Harness:OpenContentPanel()
    local panel = ui.Layer.new(nil)
    panel:SetSize(300, 400)
    self.contentSubscriptions.banktags_content({ component = panel })
    return panel
end

-- Find a component by text or content, depth first
function Harness.Find(parent, text)
    for _, child in ipairs(parent.children or {}) do
        if not child.destroyed and not child.hidden then
            local content = child.content or (child.text and child.text.content)
            if content == text then return child end
            local found = Harness.Find(child, text)
            if found ~= nil then return found end
        end
    end
    return nil
end

-- Where hosts put a plugin's menu entry
Harness.PLACEMENTS = {
    documented = function(menu) return menu.entryCount + 1 end,
    above_cancel = function(menu)
        for index, entry in ipairs(menu.entries) do
            if entry.actionType == MiniMenuActionType.CANCEL then return index + 1 end
        end
        return 1
    end,
    below_default = function(menu) return math.max(1, menu.entryCount) end,
}

-- Build a menu and let each plugin answer in the chosen order
function Harness:HostMenu(natives, silent)
    local menu = { entries = { { verbText = "Cancel", actionType = MiniMenuActionType.CANCEL } } }
    for _, native in ipairs(natives) do menu.entries[#menu.entries + 1] = native end
    setmetatable(menu, { __index = function(values, key)
        if key == "entryCount" then return #values.entries end
    end })
    local place = Harness.PLACEMENTS[self.placement]
    function menu:Add(label, action, ...)
        local entry = { verbText = not silent and label or "", overrideText = not silent and label or nil, action = action,
            arguments = { ... } }
        table.insert(self.entries, place(self), entry)
    end
    function menu:Swap(a, b) self.entries[a], self.entries[b] = self.entries[b], self.entries[a] end
    local keys = {}
    for key in pairs(self.menuSubscriptions) do keys[#keys + 1] = key end
    table.sort(keys)
    if self.menuOrder == "tags_first" then table.sort(keys, function(a, b) return a > b end) end
    for _, key in ipairs(keys) do self.menuSubscriptions[key]({ miniMenu = menu }) end
    return menu
end

-- Open an item's menu with Withdraw-1 as the native default
function Harness:MenuFor(component, silent)
    local natives = {}
    for index, verb in ipairs({ "Examine", "Withdraw-1" }) do
        natives[index] = { verbText = verb, actionType = index == 1 and 1007 or 57, componentData = {
            objConfig = { id = component.associatedObjectID, name = "Item" }, component = component } }
    end
    return self:HostMenu(natives, silent)
end

-- Open a menu over mounted content with no item under the pointer
function Harness:ContentMenu(silent)
    return self:HostMenu({}, silent)
end

-- Left-click a menu, returning the highest-priority label
function Harness.LeftClick(menu)
    local entry = menu.entries[menu.entryCount]
    if entry.action ~= nil then entry.action(table.unpack(entry.arguments or {})) end
    return entry.verbText
end

-- List a menu's entry labels in order
function Harness.Labels(menu)
    local labels = {}
    for _, entry in ipairs(menu.entries) do labels[#labels + 1] = entry.verbText end
    return labels
end

-- Choose an entry by its label, failing when it is missing
function Harness.Choose(menu, label)
    for _, entry in ipairs(menu.entries) do
        if entry.verbText == label then return entry.action(table.unpack(entry.arguments or {})) end
    end
    error(label .. " is not in the menu: " .. table.concat(Harness.Labels(menu), " | "))
end

-- Report whether a menu holds an entry
function Harness.Has(menu, label)
    for _, entry in ipairs(menu.entries) do
        if entry.verbText == label then return true end
    end
    return false
end

-- Point the mouse at a position relative to a component
function Harness:PointAt(component, x, y)
    local Geometry = require("banktags/ui/geometry")
    local left, top = Geometry.absolutePosition(component)
    self.bankHost.mouse = { x = left + x, y = top + y }
end

return Harness
