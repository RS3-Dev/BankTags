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
local function node(options)
    options = options or {}
    local value = { x = options.x, y = options.y, width = options.width,
        height = options.height, content = options.text, hooks = {} }
    function value:SetPos(x, y) self.x, self.y = x, y end
    function value:SetSize(width, height) self.width, self.height = width, height end
    function value:Subscribe(hook, action) self.hooks[hook] = action end
    function value:Destroy() self.destroyed = true end
    return value
end
id = { Component = { TOPLEVEL_V2__BANK_LAYER = 1 },
    Font = { CINZEL_13PT_BOLD = 1, MUSEO_SANS_11PT_REGULAR = 2 } }
ui = { AlignMode = { CENTRE = 1 }, Hook = { ONCLICK = 1 },
    Interfaces = { GetComponent = function() return {} end }, Layer = { new = node } }
config = { Obj = { FromID = function(value) return { id = value } end },
    Font = { MUSEO_SANS_15PT_REGULAR = { GetStringWidth = function(_, value) return #value * 7 end } } }
local function control(options)
    return { root = node(options), Destroy = function(self) self.destroyed = true end }
end
prettyui = {
    Window = { new = function(_, options)
        return { content = {}, Show = function() end, Destroy = function() end,
            Close = function(self) self.closed = true; options.onClose() end }
    end },
    Tabs = { new = function(_, entries)
        assert(#entries == 2 and entries[1].value == "import" and entries[2].value == "share")
        local pages = {}
        for index in ipairs(entries) do
            pages[index] = { content = {}, SetContentHeight = function() end }
        end
        return { GetPage = function(_, index) return assert(pages[index]) end,
            Destroy = function() end }
    end },
    Text = { new = function(_, options) return node(options) end },
    TextField = { new = function(_, options)
        local value = control(options)
        value.text, value.disabled, value.options = options.text or "", options.disabled, options
        function value:GetText() return self.text end
        function value:SetText(text, notify)
            self.text = text
            if notify and options.onChange then options.onChange(self, nil, text) end
        end
        function value:SetDisabled(disabled) self.disabled = disabled end
        function value:SetPlaceholder(text) self.placeholder = text end
        return value
    end },
    ItemSlot = { new = function(_, _, options)
        local value = control(options)
        value.disabled = options.disabled
        function value:SetObject(object) self.object = object end
        function value:SetDisabled(disabled) self.disabled = disabled end
        return value
    end },
    SimpleButton = { new = function(_, _, action, options)
        local value = control(options); value.action = action
        function value:SetDisabled(disabled) self.disabled = disabled end
        return value
    end },
    CheckboxButton = { new = function() return control() end },
    SpriteButton = { new = function() return control() end },
    ComboBox = { new = function(_, options)
        local value = control(options)
        value.entries, value.selectedID, value.disabled = options.entries, options.selectedID, options.disabled
        function value:GetSelectedID() return self.selectedID end
        function value:SetEntries(entries, selectedID)
            self.entries, self.selectedID = entries, selectedID
        end
        function value:SetDisabled(disabled) self.disabled = disabled end
        function value:Select(selectedID, notify)
            self.selectedID = selectedID
            if notify then options.onChange(self, selectedID) end
        end
        return value
    end },
}

local TagStore = require("lib/features/tags/tag_store")
local TagData = require("lib/features/tags/tag_data")
-- Share text for empty tags, each optionally in a folder
local function shareCode(names, folder)
    local data = TagData.Empty()
    for _, name in ipairs(names) do
        data.order[#data.order + 1] = name
        data.tags[name] = { rows = {}, unsorted = {}, folder = folder and folder.key }
    end
    if folder ~= nil then data.folders[folder.key] = { name = folder.name } end
    return TagData.Encode(data)
end
local source = TagData.Empty()
source.order[1] = "alpha"
source.tags.alpha = { icon = "#100", unsorted = {}, rows = {
    { kind = "label", text = "Weapons" },
    { kind = "row", slots = { { kind = "item", objectID = 100, layoutKey = "object:100:1" } } },
} }
local code = TagData.Encode(source)
local store = TagStore.new()
local app = { inGame = true, store = store, settings = {},
    features = { RefreshTags = function() end } }
local windows = require("lib/core/standalone_windows").new(app, {
    BankSettings = require("lib/features/settings/bank_settings"),
    SpritePicker = { new = function(_, options)
        return { onSelect = options.onSelect, Show = function() end,
            Destroy = function(self) self.destroyed = true end }
    end },
})
windows:OpenBankSettings()
local settings = windows.bankSettings
assert(settings.controls.importTitle.y == 0 and settings.controls.importCopy == nil)
assert(settings.importField.options.maxLines == 1 and settings.importField.root.height == 30)
-- The pasted code comes first because it fills in the name, sprite, and folder
assert(settings.importField.root.y < settings.importNameField.root.y)
assert(settings.importField.root.y < settings.importSpriteSlot.root.y)
assert(settings.importSpriteSlot.root.y < settings.importFolder.root.y)
assert(settings.importNameField.disabled and settings.importSpriteSlot.disabled)
assert(settings.importFolder.disabled and settings.importFolderName.root.hidden)
assert(settings.importFolder.root.y > settings.importField.root.y)
assert(settings.importFolder.root.y < settings.importButton.root.y)
assert(settings.generalOptions == nil and settings.placementOption == nil)
-- The title-bar X is the only close control
assert(settings.saveButton == nil and settings.closeButton == nil)

-- Pasting loads a draft without persisting it; picker results are also unsaved
settings.importField:SetText(code, true)
assert(settings.importNameField:GetText() == "alpha" and not settings.importNameField.disabled)
assert(settings.importSpriteSlot.object.id == 100 and writes == 0)
settings.importNameField:SetText("My Gear")
settings.importSpriteSlot.root.hooks[ui.Hook.ONCLICK]()
windows.spritePicker.onSelect({ objectId = 500 })
assert(settings.importSpriteSlot.object.id == 500 and writes == 0)
settings.importField:SetText(code, true)
assert(settings.importNameField:GetText() == "My Gear" and settings.importSpriteObjectID == 500)

-- Failed imports retain the draft and do not modify any live or saved tag records
store.Commit = function(_, _, message) return false, message end
settings.importButton.action()
assert(writes == 0 and #store:AllTags() == 0 and not settings.importStatus.hidden)
assert(settings.importNameField:GetText() == "My Gear" and settings.importSpriteObjectID == 500)
store.Commit = nil
settings.importButton.action()
assert(writes == 1 and store.data.tags.alpha == nil and store:GetTagSprite("my gear") == 500)
assert(store:HasTag("my gear", "object:100:1") and store:GetLabel("my gear", 0, 10) == "Weapons")
assert(TagStore.new():GetTagSprite("my gear") == 500)

-- A new paste resets overrides and invalidates an older picker selection
settings:ChooseImportSprite()
local oldPicker = windows.spritePicker
local nextCode = shareCode({ "other" })
settings.importField:SetText(nextCode, true)
oldPicker.onSelect({ objectId = 700 })
assert(settings.importNameField:GetText() == "other" and settings.importSpriteObjectID == nil)
assert(settings.importSpriteSlot.object == nil and writes == 1)
settings.importField:SetText("not an export", true)
assert(settings.importNameField.disabled and settings.importSpriteSlot.disabled)
settings.importButton.action()
assert(writes == 1)

-- Full backups still import all tags without applying single-tag overrides
settings.importField:SetText(shareCode({ "one", "two" }), true)
assert(settings.importNameField.disabled and settings.importSpriteSlot.disabled)
settings.importButton.action()
assert(writes == 2 and store.data.tags.one and store.data.tags.two)

-- Cancel discards pending metadata and closes its sprite picker
settings.importField:SetText(code, true)
settings.importNameField:SetText("Cancelled")
settings:ChooseImportSprite()
local picker = windows.spritePicker
picker.onSelect({ objectId = 900 })
settings.window:Close()
assert(picker.destroyed and windows.spritePicker == nil and writes == 2)
assert(store.data.tags.cancelled == nil)

-- New folders remain drafts through validation failures, rejected saves, and Cancel
windows:OpenBankSettings()
settings = windows.bankSettings
settings.importField:SetText(code, true)
settings.importNameField:SetText("Cancelled")
settings.importFolder:Select("new", true)
assert(not settings.importFolderName.root.hidden and settings.importButton.root.y == 344)
settings.importButton.action()
assert(writes == 2 and store:GetFolder("combat") == nil)
settings.importFolderName:SetText("Combat")
store.Commit = function(_, _, message) return false, message end
settings.importButton.action()
assert(writes == 2 and store:GetFolder("combat") == nil and store.data.tags.cancelled == nil)
store.Commit = nil
settings.window:Close()
assert(writes == 2 and store:GetFolder("combat") == nil)
windows:OpenBankSettings()
settings = windows.bankSettings
settings.importField:SetText(code, true)
settings.importNameField:SetText("Folder Gear")
settings.importFolder:Select("new", true)
settings.importFolderName:SetText("Combat")
settings.importButton.action()
assert(writes == 3 and store:GetTagFolder("folder gear") == "combat")
assert(TagStore.new():GetFolder("combat").name == "Combat")
local found = false
for _, entry in ipairs(settings.importFolder.entries) do
    if entry.id == "folder:combat" then found = true end
end
assert(found, "a newly imported folder must be available in the dropdown")

-- Filing another import uses one save and leaves the folder in its top-level position
settings.importField:SetText(shareCode({ "child" }), true)
assert(settings.importFolderName.root.hidden and settings.importFolderName:GetText() == "")
assert(settings.importFolder:GetSelectedID() == "none" and not settings.importFolder.disabled)
settings.importFolder:Select("folder:combat", true)
settings.importButton.action()
assert(writes == 4 and store:GetTagFolder("child") == "combat")
local tree = store:TagTree()
assert(tree[1].tag == "one" and tree[2].tag == "two" and tree[3].tag == "my gear")
assert(tree[4].key == "combat" and tree[4].tags[1] == "folder gear" and tree[4].tags[2] == "child")
settings.importFolder:Select("none", true)
assert(settings.importButton.root.y == 302)
settings.importButton.action()
assert(writes == 5 and store:GetTagFolder("child") == nil)
assert(store:TagTree()[5].tag == "child")

-- A new name matching an existing folder joins it rather than creating a duplicate
settings.importField:SetText(shareCode({ "another" }), true)
settings.importFolder:Select("new", true)
settings.importFolderName:SetText(" COMBAT ")
settings.importButton.action()
assert(writes == 6 and store:GetTagFolder("another") == "combat")
assert(#store:GetFolders() == 1)

-- A backup's original folder is selectable even when absent from the current store
settings.importField:SetText(shareCode({ "shared" }, { key = "incoming", name = "Incoming" }), true)
assert(settings.importFolder:GetSelectedID() == "folder:incoming")
settings.importButton.action()
assert(writes == 7 and store:GetTagFolder("shared") == "incoming")
assert(store:GetFolder("incoming").name == "Incoming")
settings:Destroy()

print("import_settings_test: ok")
