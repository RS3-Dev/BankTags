-- Provide native panel sprites and button styles

local NativeUi = {}

NativeUi.SPRITES = {
    PANEL_BACKGROUND = 8082,
    TUTORIAL_INFO = 9966,
    TUTORIAL_POINTER = 21393,
    TUTORIAL_NAV_ARROW = 9403,
    HELP_BUTTON = 36389,
}

local STYLE_FALLBACK_IDS = {
    BUTTON_PANEL = 318,
}

-- Look up a native style ID by name
function NativeUi.styleID(styleName)
    if id ~= nil and id.StyleSheet ~= nil and id.StyleSheet[styleName] ~= nil then
        return id.StyleSheet[styleName]
    end
    return STYLE_FALLBACK_IDS[styleName]
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
