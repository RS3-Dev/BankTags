package.path = "./?.lua;./?/init.lua;" .. package.path

-- Change Bank Tags' preferences in Bank Core's settings window
-- Each saves under Bank Tags' key, applies at once, and reverts if refused
-- FAKE HOST: stand-in loader, components, and menus, not the game client

local Harness = require("tools/test_support/tags_harness")
local h = Harness.new("bank_settings")
h.bankHost:SetItems({ { 4151, 1, "Abyssal whip" }, { 385, 20, "Shark" } })
h:LoadCore()
h:LoadTags()
local app = h:App()
local session, layout = h:OpenBank()
h:Tick(2)
local SETTINGS_KEY = "banktags:settings:v1"

-- Open the settings window from the gear and choose Bank Tags' section
local function openSection()
    if not session.bankSettings:IsOpen() then layout.tabRail.settingsButton.root.hooks.pressed() end
    assert(session.bankSettings.window.nav:Click("banktags"))
    return assert(app.settingsSection)
end

-- List the settings window's section labels
local function sectionLabels()
    local labels = {}
    for _, row in ipairs(session.bankSettings.window.nav.rows) do labels[#labels + 1] = row.entry.label end
    return table.concat(labels, " | ")
end

-- Bank Tags has no plugin panel; Import/Share opens from the Tags tab
local manifest = assert(io.open(h.tagsFolder .. "/plugin.json", "rb"))
assert(string.find(manifest:read("a"), '"hasRibbonIcon": false', 1, true))
manifest:close()
for _, subscription in ipairs(h.host:SubscriptionsOf("banktags")) do
    assert(string.sub(subscription, 1, 18) ~= "ContentLayerReady.", subscription .. " is a plugin panel")
end
assert(app.windows.importShare == nil)
for _, control in ipairs(app.tab.controls.owned) do
    if control.spriteName == "EXPORT" then control.action(control, false) end
end
assert(app.windows.importShare ~= nil)
app.windows:Close("importShare")

-- Bank Tags has one section, after Core's, under its owner label
layout.tabRail.settingsButton.root.hooks.pressed()
assert(sectionLabels() == "Bank Core | Bank Tags", sectionLabels())
assert(app.settingsSection == nil)
local section = openSection()
local parent = session.bankSettings.shown.values.parent
assert(Harness.Find(parent, "Bank Tags") ~= nil)

-- Each preference saves under Bank Tags' key and applies at once
assert(app.store:CreateTag("melee", 4151))
app:Changed()
section.controls.showTagSprites:SetSelected("showTagSprites", false, true)
assert(app.settings.showTagSprites == false and h.databases.banktags[SETTINGS_KEY].showTagSprites == false)
section.placement:Select("fill", true)
assert(app.settings.preserveTagLayout == false and app.store.preserveTagLayout == false)
assert(h.databases.banktags[SETTINGS_KEY].preserveTagLayout == false)
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
h.host.rejectWrites = false
section.controls.showTagSprites:SetSelected("showTagSprites", true, true)
assert(app.settings.showTagSprites and section.status.hidden)

-- Reopening the section shows the saved values in new controls
session.bankSettings:Close("closed")
assert(app.settingsSection == nil)
section = openSection()
assert(section.controls.showTagSprites:IsSelected("showTagSprites") and section.placement:GetSelectedID() == "fill")
assert(section.controls.enableDebug:IsSelected("enableDebug"))

-- Bank Core unloads, closing the section; it returns on reload
h.host:Unload("bankcore")
assert(app.settingsSection == nil and section.destroyed)
h:LoadCore()
assert(app:IsConnected())
session, layout = h:OpenBank()
h:Tick(2)
section = openSection()
assert(section.controls.showTagSprites:IsSelected("showTagSprites"))

-- Bank Tags unloads, so the window falls back to Core's section
h.host:Unload("banktags")
assert(section.destroyed and app.settingsSection == nil)
assert(sectionLabels() == "Bank Core" and session.coreSettings ~= nil)

print("bank_settings_test: ok")
