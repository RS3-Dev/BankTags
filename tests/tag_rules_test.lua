package.path = "./?.lua;./?/init.lua;" .. package.path

local TagRules = require("banktags/tags/tag_rules")

assert(TagRules.normalizeTag("  Rune Gear ") == "rune gear")
assert(TagRules.normalizeTag("a,b") == nil and TagRules.normalizeTag("   ") == nil)
assert(TagRules.normalizeTag(string.rep("a", TagRules.MAX_TAG_NAME)) ~= nil)
assert(TagRules.normalizeTag(string.rep("a", TagRules.MAX_TAG_NAME + 1)) == nil)

-- Lists are split on commas, deduplicated, sorted, and skip invalid names
local tags = TagRules.parseTagList("Food, gear,food, ," .. string.rep("x", 81))
assert(#tags == 2 and tags[1] == "food" and tags[2] == "gear")

local key, display = TagRules.folderName("  Gathering   Skills ")
assert(key == "gathering skills" and display == "Gathering Skills")
assert(TagRules.folderName(string.rep("f", TagRules.MAX_FOLDER_NAME + 1)) == nil)

assert(TagRules.labelText("  <b>Weapons</b>  ") == "bWeapons/b")
assert(#TagRules.labelText(string.rep("w", 100)) == TagRules.MAX_LABEL_TEXT)
assert(TagRules.labelText("  ") == nil)

local slots = TagRules.trimTrailingLayoutBlanks({ { kind = "item" }, { kind = "blank" }, { kind = "blank" } })
assert(#slots == 1)

print("tag_rules_test: ok")
