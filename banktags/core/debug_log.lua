-- Log debug messages only when the saved debug setting is on

local DebugLog = {}

local enabled = false

-- Turn debug logging on or off from the saved setting
function DebugLog.SetEnabled(value)
    enabled = value == true
end

-- Check whether debug logging is enabled
function DebugLog.IsEnabled()
    return enabled
end

-- Write a message when debug logging is enabled
local function debugLog(...)
    if enabled and type(log) == "function" then log(...) end
end

DebugLog.Write = debugLog

return DebugLog
