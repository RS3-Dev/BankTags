-- Build buttons with the native bank appearance

local NativeUi = require("resources/ui/native_ui")

local BankControls = {}

local NativeButton = {}
NativeButton.__index = NativeButton

-- Build a native-style button with one action
function BankControls.button(parent, content, action, options)
    options = options or {}
    local self = setmetatable({
        action = action,
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
            -- Run the button action only while enabled
            onPress = function()
                if self.disabled then return end
                if self.action ~= nil then self.action(self) end
            end,
        }
    )

    -- ui.Button holds no children, so decorations sit beside it
    -- and stay click-through
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
        -- Show the button icon's hovered appearance
        self.root:Subscribe(ui.Hook.ONMOUSEOVER, function()
            self.hovered = true
            self:_UpdateState()
            return true
        end)
        -- Restore the button icon after the pointer leaves
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

-- Refresh the button's input and appearance from its state
function NativeButton:_UpdateState()
    if self.root == nil then return end
    self.root.enabled = not self.disabled
    self.root.clickthrough = self.disabled
    self.root.hidden = self.hidden
    self.root.stylesheetID = NativeUi.styleID("BUTTON_PANEL")
    if self.root.text ~= nil then
        self.root.text.rgba = 0xE7D7B0FF
    end
    if self.icon ~= nil and self.sprites ~= nil then
        self.icon.hidden = self.hidden
        if self.disabled then
            self.icon.spriteID = self.sprites.disabled or self.sprites.neutral
        elseif self.hovered then
            self.icon.spriteID = self.sprites.active or self.sprites.neutral
        else
            self.icon.spriteID = self.sprites.neutral
        end
    end
end

-- Enable or disable the button
function NativeButton:SetDisabled(disabled)
    self.disabled = disabled == true
    self:_UpdateState()
end

-- Destroy the button and its decorations
function NativeButton:Destroy()
    prettyui.Tooltip.unbind(self)
    if self.icon ~= nil then self.icon:Destroy() end
    if self.root ~= nil then self.root:Destroy() end
    self.root = nil
    self.icon = nil
end

return BankControls
