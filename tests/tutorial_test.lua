package.path = "./?.lua;./?/init.lua;" .. package.path

-- Walk through real tag actions in the stand-in host
local Harness = require("tools/test_support/tags_harness")
local h = Harness.new("tutorial")
h.bankHost:SetItems({ { 385, 20, "Shark" } })
h:LoadCore()
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
h:OpenBank()
h:Tick(2)
local tour = app.tutorial
assert(tour.active and tour.step == 1 and cues == 1)
assert(#app.store:AllTags() == 0, "the tour creates no sample data")
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
assert(app:AddItemToTag("tutorial tag", 385, 1))
h:Tick(5)
assert(tour.step == 3)
assert(app:ShowTag("tutorial tag"))
h:Tick(5)
assert(tour.step == 4 and tour:Target() == app.tab.controls.editTagButton.root)
app.windows:OpenLayoutEditor("tutorial tag")
h:Tick(5)
assert(tour.step == 5)
local editor = app.windows.layoutEditor
assert(tour:Target() == editor.panes.sorted.view.root)
assert(tour.flashWhite.parts[5].width == tour.highlight.width - 20)
assert(tour.flashWhite.parts[5].height == tour.highlight.height - 20)
assert(editor:RecordEdit("tutorial tag", function()
    return app.store:MoveLayoutItem("tutorial tag", "object:385:1", 11, editor.columns)
end))
app:Changed()
h:Tick(5)
assert(tour.step == 6 and tour:Target() == editor.closeButton.root)
editor.closeButton.action()
h:Tick(5)
assert(not tour.active and app.settings.tutorialSeen and cues == 6)
assert(tour.window == nil and stops == 6)

-- Replay has working step buttons, arrows, and a persistent dismissal
app.tab.controls.tutorialButton.action()
assert(tour.active and tour.step == 1)
tour.stepButtons[4].action()
assert(tour.step == 4 and tour.stepButtons[4].outline.hidden == false)
tour.back.action()
assert(tour.step == 3)
h:Tick(10)
assert(tour.step == 3, "revisiting a completed step waits for a fresh action")
tour:Go(6)
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
