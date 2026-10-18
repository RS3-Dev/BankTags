package.path = "./?.lua;./?/init.lua;" .. package.path

local Json = require("lib/core/json")
local db, writes = {}, 0
PersistentDB = {
    GetString = function(_, key) return db[key] end,
    SetString = function(_, key, value)
        db[key] = value
        if key:find("manifest", 1, true) then writes = writes + 1 end
        return true
    end,
}
id = { Sprite = { RS3_ICON_SLOT_40PX_1 = 1 },
    Component = { TOPLEVEL_V2__BANK_LAYER = 1 } }
local parent = {}
ui = {
    AlignMode = { CENTRE = 1 }, Hook = { ONCLICK = 1 },
    ObjectQuantityDisplayMode = { ALWAYS = 2, NEVER = 0 },
    Interfaces = { GetComponent = function() return parent end },
}
config = { Obj = { FromID = function(value) return { id = value } end } }
prettyui = {
    Window = { new = function()
        return { content = {}, Show = function() end, Destroy = function() end,
            Close = function(self) self.closed = true end }
    end },
    Text = { new = function() return { Destroy = function() end } end },
    TextField = { new = function(_, options)
        return { text = options.text, GetText = function(self) return self.text end,
            Destroy = function() end }
    end },
    ItemSlot = { new = function()
        return { root = { Subscribe = function() end }, SetObject = function() end,
            SetTooltip = function() end, Destroy = function() end }
    end },
    SimpleButton = { new = function(_, _, action)
        return { action = action, Destroy = function() end }
    end },
}

local TagStore = require("lib/features/tags/tag_store")
local StandaloneWindows = require("lib/core/standalone_windows")
local BankFeatures = require("lib/features/bank_features")
local LayoutEditorWindow = require("lib/features/tags/layout_editor_window")
local store = TagStore.new()
local features = {
    store = store, selectedTag = nil,
    RefreshTags = function() end,
    IsSelectingItemsForTag = function() return false end,
    SetSelectedTag = function(self, tag) self.selectedTag = tag end,
}
local app = { inGame = true, store = store, features = features }
local windows = StandaloneWindows.new(app, {
    TagSettingsEditor = require("lib/features/tags/tag_settings_editor"),
    LayoutEditorWindow = { new = function(_, options)
        return {
            onCreateTag = options.onCreateTag,
            CreateNewTag = LayoutEditorWindow.CreateNewTag,
            Show = function() end,
            SelectTag = function(self, tag) self.selectedTag = tag end,
            NotifyChanged = function(self) self.notified = true end,
        }
    end },
})
features.onEditTag = function(tag, isNew) windows:OpenTagSettings(tag, isNew) end

-- Opening New Tag, choosing an icon, and cancelling never writes a placeholder
assert(BankFeatures.CreatePlaceholderTag(features, nil, true))
local editor = windows.tagSettingsEditor
assert(editor.field.text == "placeholder 1" and writes == 0)
editor:SetSprite(100)
editor.cancelButton.action()
assert(editor.window.closed and #store:AllTags() == 0 and writes == 0)
assert(#TagStore.new():AllTags() == 0)

-- Closing via the window and reopening also leaves the suggested name available
assert(BankFeatures.CreatePlaceholderTag(features, nil, true))
editor = windows.tagSettingsEditor
editor.window:Close()
assert(writes == 0 and store:NextPlaceholderTagName() == "placeholder 1")
assert(BankFeatures.CreatePlaceholderTag(features, nil, true))
editor = windows.tagSettingsEditor
editor.field.text = "   "
editor.saveButton.action()
assert(not editor.window.closed and not editor.status.hidden and writes == 0)
editor.field.text = "two,tags"
editor.saveButton.action()
assert(not editor.window.closed and writes == 0)

-- Save creates the final name and icon together; failed persistence leaves no tag
editor.field.text = "  New Gear  "
editor:SetSprite(200)
store.Commit = function(_, _, message) return false, message end
editor.saveButton.action()
assert(not editor.window.closed and #store:AllTags() == 0 and writes == 0)
store.Commit = nil
editor.saveButton.action()
assert(editor.window.closed and writes == 1)
assert(#store:AllTags() == 1 and store:AllTags()[1] == "new gear")
assert(store:GetTagSprite("new gear") == 200 and store.data.tags["placeholder 1"] == nil)
assert(TagStore.new():GetTagSprite("new gear") == 200)

-- Duplicate names cannot merge into or change an existing tag
assert(BankFeatures.CreatePlaceholderTag(features, nil, true))
editor = windows.tagSettingsEditor
editor.field.text = "NEW GEAR"
editor:SetSprite(300)
editor.saveButton.action()
assert(not editor.window.closed and writes == 1 and store:GetTagSprite("new gear") == 200)
assert(editor.status.content == "A tag with that name already exists.")

-- Existing tag editing still renames and retargets its current selection
features.selectedTag = "new gear"
windows:OpenTagSettings("new gear", false)
editor = windows.tagSettingsEditor
editor.field.text = "Renamed Gear"
editor.saveButton.action()
assert(editor.window.closed and features.selectedTag == "renamed gear")
assert(store:GetTagSprite("renamed gear") == 200)

-- The layout editor selects the new tag only after Save, never after Cancel
windows:OpenLayoutEditor("renamed gear")
local layoutEditor = windows.layoutEditor
local before = writes
assert(layoutEditor:CreateNewTag())
windows.tagSettingsEditor.cancelButton.action()
assert(layoutEditor.selectedTag == nil and writes == before)
assert(layoutEditor:CreateNewTag())
editor = windows.tagSettingsEditor
editor.field.text = "Layout Tag"
editor.saveButton.action()
assert(layoutEditor.selectedTag == "layout tag" and layoutEditor.notified)
assert(writes == before + 1 and store.data.tags["layout tag"] ~= nil)

-- Dropping an item on New Tag still commits its placeholder and membership
assert(BankFeatures.CreatePlaceholderTag(features, 123, false, "object:123:2"))
assert(store:HasTag("placeholder 1", "object:123:2"))

print("new_tag_draft_test: ok")
