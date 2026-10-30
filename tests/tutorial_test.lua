package.path = "./?.lua;./?/init.lua;" .. package.path

-- Walk through real tag actions in the stand-in host
local Harness = require("tools/test_support/tags_harness")
local h = Harness.new("tutorial")
h.bankHost:SetItems({ { 385, 20, "Shark" } })
local core = h:LoadCore()
-- Rail entries are ordered by ID, so this column comes before Bank Tags'
assert(core.result.Register({ id = "aa.before", name = "Other", icon = "STAR",
    column = { mount = function() end } }))
local tags = h:LoadTags()
local cues, stops = 0, 0
tags.env.Plugin = { resources = { tutorial_step = "step-cue" } }
tags.env.audio = {
    SoundPlaybackParams = { new = function() return {} end },
    Play = function(resource, params)
        assert(resource == "step-cue" and params.volume == 0.25)
        cues = cues + 1
        return { Stop = function() stops = stops + 1 end }
    end,
}
local app = h:App()
local session, layout = h:OpenBank()
layout:SetSidebarMode("__bankutils_ext_tab:aa.before")
h:Tick(2)
local tour = app.tutorial
assert(not tour.active and cues == 0, "the guide waits until the tag list is open")
assert(#app.store:AllTags() == 0, "the tour creates no sample data")
assert(app.tab.controls == nil)
local rail = layout.tabRail
for slot, button in ipairs(rail.buttons) do
    if rail.tabs[rail.view.first + slot - 1].id == "__bankutils_ext_tab:banktags" then
        -- Core selects a rail icon when its press is released
        h:PointAt(button.root, 5, 5)
        button.root.hooks.click()
        button.root.hooks.release()
        break
    end
end
h:Tick(5)
assert(tour.active and tour.step == 1 and app.tab.controls ~= nil and cues == 1)
assert(#tour.stepButtons == 8 and tour.counter.content == "Step 1 of 8")
assert(tour.text.content:find("Click New Tag", 1, true))
assert(tour.highlight.clickthrough and tour.arrow.clickthrough)
assert(tour.info.spriteID == 9966 and tour.info.clickthrough)
assert(tour.arrow.spriteID == 21393 and tour.arrow.width == 41 and tour.arrow.height == 54)
assert(tour.backArrow.spriteID == 9403 and tour.backArrow.isFlippedHorizontally)
assert(tour.nextArrow.spriteID == 9403 and tour.nextArrow.clickthrough)
assert(tour.backArrow.alpha == 0.35)
assert(app.tab.controls.tutorialIcon.spriteID == 36389)
app.tab.controls.tutorialButton.root.hooks.mouseover()
assert(app.tab.controls.tutorialIcon.spriteID == 36390)
app.tab.controls.tutorialButton.root.hooks.click()
assert(app.tab.controls.tutorialIcon.spriteID == 36391)
app.tab.controls.tutorialButton.root.hooks.mouseleave()
assert(app.tab.controls.tutorialIcon.spriteID == 36389)
for _, frame in ipairs({ tour.flashYellow, tour.flashWhite }) do
    assert(frame.root.clickthrough and #frame.parts == 9)
    for _, part in ipairs(frame.parts) do assert(part.clickthrough and part.isTiling) end
    assert(frame.parts[1].width == 10 and frame.parts[1].height == 10)
    assert(frame.parts[9].x + frame.parts[9].width == tour.highlight.width)
    assert(frame.parts[9].y + frame.parts[9].height == tour.highlight.height)
end
assert(tour.flashYellow.parts[1].spriteID == 11602 and tour.flashYellow.parts[9].spriteID == 11610)
assert(tour.flashWhite.parts[1].spriteID == 11611 and tour.flashWhite.parts[9].spriteID == 11619)
assert(math.abs(tour.flashYellow.root.alpha + tour.flashWhite.root.alpha - 1) < 0.0001)
assert(tour:Target() == app.tab.controls.newTagButton.root)
local x = tour.highlight.x
app.tab.controls.newTagButton.root.xyGlobal = { x = 321, y = 432 }
tour:Position()
local parentX = require("banktags/ui/geometry").absolutePosition(tour.parent)
assert(tour.highlight.x ~= x and tour.highlight.x == 320 - parentX)
assert(tour.highlight.width == app.tab.controls.newTagButton.root.width + 3)
assert(tour.arrow.rotationDegrees == 0)
app.tab.controls.newTagButton.root.xyGlobal = { x = 321, y = 2 }
tour:Position()
assert(tour.arrow.rotationDegrees == 180)
app.tab.controls.newTagButton.root.xyGlobal = nil
app.windows:OpenTagSettings("Tutorial tag", true)
assert(tour:Target() == app.windows.tagSettingsEditor.saveButton.root)
app.windows.tagSettingsEditor:Save("Tutorial tag")
h:Tick(5)
assert(tour.step == 2 and tour.tag == "tutorial tag" and cues == 2)
app.windows:Close("tagSettingsEditor")
assert(app:AddItemToTag("tutorial tag", 385))
h:Tick(5)
assert(tour.step == 3)
assert(app:ShowTag("tutorial tag"))
h:Tick(5)
assert(tour.step == 4 and tour:Target() == app.tab:RowFor("tutorial tag").root)
app.windows:OpenLayoutEditor("tutorial tag")
h:Tick(5)
assert(tour.step == 4)
local editor = app.windows.layoutEditor
assert(tour:Target() == editor.panes.sorted.view.root)
assert(tour.flashWhite.parts[5].width == tour.highlight.width - 20)
assert(tour.flashWhite.parts[5].height == tour.highlight.height - 20)
assert(editor:RecordEdit("tutorial tag", function()
    return app.store:InsertLabel("tutorial tag", 0, "Items", editor.columns)
end))
app:Changed()
h:Tick(5)
assert(tour.step == 4, "opening the editor or adding only a label does not place an item")
assert(editor:RecordEdit("tutorial tag", function()
    local shark = app.store:GetTaggedItems("tutorial tag")[1].layoutKey
    return app.store:MoveLayoutItem("tutorial tag", shark, 11, editor.columns)
end))
app:Changed()
h:Tick(5)
assert(tour.step == 5 and tour:Target() == editor.closeButton.root)
assert(app.store:CreateTag("untoured"))
assert(app.store:CreateFolder("Existing", "untoured"))
app:Changed()
editor.closeButton.action()
h:Tick(5)
-- The withdraw step points at nothing; its text says to click an item in the tag
assert(tour.step == 6 and tour:Target() == nil and tour.highlight.hidden)
local target = layout.itemHover.visibleItemInputTargets[1].root
h:PointAt(target, 5, 5)
h:Tick(2)
local menu = h:MenuFor(h.bankHost.items[1])
local withdrawEntry
for _, entry in ipairs(menu.entries) do if entry.verbText == "Withdraw-1" then withdrawEntry = entry end end
assert(withdrawEntry ~= nil)
h:Fire("MiniMenuEntrySelected", { entry = { verbText = "Examine" } })
h.bankHost:SetItems({ { 385, 19, "Shark" } })
h:Fire("InventoryUpdated", { inv = { id = 95 } })
h:Tick(8)
assert(tour.step == 6, "a quantity change alone is not a withdrawal action")
h.bankHost:SetItems({ { 385, 20, "Shark" } })
h:Fire("InventoryUpdated", { inv = { id = 95 } })
h:Tick(8)
target = layout.itemHover.visibleItemInputTargets[1].root
h:PointAt(target, 5, 5)
h:Tick(2)
menu = h:MenuFor(h.bankHost.items[1])
for _, entry in ipairs(menu.entries) do if entry.verbText == "Withdraw-1" then withdrawEntry = entry end end
h:Fire("MiniMenuEntrySelected", { entry = withdrawEntry })
assert(tour.withdrawn)
h:Tick(5)
assert(tour.step == 7, "the native withdrawal action advances without waiting on a leased snapshot")
assert(app:MoveTagToFolder("tutorial tag", "existing"))
h:Tick(5)
assert(tour.step == 7, "moving into an existing folder is not the create-folder action")
app.windows:OpenCreateFolderPrompt("tutorial tag")
assert(tour:Target() == app.windows.textPrompt.buttons[#app.windows.textPrompt.buttons].root)
app.windows.textPrompt:Save("Tutorial folder")
h:Tick(5)
assert(tour.step == 8 and app.store:GetTagFolder("tutorial tag") == "tutorial folder")
app.windows:Close("textPrompt")
assert(tour:Target() == app.tab.controls.importShareButton.root)
app.tab.controls.importShareButton.action()
assert(tour:Target() == app.windows.importShare.tabs:GetTab(2).hit)
app.windows.importShare.tabs:SetActive(2)
local shareField
for _, row in ipairs(app.windows.importShare.shareRows) do
    if row.tag == "tutorial tag" then shareField = row.field end
end
assert(tour:Target() == shareField.root)
local code = shareField:GetText()
shareField.root.hooks.click()
h:Tick(5)
assert(not tour.active and app.settings.tutorialSeen and cues == 8)
assert(tour.window == nil and stops == 8 and not shareField.root.destroyed)
assert(shareField:GetText() == code and #code > 0, "the code stays available to copy")
app.windows:Close("importShare")

-- Replay has working step buttons, arrows, and a persistent dismissal
app.tab.controls.tutorialButton.action()
assert(tour.active and tour.step == 1)
tour.stepButtons[3].action()
assert(tour.step == 3 and tour.stepButtons[3].outline.hidden == false)
tour.back.action()
assert(tour.step == 2)
h:Tick(10)
assert(tour.step == 2, "revisiting a completed step waits for a fresh action")
tour:Go(8)
tour.next.action()
assert(not tour.active)
app.tab:Build()
assert(not tour.active)

-- Closing the bank or unloading destroys overlays and stops ticking
app.tab.controls.tutorialButton.action()
local root, arrow = tour.window.root, tour.arrow
h:CloseBank()
assert(not tour.active and root.destroyed and arrow.destroyed)
h:OpenBank()
h:Tick(2)
assert(not tour.active)
app.tab.controls.tutorialButton.action()
assert(tour.active)
app:Shutdown()
assert(not tour.active and tour.window == nil)
print("tutorial_test: ok")
