package.path = "./?.lua;./?/init.lua;" .. package.path

-- Load Bank Core, the built Bank Tags, and a small import-source plugin where every injected
-- export is an ordinary data clone and no plugin sees another's globals, so each has only
-- its clone to use: Bank Tags connects to Core's and shows a tag, and the source plugin adds
-- an import source through Bank Tags' that the Import window lists. Reloads inject fresh
-- clones. How the live client copies an export is not shown here, only that a plain copy works
-- FAKE HOST: stand-in loader, clone, components, and menus, not the game client

local Harness = require("tools/test_support/tags_harness")

local h = Harness.new("cloned_exports", { separateGlobals = true, cloneExports = true })
h.bankHost:SetItems({ { 1944, 3, "Egg" }, { 1927, 1, "Milk" } })

-- Bank Tags has only the injected clone of Core's API: no published copy is in reach
local core = h:LoadCore()
local tags = h:LoadTags()
local app = h:App()
local coreClone = rawget(tags.env, "bankcore")
assert(rawget(tags.env._G, "__bankcore_api") == nil)
assert(coreClone ~= core.result and getmetatable(coreClone) == nil)
assert(app:IsConnected() and app.bank == coreClone)

-- Its tab mounts and a tag's page opens
assert(app.store:CreateTag("melee"))
app:Changed()
local _, layout = h:OpenBank()
h:Tick(2)
local tabParent = h:TabParent()
assert(tabParent ~= nil and Harness.Find(tabParent, "Melee") ~= nil)
assert(app:ShowTag("melee") and layout.pageState.view.key == "tag:melee")

-- Core reloads and the host injects a fresh clone, which Bank Tags reconnects through
h.host:Reload("bankcore", { shutdown = true, notify = true, reinject = true })
assert(tabParent.destroyed and not coreClone.GetState().running)
local freshClone = rawget(tags.env, "bankcore")
assert(freshClone ~= coreClone and freshClone ~= core.result)
assert(app:IsConnected() and app.bank == freshClone)
_, layout = h:OpenBank()
h:Tick(2)
assert(h:TabParent() ~= nil and app:ShowTag("melee") and layout.pageState.view.key == "tag:melee")

-- A plugin that requires Bank Tags adds an import source using only its injected clone
local folder = h.out .. "/importer"
os.execute('mkdir "' .. string.gsub(folder, "/", "\\") .. '" 2>nul')
local file = assert(io.open(folder .. "/main.lua", "w"))
file:write([[
local Importer = {}
function Importer.Connect()
    local handle, reason = banktags.RegisterExtension("example.importer", "Importer")
    if handle == nil then return nil, reason end
    local ok, failure = handle:RegisterImportProvider("guide", { label = "Guide", input = "text",
        request = function() end })
    if not ok then return nil, failure end
    return handle
end
Importer.handle = Importer.Connect()
return Importer
]])
file:close()
local importer = h.host:Load("importer", folder,
    { name = "importer", dependencies = { banktags = true }, optional = {} })
local tagsClone = rawget(importer.env, "banktags")
assert(rawget(importer.env._G, "__banktags_api") == nil)
assert(tagsClone ~= tags.result and getmetatable(tagsClone) == nil)
local first = importer.result.handle
assert(first ~= nil and table.concat(first:GetState().providers, ",") == "guide")

-- Bank Tags' Import window lists the source
app.windows:OpenImportShare()
local window = app.windows.importShare
local function sourceKeys()
    local keys = {}
    for index, entry in ipairs(window.importSourcePicker.entries) do keys[index] = entry.id end
    return table.concat(keys, " ")
end
assert(sourceKeys() == "builtin:code example.importer/guide")

-- Changing the clone's limits changes no limit Bank Tags enforces
local ImportAPI = h:TagsModule("banktags/imports/import_api")
tagsClone.LIMITS.owners = 0
assert(ImportAPI.LIMITS.owners == 32 and tags.result.LIMITS.owners == 32)

-- Registering again replaces the first handle, which then refuses every call
local second = assert(importer.result.Connect())
assert(not first:GetState().live and second:GetState().live)
assert(select(2, first:RegisterImportProvider("again", { label = "Guide", input = "text",
    request = function() end })) == "stale_handle")
assert(sourceKeys() == "builtin:code example.importer/guide")
assert(second:Dispose() and not second:GetState().live)
assert(sourceKeys() == "builtin:code")

-- Bank Tags reloads; the source plugin, told so, gets a fresh clone of the new API
h.host:Reload("banktags", { shutdown = true, freshEnvironment = true, notify = true,
    reinject = true, notifyRequired = true })
local reloadedClone = rawget(importer.env, "banktags")
assert(reloadedClone ~= tagsClone and not tagsClone.GetState().running)
assert(reloadedClone.GetState().running)
assert(importer.result.Connect() ~= nil)
local reloaded = h:App()
reloaded.windows:OpenImportShare()
window = reloaded.windows.importShare
assert(sourceKeys() == "builtin:code example.importer/guide")

h.host:Unload("importer")
h.host:Unload("banktags")
h.host:Unload("bankcore")

print("cloned_exports_test: ok")
