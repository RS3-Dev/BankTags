-- Start Bank Utilities: tags, cleanup views, RuneQL search and saved queries, the layout
-- editor, and Import/Share, attached to the running Bank Core. Bank Core owns the bank
-- session and its events; this plugin builds no bank controller and returns no API

-- Hot reloads may not inject the dependency global, so fall back to RuneQL's published API
local runeqlDependency = type(runeql) == "table" and runeql
    or rawget(_G, "__runeql_api")
if type(runeqlDependency) ~= "table" or tonumber(runeqlDependency.API_VERSION) ~= 2 then
    error("BankUtils requires the RuneQL Core dependency API v2")
end
runeql = runeqlDependency

-- Retain the debug preference even if the preceding app fails to stop during reload
local DebugLog = require("lib/core/debug_log")
local debugLog = DebugLog.Write

local previous = rawget(_G, "__bankutils_app")
if previous ~= nil then
    local ok, message = pcall(function() previous:Shutdown() end)
    if not ok then debugLog("Bank Utilities could not fully stop the previous reload: ", message) end
end
-- Reload shares the Lua VM, so release the old app reference before rebuilding modules
if rawget(_G, "__bankutils_app") == previous then
    _G.__bankutils_app = nil
end
-- The single-plugin build published its bank API here; its handles already refuse every call
if previous ~= nil and rawget(_G, "__bankutils_api") == previous.publicAPI then
    _G.__bankutils_api = nil
end
previous = nil
pcall(function() collectgarbage("collect") end)

-- The host retains modules across reloads; evict this plugin's cache to keep callbacks current.
-- tools/build.lua writes the list into the built main.lua, so run the built folder, not this file
if package ~= nil and package.loaded ~= nil then
    for _, moduleName in ipairs({
        -- build: every module this plugin loads, except the debug log
        -- Retired modules with no file: keep evicting them so upgrading through a hot reload
        -- releases the previous generation's cached page state and window constructors
        "lib/features/tags/bank_tag_filter",
        "lib/features/tags/tag_editor",
        "lib/features/tags/tag_layout_editor",
    }) do
        package.loaded[moduleName] = nil
    end
end

local App = require("lib/core/app")

-- Find a running Bank Core: the injected global first, then the copy it publishes
local function findCore()
    if App.IsCore(bankcore) then return bankcore end
    local published = rawget(_G, "__bankcore_api")
    if App.IsCore(published) then return published end
    return nil
end

local app = App.new()
_G.__bankutils_app = app
app:Start(findCore)

-- Attach again if the host reports that Bank Core loaded; Bank Core's own shutdown already
-- detached these features when it stopped
function PluginOptionalDependencyChanged(event)
    if event ~= nil and event.pluginIdentifier == "bankcore" and event.loaded then
        app:Reconnect()
    end
end

-- Detach from Bank Core, close this plugin's windows, and release the reload reference
function PluginShutdown()
    app:Shutdown()
    if rawget(_G, "__bankutils_app") == app then
        _G.__bankutils_app = nil
    end
end
