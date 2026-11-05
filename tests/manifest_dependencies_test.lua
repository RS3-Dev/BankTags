package.path = "./?.lua;./?/init.lua;" .. package.path

-- The client injects required dependencies from requiredDependencies, not dependencies
-- FAKE HOST: the dependency table is adapted for Core's older stand-in loader
local Harness = require("tools/test_support/tags_harness")
local h = Harness.new("manifest_dependencies")
h.bankHost:SetItems({ { 4151, 1, "Abyssal whip" } })
h:LoadCore()
h:LoadTags()
assert(type(h.tags.env.prettyui) == "table",
    "Bank Tags must declare PrettyUI under requiredDependencies so the client injects it")
local app = h:App()
assert(app.ext ~= nil)
h:OpenBank()
h:Tick(2)
assert(app.tab.controls ~= nil and app.tab.controls.newTagButton ~= nil,
    "the registered Bank Tags sidebar must mount with its required UI dependency")

print("manifest_dependencies_test: ok")
