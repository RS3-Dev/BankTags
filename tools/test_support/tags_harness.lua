-- Load the real Bank Core beside the built Bank Tags in a stand-in host
-- Bank Core is read, never changed, from BANKCORE_ROOT or ../bank-utils-core
-- FAKE HOST: stand-in loader, components, and menus, not the game client
-- Kept outside tests/ so tools/check.lua does not count it as a test program

local Harness = {}

-- How to open each menu a test built, heard by MiniMenuOpened handlers
local openers = setmetatable({}, { __mode = "k" })
-- The folder submenus each menu was given, in the order they were added
local submenus = setmetatable({}, { __mode = "k" })
-- PrettyUI's own MiniMenu handlers, by event name
local prettyMenuHandlers = {}

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
    local root = os.getenv("BANKCORE_ROOT") or "../bank-utils-core"
    root = string.gsub(root, "\\", "/")
    if not exists(root .. "/main.lua") then
        error("Bank Core was not found at " .. root .. "; set BANKCORE_ROOT to a bank-utils-core checkout", 0)
    end
    local spec = readText(root .. "/docs/API.md") or ""
    for _, needed in ipairs({ "bankcore.Register(spec)", "ext:GetBankBounds()", "`slot`" }) do
        if not string.find(spec, needed, 1, true) then
            error("Bank Core at " .. root .. " lacks " .. needed .. " in its API reference; set BANKCORE_ROOT "
                .. "to a checkout with the extension API Bank Tags uses", 0)
        end
    end
    -- Bank Tags' modules come first; Bank Core's tools fill gaps
    if not string.find(package.path, root .. "/?.lua", 1, true) then
        package.path = package.path .. ";" .. root .. "/?.lua"
    end
    return root
end

-- Find the read-only PrettyUI checkout from PRETTYUI_ROOT
function Harness.PrettyUIRoot()
    local root = os.getenv("PRETTYUI_ROOT")
    if root == nil then error("set PRETTYUI_ROOT to a PrettyUI checkout the tests load MiniMenu from", 0) end
    root = string.gsub(root, "\\", "/")
    if not exists(root .. "/src/minimenu.lua") then
        error("PrettyUI's src/minimenu.lua was not found under " .. root, 0)
    end
    return root
end

-- Load PrettyUI's real MiniMenu, recording each submenu a menu is given
-- Its handlers are kept apart so tests run them in the client's order
-- Drawing the submenu needs the client, so tests choose a child as its row click would
local function installMiniMenu()
    local root = Harness.PrettyUIRoot()
    local stubs = {
        ["src/core/mouse"] = {},
        ["src/core/sprites"] = {},
        ["src/core/math"] = assert(loadfile(root .. "/src/core/math.lua"))(),
    }
    local events = {}
    for _, name in ipairs({ "MiniMenuReady", "MiniMenuOpened", "MiniMenuClosed", "MiniMenuEntrySelected", "Logic" }) do
        events[name] = {
            Subscribe = function(_, action) prettyMenuHandlers[name] = action end,
            Unsubscribe = function() prettyMenuHandlers[name] = nil end,
        }
    end
    local env = setmetatable({ require = function(name) return assert(stubs[name], name) end, Event = events },
        { __index = _G })
    local MiniMenu = assert(loadfile(root .. "/src/minimenu.lua", "t", env))()
    MiniMenu.Start()
    prettyui.MiniMenu = setmetatable({
        AddSubmenu = function(menu, label, children, options)
            local entry = MiniMenu.AddSubmenu(menu, label, children, options)
            submenus[menu] = submenus[menu] or {}
            table.insert(submenus[menu], { entry = entry, children = children, options = options })
            return entry
        end,
    }, { __index = MiniMenu })
end

-- Run PrettyUI's real dialog stack, footer actions, and close handling.
-- Only the native window and leaf controls are stand-ins.
local function installDialogs()
    local root = Harness.PrettyUIRoot()
    local fancy = { getSize = function(label) return math.max(70, #label * 8 + 24) end }
    local windowFactory = { new = function(parent, options)
        local window = prettyui.Window.new(parent, options)
        window.content:SetSize(options.width - 16, options.height - 40)
        window.managed = {}
        local function keep(control)
            window.managed[#window.managed + 1] = control
            return control
        end
        function window:AddText(value, ...)
            assert(select("#", ...) == 0, "AddText accepts one string or options table")
            local opts = type(value) == "table" and value or { text = value }
            opts.width, opts.height = opts.width or self.content.width, opts.height or 24
            return keep(prettyui.Text.new(self.content, opts))
        end
        function window:AddTextField(opts)
            return keep(prettyui.TextField.new(self.content, opts))
        end
        function window:AddFancyButton(label, action, opts)
            opts.width, opts.height = fancy.getSize(label), 28
            local button = prettyui.SimpleButton.new(self.content, label, action, opts)
            button.root:SetPos(opts.x, opts.y, opts.xAnchor, opts.yAnchor)
            return keep(button)
        end
        local destroy = window.Destroy
        function window:Destroy()
            assert(self.root ~= nil, "dialog window destroyed twice")
            for _, control in ipairs(self.managed) do control:Destroy() end
            destroy(self)
            self.root, self.content, self.managed = nil, nil, {}
        end
        return window
    end }
    local env = setmetatable({ require = function(name)
        if name == "src/window" then return windowFactory end
        if name == "src/fancy_button" then return fancy end
        error(name)
    end }, { __index = _G })
    prettyui.Dialog = assert(loadfile(root .. "/src/dialog.lua", "t", env))()
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
        -- PrettyUI clamps the list's scroll to its rows
        function list:SetScrollPosition(position)
            local most = math.max(0, #self.rows * self.entryHeight - self.root.height)
            self.scrollY = math.max(0, math.min(math.floor(position or 0), most))
        end
        return list
    end
end

-- Give stand-in views a place and PrettyUI's scroll: clamped to the content,
-- moved by the wheel a step at a time, and reporting whether it moved
local function scrollViews()
    local newView = prettyui.SimpleView.new
    prettyui.SimpleView.new = function(parent, options)
        local view = newView(parent, options)
        view.root:SetPos(options.x or 0, options.y or 0)
        view.root:SetSize(options.width, options.height)
        view.height, view.scrollY, view.scrollStep = options.height, 0, options.scrollStep or 32
        function view:SetScrollPosition(position)
            local most = math.max(0, (self.content.height or 0) - self.height)
            self.scrollY = math.max(0, math.min(math.floor(position or 0), most))
        end
        function view:SetContentHeight(height)
            self.content.height = height
            self.scrollbarVisible = height > self.height
            self.contentWidth = self.root.width - (self.scrollbarVisible and 18 or 0)
            self:SetScrollPosition(self.scrollY)
        end
        function view:ScrollBy(delta) self:SetScrollPosition(self.scrollY + delta) end
        return view
    end
end

-- Stand in for PrettyUI's Tabs with the API Bank Tags uses:
-- new(parent, entries, options), GetPage(index).content, SetActive(index, notify),
-- GetActiveIndex, and Destroy; tab hit areas sit above a 42px header like PrettyUI's
-- A click runs SetActive(index), which hides other pages' roots and calls
-- onChange(tabs, index, value, page) only when the active tab changes and notify is not false
local TAB_HEADER = 42
local function standInTabs()
    prettyui.Tabs = { new = function(parent, entries, options)
        options = options or {}
        local tabs = { root = ui.Layer.new(parent), tabs = {}, pages = {}, onChange = options.onChange }
        tabs.root:SetPos(options.x or 0, options.y or 0)
        tabs.root:SetSize(options.width, options.height)
        tabs.content = ui.Layer.new(tabs.root)
        tabs.content:SetPos(0, TAB_HEADER)
        tabs.content:SetSize(options.width, (options.height or 0) - TAB_HEADER)
        for index, entry in ipairs(entries) do
            local hit = ui.Layer.new(tabs.root)
            hit:SetPos((index - 1) * 92, 0)
            hit:SetSize(90, TAB_HEADER)
            hit:Subscribe(ui.Hook.ONCLICK, function() tabs:SetActive(index) return false end)
            tabs.tabs[index] = { index = index, text = entry.text, value = entry.value, hit = hit }
            local page = { root = ui.Layer.new(tabs.content), index = index }
            page.root:SetSize(tabs.content.width, tabs.content.height)
            page.content = ui.Layer.new(page.root)
            page.content:SetSize(tabs.content.width, tabs.content.height)
            function page:SetContentHeight(height) self.contentHeight = height end
            tabs.pages[index] = page
        end
        function tabs:SetActive(index, notify)
            local tab = self.tabs[index]
            if tab == nil then return false end
            local previous = self.activeIndex
            self.activeIndex = index
            for pageIndex, page in ipairs(self.pages) do page.root.hidden = pageIndex ~= index end
            if notify ~= false and previous ~= index and self.onChange ~= nil then
                self.onChange(self, index, tab.value, self.pages[index])
            end
            return true
        end
        function tabs:GetActiveIndex() return self.activeIndex end
        function tabs:GetTab(index) return self.tabs[index] end
        function tabs:GetPage(index) return self.pages[index] end
        function tabs:Destroy()
            assert(self.root ~= nil, "Tabs destroyed twice")
            self.root:Destroy()
            self.root, self.pages, self.tabs = nil, {}, {}
        end
        tabs:SetActive(options.activeIndex or 1, false)
        return tabs
    end }
end

-- Install the stand-in host, build Bank Tags, and create a loader
function Harness.new(name, options)
    options = options or {}
    local coreRoot = Harness.CoreRoot()
    local bankHost = require("tools/test_support/fake_bank_host").install()
    bankHost:InstallSidebarWidgets()
    bankHost:InstallWindowWidgets()
    -- Native bank icon-tab states (stand-in sprite IDs).
    id.Sprite.BANK_TABS_HORIZONTAL_0 = 101
    id.Sprite.BANK_TABS_HORIZONTAL_1 = 102
    id.Sprite.BANK_TABS_HORIZONTAL_2 = 103
    -- Native font metrics for clipped-label hover decisions (fixed-width stand-in).
    config.Font = { MUSEO_SANS_15PT_REGULAR = {
        GetStringWidth = function(_, text) return #text * 7 end,
    } }
    -- Import/Share needs the window ComboBox, which has SetEntries
    local comboBox = prettyui.ComboBox
    bankHost:InstallPanelWidgets()
    prettyui.ComboBox = comboBox
    -- Native input fields always expose their content margins
    local newTextField = prettyui.TextField.new
    prettyui.TextField.new = function(parent, fieldOptions)
        local field = newTextField(parent, fieldOptions)
        field.root.contentMargin = { left = 8, top = 3, right = 8, bottom = 0 }
        return field
    end
    -- PrettyUI's Show shows and raises a window
    local newWindow = prettyui.Window.new
    prettyui.Window.new = function(parent, windowOptions)
        local window = newWindow(parent, windowOptions)
        function window:Show()
            self.root.hidden = false
            self.root:MoveToFront()
        end
        return window
    end
    placeListRows()
    scrollViews()
    standInTabs()
    installMiniMenu()
    installDialogs()
    -- An attached PrettyUI tooltip records its target, text, and whether it is shown
    local attach = prettyui.Tooltip.attach
    prettyui.Tooltip.attach = function(target, parent, value)
        local tooltip = attach(target, parent, value)
        tooltip.target, tooltip.parent, tooltip.text, tooltip.shown = target, parent, value, false
        function tooltip:SetText(text) self.text = text end
        function tooltip:Show() self.shown = true end
        function tooltip:Hide() self.shown = false end
        function tooltip:Destroy() self.destroyed, self.shown = true, false end
        return tooltip
    end
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
    ui.Hook.ONKEY = "key"
    ui.InputFieldActionResult = { CONTENT_CHANGE = "change", SUBMIT = "submit",
        SUBMIT_ON_ESCAPE = "escape", SUBMIT_ON_FOCUS_LOSS = "blur" }
    -- Lists report their documented selection callback when a row is picked
    local newList = prettyui.List.new
    prettyui.List.new = function(parent, listOptions)
        local list = newList(parent, listOptions)
        if listOptions.onChange ~= nil then
            function list:Click(entryID)
                for _, row in ipairs(self.rows) do
                    if row.entry.id == entryID then
                        listOptions.onChange(self, entryID, true)
                        return true
                    end
                end
                return false
            end
        end
        return list
    end
    -- Bank Core's own host events, which a test raises with Fire
    local hostSubscriptions = {}
    for _, event in ipairs({ "GameStateChanged", "MiniMenuEntrySelected", "ContentLayerReady", "SettingsLayerReady",
        "InventoryAdded", "InventoryRemoved", "InventoryUpdated" }) do
        local listeners = {}
        hostSubscriptions[event] = listeners
        Event[event] = {
            Subscribe = function(key, action) listeners[key] = action end,
            Unsubscribe = function(key) listeners[key] = nil end,
        }
    end
    -- MiniMenuReady handlers by subscription ID; tests choose the order
    local menuSubscriptions = {}
    Event.MiniMenuReady = {
        Subscribe = function(key, action) menuSubscriptions[key] = action end,
        Unsubscribe = function(key) menuSubscriptions[key] = nil end,
    }
    -- MiniMenuOpened handlers, heard when a test opens a menu to choose from it
    local openSubscriptions = {}
    Event.MiniMenuOpened = {
        Subscribe = function(key, action) openSubscriptions[key] = action end,
        Unsubscribe = function(key) openSubscriptions[key] = nil end,
    }
    -- Key events, and the menu and keybind state the editor's shortcuts read
    local keySubscriptions = {}
    for _, event in ipairs({ "KeyDown", "KeyUp", "WindowFocusChanged" }) do
        local listeners = {}
        keySubscriptions[event] = listeners
        Event[event] = {
            Subscribe = function(key, action) listeners[key] = action end,
            Unsubscribe = function(key) listeners[key] = nil end,
        }
    end
    local input = { menuOpen = false, capturing = false }
    prettyui.KeybindField = { IsCapturing = function() return input.capturing end }
    -- Values from the client docs' GameKey table, with its FromID name lookup
    local gameKeys = { Y = 37, Z = 64, C = 66, V = 67, CONTROL = 82, BACKSPACE = 85,
        LEFT = 96, RIGHT = 97, UP = 98, DOWN = 99, DELETE = 101 }
    gameKeys.FromID = function(value)
        for keyName, keyValue in pairs(gameKeys) do
            if keyValue == value then return keyName end
        end
        return nil
    end
    local Build = require("tools/build")
    local out = "dist/test/" .. name
    local built = Build.Run({ out = out })
    local Loader = require("tools/test_support/fake_plugin_host")
    local globals = { ui = ui, id = id, Event = Event, config = config, Vector4 = Vector4,
        Mouse = Mouse, Keyboard = Keyboard, MiniMenuActionType = MiniMenuActionType,
        MiniMenuEntryType = MiniMenuEntryType,
        MiniMenu = { IsOpen = function() return input.menuOpen end },
        GameKey = gameKeys,
        ModifierKey = { SHIFT = 1, CONTROL = 2, ALT = 4, ANY = 7 },
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
        menuSubscriptions = menuSubscriptions,
        openSubscriptions = openSubscriptions,
        keySubscriptions = keySubscriptions,
        hostSubscriptions = hostSubscriptions,
        input = input,
        -- Where the host adds a plugin's entry, and who hears a menu first
        placement = "above_cancel",
        menuOrder = "core_first",
        coreRoot = coreRoot,
        out = out,
        coreFolder = coreRoot,
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
    -- Core's stand-in loader predates requiredDependencies; read the client format here
    local manifest = require("banktags/core/json").decode(assert(readText(self.tagsFolder .. "/plugin.json")))
    local dependencies, optional = {}, {}
    for name in pairs(manifest.requiredDependencies or {}) do dependencies[name] = true end
    for name in pairs(manifest.optionalDependencies or {}) do optional[name] = true end
    self.tags = self.host:Load("banktags", self.tagsFolder,
        { name = manifest.name, dependencies = dependencies, optional = optional })
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

-- Report whether Bank Tags holds an extension registered with the running Core session
function Harness:Connected()
    local session = self:Session()
    return self:App().ext ~= nil and session ~= nil and session.pluginPages.owners.banktags ~= nil
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

-- Raise a host event for every plugin listening to it
function Harness:Fire(event, payload)
    local actions = {}
    for _, action in pairs(self.hostSubscriptions[event]) do actions[#actions + 1] = action end
    for _, action in ipairs(actions) do action(payload) end
end

-- Close the bank as the host does: the inventory goes before the window
function Harness:CloseBank()
    self:Fire("InventoryRemoved", { inv = { id = 95 } })
    self:Tick()
    self.bankHost:UnmountBankWindow()
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

-- Click the control that owns a visible label, including shared-dialog footer actions.
function Harness.Click(parent, text)
    local target = assert(Harness.Find(parent, text), "missing control: " .. text)
    while target ~= nil do
        local action = target.hooks.click or target.hooks.pressed
        if action ~= nil then action(); return end
        target = target.parent
    end
    error("control cannot be clicked: " .. text)
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
            arguments = { ... }, actionEntryType = MiniMenuEntryType.PLUGIN }
        table.insert(self.entries, place(self), entry)
    end
    function menu:Swap(a, b) self.entries[a], self.entries[b] = self.entries[b], self.entries[a] end
    local keys = {}
    for key in pairs(self.menuSubscriptions) do keys[#keys + 1] = key end
    table.sort(keys)
    if self.menuOrder == "tags_first" then table.sort(keys, function(a, b) return a > b end) end
    -- PrettyUI is a dependency, so it hears the menu before the plugins
    prettyMenuHandlers.MiniMenuReady({ miniMenu = menu })
    for _, key in ipairs(keys) do self.menuSubscriptions[key]({ miniMenu = menu }) end
    -- The client stops rebuilding the menu once opened, so this one is what opens
    local subscriptions = self.openSubscriptions
    openers[menu] = function()
        for _, action in pairs(subscriptions) do action({ miniMenu = menu }) end
    end
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

-- List a menu's labels as the client shows them, the left click on top
function Harness.DisplayedLabels(menu)
    local labels = {}
    for index = menu.entryCount, 1, -1 do labels[#labels + 1] = menu.entries[index].verbText end
    return labels
end

-- Open a menu by right click, once, as choosing from it needs
function Harness.Open(menu)
    local open = openers[menu]
    openers[menu] = nil
    if open ~= nil then open() end
end

-- Choose an entry by its label, failing when it is missing
function Harness.Choose(menu, label)
    Harness.Open(menu)
    for _, entry in ipairs(menu.entries) do
        if entry.verbText == label then return entry.action(table.unpack(entry.arguments or {})) end
    end
    error(label .. " is not in the menu: " .. table.concat(Harness.Labels(menu), " | "))
end

-- List a menu's submenus as { entry, children, options }
function Harness.Submenus(menu)
    return submenus[menu] or {}
end

-- Find a submenu by its parent entry's label, or nil
function Harness.Submenu(menu, label)
    for _, submenu in ipairs(Harness.Submenus(menu)) do
        if submenu.entry.verbText == label then return submenu end
    end
    return nil
end

-- List a submenu's child labels in order
function Harness.ChildLabels(submenu)
    local labels = {}
    for _, child in ipairs(submenu.children) do labels[#labels + 1] = child.label end
    return labels
end

-- Open a menu and click a child of its submenu, then close the menu
-- PrettyUI clears its submenu state before running the child, as its row click does
function Harness.ChooseChild(menu, label, childLabel)
    Harness.Open(menu)
    local submenu = Harness.Submenu(menu, label)
    if submenu == nil then error(label .. " is not a submenu in: " .. table.concat(Harness.Labels(menu), " | ")) end
    for _, child in ipairs(submenu.children) do
        if child.label == childLabel then
            prettyMenuHandlers.MiniMenuClosed({ miniMenu = menu })
            child.action(table.unpack(child.arguments or child.args or {}))
            prettyMenuHandlers.MiniMenuClosed({ miniMenu = menu })
            return
        end
    end
    error(childLabel .. " is not in " .. label .. ": " .. table.concat(Harness.ChildLabels(submenu), " | "))
end

-- Report whether a menu holds an entry
function Harness.Has(menu, label)
    for _, entry in ipairs(menu.entries) do
        if entry.verbText == label then return true end
    end
    return false
end

-- Click a Tags row as the client does: PrettyUI's row hears the press, then the row hears the release
function Harness:ClickRow(entryID)
    local list = self:App().tab.controls.list
    assert(list.list:Click(entryID), tostring(entryID) .. " has no row")
    list:RowFor(entryID).root.hooks.release()
end

-- Point at the shown page's slot at a position among its slots, counting blanks, and let Core hover it
function Harness:PointAtSlot(position)
    local layout = self:Session().layout
    local key = nil
    for _, slot in ipairs(layout.pageState.view.slots) do
        if slot.position == position then key = slot.layoutKey end
    end
    local drawn = nil
    for _, entry in ipairs(layout.itemHover.drawnPageItems) do
        if entry.layoutKey == key then drawn = entry end
    end
    assert(drawn ~= nil, "slot " .. position .. " is not drawn")
    local Geometry = require("banktags/ui/geometry")
    local values = layout.pageDisplay.pageArea
    local insetX, insetY = layout.pageDisplay:GridCellInset()
    local left, top = Geometry.absolutePosition(layout.itemHover.pageInputBlocker)
    self.bankHost.mouse = { x = left + values.contentX + drawn.x - insetX + 5,
        y = top + values.contentY + drawn.y - values.scrollY - insetY + 5 }
    self:Tick()
end

-- Open the menu for the page slot under the pointer: its stack's, or none for a ghost
function Harness:SlotMenu()
    local hover = self:Session().layout.itemHover.hoveredBankStack
    return hover ~= nil and self:MenuFor(hover.item) or self:ContentMenu()
end

-- List a tag's saved slots in page order as object IDs, 0 for a blank
function Harness:Saved(tag)
    local record, values = self:App().store.data.tags[tag], {}
    for _, entry in ipairs(record.rows) do
        for _, slot in ipairs(entry.slots or {}) do values[#values + 1] = slot.objectID or 0 end
    end
    for _, slot in ipairs(record.unsorted) do values[#values + 1] = slot.objectID or 0 end
    return table.concat(values, " ")
end

-- Send native hover coordinates to the editor surface at a content position.
function Harness:PointEditor(x, y)
    local editor = assert(self:App().windows.layoutEditor)
    local Geometry = require("banktags/ui/geometry")
    local left, top = Geometry.absolutePosition(editor.content)
    self.bankHost.mouse = { x = left + x, y = top + y }
    local surface = editor.drag ~= nil and editor.drag.sourceSurface or nil
    if surface == nil then
        for _, candidate in ipairs({ editor.panes.sorted.surface, editor.panes.unsorted.surface,
            editor.searchDragSurface }) do
            local clip = editor.surfaceClips[candidate]
            if not candidate.hidden and x >= clip.x and y >= clip.y
                and x < clip.x + clip.width and y < clip.y + clip.height then
                surface = candidate
                break
            end
        end
    end
    local previous = self.editorHoveredSurface
    if previous ~= surface and previous ~= nil then
        previous.isMouseOver = false
        if previous.hooks.mouseleave ~= nil then previous.hooks.mouseleave(previous) end
    end
    self.editorHoveredSurface = surface
    if surface ~= nil then
        surface.isMouseOver = true
        local localX, localY = x, y
        if previous ~= surface and surface.hooks.mouseover ~= nil then
            surface.hooks.mouseover(surface, localX, localY)
        end
        if surface.hooks.mouserepeat ~= nil then surface.hooks.mouserepeat(surface, localX, localY) end
    end
    self.editorPoint = { x = x, y = y }
end

-- Press a pane-local point through its editor-origin input surface
function Harness:PressEditor(surface, x, y)
    local editor = assert(self:App().windows.layoutEditor)
    local clip = editor.surfaceClips[surface]
    return surface.hooks.click(surface, clip.x + x, clip.y + y)
end

-- Release the editor's drag where it was last pointed, in its surface's native units
function Harness:ReleaseEditor()
    local editor = assert(self:App().windows.layoutEditor)
    local surface = editor.drag ~= nil and editor.drag.sourceSurface or self.editorHoveredSurface
    local point = assert(self.editorPoint, "point at the editor first")
    return surface.hooks.release(surface, point.x, point.y)
end

-- Point the mouse at a position relative to a component
function Harness:PointAt(component, x, y)
    local Geometry = require("banktags/ui/geometry")
    local left, top = Geometry.absolutePosition(component)
    self.bankHost.mouse = { x = left + x, y = top + y }
    if self.hoveredComponent ~= nil then self.hoveredComponent.isMouseOver = false end
    self.hoveredComponent = component
    component.isMouseOver = true
end

return Harness
