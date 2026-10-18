-- Protect displaced native items from transition clicks while keeping their menu actions

local Text = require("lib/core/text")

local NativeItemMenuGuard = {}
local normalize = Text.normalizeMenuText

-- Move Cancel to the highest-priority menu slot while preserving every right-click action
function NativeItemMenuGuard.PromoteCancel(menu)
    if menu == nil or menu.entries == nil or menu.Swap == nil then return false end
    local count = math.tointeger(tonumber(menu.entryCount)) or #menu.entries
    if count < 1 then return false end
    local cancelIndex = nil
    for index, entry in ipairs(menu.entries) do
        if normalize(entry.verbText) == "cancel"
            or normalize(entry.overrideText) == "cancel"
            or normalize(entry.fullText) == "cancel" then
            cancelIndex = index
            break
        end
    end
    if cancelIndex == nil then return false end
    for index = cancelIndex, count - 1 do menu:Swap(index, index + 1) end
    return true
end

return NativeItemMenuGuard
