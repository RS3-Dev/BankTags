-- Temporary click-feedback comparison; no bank item actions or persistent storage

local EVENT = "banktags_click_test"
local window, status, capture, drag
local counts = {}
local ticks = 0
local cells = {}
local useBankLayer = false
local menuAreaHovered = false
local show

-- Report callbacks independently from the client's visible click feedback
local function report(name, detail)
    counts[name] = (counts[name] or 0) + 1
    status.content = name .. ": " .. counts[name] .. " callbacks. " .. (detail or "")
    if type(log) == "function" then log("Bank Tags Click Test: ", name, " ", detail or "") end
end

-- Match the editor's fixed-origin capture surface and restore it after release
local function endDrag()
    if capture == nil then return end
    drag = nil
    capture.clip:SetPos(capture.x, capture.y)
    capture.clip:SetSize(capture.width, capture.height)
    capture.surface:SetPos(-capture.x, -capture.y)
end

-- Release all temporary UI and listeners on reload or unload
local function destroy()
    menuAreaHovered = false
    drag, capture = nil, nil
    if window ~= nil then
        local old = window
        window = nil
        old:Destroy()
    end
    status, cells = nil, {}
end

-- Keep labels and backgrounds from becoming a separate click target
local function label(parent, text, x, y, width, height, colour)
    local textControl = prettyui.Text.new(parent, {
        text = text, x = x, y = y, width = width, height = height,
        colour = colour or 0xE7D7B0FF, maxLines = 1,
        font = id.Font.MUSEO_SANS_11PT_REGULAR,
    })
    textControl.clickthrough = true
    return textControl
end

-- Build an inert decorated area; only the chosen surface receives input
local function area(parent, column, row, title, description)
    local x, y, width, height = 16 + column * 322, 72 + row * 92, 310, 80
    local root = ui.Layer.new(parent)
    root:SetPos(x, y)
    root:SetSize(width, height)
    root.clickthrough = false
    local fill = ui.Rectangle.new(root)
    fill:SetSize(width, height)
    fill.fill, fill.rgba, fill.clickthrough = true, 0x332E29FF, true
    local border = ui.Rectangle.new(root)
    border:SetSize(width, height)
    border.fill, border.rgba, border.outlineThickness, border.clickthrough = false, 0x806432FF, 1, true
    label(root, title, 10, 10, width - 20, 24, 0xE7C878FF)
    label(root, description, 10, 42, width - 20, 24)
    cells[#cells + 1] = root
    return root, x, y, width, height
end

-- Open outside the bank, using only the game-area parent and PrettyUI
show = function()
    if window ~= nil or prettyui == nil then return end
    local parent = ui.Interfaces:GetComponent(useBankLayer and id.Component.TOPLEVEL_V2__BANK_LAYER
        or id.Component.TOPLEVEL_V2__GAME_AREA)
    if parent == nil then return end
    window = prettyui.Window.new(parent, {
        title = "Bank Tags Click Test 0.0.2", x = 24, y = 48,
        width = 680, height = 550, minWidth = 680, maxWidth = 680,
        minHeight = 550, maxHeight = 550, scrollable = false,
        destroyOnClose = true,
        onClose = function()
            window, status, capture, drag, cells = nil, nil, nil, nil, {}
            menuAreaHovered = false
        end,
    })
    local parentContent = window.content
    label(parentContent, "Compare A-H with the bank closed, then open it and use the parent toggle below.", 16, 10, 632, 22)
    label(parentContent, "For H, pause over the area, then click its test action. Nothing is saved or moved.", 16, 34, 632, 22)
    status = label(parentContent, "Ready. Parent: " .. (useBankLayer and "bank layer" or "game area"), 16, 442, 632, 28)

    area(parentContent, 0, 0, "A. Plain layer", "No hooks; clickthrough = false")

    local stop = area(parentContent, 1, 0, "B. Layer, return false", "Click listener stops further listeners")
    stop:Subscribe(ui.Hook.ONCLICK, function() report("B", "Returned false."); return false end)

    local proceed = area(parentContent, 0, 1, "C. Layer, return true", "Click listener allows further listeners")
    proceed:Subscribe(ui.Hook.ONCLICK, function() report("C", "Returned true."); return true end)

    local native = area(parentContent, 1, 1, "D. Native ui.Button", "Click the inset button")
    local nativeButton = ui.Button.new(native)
    nativeButton:SetPos(10, 38)
    nativeButton:SetSize(290, 30)
    nativeButton.stylesheetID = id.StyleSheet.BUTTON_PANEL
    nativeButton.text.content = "Native button"
    nativeButton:Subscribe(ui.Hook.ONBUTTONPRESSED, function()
        report("D", "ONBUTTONPRESSED; returned false.")
        return false
    end)

    local simple = area(parentContent, 0, 2, "E. PrettyUI SimpleButton", "Click the inset button")
    prettyui.SimpleButton.new(simple, "PrettyUI button", function()
        report("E", "PrettyUI click action.")
    end, { x = 10, y = 38, width = 290, height = 30 })

    local surface, x, y, width, height = area(parentContent, 1, 2,
        "F. Editor-style drag capture", "Click, hold, drag, then release")
    surface.clickthrough = true
    local clip = ui.Layer.new(parentContent)
    clip.clickthrough = true
    local hit = ui.Layer.new(clip)
    hit:SetSize(window.contentWidth, window.content.height)
    hit.clickthrough = false
    capture = { clip = clip, surface = hit, x = x, y = y, width = width, height = height }
    endDrag()
    hit:Subscribe(ui.Hook.ONCLICK, function()
        endDrag()
        drag = { lastHold = ticks }
        clip:SetPos(0, 0)
        clip:SetSize(window.contentWidth, window.content.height)
        hit:SetPos(0, 0)
        clip:MoveToFront()
        report("F", "Press; capture expanded. Returned false.")
        return false
    end)
    hit:Subscribe(ui.Hook.ONHOLD, function()
        if drag ~= nil then drag.lastHold = ticks end
        return false
    end)
    hit:Subscribe(ui.Hook.ONDRAG, function() return false end)
    hit:Subscribe(ui.Hook.ONRELEASE, function()
        if drag ~= nil then report("F release", "Capture restored."); endDrag() end
        return false
    end)
    hit:Subscribe(ui.Hook.ONDRAGCOMPLETE, function() endDrag(); return false end)

    local item = area(parentContent, 0, 3, "G. Associated item + click layer", "Coin sprite under an input layer")
    local coin = ui.Sprite.new(item)
    coin:SetPos(264, 40)
    coin:SetSize(36, 32)
    coin:SetAssociatedObject(id.Obj.COINS)
    coin.clickthrough = true
    local itemHit = ui.Layer.new(item)
    itemHit:SetSize(310, 80)
    itemHit.clickthrough = false
    itemHit:Subscribe(ui.Hook.ONCLICK, function()
        report("G", "Associated item; returned false.")
        return false
    end)

    local menu = area(parentContent, 1, 3, "H. Mini-menu action", "Harmless custom left-click action")
    menu:Subscribe(ui.Hook.ONMOUSEOVER, function() menuAreaHovered = true; return true end)
    menu:Subscribe(ui.Hook.ONMOUSELEAVE, function() menuAreaHovered = false; return true end)
    prettyui.SimpleButton.new(parentContent, "Reset counters", function()
        counts = {}
        status.content = "Counters reset. A deliberately has no callback counter."
    end, { x = 16, y = 478, width = 144, height = 24 })
    prettyui.SimpleButton.new(parentContent, "Switch parent layer", function()
        if not useBankLayer and ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__BANK_WINDOW) == nil then
            status.content = "Open the bank first, then switch to its layer."
            return
        end
        useBankLayer = not useBankLayer
        destroy()
        show()
    end, { x = 176, y = 478, width = 200, height = 24 })
    label(parentContent, "Drag this window over the open bank.", 390, 478, 258, 24)
    window:Show()
end

Event.ContentLayerReady.Subscribe(EVENT, show)
-- Add a single no-op menu action only while the pointer is over H
Event.MiniMenuReady.Subscribe(EVENT, function(event)
    if window == nil or not menuAreaHovered then return end
    local menu = event and event.miniMenu
    if menu == nil then return end
    local labelText = "Click test H (no action)"
    menu:Add(labelText, function() report("H", "Mini-menu callback; no bank action.") end)
    for index, entry in ipairs(menu.entries) do
        if entry.overrideText == labelText or entry.fullText == labelText or entry.verbText == labelText then
            for current = index, menu.entryCount - 1 do menu:Swap(current, current + 1) end
            break
        end
    end
end)
Event.Logic.Subscribe(EVENT, function()
    ticks = ticks + 1
    if drag ~= nil and ticks - drag.lastHold >= 10 then endDrag() end
end)

show()

function PluginShutdown()
    Event.ContentLayerReady.Unsubscribe(EVENT)
    Event.MiniMenuReady.Unsubscribe(EVENT)
    Event.Logic.Unsubscribe(EVENT)
    destroy()
end
