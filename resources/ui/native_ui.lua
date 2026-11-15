-- Provide native panel sprites and button styles

local NativeUi = {}

NativeUi.SPRITES = {
    PANEL_BACKGROUND = id.Sprite.OLD_BACKGROUND_TEXTURE,
    TUTORIAL_INFO = id.Sprite.TUTSYS_INFO_ICON,
    TUTORIAL_POINTER = id.Sprite.RS3_INFO_DISPLAY_POINTER,
    TUTORIAL_NAV_ARROW = id.Sprite.RS3_ICON_CALENDAR_NAVIGATION_24PX_0,
    HELP_BUTTON = id.Sprite.RS3_ICON_INFO_21PX_2,
    HELP_HOVER = id.Sprite.RS3_ICON_INFO_21PX_3,
    HELP_PRESSED = id.Sprite.RS3_ICON_INFO_21PX_4,
}

-- Look up a native style ID by name
function NativeUi.styleID(styleName)
    return id.StyleSheet[styleName]
end

-- Create a native-style text button
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

return NativeUi
