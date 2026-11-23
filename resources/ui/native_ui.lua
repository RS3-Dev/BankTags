-- Provide native panel sprites and button styles

local NativeUi = {}

local sprite = type(id) == "table" and id.Sprite or {}

NativeUi.SPRITES = {
    PANEL_BACKGROUND = sprite.OLD_BACKGROUND_TEXTURE,
    TUTORIAL_INFO = sprite.TUTSYS_INFO_ICON,
    TUTORIAL_POINTER = sprite.RS3_INFO_DISPLAY_POINTER,
    TUTORIAL_NAV_ARROW = sprite.RS3_ICON_CALENDAR_NAVIGATION_24PX_0,
    HELP_BUTTON = sprite.RS3_ICON_INFO_21PX_2,
    HELP_HOVER = sprite.RS3_ICON_INFO_21PX_3,
    HELP_PRESSED = sprite.RS3_ICON_INFO_21PX_4,
}

-- Look up a native style ID by name
function NativeUi.styleID(styleName)
    return id.StyleSheet[styleName]
end

-- Create a native component using PrettyUI's automatic category allocator when available
function NativeUi.newComponent(nativeType, parent, options)
    if prettyui ~= nil and type(prettyui.NewComponent) == "function" then
        return prettyui.NewComponent(nativeType, parent, options)
    end
    return nativeType.new(parent)
end

-- Create a native-style text button
function NativeUi.makeButton(parent, x, y, width, height, options)
    options = options or {}
    local button = NativeUi.newComponent(ui.Button, parent)
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
