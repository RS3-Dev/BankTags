-- Run select mode, where left-clicking bank items adds them to a tag
-- Bank Core only draws the gold outline; Bank Tags runs the rest

local Config = require("banktags/core/config")
local ItemIdentity = require("banktags/tags/item_identity")
local Text = require("banktags/core/text")
local debugLog = require("banktags/core/debug_log").Write

local SelectMode = {}
SelectMode.__index = SelectMode

local PULSE_EVENT = Config.PLUGIN_REF .. "_select_pulse"
local PULSE_PERIOD = 100

-- Messages for when select mode cannot start or ends early
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

-- Return the left-click entry's label for the session's tag
function SelectMode:Label()
    return "Add to " .. Text.plain(Text.titleCase(self.session.tag))
end

-- Check whether Bank Core still shows the outline
function SelectMode:IsShown()
    local handle = self.app.handle
    return self.session ~= nil and handle ~= nil and handle:GetState().highlighted == true
end

-- List a tag's members as the copies Bank Core outlines
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

-- Start choosing items for a tag, or stop if already choosing
function SelectMode:Toggle(tag)
    if self:Tag() == tag then return self:Stop() end
    return self:Start(tag)
end

-- Outline the tag's members in the bank's own view and start the session
function SelectMode:Start(tag)
    local app = self.app
    local handle = app.handle
    if handle == nil then return false end
    -- Select mode needs the bank's own view
    if handle:GetState().openPage ~= nil then handle:LeavePage() end
    local started, reason = handle:SetItemHighlight(highlight(app.store, tag))
    if not started then
        app:ShowStatus(SelectMode.Explain(reason))
        return false
    end
    self.session = { tag = tag }
    app:ShowStatus(nil)
    self:StartPulse()
    app.tab:Refresh()
    debugLog("Bank Tags selecting items for ", tag)
    return true
end

-- Add a picked item's copy to the session's tag and outline it
function SelectMode:Picked(session, item)
    if self.session ~= session then return end
    -- Adding the item outlines it through the app's change
    self.app:AddItemToTag(session.tag, item.objectID, item.copy)
end

-- End the session once Bank Core drops its outline
function SelectMode:Follow(state)
    if self.session == nil or state.highlighted then return end
    self.session = nil
    self:StopPulse()
    if state.reason ~= nil then self.app:ShowStatus(SelectMode.Explain(state.reason)) end
    self.app.tab:Refresh()
end

-- End select mode now; Bank Core restores the items' own outlines
function SelectMode:Stop()
    if self.session == nil then return false end
    self.session = nil
    self:StopPulse()
    if self.app.handle ~= nil then self.app.handle:SetItemHighlight(nil) end
    self.app.tab:Refresh()
    return true
end

-- Drop the session without asking Bank Core, which has already gone
function SelectMode:Forget()
    self.session = nil
    self:StopPulse()
end

-- Follow a renamed tag, keeping the session running under its new name
-- The rename's app change outlines its items again
function SelectMode:Rename(oldTag, newTag)
    if self:Tag() == oldTag then self.session.tag = newTag end
end

-- Outline the tag's members again, or end a cleared session
function SelectMode:Refresh()
    local handle = self.app.handle
    if self.session == nil or handle == nil then return end
    local state = handle:GetState()
    if not state.highlighted then return self:Follow(state) end
    local updated, reason = handle:SetItemHighlight(highlight(self.app.store, self.session.tag))
    if not updated then debugLog("Bank Tags could not update select mode: ", tostring(reason)) end
end

-- Pulse the tag's row while the session runs
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

-- Set the selected row's fill and frame opacity
function SelectMode:SetRowAlpha(backgroundAlpha, borderAlpha)
    local row = self.session ~= nil and self.app.tab:RowFor(self.session.tag) or nil
    if row == nil then return end
    if row.background ~= nil then row.background.alpha = backgroundAlpha end
    for _, edge in ipairs(row.selectionFrame or {}) do edge.alpha = borderAlpha end
end

return SelectMode
