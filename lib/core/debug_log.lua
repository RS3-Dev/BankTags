-- Keep optional diagnostics behind the single saved debug preference

local DebugLog = {}

local enabled = false

-- Enable optional console output only when the saved debug preference is true
function DebugLog.SetEnabled(value)
    enabled = value == true
end

-- Check whether debug logging is enabled
function DebugLog.IsEnabled()
    return enabled
end

-- Forward diagnostics to the host log only while debugging is enabled
local function debugLog(...)
    if enabled and type(log) == "function" then log(...) end
end

DebugLog.Write = debugLog

return DebugLog
