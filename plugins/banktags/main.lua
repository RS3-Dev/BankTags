-- Start Bank Tags and connect it to Bank Core when present

-- Keep the debug preference loaded even if the last session failed to stop
local DebugLog = require("banktags/core/debug_log")
local debugLog = DebugLog.Write

local SESSION_KEY = "__banktags_session"
local API_KEY = "__banktags_api"

local previous = rawget(_G, SESSION_KEY)
if previous ~= nil then
    local ok, message = pcall(function() previous:Shutdown() end)
    if not ok then debugLog("Bank Tags could not fully stop the previous reload: ", message) end
end
-- Reloads share the Lua state, so drop the old references first
if rawget(_G, SESSION_KEY) == previous then _G[SESSION_KEY] = nil end
if previous ~= nil and rawget(_G, API_KEY) == previous.publicAPI then _G[API_KEY] = nil end
previous = nil
pcall(function() collectgarbage("collect") end)

-- Clear this plugin's cached modules so a reload runs the new code
-- tools/build.lua fills in the list, so run the built folder
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

-- Import-source plugins use the API passed to them first, then this global copy
local api = app.publicAPI
_G[API_KEY] = api

-- Follow Bank Core and RuneQL loading and unloading
function PluginDependencyUpdate(event)
    if event.pluginIdentifier == "runeql" then Catalog.SetRuneQLEnabled(event.enabled) end
    if event.pluginIdentifier ~= "bankcore" then return end
    if event.enabled then app:Connect() else app:Disconnect() end
end

-- Stop the session and release its references on unload
function PluginShutdown()
    app:Shutdown()
    if rawget(_G, SESSION_KEY) == app then _G[SESSION_KEY] = nil end
    if rawget(_G, API_KEY) == api then _G[API_KEY] = nil end
end

return api
