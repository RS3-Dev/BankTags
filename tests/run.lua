-- Run from the repository root with Lua 5.4: lua tests/run.lua
local root = (arg[0]:gsub("\\", "/"):match("^(.*)/tests/run%.lua$")) or "."
local suites = {
    "bank_state", "catalog", "connection", "editor_menus",
    "editor_names", "editor_v2", "marquee", "text_safety", "unsorted", "import_share", "native_items", "tag_ids", "page_restore",
}

-- Give each case fresh globals and module caches, including its UI stubs.
local function environment()
    local env = setmetatable({ root = root }, { __index = _G })
    env._G = env
    env.package = { path = root .. "/?.lua;" .. package.path, loaded = {} }
    for name, module in pairs(package.loaded) do env.package.loaded[name] = module end
    function env.loadfile(path)
        return loadfile(path, "t", env)
    end
    function env.require(name)
        local cached = env.package.loaded[name]
        if cached ~= nil then return cached end
        local path, problem = package.searchpath(name, env.package.path)
        assert(path, problem)
        local value = assert(env.loadfile(path))(name, path)
        if value == nil then value = true end
        env.package.loaded[name] = value
        return value
    end
    return env
end

local passed, failed, skipped = 0, 0, 0
for _, name in ipairs(suites) do
    local path = root .. "/tests/" .. name .. "_test.lua"
    local suite = assert(environment().loadfile(path))()
    local names = {}
    for test in pairs(suite.tests) do names[#names + 1] = test end
    table.sort(names)
    for _, test in ipairs(names) do
        local ok, result, reason = xpcall(function()
            local fresh = assert(environment().loadfile(path))()
            fresh.setup()
            return fresh.tests[test]()
        end, debug.traceback)
        if not ok then
            failed = failed + 1
            io.stderr:write("FAIL " .. name .. "." .. test .. "\n" .. result .. "\n")
        elseif result == "skip" then
            skipped = skipped + 1
            print("SKIP " .. name .. "." .. test .. ": " .. reason)
        else
            passed = passed + 1
        end
    end
end
print(string.format("%d passed, %d failed, %d skipped", passed, failed, skipped))
if failed > 0 then os.exit(1) end
