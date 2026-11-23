-- Confirm a removal using PrettyUI's shared dialog lifecycle and actions

local Theme = require("resources/ui/theme")
local Text = require("resources/core/text")

local ConfirmWindow = {}
ConfirmWindow.__index = ConfirmWindow

-- Create a dialog asking to confirm a removal
function ConfirmWindow.new(parent, options)
    local self = setmetatable({ closed = false }, ConfirmWindow)
    self.dialog = prettyui.Dialog.new(parent, {
        categoryID = "auto",
        title = options.title, width = options.messageLines ~= nil and 420 or 340,
        height = options.messageLines ~= nil and 172 or 164, modal = false,
        -- Draw the removal question inside the dialog
        content = function(window)
            local width = window.contentWidth
            self.message = window:AddText({
                text = Text.sanitize(options.messageLines ~= nil and options.messageLines[1] or options.message),
                x = 16, y = 10, width = width - 32,
                height = options.messageLines ~= nil and 38 or 64,
                maxLines = options.messageLines ~= nil and 2 or 4,
                colour = Theme.TEXT, alignHorizontal = ui.AlignMode.CENTRE, alignVertical = ui.AlignMode.CENTRE,
            })
            if options.messageLines ~= nil then
                self.question = window:AddText({
                    text = Text.sanitize(options.messageLines[2]),
                    x = 16, y = 52, width = width - 32, height = 36, maxLines = 2,
                    colour = Theme.TEXT, alignHorizontal = ui.AlignMode.CENTRE, alignVertical = ui.AlignMode.CENTRE,
                })
            end
            local buttonWidth, gap = 128, 12
            local left = math.floor((width - 2 * buttonWidth - gap) / 2)
            window:AddSimpleButton("Cancel", function()
                self.closed = true
                self.dialog:Destroy()
            end, { x = left, y = -36, yAnchor = 1, width = buttonWidth, height = 28 })
            -- A failed removal stays open and shows its reason
            window:AddSimpleButton(options.confirmLabel, function()
                local saved, reason = options.onConfirm()
                if saved then
                    self.closed = true
                    self.dialog:Destroy()
                    return
                end
                self.message.content = Text.plain(reason or options.failureText)
                self.message.rgba = Theme.ERROR_TEXT
                self.message.maxLines = 4
                self.message:SetSize(width - 32, 64)
                if self.question ~= nil then self.question.hidden = true end
            end, { x = left + buttonWidth + gap, y = -36, yAnchor = 1, width = buttonWidth, height = 28 })
        end,
        onDismiss = function() self.closed = true end,
        actions = {},
    })
    self.window = self.dialog.window
    return self
end

-- Show the removal confirmation
function ConfirmWindow:Show()
    self.window:Show()
end

-- Release the confirmation and its message
function ConfirmWindow:Destroy()
    self.closed = true
    self.dialog:Destroy()
    self.window, self.message, self.question = nil, nil, nil
end

return ConfirmWindow
