package.path = "./?.lua;./?/init.lua;" .. package.path

-- Change Bank Tags' preferences on its own plugin panel
-- Each saves under Bank Tags' key, applies at once, and reverts if refused
-- FAKE HOST: stand-in loader, components, and menus, not the game client

local Harness = require("tools/test_support/tags_harness")
local h = Harness.new("bank_settings")
h.bankHost:SetItems({ { 4151, 1, "Abyssal whip" }, { 385, 20, "Shark" } })
h:LoadCore()
h:LoadTags()
local app = h:App()
h:OpenBank()
h:Tick(2)
local SETTINGS_KEY = "banktags:settings:v1"

-- Draw Bank Tags' plugin panel as the host does
local function openPanel()
    local parent = ui.Layer.new(nil)
    parent:SetSize(300, 400)
    h.hostSubscriptions.ContentLayerReady.banktags_content({ component = parent })
    return assert(app.settingsSection), parent
end

-- Import/Share opens from the Tags tab
assert(app.windows.importShare == nil)
for _, control in ipairs(app.tab.controls.owned) do
    if control.spriteName == "EXPORT" then control.action(control, false) end
end
assert(app.windows.importShare ~= nil)
app.windows:Close("importShare")

-- The panel shows Bank Tags' preferences under its name
assert(app.settingsSection == nil)
local section, parent = openPanel()
assert(Harness.Find(parent, "Bank Tags") ~= nil)

-- Each preference saves under Bank Tags' key and applies at once
assert(app.store:CreateTag("melee", 4151))
app:Changed()
section.controls.showTagSprites:SetSelected("showTagSprites", false, true)
assert(app.settings.showTagSprites == false and h.databases.banktags[SETTINGS_KEY].showTagSprites == false)
section.placement:Select("fill", true)
assert(app.settings.preserveTagLayout == false and app.store.preserveTagLayout == false)
assert(h.databases.banktags[SETTINGS_KEY].preserveTagLayout == false)
-- Arrow-key movement starts off, says the arrows also move the camera, and saves like the others
assert(app.settings.arrowKeyMovement == false and not section.controls.arrowKeyMovement:IsSelected("arrowKeyMovement"))
assert(Harness.Find(parent, "Arrow keys also move the camera.") ~= nil)
section.controls.arrowKeyMovement:SetSelected("arrowKeyMovement", true, true)
assert(app.settings.arrowKeyMovement == true and h.databases.banktags[SETTINGS_KEY].arrowKeyMovement == true)
section.controls.enableDebug:SetSelected("enableDebug", true, true)
assert(h.databases.banktags[SETTINGS_KEY].enableDebug == true and section.status.hidden)
-- Bank Core's saved data holds none of them
assert(h.databases.bankcore == nil or h.databases.bankcore[SETTINGS_KEY] == nil)

-- A refused save puts each control back and says so; the saved value is unchanged
h.host.rejectWrites = true
section.controls.showTagSprites:SetSelected("showTagSprites", true, true)
assert(not section.controls.showTagSprites:IsSelected("showTagSprites") and not app.settings.showTagSprites)
assert(not section.status.hidden and section.status.content == "Could not save the setting.")
section.placement:Select("preserve", true)
assert(section.placement:GetSelectedID() == "fill" and app.store.preserveTagLayout == false)
section.controls.arrowKeyMovement:SetSelected("arrowKeyMovement", false, true)
assert(section.controls.arrowKeyMovement:IsSelected("arrowKeyMovement") and app.settings.arrowKeyMovement == true)
assert(h.databases.banktags[SETTINGS_KEY].arrowKeyMovement == true)
h.host.rejectWrites = false
section.controls.showTagSprites:SetSelected("showTagSprites", true, true)
assert(app.settings.showTagSprites and section.status.hidden)

-- A new panel replaces the old one and shows the saved values in new controls
local previous = section
section = openPanel()
assert(previous.destroyed and section ~= previous)
assert(section.controls.showTagSprites:IsSelected("showTagSprites") and section.placement:GetSelectedID() == "fill")
assert(section.controls.enableDebug:IsSelected("enableDebug"))
assert(section.controls.arrowKeyMovement:IsSelected("arrowKeyMovement"))

-- The panel needs no Bank Core: it stays and still saves while Core is gone
h.host:Unload("bankcore")
assert(app.settingsSection == section and not section.destroyed)
section.controls.showTagSprites:SetSelected("showTagSprites", false, true)
assert(h.databases.banktags[SETTINGS_KEY].showTagSprites == false)
section.controls.showTagSprites:SetSelected("showTagSprites", true, true)
h:LoadCore()
assert(h:Connected())

-- Bank Tags unloads, destroying the panel; a reload reads the saved choice back
h.host:Unload("banktags")
assert(section.destroyed and app.settingsSection == nil)
assert(h.hostSubscriptions.ContentLayerReady.banktags_content == nil)
h:LoadTags()
app = h:App()
assert(app.settings.arrowKeyMovement == true)
section = openPanel()
assert(section.controls.arrowKeyMovement:IsSelected("arrowKeyMovement"))

print("bank_settings_test: ok")
