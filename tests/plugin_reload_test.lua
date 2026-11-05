package.path = "./?.lua;./?/init.lua;" .. package.path

-- Check required imports, reloads, and shutdown cleanup
-- FAKE HOST: stand-in loader, components, and menus, not the game client

local Harness = require("tools/test_support/tags_harness")

local h = Harness.new("plugin_reload")
h.bankHost:SetItems({ { 1944, 3, "Egg" }, { 1927, 1, "Milk" } })

-- Required dependencies load before Bank Tags
h.host.sharedGlobals.__banktags_api = { RegisterExtension = function() error("stale import API") end }
local core = h:LoadCore()
local tags = h:LoadTags()
local app = h:App()
assert(app ~= nil and h:Connected())
local firstDependencyUpdate = rawget(tags.env, "PluginDependencyUpdate")
assert(type(rawget(tags.env, "PluginDependencyUpdate")) == "function")
assert(rawget(tags.env, "PluginOptionalDependencyChanged") == nil)
assert(tags.result == nil and rawget(tags.env._G, "__banktags_api") == nil)
-- No Core module was loaded into Bank Tags' cache
for moduleName in pairs(tags.env.package.loaded) do
    assert(string.sub(moduleName, 1, 19) == "resources/banktags/", moduleName .. " is not a Bank Tags module")
end

local session, layout = h:OpenBank()
h:Tick(2)
local tabParent = h:TabParent()
assert(tabParent ~= nil and Harness.Find(tabParent, "New Tag") ~= nil)
-- Core reports the open bank's bounds and columns
local bounds = app.windows:BankBounds()
assert(bounds ~= nil and bounds.columns ~= nil and bounds.width ~= nil)

-- Bank Tags saves under its own keys in its own saved data
assert(app.store:CreateTag("melee"))
assert(h.databases.banktags["banktags:tags:v4:manifest"] ~= nil)
assert(h.databases.bankcore == nil or h.databases.bankcore["banktags:tags:v4:manifest"] == nil)
for key in pairs(h.databases.banktags) do assert(string.sub(key, 1, 9) == "banktags:", key) end

-- Required imports refresh when Bank Tags reloads after Core
local oldAPI = core.result
h.host:Reload("bankcore", { shutdown = true, notify = true, reinject = true })
assert(tabParent.destroyed and select(2, oldAPI.Register({ id = "late", name = "Late" })) == "stopped")
assert(rawget(tags.env, "bankcore") == oldAPI)
local oldApp = app
h.host:Reload("banktags", { shutdown = true, freshEnvironment = true })
app = h:App()
assert(oldApp.shutDown and oldApp.ext == nil and app ~= oldApp)
assert(h:Connected() and core.result ~= oldAPI)
session, layout = h:OpenBank()
h:Tick(2)
tabParent = h:TabParent()
assert(tabParent ~= nil and not tabParent.destroyed and Harness.Find(tabParent, "Melee") ~= nil)

-- Reloading also connects through a cloned Core API
h.host:Reload("bankcore", { shutdown = true })
h.host.exports.bankcore = require("tools/test_support/fake_plugin_host").Clone(core.result)
h.host:Reload("banktags", { shutdown = true })
app = h:App()
assert(h:Connected())
session, layout = h:OpenBank()
h:Tick(2)
assert(h:TabParent() ~= nil)

-- Stop Bank Tags before unloading its required dependency
h.host:Unload("banktags")
h.host:Unload("bankcore")
assert(app.ext == nil)
assert(app.store.data.tags.melee ~= nil)
h:LoadCore()
tags = h:LoadTags()
app = h:App()
assert(h:Connected())
session, layout = h:OpenBank()
h:Tick(2)
tabParent = h:TabParent()

-- Bank Tags reloads in the same Lua state, taking the owner ID back
h.host:Reload("banktags", { freshEnvironment = true })
local reloaded = h:App()
assert(reloaded ~= app and app.shutDown and app.ext == nil and h:Connected())
assert(h.tags.result == nil and rawget(h.tags.env._G, "__banktags_api") == nil)
assert(reloaded.store.data.tags.melee ~= nil)
assert(tabParent.destroyed)
h:Tick(2)
assert(h:TabParent() ~= nil and Harness.Find(h:TabParent(), "Melee") ~= nil)
-- Told Core loaded again, the old copy stays shut down
firstDependencyUpdate({ pluginIdentifier = "bankcore", enabled = true })
assert(h:Connected() and app.ext == nil)

-- A reload that keeps the module cache still runs the new modules
local cachedApp = h:TagsModule("banktags/app")
local cachedDebugLog = h:TagsModule("banktags/core/debug_log")
h.host:Reload("banktags")
local hotReloaded = h:App()
assert(hotReloaded ~= reloaded and reloaded.shutDown and h:Connected())
assert(h:TagsModule("banktags/app") ~= cachedApp and getmetatable(hotReloaded) ~= getmetatable(reloaded))
assert(h:TagsModule("banktags/core/debug_log") == cachedDebugLog)
reloaded = hotReloaded
h:Tick(2)
assert(h:TabParent() ~= nil)

-- Unloading Bank Tags leaves nothing behind in Core
h.host:Unload("banktags")
assert(h:TabParent() == nil)
for _, subscription in ipairs(h.host:SubscriptionsOf("banktags")) do
    error("Bank Tags left " .. subscription .. " subscribed")
end
assert(reloaded.ext == nil and reloaded.shutDown)
h.host:Unload("bankcore")

-- In its own Lua state, Bank Tags connects as before
local split = Harness.new("plugin_reload_split", { separateGlobals = true })
split.bankHost:SetItems({ { 1944, 3, "Egg" } })
split:LoadCore()
local first = split:LoadTags()
assert(split:Connected())

-- The stand-in permits missing imports to exercise limited search
local Catalog = split:TagsModule("banktags/tags/catalog")
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
assert(not Catalog.IsFull(), "required dependencies receive no optional-change notification")
split.host:Reload("banktags", { shutdown = true, freshEnvironment = true })
Catalog = split:TagsModule("banktags/tags/catalog")
assert(Catalog.IsFull())
results, _, limited = Catalog.Find("eg", 10, {})
assert(not limited and found == 1 and results[1].objectId == 1944 and results[1].displayName == "Egg (eg)")

-- Explicit callbacks still stop reads from stale RuneQL exports
local dependencyUpdate = rawget(first.env, "PluginDependencyUpdate")
dependencyUpdate({ pluginIdentifier = "runeql", enabled = false })
assert(rawget(first.env, "runeql") == runeqlCatalog and not Catalog.IsFull())
results, _, limited = Catalog.Find("Egg", 10, { { objectID = 1944 } })
assert(limited and found == 1 and #results == 1)
dependencyUpdate({ pluginIdentifier = "runeql", enabled = true })
assert(Catalog.IsFull())

print("plugin_reload_test: ok")
