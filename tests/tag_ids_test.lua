-- Unique tag IDs keep saves migrated, renames stable, and same-name imports separate.
local suite = { tests = {} }

function suite.setup()
    package.path = root .. "/?.lua;" .. package.path
    Config = require("resources/core/config")
    Chunks = require("resources/core/chunked_string_store")
    Json = require("resources/core/json")
    Rules = require("resources/tags/tag_rules")
    Data = require("resources/tags/tag_data")
    savedValues = {}
    writeCount = 0
    PersistentDB = {
        GetString = function(_, key) return savedValues[key] end,
        SetString = function(_, key, value)
            writeCount = writeCount + 1
            savedValues[key] = value
            return true
        end,
    }
    Store = require("resources/tags/tag_store")
    textStore = {
        manifestKey = Config.TAGS_TEXT_MANIFEST_KEY,
        chunkPrefix = Config.TAGS_TEXT_CHUNK_PREFIX,
    }
end

suite.tests.legacy_save_migrates_to_unique_uuids_preserving_data = function()
    local legacy = {
        format = "bankutilities-tags",
        version = 4,
        order = { "herblore", "slayer" },
        folders = {
            skills = { name = "Skills", collapsed = true, icon = "#4151" },
        },
        tags = {
            herblore = {
                icon = "#2434",
                folder = "skills",
                rows = { "Potions", { "#2434", "", "#3024" } },
                unsorted = { "#15332" },
            },
            slayer = {
                rows = { { "#4151" } },
                unsorted = {},
            },
        },
    }
    assert(Chunks.Write(textStore, Json.encode(legacy)))
    writeCount = 0

    local store = Store.new()
    assert(store.loadError == nil)
    assert(writeCount > 0, "migration should persist rekeyed tags")
    local order = store:AllTags()
    assert(#order == 2 and order[1] ~= order[2])
    assert(Rules.isUUID(order[1]) and Rules.isUUID(order[2]))
    assert(store:GetTagName(order[1]) == "herblore")
    assert(store:GetTagName(order[2]) == "slayer")
    assert(store:GetTagFolder(order[1]) == "skills")
    assert(store:GetTagSprite(order[1]) == 2434)
    local folder = store:GetFolder("skills")
    assert(folder ~= nil and folder.name == "Skills" and folder.collapsed == true)
    assert(#store:GetTaggedItems(order[1]) == 3)
    assert(store:GetLabels(order[1], 10)[1].text == "Potions")
    assert(#store:GetTaggedItems(order[2]) == 1)

    -- Reloading migrated data keeps the exact same UUIDs without rewriting
    writeCount = 0
    local reloaded = Store.new()
    assert(reloaded.loadError == nil and writeCount == 0)
    local reloadedOrder = reloaded:AllTags()
    assert(reloadedOrder[1] == order[1] and reloadedOrder[2] == order[2])
    assert(reloaded:GetTagName(reloadedOrder[1]) == "herblore")
    assert(reloaded:GetTagName(reloadedOrder[2]) == "slayer")
end

suite.tests.same_name_and_duplicate_id_imports_never_overwrite_existing = function()
    local store = Store.new()
    local ok, existingID = store:CreateTag("Herblore", 2434)
    assert(ok and Rules.isUUID(existingID))
    assert(store:AddTag(existingID, 2434))

    -- Legacy share code with the same display name
    local legacyShare = Json.encode({
        format = "bankutilities-tags",
        version = 4,
        order = { "herblore" },
        folders = {},
        tags = { herblore = { rows = { { "#3024" } }, unsorted = {} } },
    })
    local imported, summary = store:ImportText(legacyShare)
    assert(imported and summary.tags == 1)
    assert(#store:AllTags() == 2)
    local importedID = store:AllTags()[1]
    assert(importedID ~= existingID and Rules.isUUID(importedID))
    assert(store:GetTagName(importedID) == "herblore")
    assert(store:GetTagName(existingID) == "herblore")
    assert(store:GetTaggedItems(existingID)[1].objectID == 2434)
    assert(store:GetTaggedItems(importedID)[1].objectID == 3024)

    -- Re-importing a UUID-keyed export of the existing tag assigns a brand-new UUID
    local exports = store:TagExports()
    local existingExport
    for _, entry in ipairs(exports) do
        if entry.tag == existingID then existingExport = entry end
    end
    assert(existingExport ~= nil and existingExport.name == "herblore")
    local reimported, reSummary = store:ImportText(existingExport.value)
    assert(reimported and reSummary.tags == 1)
    assert(#store:AllTags() == 3)
    local copyID = store:AllTags()[1]
    assert(copyID ~= existingID and copyID ~= importedID and Rules.isUUID(copyID))
    assert(store:GetTagName(copyID) == "herblore")
    assert(store:GetTaggedItems(copyID)[1].objectID == 2434)
    assert(store:GetTaggedItems(existingID)[1].objectID == 2434)
end

suite.tests.rename_preserves_stable_id_order_and_placeholder_suggestions = function()
    local store = Store.new()
    assert(store:NextPlaceholderTagName() == "placeholder 1")
    local ok1, id1 = store:CreateTag("placeholder 1", 4151)
    assert(ok1 and Rules.isUUID(id1))
    assert(store:NextPlaceholderTagName() == "placeholder 2")
    local ok2, id2 = store:CreateTag("Herblore")
    assert(ok2 and Rules.isUUID(id2) and id2 ~= id1)
    assert(store:AddTag(id1, 4151))

    local updated, returnedID = store:UpdateTag(id1, "Bossing", 11694)
    assert(updated and returnedID == id1)
    assert(store:GetTagName(id1) == "bossing")
    assert(store:GetTagSprite(id1) == 11694)
    assert(store:AllTags()[1] == id1 and store:AllTags()[2] == id2)
    assert(store:GetTaggedItems(id1)[1].objectID == 4151)
    assert(store:NextPlaceholderTagName() == "placeholder 1")

    -- Renaming to an existing display name is allowed because IDs are distinct
    local dupUpdated, dupID = store:UpdateTag(id1, "Herblore")
    assert(dupUpdated and dupID == id1)
    assert(store:GetTagName(id1) == "herblore" and store:GetTagName(id2) == "herblore")
    assert(#store:AllTags() == 2)
end

suite.tests.mixed_legacy_and_uuid_decode_avoids_collisions = function()
    local fixedID = "11111111-2222-4333-8444-555555555555"
    local mixed = {
        format = "bankutilities-tags",
        version = 4,
        order = { "legacy tag", fixedID },
        folders = {},
        tags = {
            ["legacy tag"] = { rows = {}, unsorted = {} },
            [fixedID] = { name = "modern tag", rows = {}, unsorted = {} },
        },
    }
    local data, reason, migrated = Data.Decode(Json.encode(mixed), true)
    assert(data ~= nil and reason == nil and migrated == true)
    assert(#data.order == 2)
    assert(Rules.isUUID(data.order[1]) and data.order[1] ~= fixedID)
    assert(data.order[2] == fixedID)
    assert(data.tags[data.order[1]].name == "legacy tag")
    assert(data.tags[fixedID].name == "modern tag")
end

suite.tests.single_tag_import_customizes_name_and_folder_under_new_id = function()
    local store = Store.new()
    local ok, originalID = store:CreateTag("Herblore", 2434)
    assert(ok)
    local shareCode = store:TagExports()[1].value

    local imported, summary = store:ImportText(shareCode, {
        name = "Herblore Alt",
        spriteObjectID = 3024,
        newFolderName = "Skilling",
    })
    assert(imported and summary.tags == 1)
    assert(#store:AllTags() == 2)
    local newID
    for _, id in ipairs(store:AllTags()) do
        if id ~= originalID then newID = id end
    end
    assert(Rules.isUUID(newID))
    assert(store:GetTagName(originalID) == "herblore")
    assert(store:GetTagName(newID) == "herblore alt")
    assert(store:GetTagSprite(newID) == 3024)
    assert(store:GetTagFolder(newID) == "skilling")
end

suite.tests.sidebar_search_and_labels_use_display_names_not_uuids = function()
    package.loaded["resources/sidebar/tag_list_drag"] = { StopGesture = function() end, BindRow = function() end }
    package.loaded["resources/ui/geometry"] = { trackPointer = function() end }
    package.loaded["resources/ui/sidebar_rows"] = {
        ROW_LEFT = 6, ROW_TEXT = 1, ENTRY_HEIGHT = 32,
        ContentWidth = function(w) return w end,
        CreateSearch = function() return { Destroy = function() end } end,
        CreateEmptyLabel = function() return { hidden = false, Destroy = function() end } end,
        CreateList = function()
            return {
                root = { hidden = false },
                rows = {},
                SetEntries = function() end,
                Destroy = function() end,
            }
        end,
    }
    local store = Store.new()
    local _, id1 = store:CreateTag("herblore")
    local _, id2 = store:CreateTag("slayer")
    local TagList = require("resources/sidebar/tag_list")
    local state = { searchQuery = "" }
    local list = TagList.new({}, {
        store = store,
        settings = function() return { showTagSprites = false } end,
        state = state,
        width = 220,
        listHeight = 200,
        isSelected = function() return false end,
    })
    assert(#list.entries == 2)
    assert(list.entries[1].id == id1 and list.entries[1].label == "Herblore")
    assert(list.entries[2].id == id2 and list.entries[2].label == "Slayer")

    -- Searching by UUID prefix must not match display names
    state.searchQuery = string.sub(id1, 1, 8)
    list:Refresh()
    assert(#list.entries == 0)

    -- Searching by display name finds the matching tag
    state.searchQuery = "herb"
    list:Refresh()
    assert(#list.entries == 1 and list.entries[1].id == id1 and list.entries[1].label == "Herblore")
end

suite.tests.select_mode_and_share_preview_display_tag_names_not_uuids = function()
    local store = Store.new()
    local ok, tagID = store:CreateTag("herblore", 2434)
    assert(ok and Rules.isUUID(tagID))

    -- SelectMode label uses display name
    Event = { Logic = { Subscribe = function() end, Unsubscribe = function() end } }
    local SelectMode = require("resources/sidebar/select_mode")
    local selectMode = SelectMode.new({
        store = store,
        ext = { IsOpen = function() return false end },
        nativeItems = { Refresh = function() end, RestoreHighlights = function() end },
        tab = { Refresh = function() end, RowFor = function() return nil end },
        ShowStatus = function() end,
    })
    assert(selectMode:Start(tagID))
    assert(selectMode:Tag() == tagID)
    assert(selectMode:Label() == "Add to Herblore")

    -- Renaming keeps the select session on the same ID and updates its label
    assert(store:UpdateTag(tagID, "potions"))
    assert(selectMode:Tag() == tagID)
    assert(selectMode:Label() == "Add to Potions")

    -- Share export carries UUID tag identity and human-readable display name
    local exports = store:TagExports()
    assert(#exports == 1 and exports[1].tag == tagID and exports[1].name == "potions")

    -- Decoding a UUID-keyed share code preserves the tag name for preview
    local decoded, reason, migrated = Data.Decode(exports[1].value)
    assert(decoded ~= nil and reason == nil and migrated == false)
    assert(decoded.order[1] == tagID and decoded.tags[tagID].name == "potions")
end

return suite
