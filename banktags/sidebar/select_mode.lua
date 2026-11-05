-- Run select mode, where left-clicking bank items adds them to a tag
-- It runs over the bank's own view and ends when a tag is shown or the bank closes

local Config = require("banktags/core/config")
local Text = require("banktags/core/text")
local debugLog = require("banktags/core/debug_log").Write

local SelectMode = {}
SelectMode.__index = SelectMode

local PULSE_EVENT = Config.PLUGIN_REF .. "_select_pulse"
local PULSE_PERIOD = 100

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

-- Start choosing items for a tag, or stop if already choosing
function SelectMode:Toggle(tag)
    if self:Tag() == tag then return self:Stop() end
    return self:Start(tag)
end

-- Start the session over the bank's own view, leaving a shown tag
function SelectMode:Start(tag)
    local app = self.app
    local ext = app.ext
    if ext == nil or app.store.data.tags[tag] == nil then return false end
    if ext:IsOpen() and not ext:Close() then return false end
    self.session = { tag = tag }
    app.nativeItems:Refresh()
    app:ShowStatus(nil)
    self:StartPulse()
    app.tab:Refresh()
    debugLog("Bank Tags selecting items for ", tag)
    return true
end

-- Add a picked item to the session's tag
function SelectMode:Picked(session, objectID)
    if self.session ~= session then return end
    self.app:AddItemToTag(session.tag, objectID)
end

-- End select mode now
function SelectMode:Stop()
    if self.session == nil then return false end
    self.session = nil
    self.app.nativeItems:RestoreHighlights()
    self:StopPulse()
    self.app.tab:Refresh()
    return true
end

-- Drop the session without redrawing the Tags tab
function SelectMode:Forget()
    self.session = nil
    self.app.nativeItems:RestoreHighlights()
    self:StopPulse()
end

-- Follow a renamed tag, keeping the session running under its new name
function SelectMode:Rename(oldTag, newTag)
    if self:Tag() == oldTag then self.session.tag = newTag end
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
