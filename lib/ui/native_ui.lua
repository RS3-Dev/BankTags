-- Provide native-style primitives used by the bank and its editors

local Config = require("lib/core/config")
local debugLog = require("lib/core/debug_log").Write

local NativeUi = {}

NativeUi.SPRITES = {
    LOCK = 4346,
    PANEL_BACKGROUND = 8082,
    SCROLLBAR_UP_BUTTON = 18436,
    SCROLLBAR_DOWN_BUTTON = 18437,
    SCROLLBAR_TRACK_MIDDLE = 792,
    SCROLLBAR_DRAGGER_TOP = 18423,
    SCROLLBAR_DRAGGER_BOTTOM = 18424,
    SCROLLBAR_DRAGGER_MIDDLE = 18425
}

NativeUi.SCROLLBAR = {
    BUTTON_VISIBLE_WIDTH = 16,
    BUTTON_VISIBLE_HEIGHT = 12,
    TRACK_VISIBLE_WIDTH = 16,
    BUTTON_TRACK_GAP = 0,
    THUMB_TRACK_PADDING = 0,
    DRAGGER_CAP_HEIGHT = 6,
    DRAGGER_VISIBLE_WIDTH = 12
}

local STYLE_FALLBACK_IDS = {
    RECT_DARK = 12,
    RECT_HIGHLIGHT = 65,
    RECT_MEDIUM = 173,
    RECT_BLACK = 269,
    BUTTON_DEFAULT = 96,
    BUTTON_PANEL = 318,
    BUTTON_PANEL_INACTIVE = 319
}

-- Resolve a named native style through host IDs or the known style table
function NativeUi.styleID(styleName, fallback)
    if id ~= nil and id.StyleSheet ~= nil and id.StyleSheet[styleName] ~= nil then
        return id.StyleSheet[styleName]
    end

    return STYLE_FALLBACK_IDS[styleName] or fallback
end

-- Apply a resolved native style while allowing host components that reject it
function NativeUi.applyStyle(component, styleName, fallback)
    if component == nil then
        return
    end

    local resolvedStyleID = NativeUi.styleID(styleName, fallback)

    if resolvedStyleID == nil then
        return
    end

    pcall(function()
        component.stylesheetID = resolvedStyleID
    end)
end

-- Create and position a native sprite with the requested tint and input behaviour
function NativeUi.makeSprite(parent, dynamicID, x, y, width, height, spriteID, options)
    options = options or {}

    if ui.Sprite == nil then
        return nil
    end

    local ok, sprite = pcall(function()
        return ui.Sprite.new(parent, Config.UI_CATEGORY_ID, dynamicID)
    end)

    if not ok or sprite == nil then
        debugLog("proxy sprite create failed id=", tostring(dynamicID), " sprite=", tostring(spriteID), " error=", tostring(sprite))
        return nil
    end

    sprite:SetPos(x, y)
    sprite:SetSize(width, height)
    sprite.sprite = spriteID
    sprite.colour = options.colour or Vector4.new(1.0, 1.0, 1.0, 1.0)

    pcall(function()
        sprite.clickthrough = options.clickthrough ~= false
    end)

    return sprite
end

-- Create a native-style text button and bind its press callback
function NativeUi.makeButton(parent, x, y, width, height, options)
    options = options or {}

    local button = ui.Button.new(parent)
    button:SetPos(x, y)
    button:SetSize(width, height)
    button.stylesheetID = NativeUi.styleID(options.styleName or "BUTTON_PANEL", options.fallback or Config.BUTTON_STYLE_ID)

    if button.text ~= nil then
        button.text.content = options.text or ""
    end

    if options.onPress ~= nil then
        button:Subscribe(ui.Hook.ONBUTTONPRESSED, options.onPress)
    end

    return button
end

-- Apply rotation through the host's supported sprite method and property variants
function NativeUi.setSpriteRotation(sprite, rotationRadians, rotationDegrees)
    if sprite == nil then
        return
    end

    if sprite.SetRotation ~= nil then
        pcall(function()
            sprite:SetRotation(rotationRadians)
        end)
    end

    pcall(function()
        sprite.rotation = rotationRadians
    end)

    pcall(function()
        sprite.angle = rotationRadians
    end)

    pcall(function()
        sprite.rotationDegrees = rotationDegrees
    end)

    pcall(function()
        sprite.angleDegrees = rotationDegrees
    end)
end

-- Front a component when the host exposes the operation
function NativeUi.moveToFront(component)
    if component == nil or component.MoveToFront == nil then
        return
    end

    pcall(function()
        component:MoveToFront()
    end)
end

local Scrollbar = {}
Scrollbar.__index = Scrollbar

-- Return the arrow height used to reserve space above and below the track
function Scrollbar:arrowSize()
    return self.metrics.BUTTON_VISIBLE_HEIGHT
end

-- Return the visible width reserved for a scrollbar arrow
function Scrollbar:buttonWidth()
    return math.max(1, self.metrics.BUTTON_VISIBLE_WIDTH)
end

-- Return the visible height reserved for a scrollbar arrow
function Scrollbar:buttonHeight()
    return math.max(1, self.metrics.BUTTON_VISIBLE_HEIGHT)
end

-- Center the arrow button within the scrollbar width
function Scrollbar:buttonX()
    return self.x + math.floor((self.width - self:buttonWidth()) / 2)
end

-- Return the configured visible track width
function Scrollbar:trackWidth()
    return math.max(1, self.metrics.TRACK_VISIBLE_WIDTH)
end

-- Center the track within the scrollbar width
function Scrollbar:trackX()
    return self.x + math.floor((self.width - self:trackWidth()) / 2)
end

-- Return the configured visible width of the scrollbar thumb
function Scrollbar:thumbWidth()
    return math.max(1, self.metrics.DRAGGER_VISIBLE_WIDTH)
end

-- Center the thumb within the scrollbar width
function Scrollbar:thumbX()
    return self.x + math.floor((self.width - self:thumbWidth()) / 2)
end

-- Place the track beneath the up arrow and its configured gap
function Scrollbar:trackY()
    return self.y + self:arrowSize() + self.metrics.BUTTON_TRACK_GAP
end

-- Measure the track between the two arrows and their gaps
function Scrollbar:trackHeight()
    return math.max(1, self.height - (self:arrowSize() * 2) - (self.metrics.BUTTON_TRACK_GAP * 2))
end

-- Include padding above the thumb's usable travel area
function Scrollbar:thumbTrackY()
    return self:trackY() + self.metrics.THUMB_TRACK_PADDING
end

-- Measure the thumb travel area after track padding
function Scrollbar:thumbTrackHeight()
    return math.max(1, self:trackHeight() - (self.metrics.THUMB_TRACK_PADDING * 2))
end

-- Measure the content beyond the visible viewport
function Scrollbar:maxScrollY(totalRows, rowHeight)
    return math.max(0, (totalRows * rowHeight) - self.contentHeight)
end

-- Size the thumb proportionally to visible content while respecting its minimum height
function Scrollbar:thumbHeight(totalRows, rowHeight)
    local scrollContentHeight = math.max(rowHeight, totalRows * rowHeight)

    if scrollContentHeight <= self.contentHeight then
        return self:thumbTrackHeight()
    end

    return math.max(
        self.minThumbHeight,
        math.floor((self.contentHeight / scrollContentHeight) * self:thumbTrackHeight())
    )
end

-- Convert a content offset to the thumb's position within its travel area
function Scrollbar:thumbY(totalRows, scrollY, rowHeight)
    local maxScrollY = self:maxScrollY(totalRows, rowHeight)
    local maxThumbY = self:thumbTrackHeight() - self:thumbHeight(totalRows, rowHeight)

    if maxScrollY <= 0 or maxThumbY <= 0 then
        return 0
    end

    return math.floor(((scrollY / maxScrollY) * maxThumbY) + 0.5)
end

-- Convert a track-relative mouse position into a clamped content offset
function Scrollbar:scrollValueFromMouse(relativeMouseY, totalRows, rowHeight)
    local maxScrollY = self:maxScrollY(totalRows, rowHeight)

    if maxScrollY <= 0 then
        return 0
    end

    local thumbHeight = self:thumbHeight(totalRows, rowHeight)
    local maxThumbY = self:thumbTrackHeight() - thumbHeight

    if maxThumbY <= 0 then
        return 0
    end

    local relativeY = relativeMouseY
        - self:thumbTrackY()
        - math.floor(thumbHeight / 2)
    local thumbY = math.max(0, math.min(maxThumbY, relativeY))

    return (thumbY / maxThumbY) * maxScrollY
end

-- Resize and position the track and thumb from the visible content and scroll offset
function Scrollbar:refresh(totalRows, scrollY, rowHeight)
    if self.track == nil or self.thumb == nil then
        return
    end

    local thumbHeight = self:thumbHeight(totalRows, rowHeight)
    local thumbY = self:thumbY(totalRows, scrollY, rowHeight)
    local absoluteThumbY = self:thumbTrackY() + thumbY
    local thumbCapHeight = math.min(self.metrics.DRAGGER_CAP_HEIGHT, math.floor(thumbHeight / 2))
    local thumbMiddleHeight = math.max(1, thumbHeight - (thumbCapHeight * 2))

    self.track:SetPos(self.x, self:trackY())
    self.track:SetSize(self.width, self:trackHeight())
    self.track.colour = Vector4.new(1.0, 1.0, 1.0, 0.01)

    if self.trackSprite ~= nil then
        self.trackSprite:SetPos(self:trackX(), self:trackY())
        self.trackSprite:SetSize(self:trackWidth(), self:trackHeight())
    end

    self.thumb:SetPos(self.x, absoluteThumbY)
    self.thumb:SetSize(self.width, thumbHeight)
    self.thumb.colour = Vector4.new(1.0, 1.0, 1.0, 0.01)

    if self.thumbTop ~= nil then
        self.thumbTop:SetPos(self:thumbX(), absoluteThumbY)
        self.thumbTop:SetSize(self:thumbWidth(), thumbCapHeight)
    end

    if self.thumbMiddle ~= nil then
        self.thumbMiddle:SetPos(self:thumbX(), absoluteThumbY + thumbCapHeight)
        self.thumbMiddle:SetSize(self:thumbWidth(), thumbMiddleHeight)
    end

    if self.thumbBottom ~= nil then
        self.thumbBottom:SetPos(self:thumbX(), absoluteThumbY + thumbHeight - thumbCapHeight)
        self.thumbBottom:SetSize(self:thumbWidth(), thumbCapHeight)
    end

    self:moveToFront()
end

-- Front scrollbar input and decorative parts in their intended order
function Scrollbar:moveToFront()
    NativeUi.moveToFront(self.track)
    NativeUi.moveToFront(self.trackSprite)
    NativeUi.moveToFront(self.thumb)
    NativeUi.moveToFront(self.thumbTop)
    NativeUi.moveToFront(self.thumbMiddle)
    NativeUi.moveToFront(self.thumbBottom)
    NativeUi.moveToFront(self.upArrow)
    NativeUi.moveToFront(self.downArrow)
end

-- Create a scrollbar sprite that can receive arrow or thumb input
local function makeScrollbarSprite(parent, dynamicID, x, y, width, height, spriteID)
    return NativeUi.makeSprite(parent, dynamicID, x, y, width, height, spriteID, {
        clickthrough = false
    })
end

-- Build arrow, track, and thumb controls and connect the supplied scroll callbacks
function NativeUi.createScrollbar(parent, options)
    local metrics = options.metrics or NativeUi.SCROLLBAR
    local scrollbar = setmetatable({
        parent = parent,
        x = options.x,
        y = options.y,
        width = options.width,
        height = options.height,
        contentHeight = options.contentHeight or options.height,
        minThumbHeight = options.minThumbHeight,
        metrics = metrics
    }, Scrollbar)

    scrollbar.upArrow = makeScrollbarSprite(
        parent,
        options.dynamicIDs.upArrow,
        scrollbar:buttonX(),
        options.y,
        scrollbar:buttonWidth(),
        scrollbar:buttonHeight(),
        NativeUi.SPRITES.SCROLLBAR_UP_BUTTON
    )
    NativeUi.setSpriteRotation(scrollbar.upArrow, 0, 0)

    scrollbar.downArrow = makeScrollbarSprite(
        parent,
        options.dynamicIDs.downArrow,
        scrollbar:buttonX(),
        options.y + options.height - scrollbar:buttonHeight(),
        scrollbar:buttonWidth(),
        scrollbar:buttonHeight(),
        NativeUi.SPRITES.SCROLLBAR_DOWN_BUTTON
    )

    scrollbar.track = ui.Rectangle.new(parent, Config.UI_CATEGORY_ID, options.dynamicIDs.track)
    scrollbar.track:SetPos(options.x, scrollbar:trackY())
    scrollbar.track:SetSize(options.width, scrollbar:trackHeight())
    scrollbar.track.colour = Vector4.new(1.0, 1.0, 1.0, 0.01)
    scrollbar.track.fill = true
    NativeUi.applyStyle(scrollbar.track, "RECT_BLACK", nil)

    scrollbar.trackSprite = NativeUi.makeSprite(
        parent,
        options.dynamicIDs.trackSprite,
        scrollbar:trackX(),
        scrollbar:trackY(),
        scrollbar:trackWidth(),
        scrollbar:trackHeight(),
        NativeUi.SPRITES.SCROLLBAR_TRACK_MIDDLE
    )

    scrollbar.thumb = ui.Rectangle.new(parent, Config.UI_CATEGORY_ID, options.dynamicIDs.thumb)
    scrollbar.thumb:SetPos(options.x, scrollbar:trackY())
    scrollbar.thumb:SetSize(options.width, options.minThumbHeight)
    scrollbar.thumb.colour = Vector4.new(1.0, 1.0, 1.0, 0.01)
    scrollbar.thumb.fill = true

    scrollbar.thumbTop = makeScrollbarSprite(
        parent,
        options.dynamicIDs.thumbTop,
        scrollbar:thumbX(),
        scrollbar:trackY(),
        scrollbar:thumbWidth(),
        metrics.DRAGGER_CAP_HEIGHT,
        NativeUi.SPRITES.SCROLLBAR_DRAGGER_TOP
    )

    scrollbar.thumbMiddle = makeScrollbarSprite(
        parent,
        options.dynamicIDs.thumbMiddle,
        scrollbar:thumbX(),
        scrollbar:trackY() + metrics.DRAGGER_CAP_HEIGHT,
        scrollbar:thumbWidth(),
        options.minThumbHeight - (metrics.DRAGGER_CAP_HEIGHT * 2),
        NativeUi.SPRITES.SCROLLBAR_DRAGGER_MIDDLE
    )

    scrollbar.thumbBottom = makeScrollbarSprite(
        parent,
        options.dynamicIDs.thumbBottom,
        scrollbar:thumbX(),
        scrollbar:trackY() + options.minThumbHeight - metrics.DRAGGER_CAP_HEIGHT,
        scrollbar:thumbWidth(),
        metrics.DRAGGER_CAP_HEIGHT,
        NativeUi.SPRITES.SCROLLBAR_DRAGGER_BOTTOM
    )

    if options.onThumbDrag ~= nil then
        pcall(function()
            scrollbar.thumb:Subscribe(ui.Hook.ONHOLD, options.onThumbDrag)
        end)

        pcall(function()
            scrollbar.thumb:Subscribe(ui.Hook.ONBUTTONPRESSED, options.onThumbDrag)
        end)
    end

    if options.onTrackPress ~= nil then
        pcall(function()
            scrollbar.track:Subscribe(ui.Hook.ONBUTTONPRESSED, options.onTrackPress)
        end)
    end

    if options.onUp ~= nil and scrollbar.upArrow ~= nil then
        pcall(function()
            scrollbar.upArrow:Subscribe(ui.Hook.ONBUTTONPRESSED, options.onUp)
        end)
    end

    if options.onDown ~= nil and scrollbar.downArrow ~= nil then
        pcall(function()
            scrollbar.downArrow:Subscribe(ui.Hook.ONBUTTONPRESSED, options.onDown)
        end)
    end

    return scrollbar
end

return NativeUi
