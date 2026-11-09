-- Draw the guide, step buttons, and target highlight

local Geometry = require("resources/ui/geometry")
local NativeUi = require("resources/ui/native_ui")
local Theme = require("resources/ui/theme")

local TutorialView = {}
local WIDTH, HEIGHT = 521, 144

-- Read native coordinates without converting mouse pixels
local function position(component)
    local point = component.xyGlobal
    if point ~= nil then return point.x, point.y end
    return Geometry.absolutePosition(component)
end

-- Read the position and size of a visible control
local function bounds(component)
    if component == nil or component.hidden == true or component.visibleGlobal == false then return nil end
    local x, y = position(component)
    return x, y, tonumber(component.width) or 0, tonumber(component.height) or 0
end

-- Make a non-interactive rectangle
local function rectangle(parent, colour)
    local part = ui.Rectangle.new(parent)
    part.fill, part.rgba, part.clickthrough = true, colour, true
    return part
end

-- Build the native highlight's nine sprite pieces
local function flashFrame(parent, firstSprite)
    local root = ui.Layer.new(parent)
    root.clickthrough = true
    local parts = {}
    for index = 1, 9 do
        local part = ui.Sprite.new(root)
        part.spriteID = firstSprite + index - 1
        part.clickthrough = true
        part.isTiling = true
        parts[index] = part
    end
    return { root = root, parts = parts }
end

-- Size native corners and stretch the middle strips
local function sizeFrame(frame, width, height)
    frame.root:SetSize(width, height)
    local xs, ys = { 0, 10, width - 10 }, { 0, 10, height - 10 }
    local widths, heights = { 10, width - 20, 10 }, { 10, height - 20, 10 }
    for index, part in ipairs(frame.parts) do
        local column, row = (index - 1) % 3 + 1, math.floor((index - 1) / 3) + 1
        part:SetPos(xs[column], ys[row])
        part:SetSize(widths[column], heights[row])
    end
end

-- Build the guide, step buttons, and target highlight
function TutorialView:CreateView(stepCount, rootKey)
    local parent = self.parent
    local STEP_START = WIDTH - 66 - stepCount * 31
    self.root = ui.Layer.new(parent)
    _G[rootKey] = self.root
    self.root:SetPos(0, 0)
    self.root:SetSize(0, 0, 1, 1)
    self.root.clickthrough = true
    self.window = prettyui.Window.new(self.root, {
        title = "Bank Tags Help", width = WIDTH, height = HEIGHT,
        minWidth = WIDTH, maxWidth = WIDTH, minHeight = HEIGHT, maxHeight = HEIGHT,
        x = 0, y = 0, scrollable = false, destroyOnClose = true,
        onClose = function(window) self:Stop(true, window) end,
    })
    -- The guide follows its target instead of being dragged
    if self.window.titleDrag ~= nil then self.window.titleDrag:Destroy(); self.window.titleDrag = nil end
    self.info = ui.Sprite.new(self.window.root)
    self.info:SetPos(8, 8)
    self.info:SetSize(26, 26)
    self.info.spriteID = NativeUi.SPRITES.TUTORIAL_INFO
    self.info.clickthrough = true
    self.info:MoveToFront()
    self.textBackground = rectangle(self.window.content, 0x000000FF)
    self.textBackground:SetPos(8, 16)
    self.textBackground:SetSize(WIDTH - 32, 40)
    self.textOutline = rectangle(self.window.content, 0x756C60FF)
    self.textOutline.fill = false
    self.textOutline:SetPos(8, 16)
    self.textOutline:SetSize(WIDTH - 32, 40)
    self.text = prettyui.Text.new(self.window.content, {
        text = "", x = 16, y = 19, width = WIDTH - 48, height = 34,
        colour = Theme.TEXT, font = id.Font.MUSEO_SANS_11PT_REGULAR, maxLines = 2,
    })
    self.buttons = {}
    -- Keep step controls together so closing releases every button
    local function button(label, x, action)
        local value = prettyui.SimpleButton.new(self.window.content, label, action,
            { x = x, y = 72, width = 26, height = 26 })
        self.buttons[#self.buttons + 1] = value
        return value
    end
    self.back = button("", STEP_START - 34, function() self:Go(self.step - 1) end)
    self.backArrow = ui.Sprite.new(self.back.root)
    self.backArrow:SetPos(1, 2)
    self.backArrow:SetSize(24, 24)
    self.backArrow.spriteID = NativeUi.SPRITES.TUTORIAL_NAV_ARROW
    self.backArrow.isFlippedHorizontally = true
    self.backArrow.clickthrough = true
    self.stepButtons = {}
    for index = 1, stepCount do
        local step = index
        self.stepButtons[index] = button(tostring(index), STEP_START + (index - 1) * 31,
            function() self:Go(step) end)
        local outline = ui.Rectangle.new(self.stepButtons[index].root)
        outline:SetPos(0, 0)
        outline:SetSize(0, 0, 1, 1)
        outline.fill, outline.rgba, outline.clickthrough = false, Theme.SELECTED_BORDER, true
        self.stepButtons[index].outline = outline
    end
    -- Advance the guide or finish its last step
    self.next = button("", 463, function()
        if self.step == stepCount then self:Stop(true) else self:Go(self.step + 1) end
    end)
    self.nextArrow = ui.Sprite.new(self.next.root)
    self.nextArrow:SetPos(1, 2)
    self.nextArrow:SetSize(24, 24)
    self.nextArrow.spriteID = NativeUi.SPRITES.TUTORIAL_NAV_ARROW
    self.nextArrow.clickthrough = true
    self.counter = prettyui.Text.new(self.window.content, {
        text = "", x = 16, y = 74, width = STEP_START - 64, height = 24,
        colour = Theme.MUTED_TEXT, font = id.Font.MUSEO_SANS_11PT_REGULAR,
    })
    self.highlight = ui.Layer.new(self.root)
    self.highlight.clickthrough = true
    -- TOPLEVEL_V2's FLASH_YELLOW and FLASH_WHITE nine-piece frames
    self.flashYellow = flashFrame(self.highlight, 11602)
    self.flashWhite = flashFrame(self.highlight, 11611)
    self.arrow = ui.Sprite.new(self.root)
    self.arrow.spriteID = NativeUi.SPRITES.TUTORIAL_POINTER
    self.arrow:SetSize(41, 54)
    self.arrow.clickthrough = true
end

-- Keep the guide and highlight inside the screen
function TutorialView:Position()
    local target = self:Target()
    local x, y, width, height = bounds(target)
    local parentX, parentY = position(self.parent)
    local screenWidth, screenHeight = self.parent.width, self.parent.height
    local bank = self.app.windows:BankBounds()
    local panelX = bank ~= nil and bank.x - parentX or 8
    local panelY = bank ~= nil and bank.y - parentY - HEIGHT - 8 or 8
    if panelY < 8 then
        panelY = bank ~= nil and bank.y - parentY + bank.height + 8 or 8
        if panelY + HEIGHT > screenHeight - 8 then panelY = 8 end
    end
    panelX = math.max(8, math.min(panelX, screenWidth - WIDTH - 8))
    panelY = math.max(8, math.min(panelY, screenHeight - HEIGHT - 8))
    self.window.root:SetPos(panelX, panelY)
    self.root:MoveToFront()
    self.window.root:MoveToFront()
    self.highlight.hidden = x == nil or width <= 0 or height <= 0
    self.arrow.hidden = self.highlight.hidden
    if self.highlight.hidden then return end
    x, y = x - parentX, y - parentY
    -- Rows outside their scrolling viewport must not light up
    local controls = self.app.tab.controls
    if (self.step == 2 or self.step == 3 or self.step == 7) and controls ~= nil
        and target == (self.tag ~= nil and self.app.tab:RowFor(self.tag) or {}).root then
        local _, viewportY, _, viewportHeight = bounds(controls.list.list.root)
        if viewportY ~= nil and (y + parentY < viewportY or y + parentY + height > viewportY + viewportHeight) then
            self.highlight.hidden = true
            self.arrow.hidden = true
            return
        end
    end
    self.highlight:SetPos(x - 1, y - 1)
    local w, h = math.max(20, width + 3), math.max(20, height + 3)
    self.highlight:SetSize(w, h)
    sizeFrame(self.flashYellow, w, h)
    sizeFrame(self.flashWhite, w, h)
    local pulse = 0.5 + 0.5 * math.sin(self.ticks / 7)
    self.flashYellow.root.alpha, self.flashWhite.root.alpha = pulse, 1 - pulse
    -- Put the large native arrow above the control when space permits
    local bob = 3 + 3 * math.sin(self.ticks / 7)
    if y >= 62 then
        self.arrow.rotationDegrees = 0
        self.arrow:SetPos(x + width / 2 - 20, y - 58 - bob)
    else
        self.arrow.rotationDegrees = 180
        self.arrow:SetPos(x + width / 2 - 20, y + height + 4 + bob)
    end
    self.highlight:MoveToFront()
    self.arrow:MoveToFront()
end

return TutorialView
