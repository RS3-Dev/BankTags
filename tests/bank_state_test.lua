package.path = "./?.lua;./?/init.lua;" .. package.path

-- Check bank-state snapshots, page closure, and callback cleanup
-- FAKE HOST: stand-in components and cloned plugin exports

local Harness = require("tools/test_support/tags_harness")
local Json = require("banktags/core/json")
local h = Harness.new("bank_state", { separateGlobals = true, cloneExports = true })
h.bankHost:SetItems({ { 4151, 1, "Abyssal whip" } })
local core = h:LoadCore()
local register = core.result.Register
local reads, notices, closes = 0, 0, 0
local listener, lastState

-- Record the real registration, reads, and callback delivery
core.result.Register = function(spec)
    if spec.id == "banktags" then
        local changed = assert(spec.onBankStateChanged)
        spec.onBankStateChanged = function(state)
            notices, lastState = notices + 1, state
            changed(state)
        end
        listener = spec.onBankStateChanged
    end
    local ext, reason, detail = register(spec)
    if ext ~= nil and spec.id == "banktags" then
        local read, close = ext.GetBankState, ext.Close
        ext.GetBankState = function(...)
            reads = reads + 1
            return read(...)
        end
        ext.Close = function(...)
            closes = closes + 1
            return close(...)
        end
    end
    return ext, reason, detail
end

h:LoadTags()
local app = h:App()
assert(h:Connected() and reads == 1 and notices == 0)
h:Tick(2)
assert(notices == 1 and not lastState.bankOpen and not lastState.viewAll)
assert(closes == 0)
local session, layout = h:OpenBank()
h:Tick(2)
assert(lastState.bankOpen and lastState.viewAll)
assert(app.store:CreateTag("gear") and app.store:AddTag("gear", 4151))
app:Changed()
assert(app:ShowTag("gear"))
h:Tick(2)
local before = Json.encode(app.store.data)
local closeCount = closes

-- Exercise the listener before Core's own tab cleanup
listener({ bankOpen = true, viewAll = false, searchActive = false, presetOpen = false })
assert(closes == closeCount + 1 and app:ShownTag() == nil and layout.shownPage == nil)
assert(not app.tab:RowFor("gear").entry.selected)
assert(Json.encode(app.store.data) == before)
listener({ bankOpen = true, viewAll = false, searchActive = true, presetOpen = false })
assert(closes == closeCount + 1, "hidden pages need no further close")

-- Returning to All Items waits for an explicit choice
listener({ bankOpen = true, viewAll = true, searchActive = false, presetOpen = false })
assert(app:ShownTag() == nil and layout.shownPage == nil)

-- Each native restriction closes an otherwise available tag page
for _, restriction in ipairs({ "bankOpen", "presetOpen", "searchActive", "filterActive" }) do
    assert(app:ShowTag("gear"))
    local state = { bankOpen = true, viewAll = true,
        searchActive = false, filterActive = false, presetOpen = false }
    state[restriction] = restriction ~= "bankOpen"
    closeCount = closes
    listener(state)
    assert(app:ShownTag() == nil and closes == closeCount + 1, restriction)
    assert(Json.encode(app.store.data) == before)
    listener({ bankOpen = true, viewAll = true,
        searchActive = false, filterActive = false, presetOpen = false })
    assert(app:ShownTag() == nil, "clearing a restriction must not reopen the tag")
end

-- Another plugin's page stays under that plugin's control
local other = assert(core.result.Register({ id = "other", name = "Other" }))
assert(other:SetPage({ rows = { { slots = { 4151 } } } }) and other:Open())
h:Tick(2)
closeCount = closes
listener({ bankOpen = true, viewAll = false, searchActive = false, presetOpen = false })
assert(other:IsOpen() and closes == closeCount)
assert(other:Close() and app:ShowTag("gear"))

-- Read real native signals through Core's public state API
local getComponent = ui.Interfaces.GetComponent
local background = { spriteID = 8070 }
local cancel = { visible = false }
local cancelText = { visible = true, content = "" }
local preset = { visible = false }
ui.Interfaces.GetComponent = function(self, interfaceID, staticID, categoryID, dynamicID)
    if interfaceID == 517 then
        if staticID == 166 and categoryID == 0 and dynamicID == 0 then return background end
        if staticID == 257 then
            if categoryID == 0 and dynamicID == 9 then return cancelText end
            if categoryID == nil then return cancel end
        end
        if staticID == 86 then return preset end
    end
    return getComponent(self, interfaceID, staticID, categoryID, dynamicID)
end

-- Close on native search and filter updates, including All Items
for _, mode in ipairs({
    { field = "searchActive", label = "Cancel Search", message = "Clear the bank search" },
    { field = "filterActive", label = "Clear Filter", message = "Clear the bank filter" },
}) do
    assert(app:ShownTag() == "gear")
    cancel.visible, cancelText.content = true, mode.label
    session.pluginPages:Notify()
    h:Tick(2)
    assert(lastState.viewAll and lastState[mode.field])
    assert(app:ShownTag() == nil and layout.shownPage == nil)
    local readCount = reads
    assert(not app:ShowTag("gear") and reads == readCount + 1)
    assert(app.status:find(mode.message, 1, true))
    assert(layout.shownPage == nil and Json.encode(app.store.data) == before)
    cancel.visible = false
    session.pluginPages:Notify()
    h:Tick(2)
    assert(not lastState.searchActive and not lastState.filterActive)
    assert(app:ShownTag() == nil)
    assert(app:ShowTag("gear") and app.status == nil)
end

-- Reject a filtered opening before the state callback arrives
cancel.visible, cancelText.content = true, "Clear Filter"
assert(not app:ShowTag("gear") and layout.shownPage == nil)
assert(app.status:find("Clear the bank filter", 1, true))
cancelText.content = "Cancel Search"
assert(not app:ShowTag("gear"))
assert(app.status:find("Clear the bank search", 1, true))
cancel.visible = false
assert(app:ShowTag("gear"))

-- Read the All Items button and preset control independently
background.spriteID = 8069
assert(not app:ShowTag("gear") and app:ShownTag() == nil)
assert(app.status == 'Select "All Items" to view this tag.')
background.spriteID = 8070
layout:SetNativeViewAll(true)
assert(app:ShowTag("gear"))
preset.visible = true
session.pluginPages:Notify()
h:Tick(2)
assert(lastState.viewAll and lastState.presetOpen and app:ShownTag() == nil)
assert(not app:ShowTag("gear") and app.status == 'Close the preset selector to view this tag.')
preset.visible = false
session.pluginPages:Notify()
h:Tick(2)
assert(app:ShownTag() == nil and app:ShowTag("gear"))
ui.Interfaces.GetComponent = getComponent

-- Deliver a real state update from Core's native snapshot
local viewAll = true
layout.DetectNativeViewAll = function() return viewAll end
viewAll = false
local heard = notices
session.pluginPages:Notify()
h:Tick(2)
assert(notices == heard + 1 and not lastState.viewAll)
assert(app:ShownTag() == nil and layout.shownPage == nil)
viewAll = true
layout:SetNativeViewAll(true)
session.pluginPages:Notify()
h:Tick(2)
assert(lastState.viewAll and app:ShownTag() == nil)
assert(app:ShowTag("gear"))

-- Select mode continues on the native bank's other tabs
assert(app.select:Start("gear"))
viewAll = false
layout:SetNativeViewAll(false)
h:Tick(2)
assert(not lastState.viewAll and app.select:Tag() == "gear")

-- Reconnecting replaces the old callback and reads state again
local previous = app.ext
local readCount = reads
heard = notices
assert(app:Connect() and app.ext ~= previous)
assert(reads == readCount + 1)
h:Tick(2)
assert(notices == heard + 1 and not lastState.viewAll)
assert(select(2, previous:GetBankState()) == "stale")

-- Unloading ends state delivery without a separate listener
h.host:Unload("banktags")
heard = notices
session.pluginPages:Notify()
h:Tick(2)
assert(notices == heard and app.ext == nil and app.shutDown)
h.host:Unload("bankcore")

print("bank_state_test: ok")
