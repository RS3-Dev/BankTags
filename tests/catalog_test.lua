package.path = "./?.lua;" .. package.path

local Catalog = require("banktags/tags/catalog")
local ObjectConfig = require("banktags/core/object_config")
local reads, configReads = {}, 0
ObjectConfig.DisplayName = function(objectID)
    reads[objectID] = (reads[objectID] or 0) + 1
    return objectID > 0 and ("Item " .. objectID) or nil
end
ObjectConfig.ConfigName = function(objectID)
    configReads = configReads + 1
    return "item_" .. objectID
end
ObjectConfig.ObjectID = function() return nil end
Catalog.SetRuneQLEnabled(false)
local bank = {}
for index = 1, 100 do bank[#bank + 1] = { objectID = 1 } end
for objectID = 2, 20 do bank[#bank + 1] = { objectID = objectID } end
local found, total, limited = Catalog.Find("Item", 2, bank)
assert(limited and total == 2 and found[1].objectId == 1 and found[2].objectId == 2)
assert(reads[1] == 1 and reads[2] == 1 and reads[3] == nil)
assert(configReads == 2)
reads, configReads = {}, 0
found = Catalog.Find("missing", 2, bank)
assert(#found == 0 and configReads == 0)
for objectID = 1, 20 do assert(reads[objectID] == 1) end
reads = {}
found = Catalog.Find("#1", 2, bank)
assert(#found == 1 and found[1].objectId == 1 and reads[1] == 1)

print("catalog_test: ok")
