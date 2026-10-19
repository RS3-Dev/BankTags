-- Draw Bank Tags' plugin panel: a notice and Import/Share

local PluginPanel = {}
PluginPanel.__index = PluginPanel

local MAX_WIDTH = 280
local CONTENT_HEIGHT = 200
local TEXT = 0xD7C9ADFF
local GOLD = 0xF2C66DFF

-- Mount the notice and the Import/Share button
function PluginPanel.new(parent, options)
    local self = setmetatable({ destroyed = false }, PluginPanel)
    self.view = prettyui.SimpleView.new(parent, {
        width = parent.width, height = parent.height,
        contentHeight = CONTENT_HEIGHT, scrollable = true, scrollStep = 32,
    })
    local content = self.view.content
    local contentWidth = tonumber(content.width) or 0
    if contentWidth <= 0 then contentWidth = math.max(1, (parent.width or 300) - 18) end
    local width = math.min(MAX_WIDTH, math.max(1, contentWidth - 24))
    local x = math.max(12, math.floor((contentWidth - width) / 2))
    self.background = ui.Rectangle.new(content)
    self.background:SetPos(x, 12)
    self.background:SetSize(width, 28)
    self.background.fill = true
    self.background.rgba = 0x2A231BFF
    self.background.clickthrough = true
    self.title = prettyui.Text.new(content, {
        text = "Bank Tags", x = x + 10, y = 12, width = width - 20, height = 28,
        font = id.Font.MUSEO_SANS_11PT_REGULAR, colour = GOLD, maxLines = 1,
    })
    self.title.clickthrough = true
    self.notice = prettyui.Text.new(content, {
        text = "", x = x, y = 48, width = width, height = 60,
        font = id.Font.MUSEO_SANS_11PT_REGULAR, colour = TEXT, maxLines = 3,
    })
    self.notice.clickthrough = true
    self.importButton = prettyui.SimpleButton.new(content, "Import / Share tags", function()
        if not self.destroyed then options.onOpenImport() end
    end, { x = x, y = 116, width = width, height = 30 })
    self:ShowNotice(options.notice)
    return self
end

-- Show the panel notice
function PluginPanel:ShowNotice(text)
    if self.destroyed then return end
    self.notice.content = text or ""
end

-- Release the panel controls
function PluginPanel:Destroy()
    if self.destroyed then return end
    self.destroyed = true
    for _, control in ipairs({ self.importButton, self.notice, self.title, self.background, self.view }) do
        pcall(function() control:Destroy() end)
    end
end

return PluginPanel
