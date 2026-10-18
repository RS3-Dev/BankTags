-- Add, find, and order native right-click menu entries the same way everywhere

local debugLog = require("lib/core/debug_log").Write

local MenuEntries = {}

local NAME_COLOUR = "f2c66d"

-- Place Cancel at the lowest priority
function MenuEntries.MoveCancelToEnd(menu)
    for index, entry in ipairs(menu.entries) do
        if entry.verbText == "Cancel" then
            for currentIndex = index, 2, -1 do
                menu:Swap(currentIndex, currentIndex - 1)
            end
            return
        end
    end
end

-- Move one entry to an API index
function MenuEntries.MoveToIndex(menu, currentIndex, targetIndex)
    currentIndex = math.tointeger(tonumber(currentIndex))
    targetIndex = math.tointeger(tonumber(targetIndex))
    if currentIndex == nil or targetIndex == nil then return false end
    targetIndex = math.max(1, math.min(targetIndex, menu.entryCount))
    if currentIndex < targetIndex then
        for index = currentIndex, targetIndex - 1 do
            menu:Swap(index, index + 1)
        end
    else
        for index = currentIndex, targetIndex + 1, -1 do
            menu:Swap(index, index - 1)
        end
    end
    return true
end

-- Find an entry by visible text
function MenuEntries.IndexOf(menu, displayedText, normalizeMenuText)
    local wanted = normalizeMenuText(displayedText)
    local function matches(value)
        return value ~= nil and normalizeMenuText(value) == wanted
    end
    for index, entry in ipairs(menu.entries or {}) do
        local nativeText = tostring(entry.verbText or "")
            .. " " .. tostring(entry.subjectText or "")
            .. " " .. tostring(entry.extraText or "")
        if matches(entry.overrideText) or matches(entry.fullText)
            or matches(nativeText) then return index end
    end
    return nil
end

-- Add an action followed by a highlighted name, such as a tag or launcher
function MenuEntries.AddNamedAction(menu, label, action, name)
    local text = label
        .. " <col=" .. NAME_COLOUR .. ">" .. tostring(name) .. "</col>"
    menu:Add(text, action, name)
end

-- Wrap a menu action so a failure is logged instead of escaping the host callback
function MenuEntries.Guarded(description, action)
    return function(...)
        local ok, message = pcall(action, ...)
        if not ok then debugLog("BankUtils could not ", description, ": ", message) end
    end
end

MenuEntries.NAME_COLOUR = NAME_COLOUR

return MenuEntries
