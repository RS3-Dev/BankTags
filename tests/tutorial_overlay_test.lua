package.path = "./?.lua;./?/init.lua;" .. package.path

-- FAKE HOST: keep the game area behind the bank, with separate native origins.
-- Moving a child forward cannot put it above a different parent branch.
local Harness = require("tools/test_support/tags_harness")
local h = Harness.new("tutorial_overlay")
h.bankHost.anchoredLayout = true
local screen = ui.Layer.new(nil)
screen:SetSize(1600, 1100)
local gameArea = ui.Layer.new(screen)
gameArea:SetSize(0, 0, 1, 1)
local bankLayer = ui.Layer.new(screen)
bankLayer:SetSize(0, 0, 1, 1)
-- Native coordinates may include offsets not represented by summing x and y.
bankLayer.xyGlobal = { x = 48, y = 32 }
id.Component.TOPLEVEL_V2__GAME_AREA = "game_area"
local lookup = ui.Interfaces.GetComponent
function ui.Interfaces:GetComponent(componentID, ...)
    if componentID == id.Component.TOPLEVEL_V2__GAME_AREA then return gameArea end
    if componentID == id.Component.TOPLEVEL_V2__BANK_LAYER then return bankLayer end
    return lookup(self, componentID, ...)
end
h.bankHost:SetItems({ { 385, 20, "Shark" } })
h:LoadCore()
h:LoadTags()
local app = h:App()
assert(app.store:CreateTag("melee"))
local nativeWindow = h.bankHost:MountBankWindow(714, 650)
nativeWindow.host.parent = bankLayer
bankLayer.children[#bankLayer.children + 1] = nativeWindow.host
h:OpenBank()
h:Tick(2)

local function branch(control)
    while control.parent ~= screen do control = assert(control.parent) end
    return control
end

local function global(control)
    if control.xyGlobal ~= nil then return control.xyGlobal.x, control.xyGlobal.y end
    if control.parent == nil then return control.x, control.y end
    local x, y = global(control.parent)
    return x + control.x - (control.parent.scrollX or 0),
        y + control.y - (control.parent.scrollY or 0)
end

-- Supply the native target position, including its parents' scrolling.
local function checkTarget(control)
    local x, y = global(control)
    control.xyGlobal = { x = x, y = y }
    local tour = app.tutorial
    tour:Position()
    assert(not tour.highlight.hidden and not tour.arrow.hidden)
    assert(branch(tour.highlight) == branch(control), "the guide must draw in the bank's branch")
    local outlineX, outlineY = global(tour.highlight)
    assert(outlineX == x - 1 and outlineY == y - 1, "outline must follow the native target origin")
    assert(tour.highlight.width >= control.width and tour.highlight.height >= control.height)
    assert(tour.root.front > (nativeWindow.host.front or 0), "the guide must draw above the bank")
    assert(tour.highlight.clickthrough and tour.arrow.clickthrough)
    control.xyGlobal = nil
end

local tour = app.tutorial
tour:Start()
assert(tour.root.width == bankLayer.width and tour.root.height == bankLayer.height)
checkTarget(app.tab.controls.newTagButton.root)
app.windows:OpenTagSettings("Tutorial tag", true)
checkTarget(app.windows.tagSettingsEditor.saveButton.root)
app.windows:Close("tagSettingsEditor")
tour:Go(3)
local row = app.tab:RowFor("melee").root
checkTarget(row)

-- A row scrolled out of its viewport must not leave a floating arrow behind.
local list = app.tab.controls.list.list
list.root.scrollY = 1000
local x, y = global(row)
row.xyGlobal = { x = x, y = y }
local viewX, viewY = global(list.root)
list.root.xyGlobal = { x = viewX, y = viewY }
tour:Position()
assert(tour.highlight.hidden and tour.arrow.hidden)
row.xyGlobal, list.root.xyGlobal = nil, nil
list.root.scrollY = 0

-- The editor shares the bank layer, so its controls also remain below the guide.
app.windows:OpenLayoutEditor("melee")
tour:Go(5)
checkTarget(app.windows.layoutEditor.closeButton.root)
app.windows.layoutEditor:Show()
assert(tour.root.front > app.windows.layoutEditor.window.root.front)
assert(not app.windows.layoutEditor:OverlayShown(), "tutorial decoration must not block editor actions")
tour:Stop(false)
assert(app.windows.layoutEditor.guideLayer == nil)
tour:Start()
tour:Go(5)
app.windows.layoutEditor:Show()
assert(tour.root.front > app.windows.layoutEditor.window.root.front)
app:Shutdown()

print("tutorial_overlay_test: ok")
