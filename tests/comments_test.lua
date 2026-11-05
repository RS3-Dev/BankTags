package.path = "./?.lua;" .. package.path

local Comments = require("tools/comments")
local Graph = require("tools/module_graph")
local source = Graph.Source
local output, messages = print, {}
Graph.Source = function()
    return [==[
-- Find the current item
local function valid() end
local literal = "function ignored() end"
local long = [=[ function ignoredToo() end ]=]
-- function ignoredComment() end

function missing() end
-- Too short
function short() end
-- Keep this deliberately long description above the strict ten word limit
function long() end
-- Remove the last period.
function period() end
]==]
end
print = function(message) messages[#messages + 1] = message end
local ok, problems, functions = pcall(Comments.Check, { "fixture.lua" })
Graph.Source, print = source, output
assert(ok, problems)
assert(functions == 5 and problems == 4 and #messages == 4)
assert(messages[1]:find("fixture.lua:7: missing", 1, true))
assert(messages[2]:find("short", 1, true))
assert(messages[3]:find("long", 1, true))
assert(messages[4]:find("period", 1, true))

print("comments_test: ok")
