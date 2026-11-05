-- Find the plugin's required modules from the repository root
-- Use module paths without .lua, following Bank Core's build tools

local ModuleGraph = {}

-- Read a module's source when it exists
function ModuleGraph.Source(moduleName)
    local file = io.open(moduleName .. ".lua", "r")
    if file == nil then return nil end
    local source = file:read("a")
    file:close()
    return source
end

-- List a module's required names in source order
function ModuleGraph.Requires(moduleName)
    local source = ModuleGraph.Source(moduleName)
    if source == nil then error("module " .. moduleName .. " has no file", 2) end
    return ModuleGraph.RequiresIn(source, moduleName)
end

-- Find module names and their positions in imports
function ModuleGraph.RequiresIn(source, moduleName)
    local code = ModuleGraph.Code(source)
    local names, imports, position = {}, {}, 1
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
            imports[#imports + 1] = { name = name, first = quote + 1, last = close - 1 }
        end
    end
    return names, imports
end

-- Collect every module the roots load, sorted by name
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

-- Blank comments and string contents, keeping every position
function ModuleGraph.Code(source)
    local out, index, length = {}, 1, #source
    -- Blank a source span while keeping its line breaks
    local function blank(first, last)
        out[#out + 1] = (string.gsub(string.sub(source, first, last), "[^\n]", " "))
    end
    while index <= length do
        local longOpen = string.match(source, "^%-%-%[(=*)%[", index)
        if longOpen ~= nil then
            local close = string.find(source, "]" .. longOpen .. "]", index, true)
            local last = close and close + #longOpen + 1 or length
            blank(index, last)
            index = last + 1
        elseif string.sub(source, index, index + 1) == "--" then
            local lineEnd = string.find(source, "\n", index, true) or length + 1
            blank(index, lineEnd - 1)
            index = lineEnd
        else
            local stringOpen = string.match(source, "^%[(=*)%[", index)
            local quote = string.sub(source, index, index)
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

-- List the modules a plugin entry loads, excluding the entry
function ModuleGraph.PluginModules(entry)
    local names = {}
    for _, name in ipairs((ModuleGraph.Closure({ entry }))) do
        if name ~= entry then names[#names + 1] = name end
    end
    return names
end

return ModuleGraph
