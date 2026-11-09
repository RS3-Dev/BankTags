-- Guide a first tag with native-looking highlights

local Json = require("resources/core/json")
local Settings = require("resources/core/settings")

local Tutorial = {}
Tutorial.__index = Tutorial
for name, method in pairs(require("resources/windows/tutorial_view")) do Tutorial[name] = method end
local EVENT = "banktags_tutorial"
local ROOT_KEY = "__banktags_tutorial_root"
local STEPS = {
    { text = "Click New Tag, give it a name, then Save. Tags group bank items without moving them out of your bank." },
    { text = "Right-click your tag and choose Select items, then click an item in your bank. The item stays in your bank." },
    { text = "Click your tag to see its items. Select the bank's All Items tab first if you are viewing a numbered bank tab." },
    { text = "Right-click your tag and choose Edit. Drag your item from Unsorted into the layout grid. Changes save automatically." },
    { text = "Click Close to leave the editor and return to your tag. Your layout is saved." },
    { text = "Click an item in your tag to withdraw it. Tags use the normal bank withdrawal options." },
    { text = "Right-click your tag. Choose Add to folder (or Move to folder), then Create new folder. Name it and click Create." },
    { text = "Click Import/Share, then choose Share. Click your tag's code field and press Ctrl+A, then Ctrl+C to copy it." },
}

-- Release a control that may already be closed
local function destroy(control)
    if control ~= nil then pcall(function() control:Destroy() end) end
end

-- Keep the walkthrough separate from saved tags
function Tutorial.new(app)
    -- Recover the owned UI even if an earlier shutdown lost its controller
    Event.Logic.Unsubscribe(EVENT)
    Event.MiniMenuEntrySelected.Unsubscribe(EVENT)
    destroy(rawget(_G, ROOT_KEY))
    _G[ROOT_KEY] = nil
    return setmetatable({ app = app, active = false, offered = false }, Tutorial)
end

-- Offer a first tour when the empty sidebar opens
function Tutorial:Offer()
    if not self.active and not self.offered and not self.app.settings.tutorialSeen
        and self.app.tab.controls ~= nil and self.app.store.loadError == nil
        and #self.app.store:AllTags() == 0 then self:Start() end
end

-- Open the guide without creating tutorial data
function Tutorial:Start()
    if self.active then return end
    if self.app.tab.controls == nil then return end
    -- Use the bank's layer to draw above its windows
    local parent = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__BANK_LAYER)
        or ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__GAME_AREA)
    if parent == nil or self.app.windows:BankBounds() == nil then return end
    self:Stop(false)
    self.active, self.offered, self.parent, self.ticks = true, true, parent, 0
    self.tag = self.app:ShownTag() or self.app.store:AllTags()[1]
    self:CreateView(#STEPS, ROOT_KEY)
    self:Go(1)
    self.window:Show()
    self.app.windows:SyncEditorOverlays()
    Event.Logic.Subscribe(EVENT, function() self:Tick() end)
    Event.MiniMenuEntrySelected.Subscribe(EVENT, function(event) self:ObserveWithdrawal(event.entry) end)
end

-- Observe a native withdrawal while this tag is shown
function Tutorial:ObserveWithdrawal(entry)
    if not self.active or self.step ~= 6 or entry == nil or self.app:ShownTag() ~= self.tag then return end
    local verb = tostring(entry.verbText or ""):gsub("<[^>]*>", ""):lower()
    if verb:match("^withdraw") then self.withdrawn = true end
end

-- Remove only the guide's share-field observer
function Tutorial:UnwatchShare()
    if self.shareField ~= nil then
        pcall(function() self.shareField.root:Unsubscribe(ui.Hook.ONCLICK, EVENT) end)
    end
    self.shareField, self.shareWindow, self.shareClicked = nil, nil, false
end

-- Leave the share field's own input handling intact
function Tutorial:WatchShare(window, field)
    if self.shareField == field then return end
    self:UnwatchShare()
    self.shareField, self.shareWindow = field, window
    -- Record a click on the guide's current share field
    field.root:Subscribe(ui.Hook.ONCLICK, EVENT, function()
        if self.active and self.step == 8 and self.app.windows.importShare == window then self.shareClicked = true end
        return false
    end)
end

-- Navigate without changing bank items or layouts
function Tutorial:Go(step)
    if not self.active or step < 1 or step > #STEPS then return end
    self:UnwatchShare()
    self.step, self.ticks = step, 0
    if step == 1 then
        self.initialTags = {}
        for _, tag in ipairs(self.app.store:AllTags()) do self.initialTags[tag] = true end
    end
    self.itemsBefore = self.tag ~= nil and #self.app.store:GetTaggedItems(self.tag) or 0
    self.shownBefore = self.app:ShownTag()
    self.layoutBefore = self.tag ~= nil and Json.encode(self.app.store:LayoutState(self.tag)) or nil
    self.hadEditor = self.app.windows.layoutEditor ~= nil
    self.withdrawn = false
    self.foldersBefore = {}
    for _, folder in ipairs(self.app.store:GetFolders()) do self.foldersBefore[folder.key] = true end
    self.folderBefore = self.tag ~= nil and self.app.store:GetTagFolder(self.tag) or nil
    self.text.content = STEPS[step].text
    self.counter.content = "Step " .. step .. " of " .. #STEPS
    self.back:SetDisabled(step == 1)
    self.backArrow.alpha = step == 1 and 0.35 or 1
    for index, control in ipairs(self.stepButtons) do
        control.outline.hidden = index ~= step
    end
    self:Position()
end

-- Find the current live target after rebuilds
function Tutorial:Target()
    local app, step = self.app, self.step
    local controls, editor = app.tab.controls, app.windows.layoutEditor
    if controls == nil then return nil end
    if step == 1 then
        local settings = app.windows.tagSettingsEditor
        if settings ~= nil and settings.window.root.hidden ~= true then
            return settings.saveButton.root
        end
        return controls.newTagButton.root
    elseif step == 2 or step == 3 or step == 7 then
        local prompt = app.windows.textPrompt
        if step == 7 and prompt ~= nil and not prompt.closed and prompt.folderTag == self.tag then
            return prompt.field.root
        end
        local row = self.tag ~= nil and app.tab:RowFor(self.tag) or nil
        return row ~= nil and row.root or controls.newTagButton.root
    elseif step == 4 then
        if editor == nil then
            local row = self.tag ~= nil and app.tab:RowFor(self.tag) or nil
            return row ~= nil and row.root or nil
        end
        return editor.panes.sorted.view.root
    elseif step == 5 then
        return editor ~= nil and editor.closeButton.root or nil
    elseif step == 8 then
        local window = app.windows.importShare
        if window == nil then return controls.importShareButton.root end
        if window.tabs:GetActiveIndex() ~= 2 then return window.tabs:GetTab(2).hit end
        for _, row in ipairs(window.shareRows) do
            if row.tag == self.tag then self:WatchShare(window, row.field); return row.field.root end
        end
    end
end

-- Advance only after the requested action succeeds
function Tutorial:Check()
    local app, step = self.app, self.step
    if self.tag ~= nil and app.store.data.tags[self.tag] == nil then
        self.tag = app:ShownTag() or app.store:AllTags()[1]
    end
    local complete = false
    if step == 1 then
        for _, tag in ipairs(app.store:AllTags()) do
            if not self.initialTags[tag] then self.tag, complete = tag, true; break end
        end
    elseif step == 2 then
        complete = self.tag ~= nil and #app.store:GetTaggedItems(self.tag) > self.itemsBefore
    elseif step == 3 then
        local shown = app:ShownTag()
        if shown ~= self.tag then self.shownBefore = shown end
        complete = self.tag ~= nil and shown == self.tag and shown ~= self.shownBefore
    elseif step == 4 then
        local arranged = false
        local record = self.tag ~= nil and app.store.data.tags[self.tag] or nil
        for _, row in ipairs(record ~= nil and record.rows or {}) do
            for _, slot in ipairs(row.slots or {}) do if slot.kind == "item" then arranged = true end end
        end
        complete = app.windows.layoutEditor ~= nil and self.tag ~= nil and self.layoutBefore ~= nil
            and arranged and Json.encode(app.store:LayoutState(self.tag)) ~= self.layoutBefore
    elseif step == 5 then
        if app.windows.layoutEditor ~= nil then self.hadEditor = true end
        complete = self.hadEditor and app.windows.layoutEditor == nil
    elseif step == 6 then
        complete = self.withdrawn
    elseif step == 7 then
        local folder = self.tag ~= nil and app.store:GetTagFolder(self.tag) or nil
        complete = folder ~= nil and folder ~= self.folderBefore and not self.foldersBefore[folder]
    elseif step == 8 then
        complete = self.shareClicked and self.app.windows.importShare == self.shareWindow
    end
    if complete then
        if step == #STEPS then self:Stop(true) else self:Go(step + 1) end
    end
end

-- Poll only while a walkthrough is open
function Tutorial:Tick()
    if not self.active then return end
    self.ticks = self.ticks + 1
    if self.ticks % 5 == 0 then self:Check() end
    if self.active then self:Position() end
end

-- Clear all guide input and animation listeners
function Tutorial:Stop(remember, closingWindow)
    if not self.active and self.root == nil and self.window == nil then return end
    self.active = false
    local root, window = self.root, self.window
    -- Hide the whole guide before any individual control can fail to release
    if root ~= nil then pcall(function() root.hidden = true end) end
    Event.Logic.Unsubscribe(EVENT)
    Event.MiniMenuEntrySelected.Unsubscribe(EVENT)
    self:UnwatchShare()
    for _, button in ipairs(self.buttons or {}) do destroy(button) end
    self.window, self.buttons, self.text, self.counter = nil, nil, nil, nil
    self.highlight, self.arrow, self.parent = nil, nil, nil
    -- PrettyUI finishes destroying the window after its X callback returns
    if window ~= closingWindow then destroy(window) end
    if closingWindow == nil then
        destroy(root)
        self.root = nil
        if rawget(_G, ROOT_KEY) == root then _G[ROOT_KEY] = nil end
    end
    self.app.windows:SyncEditorOverlays()
    if remember and not self.app.settings.tutorialSeen then
        -- Saving this flag must not rebuild the selected share-code field
        local settings = Settings.copy(self.app.settings)
        settings.tutorialSeen = true
        if Settings.save(settings) then
            self.app.settings = settings
        else
            self.app:ShowStatus("Could not save tutorial completion.")
        end
    end
end

return Tutorial
