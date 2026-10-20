package.path = "./?.lua;./?/init.lua;" .. package.path

-- Drive import providers through the public API and the Import/Share window
-- The game host is a stand-in, not the live client

local db, writes = {}, 0
PersistentDB = {
    GetString = function(_, key) return db[key] end,
    SetString = function(_, key, value)
        db[key] = value
        if key:find("manifest", 1, true) then writes = writes + 1 end
        return true
    end,
}

-- Logic listeners run only when the test ticks
local listeners, ticking = {}, false
Event = { Logic = {
    Subscribe = function(name, action) listeners[name] = action end,
    Unsubscribe = function(name) listeners[name] = nil end,
} }
local function tick()
    local names = {}
    for name in pairs(listeners) do names[#names + 1] = name end
    table.sort(names)
    ticking = true
    for _, name in ipairs(names) do
        if listeners[name] ~= nil then listeners[name]() end
    end
    ticking = false
end
local function listenerCount()
    local count = 0
    for _ in pairs(listeners) do count = count + 1 end
    return count
end

local function node(options)
    options = options or {}
    local value = { x = options.x, y = options.y, width = options.width,
        height = options.height, content = options.text, hooks = {} }
    function value:SetPos(x, y) self.x, self.y = x, y end
    function value:SetSize(width, height) self.width, self.height = width, height end
    function value:Subscribe(hook, action) self.hooks[hook] = action end
    function value:Destroy() self.destroyed = true end
    return value
end
id = { Component = { TOPLEVEL_V2__BANK_LAYER = 1 }, Sprite = {},
    Font = { CINZEL_13PT_BOLD = 1, MUSEO_SANS_11PT_REGULAR = 2 } }
ui = { AlignMode = { CENTRE = 1 }, Hook = { ONCLICK = 1 }, ObjectQuantityDisplayMode = {},
    Interfaces = { GetComponent = function() return {} end }, Layer = { new = node } }
-- Config names this client knows; anything else is unknown
local objects = { [101] = "iron_bar", [104] = "rune_bar" }
config = { Obj = {
    FromID = function(value)
        return { id = value, configName = objects[value] }
    end,
    iron_bar = { id = 101 },
    rune_bar = { id = 104 },
} }
local function control(options)
    return { root = node(options), Destroy = function(self) self.destroyed = true end }
end
prettyui = {
    Sprites = { SPRITE_BUTTONS = { STAR = {}, PIN = {} } },
    Window = { new = function(_, options)
        return { content = {}, Show = function() end, Destroy = function() end,
            Close = function(self) self.closed = true; options.onClose() end }
    end },
    Tabs = { new = function(_, entries)
        local pages = {}
        for index in ipairs(entries) do
            pages[index] = { content = {}, SetContentHeight = function() end }
        end
        return { GetPage = function(_, index) return assert(pages[index]) end,
            Destroy = function() end }
    end },
    Text = { new = function(_, options) return node(options) end },
    TextField = { new = function(_, options)
        local value = control(options)
        value.text, value.disabled, value.placeholder = options.text or "", options.disabled, options.placeholder
        function value:GetText() return self.text end
        function value:SetText(text, notify)
            self.text = text
            if notify and options.onChange then options.onChange(self, nil, text) end
        end
        function value:SetDisabled(disabled) self.disabled = disabled end
        function value:SetPlaceholder(text) self.placeholder = text end
        return value
    end },
    ItemSlot = { new = function(_, _, options)
        local value = control(options)
        value.disabled = options.disabled
        function value:SetObject(object) self.object = object end
        function value:SetDisabled(disabled) self.disabled = disabled end
        return value
    end },
    SimpleButton = { new = function(_, label, action, options)
        local value = control(options)
        value.label, value.action = label, action
        function value:SetDisabled(disabled) self.disabled = disabled end
        -- A disabled button ignores presses, like PrettyUI's
        function value:Press() if not self.disabled then self.action() end end
        return value
    end },
    SpriteButton = { new = function(_, spriteName, _, options)
        local value = control(options)
        value.spriteName, value.tooltip = spriteName, options.tooltip
        return value
    end },
    ComboBox = { new = function(_, options)
        local value = control(options)
        value.entries, value.selectedID, value.disabled = options.entries, options.selectedID, options.disabled
        function value:GetSelectedID() return self.selectedID end
        -- The client's combo box may repeat its selection when entries change
        function value:SetEntries(entries, selectedID)
            self.entries, self.selectedID = entries, selectedID
            if options.onChange then options.onChange(self, selectedID) end
        end
        function value:SetDisabled(disabled) self.disabled = disabled end
        function value:Select(selectedID, notify)
            self.selectedID = selectedID
            if notify then options.onChange(self, selectedID) end
        end
        return value
    end },
}

local ImportAPI = require("banktags/imports/import_api")
local ItemIdentity = require("banktags/tags/item_identity")
local ImportProviders = require("banktags/imports/import_providers")
local TagData = require("banktags/tags/tag_data")
local TagStore = require("banktags/tags/tag_store")
local TagDraft = require("banktags/imports/tag_draft")
local Windows = require("banktags/windows/windows")

local store = TagStore.new()
-- Count store commits so previews can be shown to save nothing
local commits = 0
local commit = TagStore.Commit
store.Commit = function(...)
    commits = commits + 1
    return commit(...)
end

-- Compose the window and import API as the app does
local app = { store = store, settings = {} }
function app:Changed() end
function app:BankItems() return {} end
app.imports = ImportAPI.new({
    readDraft = TagDraft.Read,
    onChange = function() app.windows:RefreshImportSources() end,
})
app.importProviders = app.imports.providers
local api = app.imports.publicAPI
app.windows = Windows.new(app)

-- Read the window's picker as a list of source keys
local function sourceKeys(settings)
    local keys = {}
    for index, entry in ipairs(settings.importSourcePicker.entries) do keys[index] = entry.id end
    return table.concat(keys, " ")
end

-- A one-tag draft with a repeated and an unknown item
local function gearDraft(name)
    return { tags = { {
        name = name,
        icon = "iron_bar",
        folder = "Guides",
        rows = { { label = "Bars" }, { "iron_bar", 104, false, "iron_bar" } },
        items = { "mystery_item" },
    } } }
end

-- The share code for one empty tag
local function shareCode(name)
    local data = TagData.Empty()
    data.order[1] = name
    data.tags[name] = { rows = {}, unsorted = {} }
    return TagData.Encode(data)
end

-- The published limits include the import sources and drafts
assert(api.LIMITS.importProviders == 16 and api.LIMITS.importProvidersPerOwner == 4)
assert(api.LIMITS.draftTags == 32 and api.LIMITS.draftEntries == 2000)
-- The registry shares the draft reader's limits without loading the reader
assert(api.LIMITS.draftTags == TagDraft.LIMITS.tags and api.LIMITS.draftEntries == TagDraft.LIMITS.entries)

app.windows:OpenImportShare()
local settings = app.windows.importShare
assert(sourceKeys(settings) == "builtin:code" and settings.source.key == "builtin:code")
assert(settings.controls.importCodeLabel.content == "Import code")
assert(settings.importButton.disabled and settings.importStatus.hidden)

-- Two owners register sources without changing the selection
local wiki = assert(api.RegisterExtension("example.wiki", "Wiki"))
local pvme = assert(api.RegisterExtension("example.pvme", "PVME"))
local wikiCalls, wikiRequests, wikiCancels = 0, {}, 0
local function wikiProvider(overrides)
    local provider = {
        label = "Wiki gear",
        icon = "STAR",
        input = "text",
        prompt = "Guide address",
        placeholder = "Paste a guide address...",
        request = function(request)
            assert(ticking, "providers run on a logic tick, not inside a window event")
            wikiCalls = wikiCalls + 1
            wikiRequests[#wikiRequests + 1] = request
            return function() wikiCancels = wikiCancels + 1 end
        end,
    }
    for key, value in pairs(overrides or {}) do provider[key] = value end
    return provider
end
assert(wiki:RegisterImportProvider("guide", wikiProvider()))
local pvmeRequests = {}
local pvmeAnswer = nil
assert(pvme:RegisterImportProvider("preset", {
    label = "PVME preset",
    input = "action",
    actionLabel = "Choose a preset",
    request = function(request)
        pvmeRequests[#pvmeRequests + 1] = request
        if pvmeAnswer ~= nil then pvmeAnswer(request) end
    end,
}))
assert(sourceKeys(settings) == "builtin:code example.pvme/preset example.wiki/guide")
assert(settings.source.key == "builtin:code")
assert(table.concat(wiki:GetState().providers, ",") == "guide")

-- Registrations are checked in full and refused with a reason
local function refused(reason, providerID, provider)
    local ok, actual = wiki:RegisterImportProvider(providerID, provider)
    assert(ok == false and actual == reason, tostring(providerID) .. " " .. tostring(actual))
end
refused("invalid_import_provider_id", "bad id", wikiProvider())
refused("invalid_import_provider_id", string.rep("a", 65), wikiProvider())
refused("duplicate_import_provider", "guide", wikiProvider())
refused("invalid_import_provider", "x", "not a table")
refused("invalid_import_provider", "x", setmetatable(wikiProvider(), {}))
refused("invalid_import_provider", "x", wikiProvider({ extra = true }))
refused("invalid_import_provider", "x", wikiProvider({ request = "call me" }))
refused("invalid_import_provider", "x", wikiProvider({ icon = "NOT_A_SPRITE" }))
refused("invalid_import_provider", "x", wikiProvider({ label = "<col=ff0000>Red" }))
refused("invalid_import_provider", "x", wikiProvider({ input = "html" }))
refused("invalid_import_provider", "x", wikiProvider({ actionLabel = "Go" }))
refused("invalid_import_provider", "x", wikiProvider({ unavailable = string.rep("x", 121) }))
for index = 2, 4 do assert(wiki:RegisterImportProvider("extra" .. index, wikiProvider())) end
refused("too_many_import_providers", "extra5", wikiProvider())
for index = 2, 4 do assert(wiki:RemoveImportProvider("extra" .. index)) end
assert(table.concat(wiki:GetState().providers, ",") == "guide")
assert(wikiCalls == 0 and listenerCount() == 0)

-- One owner cannot reach another's sources, and unknown IDs are refused
assert(select(2, pvme:RemoveImportProvider("guide")) == "unknown_import_provider")
assert(select(2, pvme:UpdateImportProvider("guide", wikiProvider())) == "unknown_import_provider")
assert(select(2, wiki:RemoveImportProvider("missing")) == "unknown_import_provider")

-- The built-in share code still previews, imports, and shares
settings.importField:SetText(shareCode("starter"), true)
assert(settings.importState == "ready" and not settings.importButton.disabled)
assert(settings.importStatus.content == "Preview: 0 items. Not saved until you import.")
assert(writes == 0 and commits == 0)
settings.importButton:Press()
assert(writes == 1 and commits == 1 and store.data.tags.starter ~= nil)
local shared = store:TagExports()[1]
assert(shared.tag == "starter" and TagData.Decode(shared.value).order[1] == "starter")
assert(#settings.shareRows == 1)

-- Choosing a source shows its input and clears the earlier draft
settings.importSourcePicker:Select("example.wiki/guide", true)
assert(settings.source.key == "example.wiki/guide" and settings.importField.text == "")
assert(settings.importField.placeholder == "Paste a guide address...")
assert(settings.controls.importCodeLabel.content == "Guide address")
assert(settings.importSourceIcon.spriteName == "STAR" and settings.importButton.disabled)
assert(settings.importState == "empty" and wikiCalls == 0)

-- Typing asks the source on the next tick; the preview saves nothing
settings.importField:SetText("guide/rotation", true)
assert(settings.importState == "loading" and wikiCalls == 0 and settings.importButton.disabled)
assert(settings.importStatus.content == "Loading from Wiki gear...")
-- Import does nothing until a draft is ready, even past the disabled state
settings:Import()
assert(commits == 1 and settings.importStatus.content == "Loading from Wiki gear...")
tick()
local request = wikiRequests[1]
assert(wikiCalls == 1 and request.input == "guide/rotation" and request.source == "guide")
assert(request:IsCurrent() and listenerCount() == 0)
assert(not pcall(function() request.input = "changed" end))
assert(rawget(request, "store") == nil and request.store == nil)
assert(request:Resolve(gearDraft("Rotation gear")))
assert(not request:IsCurrent())
-- A second answer to the same request is refused
assert(select(2, request:Resolve(gearDraft("Other"))) == "stale_request")
assert(select(2, request:Fail("late")) == "stale_request")
assert(settings.importState == "loading")
tick()
assert(settings.importState == "ready" and not settings.importButton.disabled)
assert(settings.importNameField.text == "rotation gear" and settings.importSpriteSlot.object.id == 101)
assert(settings.importFolder:GetSelectedID() == "folder:guides")
assert(settings.importStatus.content == "Preview: 3 items, 1 not recognized. Not saved until you import.")
assert(writes == 1 and commits == 1 and listenerCount() == 0)

-- Import commits the current draft once, through the store's checks
settings.importButton:Press()
assert(writes == 2 and commits == 2)
assert(store:GetTagFolder("rotation gear") == "guides")
assert(store:HasTag("rotation gear", ItemIdentity.LayoutKey(101, 1)))
assert(store:HasTag("rotation gear", ItemIdentity.LayoutKey(101, 2)))
assert(store:HasTag("rotation gear", ItemIdentity.LayoutKey(104, 1)))
assert(store:GetLabel("rotation gear", 0, 10) == "Bars")
assert(string.find(TagData.Encode(store.data, "rotation gear"), "mystery_item", 1, true))
assert(settings.importStatus.content == "Imported 1 tag.")

-- Changing the input makes the old request stale
settings.importField:SetText("guide/one", true)
tick()
local first = wikiRequests[2]
settings.importField:SetText("guide/two", true)
assert(not first:IsCurrent() and wikiCancels == 1 and settings.importButton.disabled)
assert(select(2, first:Resolve(gearDraft("One"))) == "stale_request")
tick()
local second = wikiRequests[3]
assert(second.input == "guide/two" and second:Resolve(gearDraft("Two")))
tick()
assert(settings.importNameField.text == "two" and writes == 2)

-- Another owner registering keeps the selected source and its request
settings.importField:SetText("guide/kept-while-registering", true)
tick()
local kept = wikiRequests[#wikiRequests]
local other = assert(api.RegisterExtension("example.other", "Other"))
assert(other:RegisterImportProvider("list", wikiProvider({ label = "Wiki gear" })))
assert(kept:IsCurrent() and settings.importField.text == "guide/kept-while-registering")
assert(sourceKeys(settings) == "builtin:code example.other/list example.pvme/preset example.wiki/guide")
-- Repeated labels name their owner so the picker can tell them apart
assert(settings.importSourcePicker.entries[2].label == "Wiki gear")
assert(settings.importSourcePicker.entries[4].label == "Wiki gear (Wiki)")
assert(other:Dispose() and kept:IsCurrent())
assert(kept:Resolve(gearDraft("Two")))
tick()

-- An answer recorded before the window closes is never delivered
settings.importField:SetText("guide/three", true)
tick()
local beforeClose = wikiRequests[#wikiRequests]
assert(beforeClose:Resolve(gearDraft("Three")))
local status = settings.importStatus.content
settings.window:Close()
tick()
assert(settings.importStatus.content == status and settings.importNameField.text == "")
assert(not beforeClose:IsCurrent() and listenerCount() == 0)

-- Closing the window cancels a pending request
app.windows:OpenImportShare()
settings = app.windows.importShare
assert(settings.source.key == "builtin:code")
settings.importSourcePicker:Select("example.wiki/guide", true)
settings.importField:SetText("guide/four", true)
tick()
local pending = wikiRequests[#wikiRequests]
local cancelsBefore = wikiCancels
app.windows:Close("importShare")
assert(wikiCancels == cancelsBefore + 1 and not pending:IsCurrent())
assert(select(2, pending:Resolve(gearDraft("Four"))) == "stale_request")
tick()
assert(listenerCount() == 0 and writes == 2)

-- An action source runs its own flow, answering on the tick
app.windows:OpenImportShare()
settings = app.windows.importShare
settings.importSourcePicker:Select("example.pvme/preset", true)
assert(settings.importField.root.hidden and settings.importActionButton.label == "Choose a preset")
assert(settings.importState == "empty" and #pvmeRequests == 0)
pvmeAnswer = function(answer)
    assert(answer.input == nil)
    assert(answer:Resolve({ tags = {
        { name = "Melee", folder = "Presets", items = { "iron_bar" } },
        { name = "Ranged", rows = { { 104 } } },
    } }))
end
settings.importActionButton:Press()
assert(settings.importState == "loading" and #pvmeRequests == 0)
tick()
assert(#pvmeRequests == 1 and settings.importState == "ready")
assert(settings.importStatus.content == "2 tags. Original names and sprites kept.")
assert(settings.importNameField.disabled and writes == 2)
settings.importButton:Press()
assert(writes == 3 and store:GetTagFolder("melee") == "presets" and store.data.tags.ranged ~= nil)

-- Updating an action source cancels its request without restarting it
pvmeAnswer = nil
settings.importActionButton:Press()
tick()
local beforeActionUpdate, actionRequests = pvmeRequests[#pvmeRequests], #pvmeRequests
assert(pvme:UpdateImportProvider("preset", {
    label = "PVME presets", input = "action", actionLabel = "Choose a preset",
    request = function(request) pvmeRequests[#pvmeRequests + 1] = request end,
}))
assert(not beforeActionUpdate:IsCurrent() and settings.importState == "empty")
tick()
assert(#pvmeRequests == actionRequests and settings.importActionButton.label == "Choose a preset")

-- Switching sources cancels the outstanding request
settings.importActionButton:Press()
tick()
local orphan = pvmeRequests[2]
settings.importSourcePicker:Select("example.wiki/guide", true)
assert(not orphan:IsCurrent() and select(2, orphan:Resolve(gearDraft("Orphan"))) == "stale_request")
assert(settings.importActionButton == nil and not settings.importField.root.hidden)

-- A source that errors shows a short message; the share code still works
assert(wiki:UpdateImportProvider("guide", wikiProvider({
    request = function() error("internal parser detail at line 12") end,
})))
settings.importField:SetText("guide/broken", true)
tick()
assert(settings.importState == "error" and settings.importButton.disabled)
assert(settings.importStatus.content == "Wiki gear stopped with an error.")
assert(not string.find(settings.importStatus.content, "parser", 1, true))
settings.importSourcePicker:Select("builtin:code", true)
settings.importField:SetText(shareCode("after error"), true)
settings.importButton:Press()
assert(writes == 4 and store.data.tags["after error"] ~= nil)
assert(wiki:UpdateImportProvider("guide", wikiProvider()))

-- Ask the wiki source again and return the request it receives
local function ask(input)
    settings.importField:SetText(input, true)
    tick()
    return wikiRequests[#wikiRequests]
end
settings.importSourcePicker:Select("example.wiki/guide", true)

-- Failures show the provider's message as one short, plain line
local failing = ask("guide/fail")
assert(failing:Fail("Guide <b>not</b> found\n(404)"))
tick()
assert(settings.importState == "error" and settings.importStatus.content == "Guide bnot/b found (404)")
failing = ask("guide/fail-long")
assert(failing:Fail(string.rep("x", 500)))
tick()
assert(settings.importStatus.content == "The source could not load this import.")
failing = ask("guide/fail-nil")
assert(failing:Fail())
tick()
assert(settings.importStatus.content == "The source could not load this import.")

-- Broken drafts are refused without running any of their code
local touched = false
local trap = setmetatable({}, { __index = function() touched = true end,
    __pairs = function() touched = true end, __len = function() touched = true return 1 end })
local manyTags = { tags = {} }
for index = 1, 33 do manyTags.tags[index] = { name = "t" .. index } end
local hugeRow = {}
for index = 1, 2001 do hugeRow[index] = 101 end
local badDrafts = {
    "not a table",
    {},
    { tags = {} },
    trap,
    { tags = trap },
    { tags = { trap } },
    { tags = { { name = "x", rows = trap } } },
    { tags = { { name = "x" } }, extra = true },
    { tags = { [1] = { name = "x" }, [3] = { name = "y" } } },
    manyTags,
    { tags = { { name = "x", rows = { hugeRow } } } },
    { tags = { { name = "a,b" } } },
    { tags = { { name = "<img=1>" } } },
    { tags = { { name = "same" }, { name = "SAME" } } },
    { tags = { { name = "x", rows = { { label = "Bars", extra = 1 } } } } },
    { tags = { { name = "x", rows = { { label = string.rep("l", 61) } } } } },
    { tags = { { name = "x", items = { false } } } },
    { tags = { { name = "x", items = { {} } } } },
    { tags = { { name = "x", items = { -1 } } } },
    { tags = { { name = "x", items = { 1.5 } } } },
    { tags = { { name = "x", items = { "iron_bar:2" } } } },
    { tags = { { name = "x", items = { "#101" } } } },
    { tags = { { name = "x", icon = {} } } },
    { tags = { { name = "x", folder = string.rep("f", 41) } } },
    { tags = { { name = "x", callback = function() end } } },
}
for index, draft in ipairs(badDrafts) do
    local bad = ask("guide/bad" .. index)
    local ok, reason = bad:Resolve(draft)
    assert(ok == false and reason == "invalid_draft", "draft " .. index)
    tick()
    assert(settings.importState == "invalid" and settings.importButton.disabled, "draft " .. index)
    assert(settings.importStatus.content == "The source returned tags Bank Tags cannot read.")
end
assert(not touched and writes == 4)

-- An update asks the selected source again and drops the old request
local beforeUpdate = ask("guide/kept")
assert(wiki:UpdateImportProvider("guide", wikiProvider({ label = "Wiki gear lists" })))
assert(not beforeUpdate:IsCurrent() and settings.importField.text == "guide/kept")
assert(settings.importState == "loading")
tick()
assert(wikiRequests[#wikiRequests].input == "guide/kept")
-- An invalid update keeps the last good source
assert(select(2, wiki:UpdateImportProvider("guide", { label = "" })) == "invalid_import_provider")
assert(settings.source.label == "Wiki gear lists")
-- An unavailable source explains itself and is never asked
local callsBefore = wikiCalls
assert(wiki:UpdateImportProvider("guide", wikiProvider({ unavailable = "Open the wiki plugin first." })))
assert(settings.importState == "unavailable" and settings.importField.disabled)
assert(settings.importStatus.content == "Open the wiki plugin first.")
settings.importField:SetText("guide/ignored", true)
tick()
assert(wikiCalls == callsBefore and settings.importButton.disabled)
assert(wiki:UpdateImportProvider("guide", wikiProvider()))

-- Removing the selected source falls back to the share code
local removed = ask("guide/removed")
assert(wiki:RemoveImportProvider("guide"))
assert(settings.source.key == "builtin:code" and settings.importField.text == "")
assert(settings.importSourcePicker:GetSelectedID() == "builtin:code")
assert(not removed:IsCurrent() and sourceKeys(settings) == "builtin:code example.pvme/preset")
tick()
assert(settings.importState == "empty" and writes == 4)

-- Replacing an owner removes its sources and retires its old handle
assert(wiki:RegisterImportProvider("guide", wikiProvider()))
settings.importSourcePicker:Select("example.wiki/guide", true)
local replaced = ask("guide/replaced")
local reloadedWiki = assert(api.RegisterExtension("example.wiki", "Wiki"))
assert(not replaced:IsCurrent() and settings.source.key == "builtin:code")
assert(select(2, wiki:RegisterImportProvider("guide", wikiProvider())) == "stale_handle")
assert(select(2, wiki:UpdateImportProvider("guide", wikiProvider())) == "stale_handle")
assert(select(2, wiki:RemoveImportProvider("guide")) == "stale_handle")
assert(#wiki:GetState().providers == 0)
assert(reloadedWiki:RegisterImportProvider("guide", wikiProvider()))

-- Disposing an owner removes its sources
settings.importSourcePicker:Select("example.pvme/preset", true)
settings.importActionButton:Press()
tick()
local disposed = pvmeRequests[#pvmeRequests]
assert(pvme:Dispose())
assert(not disposed:IsCurrent() and settings.source.key == "builtin:code")
assert(sourceKeys(settings) == "builtin:code example.wiki/guide")

-- The registry's count always matches the sources it holds
local function consistent()
    local count = 0
    for _ in pairs(app.importProviders.records) do count = count + 1 end
    return count == app.importProviders.count
end

-- Set up an owner whose cancel callbacks register another owner's sources
local host = assert(api.RegisterExtension("example.host", "Host"))
local deliveries = 0
local function doomedOwner()
    local doomed = assert(api.RegisterExtension("example.doomed", "Doomed"))
    local requests, cancelled = {}, { peersStale = true }
    for index = 1, 3 do
        assert(doomed:RegisterImportProvider("s" .. index, wikiProvider({
            request = function(request)
                requests[index] = request
                return function()
                    for _, peer in ipairs(requests) do
                        if peer:IsCurrent()
                            or select(2, peer:Resolve(gearDraft("Dead"))) ~= "stale_request" then
                            cancelled.peersStale = false
                        end
                    end
                    if app.importProviders:Begin("example.doomed/s3", "again", function() end) then
                        cancelled.peersStale = false
                    end
                    cancelled[index] = host:RegisterImportProvider("late" .. index, wikiProvider())
                end
            end,
        })))
    end
    settings.importSourcePicker:Select("example.doomed/s1", true)
    settings.importField:SetText("doomed/one", true)
    for index = 2, 3 do
        assert(app.importProviders:Begin("example.doomed/s" .. index, "doomed/" .. index,
            function() deliveries = deliveries + 1 end))
    end
    tick()
    assert(#requests == 3)
    return doomed, requests, cancelled
end
-- The doomed owner is fully removed; the host's late sources still work
local function leftCleanly(requests, cancelled)
    assert(cancelled.peersStale and cancelled[1] and cancelled[2] and cancelled[3])
    assert(sourceKeys(settings) == "builtin:code example.host/late1 example.host/late2 "
        .. "example.host/late3 example.wiki/guide", sourceKeys(settings))
    assert(settings.source.key == "builtin:code" and consistent())
    for _, request in ipairs(requests) do
        assert(select(2, request:Resolve(gearDraft("Dead"))) == "stale_request")
    end
    tick()
    assert(deliveries == 0 and settings.importState == "empty" and writes == 4)
    settings.importSourcePicker:Select("example.host/late2", true)
    assert(ask("late/two"):Resolve(gearDraft("Late")))
    tick()
    assert(settings.importState == "ready" and settings.importNameField.text == "late")
    for index = 1, 3 do assert(host:RemoveImportProvider("late" .. index)) end
    settings.importSourcePicker:Select("builtin:code", true)
end

-- Replacing then disposing the owner each finish its cleanup
local doomed, doomedRequests, doomedCancels = doomedOwner()
local replacement = assert(api.RegisterExtension("example.doomed", "Doomed"))
assert(replacement:GetState().live and not doomed:GetState().live)
leftCleanly(doomedRequests, doomedCancels)
doomed, doomedRequests, doomedCancels = doomedOwner()
assert(doomed:Dispose() and not replacement:GetState().live)
leftCleanly(doomedRequests, doomedCancels)

-- Cancel callbacks that edit sources leave each counted once
local function selfEditing(onCancel)
    return wikiProvider({ request = function() return onCancel end })
end
assert(host:RegisterImportProvider("edit", selfEditing(function()
    assert(host:RemoveImportProvider("edit"))
end)))
assert(app.importProviders:Begin("example.host/edit", "x", function() end))
tick()
assert(host:UpdateImportProvider("edit", wikiProvider()))
assert(#host:GetState().providers == 0 and consistent())
assert(host:RegisterImportProvider("edit", selfEditing(function()
    assert(host:RegisterImportProvider("edit", wikiProvider({ label = "Edit again" })))
end)))
assert(app.importProviders:Begin("example.host/edit", "x", function() end))
tick()
assert(host:RemoveImportProvider("edit"))
assert(host:GetState().providers[1] == "edit" and consistent())
assert(app.importProviders.records["example.host/edit"].label == "Edit again")
assert(host:RemoveImportProvider("edit"))

-- A dead owner's sources cannot start, answer, or deliver
local soloAlive = true
local solo = ImportProviders.new({ isLive = function() return soloAlive end,
    readDraft = TagDraft.Read })
local soloOwner = { id = "example.solo", label = "Solo" }
assert(solo:Register(soloOwner, "s", wikiProvider()))
assert(solo:Begin("example.solo/s", "x", function() deliveries = deliveries + 1 end))
tick()
assert(wikiRequests[#wikiRequests]:Resolve(gearDraft("Solo")))
local soloLate = solo:Begin("example.solo/s", "y", function() deliveries = deliveries + 1 end)
soloAlive = false
local soloCalls = wikiCalls
tick()
assert(wikiCalls == soloCalls and deliveries == 0 and soloLate ~= nil and solo:Begin("example.solo/s", "z", function() end) == nil)
solo:Close()

-- Without a draft reader, sources register but drafts fail once
local unread = ImportProviders.new({ isLive = function() return true end })
local unreadOwner = { id = "example.unread", label = "Unread" }
local unreadResults = {}
assert(unread:Register(unreadOwner, "s", wikiProvider()))
assert(unread:Begin("example.unread/s", "x", function(state, value)
    unreadResults[#unreadResults + 1] = state .. ":" .. value
end))
tick()
local unreadOK, unreadReason = wikiRequests[#wikiRequests]:Resolve(gearDraft("Unread"))
assert(not unreadOK and unreadReason == "unavailable")
assert(select(2, wikiRequests[#wikiRequests]:Resolve(gearDraft("Again"))) == "stale_request")
tick()
assert(#unreadResults == 1 and string.find(unreadResults[1], "^error:") ~= nil)
-- A reader attached later is used by the next request
unread:SetDraftReader(TagDraft.Read)
assert(unread:Begin("example.unread/s", "y", function(state)
    unreadResults[#unreadResults + 1] = state
end))
tick()
assert(wikiRequests[#wikiRequests]:Resolve(gearDraft("Read")))
tick()
assert(unreadResults[2] == "ready")
unread:Close()

-- Shutdown cancels requests, falls back to the share code, and refuses handles
local closingResult
assert(host:RegisterImportProvider("closing", selfEditing(function()
    closingResult = select(2, host:RegisterImportProvider("during_close", wikiProvider()))
end)))
assert(app.importProviders:Begin("example.host/closing", "x", function() deliveries = deliveries + 1 end))
tick()
settings.importSourcePicker:Select("example.wiki/guide", true)
local atShutdown = ask("guide/shutdown")
app.imports:Close()
assert(closingResult == "stale_handle" and next(app.importProviders.records) == nil)
assert(app.importProviders.count == 0 and #app.importProviders.queue == 0)
assert(not atShutdown:IsCurrent() and select(2, atShutdown:Resolve(gearDraft("Late"))) == "stale_request")
assert(settings.source.key == "builtin:code" and sourceKeys(settings) == "builtin:code")
assert(select(2, reloadedWiki:RegisterImportProvider("next", wikiProvider())) == "stale_handle")
assert(select(2, api.RegisterExtension("example.next", "Next")) == "stale_api")
tick()
assert(listenerCount() == 0 and writes == 4 and deliveries == 0)
-- The share code keeps working in the open window
settings.importField:SetText(shareCode("after shutdown"), true)
settings.importButton:Press()
assert(writes == 5 and store.data.tags["after shutdown"] ~= nil)
app.windows:CloseAll()

print("import_providers_test: ok")
