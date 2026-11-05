package.path = "./?.lua;" .. package.path

local Build = require("tools/build")
local Graph = require("tools/module_graph")

-- Read a packaged file's bytes
local function read(path)
    local file = assert(io.open(path, "rb"))
    local bytes = file:read("a")
    file:close()
    return bytes
end

-- Only import names change; examples and comments stay intact
local source = [==[
-- require("ignored/comment")
local example = "require('ignored/string')"
local a = require("banktags/app")
local b = require 'banktags/core/json'
local c = require ( 'banktags/tags/tag_data' )
object.require("ignored/method")
]==]
local expected = [==[
-- require("ignored/comment")
local example = "require('ignored/string')"
local a = require("resources/banktags/app")
local b = require 'resources/banktags/core/json'
local c = require ( 'resources/banktags/tags/tag_data' )
object.require("ignored/method")
]==]
assert(Build.RuntimeSource(source, "fixture") == expected)

local options = { out = "dist/test/build_package" }
local built = Build.Run(options)
assert(built.folder == options.out .. "/banktags")
local shipped = {}
for _, file in ipairs(built.files) do
    assert(file.path == "main.lua" or file.path == "plugin.json"
        or file.path:sub(1, 10) == "resources/", "supporting file outside resources: " .. file.path)
    shipped[file.path] = true
end
assert(shipped["main.lua"] and shipped["plugin.json"] and shipped["resources/tutorial_step.ogg"])
for _, file in ipairs(built.files) do
    local bytes = read(built.folder .. "/" .. file.path)
    if file.path:match("%.lua$") then
        for _, name in ipairs(Graph.RequiresIn(bytes, file.path)) do
            assert(name:sub(1, 10) == "resources/", "import outside resources: " .. name)
            assert(shipped[name .. ".lua"], "unshipped import: " .. name)
        end
    end
end

-- Rebuilding preserves exactly the same package layout
local rebuilt = Build.Run(options)
assert(#rebuilt.files == #built.files)
for _, file in ipairs(rebuilt.files) do assert(shipped[file.path]) end

print("build_test: ok")
