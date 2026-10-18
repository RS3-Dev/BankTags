-- Run select mode: Bank Core's pick session makes "Add to <tag>" the left click on native
-- bank items and outlines the tag's members in gold, while the Tags tab shows the tag being
-- filled, pulses its row, and offers Done

local Config = require("banktags/core/config")
local ItemIdentity = require("banktags/tags/item_identity")
local Text = require("banktags/core/text")
local debugLog = require("banktags/core/debug_log").Write

local SelectMode = {}
SelectMode.__index = SelectMode

local PULSE_EVENT = Config.PLUGIN_REF .. "_select_pulse"
local PULSE_PERIOD = 100

-- What the tab says when Bank Core cannot start or keep select mode
local REFUSALS = {
    not_all_items = 'Select "All Items" before choosing items for a tag.',
    preset_open = 'Select "Return to Bank" before choosing items for a tag.',
    bank_closed = "Open your bank to choose items for a tag.",
    building = "The bank is still updating. Try again.",
    transition = "The bank is still updating. Try again.",
    page_open = "Close the shown tag before choosing items.",
}

-- Explain why select mode could not start or ended early
function SelectMode.Explain(reason)
    return REFUSALS[reason] or ("Select mode is unavailable (" .. tostring(reason) .. ").")
end

-- Create select mode for an app; no session runs until Start
function SelectMode.new(app)
    return setmetatable({ app = app, session = nil, pulseTicks = 0 }, SelectMode)
end

-- Return the tag select mode is filling, or nil
function SelectMode:Tag()
    return self.session ~= nil and self.session.tag or nil
end

-- List a tag's members as the item copies Bank Core outlines, in a stable order
local function highlight(store, tag)
    local keys = {}
    for key in pairs(store:Members(tag) or {}) do keys[#keys + 1] = key end
    table.sort(keys)
    local copies = {}
    for _, key in ipairs(keys) do
        local objectID, copy = ItemIdentity.ParseKey(key)
        if objectID ~= nil then copies[#copies + 1] = { item = objectID, copy = copy } end
    end
    return copies
end

-- Describe the pick session's entry and outlines for the session's tag
function SelectMode:Pick(session)
    return {
        label = "Add to " .. Text.plain(Text.titleCase(session.tag)),
        highlight = highlight(self.app.store, session.tag),
    }
end

-- Start choosing items for a tag, leaving a shown tag first; a second start for the same
-- tag stops instead
function SelectMode:Toggle(tag)
    if self:Tag() == tag then return self:Stop() end
    return self:Start(tag)
end

-- Ask Bank Core for a pick session over the bank's own items
function SelectMode:Start(tag)
    local app = self.app
    if app.handle == nil then return false end
    -- Select mode works on the bank's own view, so a shown tag closes first
    if app.shownTag ~= nil then app.handle:LeavePage() end
    local session = { tag = tag }
    local pick = self:Pick(session)
    pick.onPick = function(item) self:Picked(session, item) end
    pick.onEnd = function(reason) self:Ended(session, reason) end
    local previous = self.session
    self.session = session
    local started, reason = app.handle:BeginItemPick(pick)
    if not started then
        self.session = previous
        app:ShowStatus(SelectMode.Explain(reason))
        return false
    end
    app:ShowStatus(nil)
    self:StartPulse()
    app.tab:Refresh()
    debugLog("Bank Tags selecting items for ", tag)
    return true
end

-- Add a picked item's copy to the session's tag and outline it
function SelectMode:Picked(session, item)
    if self.session ~= session then return end
    if self.app:AddItemToTag(session.tag, item.objectID, item.copy) then self:Refresh() end
end

-- Forget a session Bank Core ended, explaining an ending the player did not choose
function SelectMode:Ended(session, reason)
    if self.session ~= session then return end
    self.session = nil
    self:StopPulse()
    if reason ~= "ended" and reason ~= "page_open" and reason ~= "replaced" then
        self.app:ShowStatus(SelectMode.Explain(reason))
    end
    self.app.tab:Refresh()
end

-- End select mode now; Bank Core restores the items' own outlines
function SelectMode:Stop()
    if self.session == nil then return false end
    self.session = nil
    self:StopPulse()
    if self.app.handle ~= nil then self.app.handle:EndItemPick() end
    self.app.tab:Refresh()
    return true
end

-- Drop the session without asking Bank Core, which has already gone
function SelectMode:Forget()
    self.session = nil
    self:StopPulse()
end

-- Follow a renamed tag, keeping the session running under its new name
function SelectMode:Rename(oldTag, newTag)
    if self:Tag() ~= oldTag then return end
    self.session.tag = newTag
    self:Refresh()
end

-- Update the entry label and outlines after the tag's members change
function SelectMode:Refresh()
    if self.session == nil or self.app.handle == nil then return end
    local updated, reason = self.app.handle:UpdateItemPick(self:Pick(self.session))
    if not updated then debugLog("Bank Tags could not update select mode: ", tostring(reason)) end
end

-- Pulse the tag's row while the session runs, so the tag being filled stays obvious
function SelectMode:StartPulse()
    self:StopPulse()
    Event.Logic.Subscribe(PULSE_EVENT, function() self:Pulse() end)
end

-- Stop pulsing and restore the row
function SelectMode:StopPulse()
    Event.Logic.Unsubscribe(PULSE_EVENT)
    self.pulseTicks = 0
    self:SetRowAlpha(1, 1)
end

-- Advance the pulse one tick
function SelectMode:Pulse()
    self.pulseTicks = self.pulseTicks + 1
    local phase = (self.pulseTicks % PULSE_PERIOD) / PULSE_PERIOD
    local wave = 0.5 - 0.5 * math.cos(phase * math.pi * 2)
    self:SetRowAlpha(0.62 + wave * 0.38, 0.4 + wave * 0.6)
end

-- Set the selected row's fill and frame opacity, when the Tags tab shows it
function SelectMode:SetRowAlpha(backgroundAlpha, borderAlpha)
    local row = self.session ~= nil and self.app.tab:RowFor(self.session.tag) or nil
    if row == nil then return end
    if row.background ~= nil then row.background.alpha = backgroundAlpha end
    for _, edge in ipairs(row.selectionFrame or {}) do edge.alpha = borderAlpha end
end

return SelectMode
