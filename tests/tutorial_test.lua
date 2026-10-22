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
for _, edge in ipairs(tour.edges) do assert(edge.clickthrough) end
assert(tour:Target() == app.tab.controls.newTagButton.root)
local x = tour.highlight.x
app.tab.controls.newTagButton.root.xyGlobal = { x = 321, y = 432 }
tour:Position()
local parentX = require("banktags/ui/geometry").absolutePosition(tour.parent)
assert(tour.highlight.x ~= x and tour.highlight.x == 318 - parentX)
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
