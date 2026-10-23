package.path = "./?.lua;./?/init.lua;" .. package.path

-- Drag Tags rows to reorder them, as a player would
-- FAKE HOST: stand-in loader, components, mouse, and menus, not the game client
-- The client's own event order and pointer capture during a hold are not modelled

local Harness = require("tools/test_support/tags_harness")
local h = Harness.new("sidebar_drag")
h.bankHost:SetItems({ { 4151, 1, "Abyssal whip" }, { 385, 20, "Shark" } })
h:LoadCore()
h:LoadTags()
local app = h:App()
local _, layout = h:OpenBank()
h:Tick(2)

for _, name in ipairs({ "alpha", "bravo", "melee", "ranged", "magic", "charlie", "mining", "fishing" }) do
    assert(app.store:CreateTag(name))
end
assert(app.store:AddTag("melee", 4151))
assert(app.store:CreateFolder("Combat", "melee"))
assert(app.store:SetTagFolder("ranged", "combat") and app.store:SetTagFolder("magic", "combat"))
assert(app.store:CreateFolder("Skills", "mining") and app.store:SetTagFolder("fishing", "skills"))
app:Changed()

local Geometry = h:TagsModule("banktags/ui/geometry")
local Chunks = h:TagsModule("banktags/core/chunked_string_store")
local ENTRY = 32
local COMBAT, SKILLS = "__banktags_folder:combat", "__banktags_folder:skills"
-- Raw mouse pixels per interface unit: Windows display scaling times the game's interface scale
local rawScale = 1.25

-- Count saves of the tag data
local saves, failWrites = 0, false
local write = Chunks.Write
Chunks.Write = function(...)
    saves = saves + 1
    if failWrites then return false, { stage = "manifest", reason = "disk full" } end
    return write(...)
end

local function tagList() return app.tab.controls.list end
local function order() return table.concat(app.store:AllTags(), ",") end
local function rowIDs()
    local ids = {}
    for _, row in ipairs(tagList().list.rows) do ids[#ids + 1] = row.entry.id end
    return table.concat(ids, ",")
end

-- Hover a row so the native hover event calibrates raw pixels, as the client does
local function hover(entryID)
    local row = tagList():RowFor(entryID)
    local x, y = Geometry.absolutePosition(row.root)
    y = y - tagList().list.scrollY
    row.root.xyGlobal = { x = x, y = y }
    h.bankHost.mouse = { x = (x + 20) * rawScale, y = (y + 10) * rawScale }
    row.root.hooks.mouserepeat(row.root, 20, 10)
end

-- Put the raw pointer at a height in the list's rows
local function pointAt(contentY, x)
    local list = tagList().list
    local left, top = Geometry.absolutePosition(list.viewport)
    h.bankHost.mouse = { x = (left + (x or 40)) * rawScale, y = (top + contentY - list.scrollY) * rawScale }
end

-- Press a row through PrettyUI's own row click, at a height in the rows
local function press(entryID, contentY)
    pointAt(contentY)
    assert(tagList().list:Click(entryID))
    return tagList():RowFor(entryID).root
end

-- Hold the pressed row with the pointer at a height in the rows
local function holdAt(root, contentY, x)
    pointAt(contentY, x)
    root.hooks.hold()
end

-- Drag a row from its middle to a height and release it there
-- The client's drag events carry screen positions that are wrong under Windows scaling
local function drag(entryID, toY)
    local index
    for rowIndex, row in ipairs(tagList().list.rows) do
        if row.entry.id == entryID then index = rowIndex end
    end
    local root = press(entryID, (index - 1) * ENTRY + 16)
    holdAt(root, toY)
    root.hooks.drag(root, 5000, -5000)
    root.hooks.dragcomplete(root, nil, 9999, 9999)
    -- A second release event for the same gesture does nothing
    root.hooks.release(root, 9999, 9999)
end

hover("alpha")
local pointerX, pointerY = Geometry.interfaceMousePosition()
local alphaX, alphaY = Geometry.absolutePosition(tagList():RowFor("alpha").root)
assert(math.abs(pointerX - (alphaX + 20)) < 0.001 and math.abs(pointerY - (alphaY + 10)) < 0.001,
    "native hover calibrates 125% display scaling")
assert(rowIDs() == "alpha,bravo," .. COMBAT .. ",melee,ranged,magic,charlie," .. SKILLS .. ",mining,fishing")

-- A press and release selects; a small wobble is still a click
local root = press("alpha", 10)
holdAt(root, 14, 43)
assert(not tagList().gesture.dragging and app.shownTag == nil, "a press alone selects nothing")
root.hooks.release()
h:Tick(2)
assert(app.shownTag == "alpha" and saves == 0)
h:ClickRow("alpha")
h:Tick(2)
assert(app.shownTag == nil)

-- Past the threshold the row lifts: an invisible cover over the list, a ghost, and a drop line
local list = tagList()
local clicks = list.clicks
root = press("alpha", 10)
assert(list.clicks == clicks + 1, "a press makes older row menus out of date")
holdAt(root, 50)
local gesture = list.gesture
assert(gesture.dragging and gesture.row.root == root)
assert(list:RowFor("alpha") == nil, "the cover leaves PrettyUI's rows")
assert(root.y == list.list.scrollY and root.height == list.list.viewport.height)
assert(root.hooks.mouserepeat == nil, "the moved cover does not recalibrate the pointer")
for _, part in ipairs(gesture.row.parts) do assert(part.hidden) end
assert(gesture.ghost.clickthrough and not gesture.ghost.destroyed)
assert(not gesture.line.hidden and gesture.line.clickthrough and gesture.line.y == 2 * ENTRY - 1)
assert(gesture.target.entry.tag == "bravo" and gesture.target.after)
-- Over its own place there is no line, and a release there saves nothing
holdAt(root, 20)
assert(gesture.target == nil and gesture.line.hidden)
holdAt(root, 40)
assert(gesture.target == nil, "just below itself, alpha would not move")
-- During the drag no row claims the pointer, so menus and drops find no row
assert(list:HoveredEntry() == nil)
holdAt(root, 50)
local ghost, line = gesture.ghost, gesture.line
root.hooks.release()
assert(order() == "bravo,alpha,melee,ranged,magic,charlie,mining,fishing" and saves == 1)
assert(ghost.destroyed and line.destroyed and root.destroyed and tagList().gesture == nil)
assert(app.shownTag == nil, "a drag never selects")
root.hooks.release()
root.hooks.dragcomplete(root, nil, 0, 0)
assert(saves == 1, "one save per drop")

-- A top-level tag goes before or after a whole folder, never inside it
drag("charlie", 6 * ENTRY - 10)
assert(order() == "bravo,alpha,melee,ranged,magic,charlie,mining,fishing" and saves == 1,
    "charlie is already just after Combat")
drag("charlie", 2 * ENTRY + 4)
assert(order() == "bravo,alpha,charlie,melee,ranged,magic,mining,fishing" and saves == 2)
root = press("bravo", 16)
holdAt(root, 4 * ENTRY + 16)
assert(tagList().gesture.target.entry.kind == "folder" and tagList().gesture.target.after == false)
holdAt(root, 6 * ENTRY + 20)
assert(tagList().gesture.target.entry.key == "combat" and tagList().gesture.target.after)
root.hooks.release()
assert(order() == "alpha,charlie,melee,ranged,magic,bravo,mining,fishing" and saves == 3)
assert(app.store:GetTagFolder("bravo") == nil)

-- A folder moves as one block with its tags
assert(rowIDs() == "alpha,charlie," .. COMBAT .. ",melee,ranged,magic,bravo," .. SKILLS .. ",mining,fishing")
drag(COMBAT, 9 * ENTRY + 20)
assert(order() == "alpha,charlie,bravo,mining,fishing,melee,ranged,magic" and saves == 4)
assert(app.store:GetTagFolder("melee") == "combat" and app.store:GetTagFolder("mining") == "skills")

-- A folder's tag moves only among that folder's tags
assert(rowIDs() == "alpha,charlie,bravo," .. SKILLS .. ",mining,fishing," .. COMBAT .. ",melee,ranged,magic")
root = press("magic", 9 * ENTRY + 16)
for _, y in ipairs({ 10, 3 * ENTRY + 10, 4 * ENTRY + 10, 6 * ENTRY + 10 }) do
    holdAt(root, y)
    assert(tagList().gesture.target == nil and tagList().gesture.line.hidden, "outside its folder at " .. y)
end
holdAt(root, 7 * ENTRY + 4)
assert(tagList().gesture.target.entry.tag == "melee" and not tagList().gesture.target.after)
root.hooks.release()
assert(order() == "alpha,charlie,bravo,mining,fishing,magic,melee,ranged" and saves == 5)
assert(app.store:GetTagFolder("magic") == "combat")

-- A collapsed folder moves with its hidden tags and stays collapsed
h:ClickRow(SKILLS)
assert(app.store:GetFolder("skills").collapsed)
assert(rowIDs() == "alpha,charlie,bravo," .. SKILLS .. "," .. COMBAT .. ",magic,melee,ranged")
saves = 0
drag(SKILLS, 8 * ENTRY - 4)
assert(order() == "alpha,charlie,bravo,magic,melee,ranged,mining,fishing" and saves == 1)
assert(app.store:GetFolder("skills").collapsed and rowIDs() == "alpha,charlie,bravo," .. COMBAT
    .. ",magic,melee,ranged," .. SKILLS)

-- A failed save keeps the order and says why
failWrites = true
drag("alpha", 2 * ENTRY + 20)
failWrites = false
assert(order() == "alpha,charlie,bravo,magic,melee,ranged,mining,fishing" and saves == 2)
assert(type(app.status) == "string" and string.find(app.status, "disk full", 1, true) ~= nil)
app:ShowStatus(nil)

-- Leaving the list or releasing outside it cancels without a save
saves = 0
root = press("alpha", 16)
holdAt(root, 2 * ENTRY + 20)
ghost = tagList().gesture.ghost
holdAt(root, 2 * ENTRY + 20, -30)
assert(tagList().gesture == nil and ghost.destroyed and tagList():RowFor("alpha") ~= nil)
root.hooks.release()
root = press("alpha", 16)
holdAt(root, 2 * ENTRY + 20)
pointAt(2 * ENTRY + 20, 5000)
root.hooks.mouseleave()
assert(tagList().gesture == nil)
root = press("alpha", 16)
holdAt(root, 2 * ENTRY + 20)
pointAt(-200)
root.hooks.release()
assert(tagList().gesture == nil and saves == 0 and order() == "alpha,charlie,bravo,magic,melee,ranged,mining,fishing")

-- A drag whose release never arrives ends at the next press, which does nothing else
root = press("alpha", 16)
holdAt(root, 2 * ENTRY + 20)
press("bravo", 2 * ENTRY + 16)
assert(tagList().gesture == nil and tagList():RowFor("alpha") ~= nil)
h:ClickRow("bravo")
h:Tick(2)
assert(app.shownTag == "bravo" and saves == 0)

-- Searches show some rows only, so they never drag; selection still works
tagList().search.root.hooks.contentchanged(nil, "change", "a")
assert(tagList().gesture == nil)
root = press("charlie", 16)
holdAt(root, 5 * ENTRY)
assert(not tagList().gesture.dragging)
root.hooks.release()
h:Tick(2)
assert(app.shownTag == "charlie" and saves == 0)
-- Typing a search mid-drag ends the drag
tagList().search.root.hooks.contentchanged(nil, "change", "")
root = press("alpha", 16)
holdAt(root, 3 * ENTRY)
ghost = tagList().gesture.ghost
tagList().search.root.hooks.contentchanged(nil, "change", "m")
assert(tagList().gesture == nil and ghost.destroyed)
root.hooks.release()
assert(saves == 0)

-- A bank item dropped on a tag row tags it once and never reorders, filtered or not
local function dropOn(tag)
    local row = tagList():RowFor(tag)
    h:PointAt(row.root, 20, 10)
    app.tab.callbacks.onItemDrop({ view = "native", objectID = 385, copy = 1 })
    -- The drag's end reaches the row beneath, which was never pressed
    row.root.hooks.release()
    row.root.hooks.dragcomplete(row.root, nil, 9999, 9999)
end
local before = order()
dropOn("mining")
assert(app.store:HasTag("mining", "object:385:1") and order() == before and saves == 1)
tagList().search.root.hooks.contentchanged(nil, "change", "")
dropOn("alpha")
assert(app.store:HasTag("alpha", "object:385:1") and order() == before and saves == 2)
dropOn("alpha")
assert(saves == 2, "the same stack is not added twice")

-- A row menu built before a drag is out of date after it; a new one acts
h:ClickRow("charlie")
h:Tick(2)
assert(app.shownTag == nil)
saves = 0
local alphaRow = tagList():RowFor("alpha")
h:PointAt(alphaRow.root, 20, 10)
local menu = h:ContentMenu()
assert(order() == before and saves == 0, "opening a menu moves nothing")
drag("alpha", ENTRY + 20)
assert(order() == "charlie,alpha,bravo,magic,melee,ranged,mining,fishing" and saves == 1)
Harness.Choose(menu, "Select <col=f2c66d>Alpha</col>")
h:Tick(2)
assert(app.shownTag == nil, "the stale menu does nothing")
h:PointAt(tagList():RowFor("alpha").root, 20, 10)
menu = h:ContentMenu()
Harness.Choose(menu, "Select <col=f2c66d>Alpha</col>")
h:Tick(2)
assert(app.shownTag == "alpha" and saves == 1)
-- Mid-drag, the pointer is over no row, so a menu offers nothing from the list
root = press("bravo", 2 * ENTRY + 16)
holdAt(root, 6 * ENTRY + 20)
-- The cover is under the pointer, but it is no longer one of the list's rows
root.isMouseOver = true
assert(#h:ContentMenu().entries == 1)
root.hooks.release()
assert(order() == "charlie,alpha,magic,melee,ranged,bravo,mining,fishing")
assert(app.shownTag == "alpha", "the shown tag stays shown through a drag")

-- In a short list the wheel and the list's edges scroll during a drag
local mount = layout.tabMount
local fullHeight = mount.bounds.height
mount:Resize({ x = mount.bounds.x, y = mount.bounds.y, width = mount.bounds.width, height = 218 })
list = tagList()
local viewportHeight = list.list.viewport.height
assert(viewportHeight == 4 * ENTRY, viewportHeight)
-- Scroll as PrettyUI does, resizing only the rows it lists
local rowCount = #list.list.rows
local scrolls = 0
function list.list:_OnScrollWheel(_, delta)
    scrolls = scrolls + 1
    self.scrollY = math.max(0, math.min(rowCount * ENTRY - viewportHeight, self.scrollY + delta * ENTRY))
    for _, row in ipairs(self.rows) do row.root:SetSize(row.root.width, ENTRY) end
    return false
end
saves = 0
root = press("charlie", 16)
holdAt(root, 40)
assert(scrolls == 0)
list.list:_OnScrollWheel(root, 1)
assert(root.height == viewportHeight, "scrolling leaves the cover's size alone")
holdAt(root, ENTRY + 40)
assert(root.y == ENTRY, "the cover follows the scrolled rows")
-- Arriving at the bottom edge scrolls one row; staying there does not scroll again
holdAt(root, ENTRY + viewportHeight - 4)
assert(scrolls == 2 and list.list.scrollY == 2 * ENTRY and root.y == 2 * ENTRY)
holdAt(root, 2 * ENTRY + viewportHeight - 4)
assert(scrolls == 2)
-- The pointer leaving the cover inside the list puts the cover back beneath it
list.list:_OnScrollWheel(root, 1)
pointAt(3 * ENTRY + 60)
root.hooks.mouseleave()
assert(tagList().gesture ~= nil and root.y == 3 * ENTRY)
-- The drop lands where the line shows in the scrolled rows
holdAt(root, 5 * ENTRY + 20)
assert(tagList().gesture.target.entry.key == "combat" and tagList().gesture.target.after)
root.hooks.release()
assert(order() == "alpha,magic,melee,ranged,charlie,bravo,mining,fishing" and saves == 1)
assert(tagList().list.scrollY == 3 * ENTRY, "the list keeps its scroll")

-- Resizing or closing the bank mid-drag ends the drag without a save
root = press("charlie", 5 * ENTRY + 16)
holdAt(root, 4 * ENTRY + 8)
ghost = tagList().gesture.ghost
mount:Resize({ x = mount.bounds.x, y = mount.bounds.y, width = mount.bounds.width, height = fullHeight })
assert(ghost.destroyed and root.destroyed and tagList().gesture == nil)
root.hooks.release()
root = press("alpha", 16)
holdAt(root, 4 * ENTRY)
ghost = tagList().gesture.ghost
h.bankHost:UnmountBankWindow()
layout:Restore()
assert(app.tab.controls == nil and ghost.destroyed and root.destroyed)
root.hooks.release()
assert(saves == 1)

-- Independent game interface scaling: a fresh hover calibrates the combined scale
h.host.globals.game = { options = { InterfaceScale = { setting = 150 } } }
rawScale = 1.25 * 1.5
local _
_, layout = h:OpenBank()
h:Tick(2)
hover("alpha")
assert(rowIDs() == "alpha," .. COMBAT .. ",magic,melee,ranged,charlie,bravo," .. SKILLS)
drag("bravo", 6)
assert(order() == "bravo,alpha,magic,melee,ranged,charlie,mining,fishing" and saves == 2)

print("sidebar_drag_test: ok")
