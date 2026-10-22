-- Guide a first tag with native-looking highlights

local Geometry = require("banktags/ui/geometry")
local Json = require("banktags/core/json")
local NativeUi = require("banktags/ui/native_ui")
local Theme = require("banktags/ui/theme")

local Tutorial = {}
Tutorial.__index = Tutorial
local EVENT = "banktags_tutorial"
local WIDTH, HEIGHT = 480, 156
local STEPS = {
    { title = "Create a tag", text = "Click New Tag, give it a name, then Save. Tags group bank items without moving them out of your bank." },
    { title = "Add bank items", text = "In the bank's All Items view, drag an item onto your new tag in the sidebar. The item stays in your bank." },
    { title = "Open your tag", text = "Click your tag to see its items. Select the bank's All Items tab first if you are viewing a numbered bank tab." },
    { title = "Edit the layout", text = "Click the pencil beside New Tag to open the layout editor. You can also right-click your tag and choose Edit." },
    { title = "Arrange your items", text = "Drag an item into a different slot, or move an item from Unsorted into Layout. Changes save automatically. Ctrl+Z undoes an edit." },
    { title = "Return to your bank", text = "Click Close to leave the editor. Your layout is saved. You can replay this tutorial using the ? button in the Tags sidebar." },
}

-- Read native coordinates without converting mouse pixels
local function bounds(component)
    if component == nil or component.hidden == true or component.visibleGlobal == false then return nil end
    local point = component.xyGlobal
    local x, y
    if point ~= nil then x, y = point.x, point.y else x, y = Geometry.absolutePosition(component) end
    return x, y, tonumber(component.width) or 0, tonumber(component.height) or 0
end

-- Make a non-interactive rectangle
local function rectangle(parent, colour)
    local part = ui.Rectangle.new(parent)
    part.fill, part.rgba, part.clickthrough = true, colour, true
    return part
end

-- Keep the walkthrough separate from saved tags
function Tutorial.new(app)
    return setmetatable({ app = app, active = false, offered = false }, Tutorial)
end

-- Offer the first tour only to an empty store
function Tutorial:Mounted()
    if not self.active and not self.offered and not self.app.settings.tutorialSeen
        and #self.app.store:AllTags() == 0 then self:Start() end
end

-- Open the guide without creating tutorial data
function Tutorial:Start()
    if self.active then return end
    local parent = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__GAME_AREA)
        or ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__BANK_LAYER)
    if parent == nil or self.app.tab.controls == nil then return end
    self.active, self.offered, self.parent, self.ticks = true, true, parent, 0
    self.tag = self.app.shownTag or self.app.store:AllTags()[1]
    self.window = prettyui.Window.new(parent, {
        title = "Bank Tags Help", width = WIDTH, height = HEIGHT,
        minWidth = WIDTH, maxWidth = WIDTH, minHeight = HEIGHT, maxHeight = HEIGHT,
        x = 0, y = 0, scrollable = false,
        onClose = function() self:Stop(true) end,
    })
    -- The guide follows its target instead of being dragged
    if self.window.titleDrag ~= nil then self.window.titleDrag:Destroy(); self.window.titleDrag = nil end
    self.text = prettyui.Text.new(self.window.content, {
        text = "", x = 14, y = 8, width = WIDTH - 44, height = 58,
        colour = Theme.TEXT, font = id.Font.MUSEO_SANS_11PT_REGULAR, maxLines = 3,
    })
    self.buttons = {}
    local function button(label, x, action)
        local value = prettyui.SimpleButton.new(self.window.content, label, action,
            { x = x, y = 76, width = 28, height = 26 })
        self.buttons[#self.buttons + 1] = value
        return value
    end
    self.back = button("<", 166, function() self:Go(self.step - 1) end)
    self.stepButtons = {}
    for index = 1, #STEPS do
        local step = index
        self.stepButtons[index] = button(tostring(index), 200 + (index - 1) * 32,
            function() self:Go(step) end)
        local outline = ui.Rectangle.new(self.stepButtons[index].root)
        outline:SetPos(0, 0)
        outline:SetSize(0, 0, 1, 1)
        outline.fill, outline.rgba, outline.clickthrough = false, Theme.SELECTED_BORDER, true
        self.stepButtons[index].outline = outline
    end
    self.next = button(">", 398, function()
        if self.step == #STEPS then self:Stop(true) else self:Go(self.step + 1) end
    end)
    self.counter = prettyui.Text.new(self.window.content, {
        text = "", x = 14, y = 78, width = 144, height = 24,
        colour = Theme.MUTED_TEXT, font = id.Font.MUSEO_SANS_11PT_REGULAR,
    })
    self.highlight = ui.Layer.new(parent)
    self.highlight.clickthrough = true
    self.edges = {}
    for index = 1, 4 do self.edges[index] = rectangle(self.highlight, Theme.SELECTED_BORDER) end
    self.arrow = ui.Sprite.new(parent)
    self.arrow.spriteID = id.Sprite.BANK_ARROW_UP_0
    self.arrow:SetSize(40, 48)
    self.arrow.clickthrough = true
    self:Go(1)
    self.window:Show()
    Event.Logic.Subscribe(EVENT, function() self:Tick() end)
end

-- Play one quiet cue for a newly displayed step
function Tutorial:PlayCue()
    if audio == nil or Plugin == nil or Plugin.resources == nil then return end
    local resource = Plugin.resources.tutorial_step
    if resource == nil then return end
    local params = audio.SoundPlaybackParams.new()
    params.volume = 0.25
    pcall(function() self.sound = audio.Play(resource, params) end)
end

-- Navigate without changing bank items or layouts
function Tutorial:Go(step)
    if not self.active or step < 1 or step > #STEPS then return end
    self.step, self.ticks = step, 0
    if step == 1 then
        self.initialTags = {}
        for _, tag in ipairs(self.app.store:AllTags()) do self.initialTags[tag] = true end
    end
    self.itemsBefore = self.tag ~= nil and #self.app.store:GetTaggedItems(self.tag) or 0
    self.shownBefore = self.app.shownTag
    self.editorBefore = self.app.windows.layoutEditor
    self.layoutBefore = self.tag ~= nil and Json.encode(self.app.store:LayoutState(self.tag)) or nil
    self.hadEditor = self.app.windows.layoutEditor ~= nil
    self.text.content = STEPS[step].text
    self.counter.content = "Step " .. step .. " of " .. #STEPS
    self.back:SetDisabled(step == 1)
    for index, control in ipairs(self.stepButtons) do
        control.outline.hidden = index ~= step
    end
    if self.sound ~= nil then self.sound:Stop(); self.sound = nil end
    self:PlayCue()
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
    elseif step == 2 or step == 3 then
        local row = self.tag ~= nil and app.tab:RowFor(self.tag) or nil
        return row ~= nil and row.root or controls.newTagButton.root
    elseif step == 4 or editor == nil then
        return controls.editTagButton ~= nil and controls.editTagButton.root or nil
    elseif step == 5 then
        return editor.panes.sorted.view.root
    else
        return editor.closeButton.root
    end
end

-- Advance only after the requested action succeeds
function Tutorial:Check()
    local app, step = self.app, self.step
    if self.tag ~= nil and app.store.data.tags[self.tag] == nil then
        self.tag = app.shownTag or app.store:AllTags()[1]
    end
    local complete = false
    if step == 1 then
        for _, tag in ipairs(app.store:AllTags()) do
            if not self.initialTags[tag] then self.tag, complete = tag, true; break end
        end
    elseif step == 2 then
        complete = self.tag ~= nil and #app.store:GetTaggedItems(self.tag) > self.itemsBefore
    elseif step == 3 then
        complete = self.tag ~= nil and app.shownTag == self.tag and app.shownTag ~= self.shownBefore
    elseif step == 4 then
        complete = app.windows.layoutEditor ~= nil and app.windows.layoutEditor ~= self.editorBefore
            and app.windows.layoutEditor.selectedTag == self.tag
    elseif step == 5 then
        complete = app.windows.layoutEditor ~= nil and self.tag ~= nil and self.layoutBefore ~= nil
            and Json.encode(app.store:LayoutState(self.tag)) ~= self.layoutBefore
    elseif step == 6 then
        if app.windows.layoutEditor ~= nil then self.hadEditor = true end
        complete = self.hadEditor and app.windows.layoutEditor == nil
    end
    if complete then
        if step == #STEPS then self:Stop(true) else self:Go(step + 1) end
    end
end

-- Keep the guide and highlight inside the screen
function Tutorial:Position()
    local target = self:Target()
    local x, y, width, height = bounds(target)
    local parentX, parentY = Geometry.absolutePosition(self.parent)
    local screenWidth, screenHeight = self.parent.width, self.parent.height
    local bank = self.app.state ~= nil and self.app.state.bounds or nil
    local panelX = bank ~= nil and bank.x - parentX or 8
    local panelY = bank ~= nil and bank.y - parentY - HEIGHT - 8 or 8
    if panelY < 8 then
        panelY = bank ~= nil and bank.y - parentY + bank.height + 8 or 8
        if panelY + HEIGHT > screenHeight - 8 then panelY = 8 end
    end
    panelX = math.max(8, math.min(panelX, screenWidth - WIDTH - 8))
    panelY = math.max(8, math.min(panelY, screenHeight - HEIGHT - 8))
    self.window.root:SetPos(panelX, panelY)
    self.window.root:MoveToFront()
    self.highlight.hidden = x == nil or width <= 0 or height <= 0
    self.arrow.hidden = self.highlight.hidden
    if self.highlight.hidden then return end
    x, y = x - parentX, y - parentY
    -- Rows outside their scrolling viewport must not light up
    local controls = self.app.tab.controls
    if (self.step == 2 or self.step == 3) and controls ~= nil then
        local _, viewportY, _, viewportHeight = bounds(controls.list.list.root)
        if viewportY ~= nil and (y + parentY < viewportY or y + parentY + height > viewportY + viewportHeight) then
            self.highlight.hidden = true
            self.arrow.hidden = true
            return
        end
    end
    self.highlight:SetPos(x - 3, y - 3)
    self.highlight:SetSize(width + 6, height + 6)
    local w, h = width + 6, height + 6
    local positions = { { 0, 0, w, 2 }, { 0, h - 2, w, 2 }, { 0, 2, 2, h - 4 }, { w - 2, 2, 2, h - 4 } }
    for index, part in ipairs(self.edges) do
        local pos = positions[index]
        part:SetPos(pos[1], pos[2]); part:SetSize(pos[3], pos[4])
        part.alpha = 0.45 + 0.55 * (0.5 + 0.5 * math.sin(self.ticks / 7))
    end
    -- Put the large native arrow above the control when space permits
    if y >= 56 then
        NativeUi.setSpriteRotation(self.arrow, math.pi, 180)
        self.arrow:SetPos(x + width / 2 - 20, y - 52)
    else
        NativeUi.setSpriteRotation(self.arrow, 0, 0)
        self.arrow:SetPos(x + width / 2 - 20, y + height + 4)
    end
    self.highlight:MoveToFront()
    self.arrow:MoveToFront()
end

-- Poll only while a walkthrough is open
function Tutorial:Tick()
    if not self.active then return end
    self.ticks = self.ticks + 1
    if self.ticks % 5 == 0 then self:Check() end
    if self.active then self:Position() end
end

-- Clear all guide input and animation listeners
function Tutorial:Stop(remember)
    if not self.active then return end
    self.active = false
    Event.Logic.Unsubscribe(EVENT)
    if self.sound ~= nil then self.sound:Stop(); self.sound = nil end
    for _, button in ipairs(self.buttons) do button:Destroy() end
    self.text:Destroy()
    self.counter:Destroy()
    self.highlight:Destroy()
    self.arrow:Destroy()
    self.window:Destroy()
    self.window, self.highlight, self.parent = nil, nil, nil
    if remember then
        local saved, reason = self.app:SetSetting("tutorialSeen", true)
        if not saved then self.app:ShowStatus(reason) end
    end
end

return Tutorial
