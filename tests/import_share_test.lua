package.path = "./?.lua;./?/init.lua;" .. package.path

-- Pasted codes and full backups still preview, customize, save, and share
local Harness = require("tools/test_support/tags_harness")
local h = Harness.new("import_share")
h.bankHost:SetItems({ { 385, 20, "Shark" } })
h:LoadCore()
h:LoadTags()
local app = h:App()
assert(app.store:CreateTag("supplies", 385))
assert(app:AddItemToTag("supplies", 385))
h:OpenBank()
h:Tick(2)
app.windows:OpenImportShare()
local window = app.windows.importShare
local Json = require("banktags/core/json")
local code = app.store:TagExports()[1].value
local before = Json.encode(app.store.data)
assert(window.importButton.disabled)
window.importField:SetText(code, true)
assert(not window.importButton.disabled and window.importSingleTag == "supplies")
assert(Json.encode(app.store.data) == before, "preview must not save anything")
window.importNameField:SetText("Imported supplies")
window.importFolder:Select("new", true)
window.importFolderName:SetText("Food")
window.importButton.action()
assert(app.store.data.tags["imported supplies"] ~= nil)
assert(app.store:GetTagFolder("imported supplies") == "food")
assert(app.store:GetTagSprite("imported supplies") == 385)
assert(#app.store:GetTaggedItems("imported supplies") == 1)
assert(window.importStatus.content == "Imported 1 tag.")
assert(#window.shareRows == 2 and #window.shareRows[2].field:GetText() > 0)

-- Multi-tag backups keep their names and do not enable single-tag overrides
local backup = h:TagsModule("banktags/tags/tag_data").Encode(app.store.data)
window.importField:SetText(backup, true)
assert(window.importSingleTag == nil and window.importNameField.disabled)
assert(window.importSpriteSlot.disabled and window.importFolder.disabled)
assert(window.importStatus.content:find("Backup: 2 tags.", 1, true))
window.importButton.action()
assert(window.importStatus.content == "Imported 2 tags.")

-- A failed save keeps the preview and its chosen name available to retry
window.importField:SetText(code, true)
window.importNameField:SetText("Retry supplies")
app.store.loadError = "Save unavailable."
before = Json.encode(app.store.data)
window.importButton.action()
assert(Json.encode(app.store.data) == before and window.importStatus.content == "Save unavailable.")
assert(window.importNameField:GetText() == "Retry supplies" and not window.importButton.disabled)
app.store.loadError = nil
window.importButton.action()
assert(app.store.data.tags["retry supplies"] ~= nil)

-- Invalid or emptied input invalidates the previous preview, even without a change event
window.importField:SetText("{}", false)
before = Json.encode(app.store.data)
window.importButton.action()
assert(window.importState == "invalid" and window.importButton.disabled)
assert(Json.encode(app.store.data) == before)
window.importField:SetText("", true)
assert(window.importButton.disabled and window.importStatus.hidden)

-- An icon picker cannot change a preview replaced while it was open
window.importField:SetText(code, true)
local choose
window.options.onChooseImportSprite = function(callback) choose = callback end
window:ChooseImportSprite()
window.importField:SetText("{}", true)
choose(1944)
assert(window.importSpriteObjectID == nil)
app.windows:Close("importShare")
app:Shutdown()
print("import_share_test: ok")
