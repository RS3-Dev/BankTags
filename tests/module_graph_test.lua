package.path = "./?.lua;" .. package.path

local Graph = require("tools/module_graph")
local source = [==[
-- require("ignored/comment")
local a = require("banktags/app")
local b = require 'banktags/core/json'
local c = require ( 'banktags/tags/tag_data' )
local text = "require('ignored/string') and \\\"quoted\\\""
local long = [=[ require('ignored/long_string') ]=]
--[=[ require('ignored/long_comment') ]=]
local other = object.require("ignored/method")
object:require("ignored/colon")
]==]
local code = Graph.Code(source)
assert(#code == #source)
assert(select(2, code:gsub("\n", "")) == select(2, source:gsub("\n", "")))
local names = Graph.RequiresIn(source, "fixture")
assert(table.concat(names, ",") == "banktags/app,banktags/core/json,banktags/tags/tag_data")
for _, unsupported in ipairs({ 'require(name)', 'require "bad.name"', 'require("unfinished"', 'require [[long]]' }) do
    local ok, reason = pcall(Graph.RequiresIn, unsupported, "fixture")
    assert(not ok and reason:find("fixture:1", 1, true))
end
local modules, included = Graph.Closure({ "plugins/banktags/main" })
assert(#modules > 1 and included["banktags/app"] and included["banktags/tags/tag_store"])
assert(not included["tools/build"])

print("module_graph_test: ok")
