package.path = "./?.lua;./?/init.lua;" .. package.path

-- Load the built Bank Tags beside Bank Core in every load order
-- FAKE HOST: stand-in loader, components, and menus, not the game client

local Harness = require("tools/test_support/tags_harness")

local h = Harness.new("plugin_reload")
h.bankHost:SetItems({ { 1944, 3, "Egg" }, { 1927, 1, "Milk" } })

-- Bank Tags loads without Bank Core and says Core is needed
local tags = h:LoadTags()
local app = h:App()
assert(app ~= nil and not app:IsConnected())
assert(type(rawget(tags.env, "PluginDependencyUpdate")) == "function")
assert(rawget(tags.env, "PluginOptionalDependencyChanged") == nil)
local api = tags.result
assert(type(api.RegisterExtension) == "function" and api.GetState().running)
assert(rawget(tags.env._G, "__banktags_api") == api)
local panel = h:OpenContentPanel()
assert(Harness.Find(panel, "Bank Tags needs Bank Core. Enable Bank Core to use tags in your bank.") ~= nil)
-- Another plugin can add an import source without Bank Core; the window lists it
local importer = assert(api.RegisterExtension("example.guides", "Guides"))
assert(importer:RegisterImportProvider("guide", { label = "Guide", input = "text",
    request = function() end }))
assert(table.concat(importer:GetState().providers, ",") == "guide")
-- No Core module was loaded into Bank Tags' cache
for moduleName in pairs(tags.env.package.loaded) do
    assert(string.sub(moduleName, 1, 9) == "banktags/", moduleName .. " is not a Bank Tags module")
end

-- Core arrives late, and the dependency update connects Bank Tags
local core = h:LoadCore()
assert(app:IsConnected() and app.bank == core.result)
assert(Harness.Find(panel, "Bank Tags needs Bank Core. Enable Bank Core to use tags in your bank.") == nil)
local session, layout = h:OpenBank()
h:Tick(2)
local tabParent = h:TabParent()
assert(tabParent ~= nil and Harness.Find(tabParent, "New Tag") ~= nil)
-- The listener reported Core's state, columns, and bounds
assert(app.state ~= nil and app.state.columns ~= nil and app.state.bounds ~= nil)

-- Bank Tags saves under its own keys in its own saved data
assert(app.store:CreateTag("melee"))
assert(h.databases.banktags["banktags:tags:v3:manifest"] ~= nil)
assert(h.databases.bankcore == nil or h.databases.bankcore["banktags:tags:v3:manifest"] == nil)
for key in pairs(h.databases.banktags) do assert(string.sub(key, 1, 9) == "banktags:", key) end

-- Core reloads, and Bank Tags reconnects to the new API
local oldAPI = core.result
h.host:Reload("bankcore", { shutdown = true, notify = true, reinject = true })
assert(tabParent.destroyed and not oldAPI.GetState().running)
assert(app:IsConnected() and app.bank == core.result and app.bank ~= oldAPI)
session, layout = h:OpenBank()
h:Tick(2)
tabParent = h:TabParent()
assert(tabParent ~= nil and not tabParent.destroyed and Harness.Find(tabParent, "Melee") ~= nil)

-- A reload still connects through a cloned Core API
h.host:Reload("bankcore", { shutdown = true })
h.host.exports.bankcore = require("tools/test_support/fake_plugin_host").Clone(core.result)
h.host:Notify("bankcore", true, true)
assert(app:IsConnected() and app.bank == h.host.exports.bankcore)
session, layout = h:OpenBank()
h:Tick(2)
assert(h:TabParent() ~= nil)

-- Core unloads; Bank Tags lets go and its tags stay saved
h.host:Unload("bankcore")
assert(not app:IsConnected() and app.handle == nil)
assert(Harness.Find(panel, "Bank Tags needs Bank Core. Enable Bank Core to use tags in your bank.") ~= nil)
assert(app.store.data.tags.melee ~= nil)
h:LoadCore()
assert(app:IsConnected())
session, layout = h:OpenBank()
h:Tick(2)
tabParent = h:TabParent()

-- Bank Tags reloads in the same Lua state, taking the owner ID back
h.host:Reload("banktags", { freshEnvironment = true })
local reloaded = h:App()
assert(reloaded ~= app and app.shutDown and reloaded:IsConnected())
-- The old import API closed; plugins register again
assert(not importer:GetState().live and not api.GetState().running)
assert(select(2, importer:RegisterImportProvider("again", { label = "Guide", input = "text",
    request = function() end })) == "stale_handle")
assert(h.tags.result.GetState().running and h.tags.result ~= api)
assert(reloaded.store.data.tags.melee ~= nil)
assert(tabParent.destroyed)
h:Tick(2)
assert(h:TabParent() ~= nil and Harness.Find(h:TabParent(), "Melee") ~= nil)
-- Told Core loaded again, the old copy stays shut down
rawget(tags.env, "PluginDependencyUpdate")({ pluginIdentifier = "bankcore", enabled = true })
assert(reloaded:IsConnected() and not app:IsConnected())

-- A reload that keeps the module cache still runs the new modules
local cachedApp = h:TagsModule("banktags/app")
h.host:Reload("banktags")
local hotReloaded = h:App()
assert(hotReloaded ~= reloaded and reloaded.shutDown and hotReloaded:IsConnected())
assert(h:TagsModule("banktags/app") ~= cachedApp and getmetatable(hotReloaded) ~= getmetatable(reloaded))
assert(h:TagsModule("banktags/core/debug_log") ~= nil)
reloaded = hotReloaded
h:Tick(2)
assert(h:TabParent() ~= nil)

-- Unloading Bank Tags leaves nothing behind in Core
h.host:Unload("banktags")
assert(h:TabParent() == nil)
for _, subscription in ipairs(h.host:SubscriptionsOf("banktags")) do
    error("Bank Tags left " .. subscription .. " subscribed")
end
assert(not reloaded:IsConnected() and reloaded.imports.closed)
h.host:Unload("bankcore")

-- Across separate Lua states, the replaced copy stays idle
local split = Harness.new("plugin_reload_split", { separateGlobals = true })
split.bankHost:SetItems({ { 1944, 3, "Egg" } })
split:LoadCore()
local first = split:LoadTags()
local firstApp = rawget(first.env, "__banktags_session")
assert(firstApp:IsConnected())
local second = split.host:Load("banktags_copy", split.tagsFolder,
    { name = "banktags", dependencies = {}, optional = { bankcore = true, runeql = true } })
local secondApp = rawget(second.env, "__banktags_session")
assert(secondApp:IsConnected() and not firstApp:IsConnected())
rawget(first.env, "PluginDependencyUpdate")({ pluginIdentifier = "bankcore", enabled = true })
assert(firstApp.retired and not firstApp:IsConnected() and secondApp:IsConnected())
rawget(second.env, "PluginDependencyUpdate")({ pluginIdentifier = "bankcore", enabled = true })
assert(secondApp:IsConnected())
local firstPanel = ui.Layer.new(nil)
firstPanel:SetSize(300, 400)
firstApp:CreatePanel(firstPanel)
assert(Harness.Find(firstPanel, "A newer copy of Bank Tags took over; this copy is idle.") ~= nil)

-- Without RuneQL the catalog is limited; with it RuneQL is searched
local Catalog = split.tags.env.package.loaded["banktags/tags/catalog"]
assert(not Catalog.IsFull())
local results, _, limited = Catalog.Find("Egg", 10, { { objectID = 1944 } })
assert(limited and #results == 1 and results[1].objectId == 1944)
local found = 0
local runeqlCatalog = { Catalog = { Find = function(query)
    found = found + 1
    return { { configName = "egg", displayName = "Egg (" .. query .. ")" } }, 1
end } }
config.Obj.egg = { id = 1944 }
split.host.exports.runeql = runeqlCatalog
split.host:Notify("runeql", true, true)
assert(Catalog.IsFull())
results, _, limited = Catalog.Find("eg", 10, {})
assert(not limited and found == 1 and results[1].objectId == 1944 and results[1].displayName == "Egg (eg)")

-- RuneQL unloads, and Bank Tags stops reading its leftover global
split.host:Notify("runeql", false, false)
assert(rawget(first.env, "runeql") == runeqlCatalog and not Catalog.IsFull())
results, _, limited = Catalog.Find("Egg", 10, { { objectID = 1944 } })
assert(limited and found == 1 and #results == 1)
split.host:Notify("runeql", true, true)
assert(Catalog.IsFull())

print("plugin_reload_test: ok")
