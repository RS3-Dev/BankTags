package.path = "./?.lua;./?/init.lua;" .. package.path

local db, writes = {}, 0
PersistentDB = {
    GetString = function(_, key) return db[key] end,
    SetString = function(_, key, value)
        db[key] = value
        if key:find("manifest", 1, true) then writes = writes + 1 end
        return true
    end,
}

local TagStore = require("lib/features/tags/tag_store")
local store = TagStore.new()
for index, tag in ipairs({ "first", "a", "middle", "b", "c", "last" }) do
    assert(store:CreateTag(tag) and store:AddTag(tag, index))
end
assert(store:CreateFolder("Folder", "a"))
assert(store:SetTagFolder("b", "folder"))
assert(store:CreateFolder("Other", "c"))
-- Existing saves can interleave members of a folder with top-level entries
assert(store:SaveTagOrder({ "first", "a", "middle", "b", "c", "last" }))

local function treeText(target)
    local nodes = {}
    for _, node in ipairs(target:TagTree()) do
        nodes[#nodes + 1] = node.kind == "tag" and node.tag
            or node.key .. "[" .. table.concat(node.tags, ",") .. "]"
    end
    return table.concat(nodes, "|")
end

assert(treeText(store) == "first|folder[a,b]|middle|other[c]|last")
assert(store:MoveSidebarEntry("b", nil, -1))
assert(treeText(store) == "first|folder[b,a]|middle|other[c]|last")
assert(store:MoveSidebarEntry(nil, "folder", 1))
assert(treeText(store) == "first|middle|folder[b,a]|other[c]|last")
assert(store:MoveSidebarEntry("middle", nil, 1))
assert(treeText(store) == "first|folder[b,a]|middle|other[c]|last")
assert(store:SetFolderCollapsed("folder", true))
assert(store:MoveSidebarEntry(nil, "folder", 1))
assert(store:GetFolder("folder").collapsed)
assert(treeText(TagStore.new()) == treeText(store))

-- Boundaries and stale entries never write or change tiers
local before, beforeWrites = treeText(store), writes
assert(not store:MoveSidebarEntry("b", nil, -1))
assert(not store:MoveSidebarEntry("a", nil, 1))
assert(not store:MoveSidebarEntry("c", nil, -1))
assert(not store:MoveSidebarEntry("first", nil, -1))
assert(not store:MoveSidebarEntry("last", nil, 1))
assert(not store:MoveSidebarEntry(nil, "missing", 1))
assert(not store:MoveSidebarEntry("missing", nil, 1))
assert(not store:MoveSidebarEntry("first", nil, 2))
assert(treeText(store) == before and writes == beforeWrites)

-- A rejected save restores the previous order in memory and on reload
store.Commit = function(_, _, message) return false, message end
assert(not store:MoveSidebarEntry(nil, "folder", -1))
assert(treeText(store) == before and treeText(TagStore.new()) == before)
store.Commit = nil

-- Promote the first member without moving the folder or the other top-level rows
assert(store:SetTagFolder("b", nil))
assert(treeText(store) == "first|middle|folder[a]|b|other[c]|last")
assert(store:GetTagFolder("b") == nil)
assert(store:MoveSidebarEntry("b", nil, -1))
assert(treeText(store) == "first|middle|b|folder[a]|other[c]|last")
-- Filing an earlier tag appends it to the destination without pulling the folder up
assert(store:SetTagFolder("first", "other"))
assert(treeText(store) == "middle|b|folder[a]|other[c,first]|last")
assert(store:SetTagFolder("a", "other"))
assert(store:GetFolder("folder") == nil)
assert(treeText(store) == "middle|b|other[c,first,a]|last")
assert(store:CreateFolder("New", "first"))
assert(treeText(store) == "middle|b|other[c,a]|new[first]|last")
assert(store:SetTagFolder("first", nil))
assert(store:GetFolder("new") == nil)
assert(treeText(store) == "middle|b|other[c,a]|first|last")
assert(store:DeleteFolder("other"))
assert(treeText(store) == "middle|b|c|a|first|last")

-- Hierarchical order survives a reload
assert(store:CreateFolder("Shared", "c"))
assert(store:SetTagFolder("a", "shared"))
assert(store:MoveSidebarEntry(nil, "shared", -1))
assert(treeText(TagStore.new()) == treeText(store))

print("tag_sidebar_order_test: ok")
