-- Walk the require graph from the plugin entry and report which modules it needs.
-- The package builder copies exactly this list. Adapted from Bank Core's build tools.
-- Run from the repository root; module names are paths without ".lua"

local ModuleGraph = {}

-- Read a module's source, or nil when the file does not exist
function ModuleGraph.Source(moduleName)
    local file = io.open(moduleName .. ".lua", "r")
    if file == nil then return nil end
    local source = file:read("a")
    file:close()
    return source
end

-- List the modules one module requires, in source order. A call is the global
-- `require`, then optional parentheses around one quoted module name; whitespace and
-- line breaks may sit between the parts, and comments and strings are ignored. Any other
-- use of `require`, such as a computed name, raises an error instead of being skipped,
-- so a package built from this graph never silently misses a module
function ModuleGraph.Requires(moduleName)
    local source = ModuleGraph.Source(moduleName)
    if source == nil then error("module " .. moduleName .. " has no file", 2) end
    return ModuleGraph.RequiresIn(source, moduleName)
end

-- List the modules a source text requires; moduleName only labels errors
function ModuleGraph.RequiresIn(source, moduleName)
    local code = ModuleGraph.Code(source)
    local names, position = {}, 1
    while true do
        local start, finish = string.find(code, "%f[%w_]require%f[^%w_]", position)
        if start == nil then break end
        position = finish + 1
        local before = start - 1
        while before > 0 and string.find(string.sub(code, before, before), "%s") do
            before = before - 1
        end
        local previous = string.sub(code, before, before)
        if previous ~= "." and previous ~= ":" then
            local line = select(2, string.gsub(string.sub(source, 1, start), "\n", "")) + 1
            local where = moduleName .. ":" .. line
            local quote = string.match(code, "^%s*%(%s*()[\"']", finish + 1)
            local parenthesised = quote ~= nil
            if not parenthesised then quote = string.match(code, "^%s*()[\"']", finish + 1) end
            if quote == nil then error("unsupported require form at " .. where, 2) end
            local close = string.find(code, string.sub(code, quote, quote), quote + 1, true)
            local name = close and string.sub(source, quote + 1, close - 1)
            if name == nil or not string.find(name, "^[%w_/]+$") then
                error("unsupported require name at " .. where, 2)
            end
            position = close + 1
            if parenthesised then
                local after = string.match(code, "^%s*%)()", position)
                if after == nil then error("unsupported require form at " .. where, 2) end
                position = after
            end
            names[#names + 1] = name
        end
    end
    return names
end

-- Collect every module the roots load, directly or through other modules, sorted by name
function ModuleGraph.Closure(roots)
    local seen, pending = {}, {}
    for _, root in ipairs(roots) do pending[#pending + 1] = root end
    while #pending > 0 do
        local name = table.remove(pending)
        if not seen[name] then
            seen[name] = true
            for _, required in ipairs(ModuleGraph.Requires(name)) do
                pending[#pending + 1] = required
            end
        end
    end
    local names = {}
    for name in pairs(seen) do names[#names + 1] = name end
    table.sort(names)
    return names, seen
end

-- Blank out comments and string contents with spaces, keeping code, quote marks, and
-- line breaks, so every position in the result is the same position in the source
function ModuleGraph.Code(source)
    local out, index, length = {}, 1, #source
    local function blank(first, last)
        out[#out + 1] = (string.gsub(string.sub(source, first, last), "[^\n]", " "))
    end
    while index <= length do
        local rest = string.sub(source, index)
        local longOpen = string.match(rest, "^%-%-%[(=*)%[")
        if longOpen ~= nil then
            local close = string.find(source, "]" .. longOpen .. "]", index, true)
            local last = close and close + #longOpen + 1 or length
            blank(index, last)
            index = last + 1
        elseif string.sub(rest, 1, 2) == "--" then
            local lineEnd = string.find(source, "\n", index, true) or length + 1
            blank(index, lineEnd - 1)
            index = lineEnd
        else
            local stringOpen = string.match(rest, "^%[(=*)%[")
            local quote = string.sub(rest, 1, 1)
            if stringOpen ~= nil then
                local close = string.find(source, "]" .. stringOpen .. "]", index, true)
                local last = close and close + #stringOpen + 1 or length
                blank(index, last)
                index = last + 1
            elseif quote == '"' or quote == "'" then
                local cursor = index + 1
                while cursor <= length do
                    local character = string.sub(source, cursor, cursor)
                    if character == "\\" then
                        cursor = cursor + 2
                    elseif character == quote or character == "\n" then
                        break
                    else
                        cursor = cursor + 1
                    end
                end
                local last = math.min(cursor, length)
                out[#out + 1] = quote
                if last > index + 1 then blank(index + 1, last - 1) end
                if last > index then out[#out + 1] = string.sub(source, last, last) end
                index = last + 1
            else
                out[#out + 1] = quote
                index = index + 1
            end
        end
    end
    return table.concat(out)
end

-- List the modules a plugin's entry file loads, directly or not, without the entry itself.
-- The entry is a path without ".lua", such as plugins/banktags/main
function ModuleGraph.PluginModules(entry)
    local names = {}
    for _, name in ipairs((ModuleGraph.Closure({ entry }))) do
        if name ~= entry then names[#names + 1] = name end
    end
    return names
end

return ModuleGraph
