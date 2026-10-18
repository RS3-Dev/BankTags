package.path = "./?.lua;./?/init.lua;" .. package.path

-- Load the built Bank Tags beside the real Bank Core in isolated plugin environments and
-- follow the dependency through every load order: Bank Tags without Core, Core arriving
-- late, Core reloading and unloading, Bank Tags reloading with and without a shared Lua
-- state, and RuneQL present or absent. Each plugin has its own module cache and saved data
-- FAKE HOST: stand-in loader, components, and menus, not the game client

local Harness = require("tools/test_support/tags_harness")

local h = Harness.new("plugin_reload")
h.bankHost:SetItems({ { 1944, 3, "Egg" }, { 1927, 1, "Milk" } })

-- Bank Tags loads without Bank Core: it publishes its own API and says Core is needed
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

-- Core arrives late; the host's dependency update connects Bank Tags and clears the notice
local core = h:LoadCore()
assert(app:IsConnected() and app.bank == core.result)
assert(Harness.Find(panel, "Bank Tags needs Bank Core. Enable Bank Core to use tags in your bank.") == nil)
local session, layout = h:OpenBank()
h:Tick(2)
local tabParent = h:TabParent()
assert(tabParent ~= nil and Harness.Find(tabParent, "New Tag") ~= nil)
-- The listener reported the bank's state, including Core's columns and bounds
assert(app.state ~= nil and app.state.columns ~= nil and app.state.bounds ~= nil)

-- Bank Tags saves under its own keys in its own saved data
assert(app.store:CreateTag("melee"))
assert(h.databases.banktags["banktags:tags:v3:manifest"] ~= nil)
assert(h.databases.bankcore == nil or h.databases.bankcore["banktags:tags:v3:manifest"] == nil)
for key in pairs(h.databases.banktags) do assert(string.sub(key, 1, 9) == "banktags:", key) end

-- Core reloads: its old session closes Bank Tags' column, and Bank Tags reconnects to the
-- new API through the host's documented PluginDependencyUpdate
local oldAPI = core.result
h.host:Reload("bankcore", { shutdown = true, notify = true, reinject = true })
assert(tabParent.destroyed and not oldAPI.GetState().running)
assert(app:IsConnected() and app.bank == core.result and app.bank ~= oldAPI)
session, layout = h:OpenBank()
h:Tick(2)
tabParent = h:TabParent()
assert(tabParent ~= nil and not tabParent.destroyed and Harness.Find(tabParent, "Melee") ~= nil)

-- A host that clones exports hands Bank Tags a copy of Core's API; a reload still connects
h.host:Reload("bankcore", { shutdown = true })
h.host.exports.bankcore = Harness.CloneAPI(core.result)
h.host:Notify("bankcore", true, true)
assert(app:IsConnected() and app.bank == h.host.exports.bankcore)
session, layout = h:OpenBank()
h:Tick(2)
assert(h:TabParent() ~= nil)

-- Core unloads: Bank Tags lets go and says Core is needed again; its tags stay saved
h.host:Unload("bankcore")
assert(not app:IsConnected() and app.handle == nil)
assert(Harness.Find(panel, "Bank Tags needs Bank Core. Enable Bank Core to use tags in your bank.") ~= nil)
assert(app.store.data.tags.melee ~= nil)
h:LoadCore()
assert(app:IsConnected())
session, layout = h:OpenBank()
h:Tick(2)
tabParent = h:TabParent()

-- Bank Tags reloads in the same Lua state: the previous session shuts down, its column
-- closes, and the new session takes the owner ID and reads the same saved tags
h.host:Reload("banktags", { freshEnvironment = true })
local reloaded = h:App()
assert(reloaded ~= app and app.shutDown and reloaded:IsConnected())
-- The old copy's import API closed with it; plugins register again with the new one
assert(not importer:GetState().live and not api.GetState().running)
assert(select(2, importer:RegisterImportProvider("again", { label = "Guide", input = "text",
    request = function() end })) == "stale_handle")
assert(h.tags.result.GetState().running and h.tags.result ~= api)
assert(reloaded.store.data.tags.melee ~= nil)
assert(tabParent.destroyed)
h:Tick(2)
assert(h:TabParent() ~= nil and Harness.Find(h:TabParent(), "Melee") ~= nil)
-- The old copy, told Core loaded again, stays shut down and takes nothing back
rawget(tags.env, "PluginDependencyUpdate")({ pluginIdentifier = "bankcore", enabled = true })
assert(reloaded:IsConnected() and not app:IsConnected())

-- Unloading Bank Tags leaves no column, listener, or subscription behind in Core
h.host:Unload("banktags")
assert(h:TabParent() == nil)
for _, subscription in ipairs(h.host:SubscriptionsOf("banktags")) do
    error("Bank Tags left " .. subscription .. " subscribed")
end
assert(not reloaded:IsConnected() and reloaded.imports.closed)
h.host:Unload("bankcore")

-- Separate Lua states: a newer copy takes the owner ID while the older one keeps running.
-- The older copy, told Core loaded, sees it was replaced and stays idle: no ping-pong
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

-- RuneQL is optional: without it the catalog is limited to the bank and exact lookups;
-- with it the injected global's catalog is searched
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

print("plugin_reload_test: ok")
