-- Add Bank Tags' entries to native menus without changing the default
-- Live clients place added entries inconsistently, so each one is found and moved

local MenuEntries = {}

local NAME_COLOUR = "f2c66d"

-- Find the Cancel entry
local function cancelIndex(menu)
    for index, entry in ipairs(menu.entries) do
        if entry.actionType == MiniMenuActionType.CANCEL then return index end
    end
    return nil
end

-- Make Cancel the left click
function MenuEntries.PromoteCancel(menu)
    local index = cancelIndex(menu)
    if index == nil then return end
    for current = index, menu.entryCount - 1 do menu:Swap(current, current + 1) end
end

-- Describe an entry well enough to tell it from its neighbours
local function signature(entry)
    return table.concat({ tostring(entry.actionType), tostring(entry.overrideText),
        tostring(entry.fullText), tostring(entry.verbText), tostring(entry.subjectText) }, "\n")
end

-- Normalize menu text for comparison
local function normalize(value)
    return string.lower((tostring(value or ""):gsub("<[^>]->", "")):match("^%s*(.-)%s*$"))
end

-- Add one entry and find where the host put it
local function add(menu, entry)
    local text = entry.label
    if entry.subject ~= nil then text = text .. " <col=" .. NAME_COLOUR .. ">" .. entry.subject .. "</col>" end
    local before = {}
    for index, current in ipairs(menu.entries) do before[index] = signature(current) end
    menu:Add(text, entry.action)
    local entries, count = menu.entries, menu.entryCount
    if count ~= #before + 1 then return nil end
    local added = count
    for index = 1, count do
        if signature(entries[index]) ~= before[index] then
            added = index
            break
        end
    end
    local wanted, found = normalize(text), entries[added]
    if normalize(found.overrideText) ~= wanted and normalize(found.fullText) ~= wanted
        and normalize(found.verbText) ~= wanted then
        return nil
    end
    return added
end

-- Move an entry from one index to another, shifting the ones between
local function move(menu, from, to)
    local step = from < to and 1 or -1
    for current = from, to - step, step do menu:Swap(current, current + step) end
end

-- Add entries at the lowest priority, keeping the default
-- If placement fails, Cancel becomes the default
function MenuEntries.AddLow(menu, entries)
    if #entries == 0 then return end
    local top = menu.entries[menu.entryCount]
    local topSignature = top ~= nil and signature(top) or nil
    local cancelTop = top ~= nil and top.actionType == MiniMenuActionType.CANCEL
    local first = menu.entries[1]
    local base = (not cancelTop and first ~= nil and first.actionType == MiniMenuActionType.CANCEL) and 1 or 0
    for index, entry in ipairs(entries) do
        local added = add(menu, entry)
        if added == nil then
            MenuEntries.PromoteCancel(menu)
            return
        end
        move(menu, added, base + index)
    end
    local now = menu.entries[menu.entryCount]
    if now == nil or signature(now) ~= topSignature then MenuEntries.PromoteCancel(menu) end
end

-- Make an entry the left-click default
-- If Cancel already is, add it low instead
function MenuEntries.AddDefault(menu, entry)
    local top = menu.entries[menu.entryCount]
    if top == nil or top.actionType == MiniMenuActionType.CANCEL then
        MenuEntries.AddLow(menu, { entry })
        return
    end
    local added = add(menu, entry)
    if added == nil then
        MenuEntries.PromoteCancel(menu)
        return
    end
    move(menu, added, menu.entryCount)
end

return MenuEntries
