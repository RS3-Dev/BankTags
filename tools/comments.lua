-- Check short descriptions above named Lua functions

local ModuleGraph = require("tools/module_graph")
local Comments = {}

-- Find missing or overly long function summaries
function Comments.Check(paths)
    local problems, functions = 0, 0
    for _, path in ipairs(paths) do
        local source = assert(ModuleGraph.Source((path:gsub("%.lua$", ""))))
        local lines = {}
        for line in (source .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = line end
        local code = ModuleGraph.Code(source)
        local position, line = 1, 1
        while true do
            local first, last, name = code:find("%f[%w_]function%s+([%a_][%w_%.:]*)%s*%(", position)
            if first == nil then break end
            line = line + select(2, code:sub(position, first - 1):gsub("\n", ""))
            functions = functions + 1
            local summary = (lines[line - 1] or ""):match("^%s*%-%-%s+(.-)%s*$")
            local words = summary ~= nil and select(2, summary:gsub("%S+", "")) or 0
            if words < 3 or words > 10 or summary:sub(-1) == "." then
                problems = problems + 1
                print(path .. ":" .. line .. ": " .. name .. " needs a 3-10 word summary without a final period")
            end
            line = line + select(2, code:sub(first, last):gsub("\n", ""))
            position = last + 1
        end
    end
    return problems, functions
end

return Comments
