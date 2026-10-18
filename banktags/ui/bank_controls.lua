-- Build buttons with the native bank appearance

local NativeUi = require("banktags/ui/native_ui")

local BankControls = {}

local NativeButton = {}
NativeButton.__index = NativeButton

-- Build a native-style button with separate decorative children and one action callback
function BankControls.button(parent, content, action, options)
    options = options or {}
    local self = setmetatable({
        action = action,
        active = options.active == true,
        disabled = options.disabled == true,
        spriteName = options.spriteName,
        parent = parent,
        x = options.x or 0,
        y = options.y or 0,
        width = options.width or options.size or 24,
        height = options.height or options.size or 24,
        iconSize = options.iconSize,
        hidden = options.hidden == true,
    }, NativeButton)

    self.root = NativeUi.makeButton(
        parent,
        self.x,
        self.y,
        self.width,
        self.height,
        {
            text = self.spriteName == nil and tostring(content or "") or "",
            onPress = function()
                if self.disabled then return end
                if self.action ~= nil then self.action(self, self.active) end
            end,
        }
    )

    -- ui.Button is an input component, not a ComponentCollectionBase. Keep
    -- decorative children beside it on the rail and make them click-through
    if self.spriteName ~= nil then
        self.sprites = prettyui.Sprites.SPRITE_BUTTONS[self.spriteName]
        self.icon = ui.Sprite.new(parent)
        local iconSize = self.iconSize or math.max(12, self.height - 8)
        self.iconSize = iconSize
        self.icon:SetPos(
            self.x + math.floor((self.width - iconSize) / 2),
            self.y + math.floor((self.height - iconSize) / 2)
        )
        self.icon:SetSize(iconSize, iconSize)
        self.icon.clickthrough = true
        self.root:Subscribe(ui.Hook.ONMOUSEOVER, function()
            self.hovered = true
            self:_UpdateState()
            return true
        end)
        self.root:Subscribe(ui.Hook.ONMOUSELEAVE, function()
            self.hovered = false
            self:_UpdateState()
            return true
        end)
    end

    prettyui.Tooltip.bind(self, self.root, parent, options.tooltip)
    self:_UpdateState()
    return self
end

-- Refresh button input, label, icon, and selection appearance from its current state
function NativeButton:_UpdateState()
    if self.root == nil then return end
    self.root.enabled = not self.disabled
    self.root.clickthrough = self.disabled
    self.root.hidden = self.hidden
    self.root.stylesheetID = NativeUi.styleID("BUTTON_PANEL")
    if self.root.text ~= nil then
        self.root.text.rgba = self.active and 0xF2C66DFF or 0xE7D7B0FF
    end
    if self.icon ~= nil and self.sprites ~= nil then
        self.icon.hidden = self.hidden
        if self.disabled then
            self.icon.spriteID = self.sprites.disabled or self.sprites.neutral
        elseif self.active or self.hovered then
            self.icon.spriteID = self.sprites.active or self.sprites.neutral
        else
            self.icon.spriteID = self.sprites.neutral
        end
    end
end

-- Resize the button and recenter its icon
function NativeButton:SetSize(width, height)
    self.width = width or self.width
    self.height = height or self.height
    self.root:SetSize(self.width, self.height)
    if self.icon ~= nil then
        self.icon:SetPos(
            self.x + math.floor((self.width - self.iconSize) / 2),
            self.y + math.floor((self.height - self.iconSize) / 2)
        )
    end
end

-- Update visibility and refresh the control's own appearance
function NativeButton:SetHidden(hidden)
    self.hidden = hidden == true
    self:_UpdateState()
end

-- Update selection state and refresh the control's own appearance
function NativeButton:SetActive(active)
    self.active = active == true
    self:_UpdateState()
end

-- Use the existing active-state setter for callers that use selection terminology
function NativeButton:SetSelected(selected)
    self:SetActive(selected)
end

-- Update input availability and refresh the control's own appearance
function NativeButton:SetDisabled(disabled)
    self.disabled = disabled == true
    self:_UpdateState()
end

-- Update the tooltip through the shared PrettyUI binding
function NativeButton:SetTooltip(value)
    return prettyui.Tooltip.set(self, value)
end

-- Unbind the tooltip and destroy the button and its decorative siblings
function NativeButton:Destroy()
    prettyui.Tooltip.unbind(self)
    if self.icon ~= nil then self.icon:Destroy() end
    if self.root ~= nil then self.root:Destroy() end
    self.root = nil
    self.icon = nil
end

return BankControls
