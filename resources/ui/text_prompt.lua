-- Ask for a short name using PrettyUI's shared dialog lifecycle and footer

local Theme = require("resources/ui/theme")
local Text = require("resources/core/text")

local TextPrompt = {}
TextPrompt.__index = TextPrompt

-- Create a short text prompt with shared dialog controls
function TextPrompt.new(parent, options)
    local self = setmetatable({ onSave = options.onSave, onDelete = options.onDelete, closed = false }, TextPrompt)
    local actions = {}
    if self.onDelete ~= nil then
        actions[#actions + 1] = { label = options.deleteLabel or "Delete", onClick = function() self:Delete() end }
    end
    actions[#actions + 1] = { label = "Cancel", onClick = function() self.closed = true; return true end }
    -- Save the text currently entered in the prompt
    actions[#actions + 1] = { label = options.saveLabel or "Save", onClick = function()
        self:Save(self.field:GetText())
    end }
    self.dialog = prettyui.Dialog.new(parent, {
        title = options.title or "Name", width = 360, height = 176, modal = false,
        actions = actions,
        onDismiss = function() self.closed = true end,
        -- Build the prompt's heading, text field, and feedback
        content = function(window)
            window:AddText({ text = options.heading or "NAME", x = 16, y = 10, width = 312, height = 20,
                colour = Theme.HEADING_TEXT })
            self.field = window:AddTextField({
                x = 16, y = 31, width = 312, height = 30, text = Text.plain(options.text),
                placeholder = options.placeholder or "", maxLength = options.maxLength or 40,
                onSubmit = function(_, value) self:Save(value) end,
                onChange = function(field, _, value) Text.cleanField(field, value) end,
            })
            self.status = window:AddText({ text = "", x = 16, y = 70, width = 312, height = 18,
                colour = Theme.ERROR_TEXT, alignHorizontal = ui.AlignMode.CENTRE })
            self.status.hidden = true
        end,
    })
    self.window = self.dialog.window
    return self
end

-- Save accepted input or keep rejected input for correction
function TextPrompt:Submit(action, fallback)
    if self.closed or action == nil then return end
    local saved, reason = action()
    if saved then
        self.closed = true
        self.dialog:Destroy()
    else
        self.status.content = Text.plain(reason or fallback)
        self.status.hidden = false
    end
end

-- Submit the entered text for saving
function TextPrompt:Save(value)
    if self.onSave ~= nil then
        self:Submit(function() return self.onSave(Text.plain(value)) end, "Could not save.")
    end
end

-- Submit the prompt's removal action
function TextPrompt:Delete()
    self:Submit(self.onDelete, "Could not delete.")
end

-- Show the text prompt
function TextPrompt:Show()
    self.window:Show()
end

-- Release the prompt and its callbacks
function TextPrompt:Destroy()
    self.closed = true
    self.dialog:Destroy()
    self.window, self.field, self.status, self.onSave, self.onDelete = nil, nil, nil, nil, nil
end

return TextPrompt
