package.path = "./?.lua;./?/init.lua;" .. package.path

-- Run every plugin on plain data clones of the others' exports
-- Bank Tags connects and reloads through Core's injected clone
-- FAKE HOST: stand-in loader, clone, components, and menus, not the game client

local Harness = require("tools/test_support/tags_harness")

local h = Harness.new("cloned_exports", { separateGlobals = true, cloneExports = true })
h.bankHost:SetItems({ { 1944, 3, "Egg" }, { 1927, 1, "Milk" } })

-- Bank Tags has only the injected clone of Core's API
local core = h:LoadCore()
local tags = h:LoadTags()
local app = h:App()
local coreClone = rawget(tags.env, "bankcore")
assert(rawget(tags.env._G, "__bankcore_api") == nil)
assert(coreClone ~= core.result and getmetatable(coreClone) == nil)
assert(h:Connected())

-- Its tab mounts and a tag's page opens
assert(app.store:CreateTag("melee"))
app:Changed()
local _, layout = h:OpenBank()
h:Tick(2)
local tabParent = h:TabParent()
assert(tabParent ~= nil and Harness.Find(tabParent, "Melee") ~= nil)
assert(app:ShowTag("melee") and app:ShownTag() == "melee" and layout.shownPage ~= nil)

-- Core reloads and Bank Tags reconnects through a fresh clone
h.host:Reload("bankcore", { shutdown = true, notify = true, reinject = true })
assert(tabParent.destroyed and select(2, coreClone.Register({ id = "late", name = "Late" })) == "stopped")
local freshClone = rawget(tags.env, "bankcore")
assert(freshClone ~= coreClone and freshClone ~= core.result)
assert(h:Connected())
_, layout = h:OpenBank()
h:Tick(2)
assert(h:TabParent() ~= nil and app:ShowTag("melee") and app:ShownTag() == "melee")

-- Bank Tags reloads and reconnects through Core's injected clone.
h.host:Reload("banktags", { shutdown = true, freshEnvironment = true })
assert(h:Connected() and app.shutDown)
assert(h.tags.result == nil and rawget(h.tags.env._G, "__banktags_api") == nil)
local reloaded = h:App()
h:OpenBank()
h:Tick(2)
assert(reloaded.store.data.tags.melee ~= nil and reloaded:ShowTag("melee"))
h.host:Unload("banktags")
h.host:Unload("bankcore")

print("cloned_exports_test: ok")
