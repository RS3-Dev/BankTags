-- Build Bank Tags, run every test, and check the built files
-- Usage, from the repository root: lua54 tools/check.lua
-- Tests read Bank Core from BANKCORE_ROOT and PrettyUI's MiniMenu from PRETTYUI_ROOT; see tests/README.md
-- Each test runs in its own process because the tests install different host stand-ins

package.path = "./?.lua;" .. package.path

local interpreter = arg[-1] or "lua54"
-- luac sits beside the interpreter in the Lua binary distribution
local compiler = interpreter:gsub("lua(%d*)%.exe$", "luac%1.exe"):gsub("lua(%d*)$", "luac%1")

-- Globals the game host and Lua itself provide, and the dependency globals it injects
local ALLOWED = {}
for name in ([[
ui id Event prettyui PersistentDB config game Mouse Vector4 log bankcore runeql MiniMenuActionType
MiniMenu GameKey
PluginShutdown PluginDependencyUpdate pairs ipairs type tostring tonumber math string table
pcall error select next setmetatable getmetatable rawget rawset require print os io load
assert collectgarbage package _G utf8 coroutine debug
]]):gmatch("%S+") do ALLOWED[name] = true end

-- Run a command and return whether it succeeded and what it printed
local function run(command)
    local handle = io.popen(command .. " 2>&1")
    local output = handle:read("a")
    local ok = handle:close()
    return ok == true, output
end

-- List the tracked files matching git pathspecs
local function trackedFiles(...)
    local _, output = run("git ls-files " .. table.concat({ ... }, " "))
    local files = {}
    for path in output:gmatch("[^\r\n]+") do files[#files + 1] = path end
    return files
end

local failures = 0

-- Compile the built folder, since that is what the client loads
local Build = require("tools/build")
local built, build = pcall(Build.Run, { out = "dist/check" })
if not built then
    print("BUILD FAILED " .. tostring(build))
    os.exit(1)
end
local runtime, shipped, strays = {}, {}, 0
for _, file in ipairs(build.files) do
    if string.match(file.path, "%.lua$") then runtime[#runtime + 1] = build.folder .. "/" .. file.path end
    shipped[file.source] = true
    if string.match(file.source, "^reference/") or string.match(file.source, "^tests/")
        or string.match(file.source, "^tools/") then
        strays = strays + 1
        print("SHIPPED " .. file.source .. " is not runtime source")
    end
end
print(("built %d files into %s"):format(#build.files, build.folder))

-- A runtime source the entry never loads would never ship
local orphans = 0
for _, path in ipairs(trackedFiles('"plugins/*.lua"', '"banktags/*.lua"')) do
    if not shipped[path] then
        orphans = orphans + 1
        print("NOT SHIPPED " .. path .. " is loaded by nothing")
    end
end

-- Name the Bank Core checkout the tests run against
local coreRoot = os.getenv("BANKCORE_ROOT") or "../bank-utilities"
local _, coreHead = run('git -C "' .. coreRoot .. '" log -1 --format="%h %s"')
print("Bank Core for tests: " .. coreRoot .. " at " .. (coreHead:match("[^\r\n]+") or "unknown"))
-- Name the PrettyUI checkout the tests load MiniMenu from
local prettyRoot = os.getenv("PRETTYUI_ROOT")
if prettyRoot == nil then
    print("PrettyUI for tests: PRETTYUI_ROOT is not set, so tests that load Bank Tags fail")
else
    local _, prettyHead = run('git -C "' .. prettyRoot .. '" log -1 --format="%h %s"')
    print("PrettyUI for tests: " .. prettyRoot .. " at " .. (prettyHead:match("[^\r\n]+") or "unknown"))
end

local tests = trackedFiles('"tests/*_test.lua"')
for _, path in ipairs(tests) do
    local ok, output = run(('"%s" %s'):format(interpreter, path))
    if not ok then
        failures = failures + 1
        print("FAIL " .. path .. "\n" .. output)
    end
end
print(("%d of %d tests passed"):format(#tests - failures, #tests))

local globalProblems = 0
for _, path in ipairs(runtime) do
    local ok, listing = run(('"%s" -p -l -l %s'):format(compiler, path))
    if not ok then
        globalProblems = globalProblems + 1
        print("COMPILE ERROR " .. path .. "\n" .. listing)
    else
        local unexpected, seen = {}, {}
        for name in listing:gmatch('TABUP%s.-_ENV "([^"]+)"') do
            if not ALLOWED[name] and not seen[name] then
                seen[name] = true
                unexpected[#unexpected + 1] = name
            end
        end
        if #unexpected > 0 then
            globalProblems = globalProblems + 1
            table.sort(unexpected)
            print(path .. " uses unexpected globals: " .. table.concat(unexpected, ", "))
        end
    end
end
print(("%d of %d built runtime files compile with no unexpected globals"):format(
    #runtime - globalProblems, #runtime))

os.exit(failures == 0 and globalProblems == 0 and orphans == 0 and strays == 0 and 0 or 1)
