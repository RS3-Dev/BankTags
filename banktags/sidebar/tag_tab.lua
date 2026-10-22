-- Draw the Tags tab Bank Core mounts in its sidebar

local BankControls = require("banktags/ui/bank_controls")
local Geometry = require("banktags/ui/geometry")
local SidebarRows = require("banktags/ui/sidebar_rows")
local TagList = require("banktags/sidebar/tag_list")
local Text = require("banktags/core/text")
local Theme = require("banktags/ui/theme")
local NativeUi = require("banktags/ui/native_ui")

local TagTab = {}
TagTab.__index = TagTab

local FOOTER_X = SidebarRows.CONTENT_X
local FOOTER_BUTTON_HEIGHT = 28
local FOOTER_BUTTON_GAP = 8
local ICON_BUTTON_SIZE = 28
local STATUS_HEIGHT = 40
local PANEL_HEIGHT = 156
local PANEL_INSET = 10

-- Create the tab's mount callbacks, kept registered across updates
function TagTab.new(app)
    local self = setmetatable({ app = app, ctx = nil, controls = nil, listState = { searchQuery = "" } },
        TagTab)
    self.callbacks = {
        mount = function(ctx)
            self.ctx = ctx
            self:Build()
        end,
        resize = function() self:Build() end,
        unmount = function() self:Unmount() end,
        onItemDrop = function(item, x, y) self:Drop(item, x, y) end,
    }
    return self
end

-- Report whether the column is mounted now
function TagTab:IsMounted()
    return self.controls ~= nil
end

-- Describe the column's arrangement so refreshes rebuild only on change
function TagTab:Arrangement()
    return tostring(self.app.select:Tag()) .. "\n" .. tostring(self.app.status) .. "\n"
        .. tostring(self.app.shownTag ~= nil)
end

-- Destroy the column's controls; Bank Core destroys the layers they sit in
function TagTab:DestroyControls()
    local controls = self.controls
    self.controls = nil
    if controls == nil then return end
    controls.list:Destroy()
    for _, control in ipairs(controls.owned) do pcall(function() control:Destroy() end) end
    pcall(function() prettyui.Tooltip.unregisterContext(controls.parent) end)
end

-- Forget the column when Bank Core unmounts it
function TagTab:Unmount()
    self.app.tutorial:Stop(false)
    self:DestroyControls()
    self.ctx = nil
end

-- Add a click-through text line to the column
local function addText(parent, content, x, y, width, height, colour, maxLines)
    local text = ui.Text.new(parent)
    text:SetPos(x, y)
    text:SetSize(width, height)
    text.content = content
    text.font = id.Font.MUSEO_SANS_11PT_REGULAR
    text.rgba = colour
    text.isShadowed = true
    text.maxLines = maxLines or 1
    text.alignVertical = ui.AlignMode.CENTRE
    text.clickthrough = true
    return text
end

-- Add a filled click-through rectangle to the column
local function addRectangle(parent, x, y, width, height, colour)
    local value = ui.Rectangle.new(parent)
    value:SetPos(x, y)
    value:SetSize(width, height)
    value.fill = true
    value.rgba = colour
    value.clickthrough = true
    return value
end

-- Draw the select-mode panel with its tag, help, and Done
function TagTab:BuildSelectPanel(controls, top, width)
    local app, parent = self.app, controls.parent
    local tag = app.select:Tag()
    local owned = controls.owned
    local panel = ui.Layer.new(parent)
    panel:SetPos(FOOTER_X, top)
    panel:SetSize(width, PANEL_HEIGHT)
    panel.clickthrough = true
    owned[#owned + 1] = panel
    addRectangle(panel, 0, 0, width, PANEL_HEIGHT, Theme.ROW_EVEN)
    addRectangle(panel, 0, 0, width, 1, Theme.FRAME)
    addText(panel, "Select mode", PANEL_INSET, 4, width - PANEL_INSET * 2, 22, Theme.HEADING_TEXT)
    addRectangle(panel, PANEL_INSET, 26, width - PANEL_INSET * 2, 1, Theme.HEADING_LINE)
    local nameLeft = PANEL_INSET
    local objectID = app.store:GetTagSprite(tag)
    if objectID ~= nil then
        local icon = ui.Sprite.new(panel)
        icon:SetPos(PANEL_INSET, 32)
        icon:SetSize(28, 28)
        icon:SetAssociatedObject(objectID)
        icon.associatedObjectQuantityMode = ui.ObjectQuantityDisplayMode.NEVER
        icon.clickthrough = true
        nameLeft = PANEL_INSET + 34
    end
    addText(panel, Text.titleCase(tag), nameLeft, 32, width - nameLeft - PANEL_INSET, 28, Theme.TEXT)
    addText(panel, "Click items in your bank to add them to this tag.",
        PANEL_INSET, 62, width - PANEL_INSET * 2, 30, Theme.MUTED_TEXT, 2)
    addText(panel, "Items already in this tag have a gold outline.",
        PANEL_INSET, 90, width - PANEL_INSET * 2, 30, Theme.MUTED_TEXT, 2)
    owned[#owned + 1] = BankControls.button(parent, "Done", function() app.select:Stop() end, {
        x = FOOTER_X + PANEL_INSET,
        y = top + PANEL_HEIGHT - FOOTER_BUTTON_HEIGHT - 6,
        width = width - PANEL_INSET * 2,
        height = FOOTER_BUTTON_HEIGHT,
    })
end

-- Draw the footer with Import/Share, New Tag, and the layout editor
function TagTab:BuildFooter(controls, height, width)
    local app, parent, owned = self.app, controls.parent, controls.owned
    local top = height - 36
    owned[#owned + 1] = BankControls.button(parent, nil, function() app.windows:OpenImportShare() end, {
        x = FOOTER_X, y = top, size = ICON_BUTTON_SIZE, iconSize = 18,
        spriteName = "EXPORT", tooltip = "Import and share bank tags",
    })
    local editing = app.shownTag ~= nil
    local newTagX = FOOTER_X + ICON_BUTTON_SIZE + FOOTER_BUTTON_GAP
    local newTagWidth = width - ICON_BUTTON_SIZE - FOOTER_BUTTON_GAP
        - ICON_BUTTON_SIZE - FOOTER_BUTTON_GAP
        - (editing and ICON_BUTTON_SIZE + FOOTER_BUTTON_GAP or 0)
    controls.newTagButton = BankControls.button(parent, "New Tag", function()
        app:ShowStatus(nil)
        app.windows:OpenTagSettings(app.store:NextPlaceholderTagName(), true)
    end, {
        x = newTagX, y = top, width = newTagWidth, height = FOOTER_BUTTON_HEIGHT,
        tooltip = "Create a new bank tag",
    })
    owned[#owned + 1] = controls.newTagButton
    if editing then
        controls.editTagButton = BankControls.button(parent, nil, function()
            app.windows:OpenLayoutEditor(app.shownTag)
        end, {
            x = newTagX + newTagWidth + FOOTER_BUTTON_GAP, y = top, size = ICON_BUTTON_SIZE, iconSize = 18,
            spriteName = "PENCIL", tooltip = "Edit tag layout",
        })
        owned[#owned + 1] = controls.editTagButton
    end
    controls.tutorialButton = BankControls.button(parent, "", function() app.tutorial:Start() end, {
        x = FOOTER_X + width - ICON_BUTTON_SIZE, y = top,
        width = ICON_BUTTON_SIZE, height = FOOTER_BUTTON_HEIGHT, tooltip = "Help",
    })
    owned[#owned + 1] = controls.tutorialButton
    -- The native Help sprite supplies its own button frame
    local help = controls.tutorialButton.root
    help.alpha = 0
    controls.tutorialIcon = ui.Sprite.new(parent)
    local icon = controls.tutorialIcon
    icon:SetPos(FOOTER_X + width - ICON_BUTTON_SIZE + 4, top + 4)
    icon:SetSize(19, 19)
    icon.spriteID = NativeUi.SPRITES.HELP_BUTTON
    icon.clickthrough = true
    owned[#owned + 1] = icon
    help:Subscribe(ui.Hook.ONMOUSEOVER, function()
        icon.spriteID = NativeUi.SPRITES.HELP_BUTTON + 1
        return false
    end)
    help:Subscribe(ui.Hook.ONMOUSELEAVE, function()
        icon.spriteID = NativeUi.SPRITES.HELP_BUTTON
        return false
    end)
    help:Subscribe(ui.Hook.ONCLICK, function()
        icon.spriteID = NativeUi.SPRITES.HELP_BUTTON + 2
        return false
    end)
    help:Subscribe(ui.Hook.ONRELEASE, function()
        icon.spriteID = NativeUi.SPRITES.HELP_BUTTON + (help.isMouseOver and 1 or 0)
        return false
    end)
end

-- Build the column inside Bank Core's parent
function TagTab:Build()
    self:DestroyControls()
    local ctx = self.ctx
    if ctx == nil then return end
    local app = self.app
    local bounds = ctx:GetBounds()
    local parent, overlay = ctx.parent, ctx.overlay
    local width = SidebarRows.ContentWidth(bounds.width)
    local controls = { parent = parent, owned = {}, arrangement = self:Arrangement() }
    -- Tooltips draw in the overlay so the column does not clip them
    prettyui.Tooltip.registerContext(parent, overlay, function(target)
        local x, y = Geometry.absolutePosition(target)
        local originX, originY = Geometry.absolutePosition(overlay)
        return x - originX, y - originY
    end)

    local bottom = bounds.height - SidebarRows.FOOTER_HEIGHT
    if app.select:Tag() ~= nil then bottom = bottom - PANEL_HEIGHT - 4 end
    if app.status ~= nil then bottom = bottom - STATUS_HEIGHT end
    controls.list = TagList.new(parent, {
        store = app.store,
        settings = function() return app.settings end,
        state = self.listState,
        width = bounds.width,
        listHeight = math.max(1, bottom - SidebarRows.LIST_TOP - 4),
        isSelected = function(tag) return tag == app.shownTag or tag == app.select:Tag() end,
        onSelect = function(tag)
            app:ShowStatus(nil)
            app:ToggleTag(tag)
        end,
        onChanged = function() app:Changed(nil) end,
    })
    self.controls = controls
    if app.status ~= nil then
        controls.owned[#controls.owned + 1] = addText(parent, app.status, FOOTER_X, bottom,
            width, STATUS_HEIGHT - 4, Theme.ERROR_TEXT, 3)
    end
    if app.select:Tag() ~= nil then
        self:BuildSelectPanel(controls, bounds.height - SidebarRows.FOOTER_HEIGHT - PANEL_HEIGHT, width)
    end
    self:BuildFooter(controls, bounds.height, width)
    app.tutorial:Mounted()
end

-- Show current tags, rebuilding only when the arrangement changed
function TagTab:Refresh()
    if self.controls == nil then return end
    if self.controls.arrangement ~= self:Arrangement() then
        self:Build()
    else
        self.controls.list:Refresh()
    end
end

-- Find the drawn row for a tag, if the column shows it
function TagTab:RowFor(tag)
    return self.controls ~= nil and self.controls.list:RowFor(tag) or nil
end

-- Tag a dropped item, or start a new tag from New Tag
-- Numbered tabs name no copy, so those drops tag the first copy
function TagTab:Drop(item, x, y)
    local hovered = self.controls ~= nil and self.controls.list:HoveredEntry() or nil
    log("Bank Tags drop trace: mounted=", tostring(self.controls ~= nil), " view=", tostring(item.view),
        " tag=", tostring(hovered ~= nil and hovered.tag), " newTagHover=",
        tostring(self.controls ~= nil and self.controls.newTagButton.root.isMouseOver),
        " x=", tostring(x), " y=", tostring(y))
    if self.controls == nil or item.view ~= "native" then return end
    local objectID = type(item.objectID) == "number" and math.tointeger(item.objectID) or nil
    if objectID == nil or objectID <= 0 then return end
    local copy = item.copy or 1
    if self.controls.newTagButton.root.isMouseOver == true then
        self.app:CreateTagWithItem(objectID, copy)
        return
    end
    local entry = self.controls.list:HoveredEntry()
    if entry ~= nil and entry.kind == "tag" then
        self.app:AddItemToTag(entry.tag, objectID, copy)
    end
end

return TagTab
