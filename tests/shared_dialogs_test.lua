package.path = "./?.lua;./?/init.lua;" .. package.path

-- Use PrettyUI's real dialog lifecycle with native window/control stand-ins
local Harness = require("tools/test_support/tags_harness")
local h = Harness.new("shared_dialogs")
h:LoadCore()
h:LoadTags()
local app = h:App()
assert(app.store:CreateTag("melee"))
h:OpenBank()
h:Tick(2)
local parent = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__BANK_LAYER)
-- Count the parent's open shared dialogs
local function depth() return prettyui.Dialog.depth(parent) end

-- Rejecting a name leaves the input and dialog open; a successful retry releases it
app.windows:OpenCreateFolderPrompt("melee")
local prompt = app.windows.textPrompt
assert(depth() == 1)
prompt.field:SetText("")
Harness.Click(prompt.window.content, "Create")
assert(not prompt.closed and not prompt.status.hidden and depth() == 1)
prompt.field:SetText("Gear")
Harness.Click(prompt.window.content, "Create")
assert(prompt.closed and prompt.window.root == nil and depth() == 0)
assert(app.store:GetTagFolder("melee") == "gear")

-- Cancel and the title-bar X perform no edit and both release the dialog
app.windows:OpenCreateFolderPrompt("melee")
prompt = app.windows.textPrompt
Harness.Click(prompt.window.content, "Cancel")
assert(prompt.closed and depth() == 0)
app.windows:OpenCreateFolderPrompt("melee")
prompt = app.windows.textPrompt
prompt.window:Close()
assert(prompt.closed and prompt.window.root == nil and depth() == 0)

-- The optional Delete action also keeps rejected edits open for a retry
local accepted, deletes = false, 0
app.windows:OpenPageLabelPrompt({ text = "Weapons", onSave = function() return true end,
    onDelete = function() deletes = deletes + 1; return accepted, "Could not remove label." end })
prompt = app.windows.textPrompt
Harness.Click(prompt.window.content, "Delete")
assert(deletes == 1 and not prompt.closed and prompt.status.content == "Could not remove label.")
accepted = true
Harness.Click(prompt.window.content, "Delete")
assert(deletes == 2 and prompt.closed and depth() == 0)

-- A refused confirmation preserves the tag and explains why; retry can finish
app.windows:OpenTagDeleteConfirm("melee")
local confirm = app.windows.tagDeleteConfirm
app.store.loadError = "Save unavailable."
Harness.Click(confirm.window.content, "Delete")
assert(not confirm.closed and confirm.message.content == "Save unavailable." and depth() == 1)
assert(app.store.data.tags.melee ~= nil)
app.store.loadError = nil
Harness.Click(confirm.window.content, "Delete")
assert(confirm.closed and confirm.window.root == nil and depth() == 0)
assert(app.store.data.tags.melee == nil)

-- Bank close and reload release all owned shared dialogs
assert(app.store:CreateTag("food"))
app.windows:OpenCreateFolderPrompt("food")
app.windows:OpenTagDeleteConfirm("food")
assert(depth() == 2)
h:CloseBank()
assert(depth() == 0)
h:OpenBank()
h:Tick(2)
parent = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__BANK_LAYER)
app.windows:OpenCreateFolderPrompt("food")
assert(depth() == 1)
h.host:Reload("banktags", { shutdown = true })
assert(depth() == 0)
h:App():Shutdown()
print("shared_dialogs_test: ok")
