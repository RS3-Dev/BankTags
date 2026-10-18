-- Start Bank Tags: tags, folders, layouts, select mode, and Import/Share, shown in the bank
-- through Bank Core's public API. Bank Core is an optional dependency only because the host
-- reports changes for optional dependencies; without it, the plugin panel says it is needed

-- Retain the debug preference even if the preceding session fails to stop during reload
local DebugLog = require("banktags/core/debug_log")
local debugLog = DebugLog.Write

local SESSION_KEY = "__banktags_session"
local API_KEY = "__banktags_api"

local previous = rawget(_G, SESSION_KEY)
if previous ~= nil then
    local ok, message = pcall(function() previous:Shutdown() end)
    if not ok then debugLog("Bank Tags could not fully stop the previous reload: ", message) end
end
-- Reload shares the Lua state, so release the old references before rebuilding modules
if rawget(_G, SESSION_KEY) == previous then _G[SESSION_KEY] = nil end
if previous ~= nil and rawget(_G, API_KEY) == previous.publicAPI then _G[API_KEY] = nil end
previous = nil
pcall(function() collectgarbage("collect") end)

-- The host retains modules across reloads; evict this plugin's cache to keep callbacks current.
-- tools/build.lua writes the list into the built main.lua, so run the built folder, not this file
if package ~= nil and package.loaded ~= nil then
    for _, moduleName in ipairs({
        -- build: every module this plugin loads, except the debug log
    }) do
        package.loaded[moduleName] = nil
    end
end

local App = require("banktags/app")
local Catalog = require("banktags/tags/catalog")
local app = App.new()
_G[SESSION_KEY] = app
app:Start()

-- Plugins that add import sources read the injected banktags global first and this copy second
local api = app.publicAPI
_G[API_KEY] = api

-- Connect when Bank Core loads and let go when it unloads; RuneQL is read when searching,
-- and only while the host last reported it enabled
function PluginDependencyUpdate(event)
    if event.pluginIdentifier == "runeql" then Catalog.SetRuneQLEnabled(event.enabled) end
    if event.pluginIdentifier ~= "bankcore" then return end
    if event.enabled then app:Connect() else app:Disconnect() end
end

-- Stop the session and release its reload and API references when the host unloads Bank Tags
function PluginShutdown()
    app:Shutdown()
    if rawget(_G, SESSION_KEY) == app then _G[SESSION_KEY] = nil end
    if rawget(_G, API_KEY) == api then _G[API_KEY] = nil end
end

return api
