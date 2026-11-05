package.path = "./?.lua;" .. package.path

local Json = require("banktags/core/json")
local TagData = require("banktags/tags/tag_data")

-- Check every control character survives a round trip
for byte = 0, 31 do
    local value = "before" .. string.char(byte) .. "after"
    local encoded = Json.encode(value)
    assert(not encoded:find("[%z\1-\31]"))
    assert(Json.decode(encoded) == value)
end
assert(Json.decode(Json.encode('quote " and slash \\')) == 'quote " and slash \\')
assert(Json.decode('"\\u00e9\\u4e2d\\ud83d\\ude00"') == utf8.char(0xE9, 0x4E2D, 0x1F600))
assert(Json.decode('"\\u0000"') == "\0")
assert(Json.decode('"\\b\\f\\n\\r\\t\\/"') == "\b\f\n\r\t/")

-- Keep empty values in their original array positions
local values = Json.decode('[null,1,null,false,null]')
assert(#values == 5 and values[1] == Json.null and values[3] == Json.null and values[5] == Json.null)
assert(Json.encode(values) == '[null,1,null,false,null]')
assert(Json.encode(Json.decode('{"empty":null}')) == '{"empty":null}')
local imported = assert(TagData.Decode([=[{"format":"bankutilities-tags","version":4,
    "tags":{"gear":{"rows":[["#4151",null,"#385"]]},"absent":null}}]=]))
local slots = imported.tags.gear.rows[1].slots
assert(#imported.order == 1 and #slots == 3)
assert(slots[1].objectID == 4151 and slots[2].kind == "blank" and slots[3].objectID == 385)
assert(not TagData.Decode('{"format":"bankutilities-tags","version":4,"tags":null}', true))

-- Refuse malformed strings, numbers, and oversized nesting
for _, source in ipairs({
    '"\\u1"', '"\\u-001"', '"\\uZZZZ"', '"\\ud800"', '"\\udc00"', '"\\ud800\\u0041"',
    '"raw\nline"', '"raw\0byte"', '"\\x"', '"unfinished',
    '01', '-01', '1.', '1e', '1e+', '1.e2', '-.1', '+1', '1e999',
    '[1e]', '{"n":1e+}', '[1,]', '{"n":1,}', 'true false', '\v1',
    string.rep('[', 129) .. '0' .. string.rep(']', 129),
}) do
    assert(not pcall(Json.decode, source), "invalid JSON was accepted: " .. source)
end
for _, value in ipairs({ 0, -0.5, 42, 1e30, -1e-20 }) do
    assert(Json.decode(Json.encode(value)) == value)
end
assert(Json.decode(" \t\r\n -12.5e+2 \n") == -1250)
assert(not pcall(Json.encode, math.huge))
assert(not pcall(Json.encode, -math.huge))
assert(not pcall(Json.encode, 0 / 0))
assert(not pcall(Json.encode, { [2] = "sparse" }))

print("json_test: ok")
