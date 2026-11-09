-- Confirm a removal using PrettyUI's shared dialog lifecycle and actions

local Theme = require("resources/ui/theme")

local ConfirmWindow = {}
ConfirmWindow.__index = ConfirmWindow

-- Create a dialog asking to confirm a removal
function ConfirmWindow.new(parent, options)
    local self = setmetatable({ closed = false }, ConfirmWindow)
    self.dialog = prettyui.Dialog.new(parent, {
        title = options.title, width = 340, height = 164, modal = false,
        -- Draw the removal question inside the dialog
        content = function(window)
            self.message = window:AddText({
                text = options.message, x = 16, y = 18, width = 292, height = 52, maxLines = 4,
                colour = Theme.TEXT, alignHorizontal = ui.AlignMode.CENTRE,
            })
        end,
        onDismiss = function() self.closed = true end,
        actions = {
            { label = "Cancel", onClick = function() self.closed = true; return true end },
            -- Keep rejected removals open with their failure reason
            { label = options.confirmLabel, onClick = function()
                local saved, reason = options.onConfirm()
                if saved then self.closed = true; return true end
                self.message.content = tostring(reason or options.failureText)
                self.message.rgba = Theme.ERROR_TEXT
                return false
            end },
        },
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
    self.window, self.message = nil, nil
end

return ConfirmWindow
