package.path = "./?.lua;./?/init.lua;" .. package.path

-- The client injects required dependencies from requiredDependencies, not dependencies
-- FAKE HOST: the dependency table is adapted for Core's older stand-in loader
local Harness = require("tools/test_support/tags_harness")
local h = Harness.new("manifest_dependencies")
h.bankHost:SetItems({ { 4151, 1, "Abyssal whip" } })
local searches = 0
config.Obj.abyssal_whip = { id = 4151 }
h.host.exports.runeql = { Catalog = { Find = function(query)
    assert(query == "whip")
    searches = searches + 1
    return { { configName = "abyssal_whip", displayName = "Abyssal whip" } }, 1
end } }
h:LoadCore()
h:LoadTags()
assert(type(h.tags.env.prettyui) == "table",
    "Bank Tags must declare PrettyUI under requiredDependencies so the client injects it")
assert(type(h.tags.env.bankcore) == "table" and type(h.tags.env.runeql) == "table",
    "Bank Core and RuneQL must be injected as required dependencies")
assert(next(h.tags.manifest.optional) == nil, "Bank Tags must not declare optional dependencies")
local results, _, limited = h:TagsModule("banktags/tags/catalog").Find("whip", 40, {})
assert(searches == 1 and not limited and results[1].objectId == 4151,
    "catalog search must use the injected RuneQL dependency")
local app = h:App()
assert(app.ext ~= nil)
h:OpenBank()
h:Tick(2)
assert(app.tab.controls ~= nil and app.tab.controls.newTagButton ~= nil,
    "the registered Bank Tags sidebar must mount with its required UI dependency")

print("manifest_dependencies_test: ok")
