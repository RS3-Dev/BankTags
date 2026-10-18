-- Build the Bank Tags plugin folder from the canonical source: its entry, manifest, and
-- exactly the modules the entry's require graph loads. The entry's eviction list is
-- generated from that graph. Tests, tools, and reference material never ship.
-- Usage, from the repository root:
--   lua54 tools/build.lua [--out dist]

local ModuleGraph = require("tools/module_graph")
local Json = require("banktags/core/json")

local Build = {}

Build.DEFAULT_OUT = "dist"
Build.MANIFEST = "build_manifest.lua"
Build.PLUGIN = { name = "banktags", entry = "plugins/banktags/main", manifest = "plugins/banktags/plugin.json" }
-- The line in the entry that the built main.lua replaces with the entry's modules
Build.EVICTION_MARKER = "-- build: every module this plugin loads, except the debug log"
-- The debug log stays loaded on purpose, so the debug preference survives a reload whose
-- previous run failed to stop
Build.KEPT_LOADED = "banktags/core/debug_log"
-- Top-level source directories an output may never be placed in
local SOURCE_DIRECTORIES = {
    banktags = true, plugins = true, tools = true, tests = true, reference = true,
}

local WINDOWS = package.config:sub(1, 1) == "\\"

-- Read a file's bytes, failing loudly when it is missing
local function readFile(path)
    local file = io.open(path, "rb")
    if file == nil then error("cannot read " .. path, 0) end
    local bytes = file:read("a")
    file:close()
    return bytes
end

-- Write bytes to a file, replacing it
local function writeFile(path, bytes)
    local file = io.open(path, "wb")
    if file == nil then error("cannot write " .. path, 0) end
    file:write(bytes)
    file:close()
end

-- Quote a path for the shell, with the platform's separators
local function shellPath(path)
    if WINDOWS then path = string.gsub(path, "/", "\\") end
    return '"' .. path .. '"'
end

-- Run shell commands in order, stopping at the first failure; returns success and output
local function shell(commands)
    if #commands == 0 then return true, "" end
    local handle = io.popen("(" .. table.concat(commands, " && ") .. ") 2>&1")
    local output = handle:read("a")
    return handle:close() == true, output
end

-- List a directory's entries, or nil when it does not exist
local function listDirectory(path)
    local command = WINDOWS and ("if exist " .. shellPath(path .. "/") .. " dir /b " .. shellPath(path))
        or ("[ -d " .. shellPath(path) .. " ] && ls -A " .. shellPath(path))
    local ok, output = shell({ command })
    if not ok then return nil end
    local names = {}
    for name in string.gmatch(output, "[^\r\n]+") do names[#names + 1] = name end
    return names
end

-- Refuse an output path that could reach the source tree or anything outside the repository:
-- it must be relative, use only letters, digits, _, and -, sit outside every source
-- directory, and be ignored by git
function Build.CheckOutput(out)
    if type(out) ~= "string" or string.match(out, "^[%w_%-][%w_%-/]*$") == nil
        or string.find(out, "//", 1, true) ~= nil or string.sub(out, -1) == "/" then
        return false, "the output must be a relative path of letters, digits, _, and -"
    end
    local first = string.match(out, "^[^/]+")
    if SOURCE_DIRECTORIES[first] then return false, "the output may not be inside " .. first .. "/" end
    local inGit = shell({ "git rev-parse --is-inside-work-tree" })
    if inGit and not shell({ "git check-ignore -q " .. shellPath(out .. "/" .. Build.MANIFEST) }) then
        return false, "the output " .. out .. " is not ignored by git; add it to .gitignore"
    end
    return true
end

-- Return the entry's built bytes: the marker line becomes one quoted name per module the
-- entry loads, at the marker's indent
function Build.Entry()
    local plugin = Build.PLUGIN
    local marker = "\n([ \t]*)" .. string.gsub(Build.EVICTION_MARKER, "%p", "%%%0") .. "(\r?)%f[\n]"
    local bytes, count = string.gsub(readFile(plugin.entry .. ".lua"), marker, function(indent, cr)
        local lines = {}
        for _, name in ipairs(ModuleGraph.PluginModules(plugin.entry)) do
            if name ~= Build.KEPT_LOADED then lines[#lines + 1] = indent .. '"' .. name .. '",' end
        end
        return "\n" .. table.concat(lines, cr .. "\n") .. cr
    end)
    if count ~= 1 then error(plugin.entry .. " needs exactly one eviction marker line", 0) end
    return bytes
end

-- List the files the plugin folder holds, sorted so the output is the same every time
function Build.Plan()
    local plugin = Build.PLUGIN
    local files = {
        { path = "main.lua", source = plugin.entry .. ".lua", entry = true },
        { path = "plugin.json", source = plugin.manifest, manifest = true },
    }
    for _, moduleName in ipairs(ModuleGraph.PluginModules(plugin.entry)) do
        files[#files + 1] = { path = moduleName .. ".lua", source = moduleName .. ".lua" }
    end
    table.sort(files, function(a, b) return a.path < b.path end)
    return files
end

-- List every directory the planned files need, parents before children
local function plannedDirectories(name, files)
    local seen, directories = {}, { name }
    for _, file in ipairs(files) do
        local prefix = name
        local folder = string.match(file.path, "^(.*)/[^/]+$")
        for part in string.gmatch(folder or "", "[^/]+") do
            prefix = prefix .. "/" .. part
            if not seen[prefix] then
                seen[prefix] = true
                directories[#directories + 1] = prefix
            end
        end
    end
    table.sort(directories)
    return directories
end

-- True for segments of letters, digits, _, and - joined by single slashes
local function isRelativePath(path)
    return type(path) == "string" and string.gsub(string.gsub(path, "[%w_%-]+", "x"), "/x", "") == "x"
end

-- Read the previous build's manifest from the output, or nil when there is none. It must
-- name only .lua and .json files under relative paths before anything is deleted
local function previousManifest(out)
    local path = out .. "/" .. Build.MANIFEST
    local file = io.open(path, "rb")
    if file == nil then return nil end
    file:close()
    local chunk = loadfile(path, "t", {})
    local ok, manifest = pcall(chunk or error)
    local valid = ok and type(manifest) == "table" and manifest.name == Build.PLUGIN.name
        and type(manifest.files) == "table" and type(manifest.directories) == "table"
    for _, filePath in ipairs(valid and manifest.files or {}) do
        local stem, extension = string.match(tostring(filePath), "^(.*)%.(%a+)$")
        if (extension ~= "lua" and extension ~= "json") or not isRelativePath(stem) then valid = false end
    end
    for _, directory in ipairs(valid and manifest.directories or {}) do
        if not isRelativePath(directory) then valid = false end
    end
    if not valid then error(path .. " is not a build manifest; remove the output by hand", 0) end
    return manifest
end

-- Remove only what the previous build wrote: its files, then its now empty directories
local function cleanOutput(out)
    local manifest = previousManifest(out)
    if manifest == nil then
        local entries = listDirectory(out)
        if entries ~= nil and #entries > 0 then
            error(out .. " holds files no build wrote; empty it or choose another --out", 0)
        end
        return
    end
    for _, filePath in ipairs(manifest.files) do os.remove(out .. "/" .. manifest.name .. "/" .. filePath) end
    local commands = {}
    for index = #manifest.directories, 1, -1 do
        local path = shellPath(out .. "/" .. manifest.directories[index])
        commands[#commands + 1] = WINDOWS
            and ("(if exist " .. string.sub(path, 1, -2) .. '\\" rmdir ' .. path .. ")")
            or ("{ [ ! -d " .. path .. " ] || rmdir " .. path .. "; }")
    end
    local ok, output = shell(commands)
    if not ok then error("a built folder holds files the last build did not write: " .. output, 0) end
    os.remove(out .. "/" .. Build.MANIFEST)
end

-- Write the manifest naming every file and directory this build wrote
local function writeManifest(out, files, directories)
    local lines = { "-- Written by tools/build.lua; the next build removes exactly these files", "return {",
        ("    name = %q,"):format(Build.PLUGIN.name), "    files = {" }
    for _, file in ipairs(files) do lines[#lines + 1] = ("        %q,"):format(file.path) end
    lines[#lines + 1] = "    },"
    lines[#lines + 1] = "    directories = {"
    for _, directory in ipairs(directories) do lines[#lines + 1] = ("        %q,"):format(directory) end
    lines[#lines + 1] = "    },"
    lines[#lines + 1] = "}"
    writeFile(out .. "/" .. Build.MANIFEST, table.concat(lines, "\n") .. "\n")
end

-- Build the plugin into options.out (default dist) and return what was written
function Build.Run(options)
    options = options or {}
    local out = options.out or Build.DEFAULT_OUT
    local allowed, reason = Build.CheckOutput(out)
    if not allowed then error(reason, 0) end

    -- Read every source before touching the output, so a bad source changes nothing
    local files = Build.Plan()
    for _, file in ipairs(files) do
        file.bytes = file.entry and Build.Entry() or readFile(file.source)
        if file.manifest then
            local ok, manifest = pcall(Json.decode, file.bytes)
            if not ok or type(manifest) ~= "table" or manifest.name ~= Build.PLUGIN.name then
                error(file.source .. " does not decode as the " .. Build.PLUGIN.name .. " manifest", 0)
            end
        end
    end

    cleanOutput(out)
    local name = Build.PLUGIN.name
    local directories = plannedDirectories(name, files)
    local commands = {}
    if listDirectory(out) == nil then commands[1] = (WINDOWS and "mkdir " or "mkdir -p ") .. shellPath(out) end
    for _, directory in ipairs(directories) do
        commands[#commands + 1] = (WINDOWS and "mkdir " or "mkdir -p ") .. shellPath(out .. "/" .. directory)
    end
    local ok, output = shell(commands)
    if not ok then error("could not create the output folders: " .. output, 0) end
    for _, file in ipairs(files) do
        writeFile(out .. "/" .. name .. "/" .. file.path, file.bytes)
        file.bytes = nil
    end
    writeManifest(out, files, directories)
    return { out = out, folder = out .. "/" .. name, files = files, directories = directories }
end

-- Read command-line options for a build
local function readArguments(arguments)
    local options = {}
    local index = 1
    while index <= #arguments do
        if arguments[index] == "--out" then
            options.out = arguments[index + 1]
            index = index + 2
        else
            error("unknown option " .. tostring(arguments[index]), 0)
        end
    end
    return options
end

local scriptArguments = { ... }
if scriptArguments[1] ~= "tools/build" then
    package.path = "./?.lua;" .. package.path
    local ok, result = pcall(function() return Build.Run(readArguments(scriptArguments)) end)
    if not ok then
        io.stderr:write("build failed: " .. tostring(result) .. "\n")
        os.exit(1)
    end
    print(("%s: %d files"):format(result.folder, #result.files))
end

return Build
