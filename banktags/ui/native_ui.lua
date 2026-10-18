-- Provide the native-style pieces Bank Tags draws with: panel sprites, button styles, and
-- sprite rotation

local NativeUi = {}

NativeUi.SPRITES = {
    PANEL_BACKGROUND = 8082,
}

local STYLE_FALLBACK_IDS = {
    BUTTON_PANEL = 318,
}

-- Resolve a named native style through host IDs or the known style table
function NativeUi.styleID(styleName)
    if id ~= nil and id.StyleSheet ~= nil and id.StyleSheet[styleName] ~= nil then
        return id.StyleSheet[styleName]
    end
    return STYLE_FALLBACK_IDS[styleName]
end

-- Create a native-style text button and bind its press callback
function NativeUi.makeButton(parent, x, y, width, height, options)
    options = options or {}
    local button = ui.Button.new(parent)
    button:SetPos(x, y)
    button:SetSize(width, height)
    button.stylesheetID = NativeUi.styleID("BUTTON_PANEL")
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
    if sprite.SetRotation ~= nil then
        pcall(function() sprite:SetRotation(rotationRadians) end)
    end
    pcall(function() sprite.rotation = rotationRadians end)
    pcall(function() sprite.angle = rotationRadians end)
    pcall(function() sprite.rotationDegrees = rotationDegrees end)
    pcall(function() sprite.angleDegrees = rotationDegrees end)
end

return NativeUi
