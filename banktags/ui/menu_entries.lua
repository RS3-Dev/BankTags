-- Add Bank Tags' entries to a native right-click menu without disturbing its default. The
-- host lists entries from lowest to highest priority, and a left click runs the last one.
-- The API documents Add as appending there, but live clients placed plugin entries just
-- above Cancel or just below the native default, so each new entry is found by comparing
-- the list before and after, then moved. Bank Core may promote Cancel before or after
-- this runs; nothing here relies on which comes first

local MenuEntries = {}

local NAME_COLOUR = "f2c66d"

-- Find the Cancel entry
local function cancelIndex(menu)
    for index, entry in ipairs(menu.entries) do
        if entry.actionType == MiniMenuActionType.CANCEL then return index end
    end
    return nil
end

-- Place Cancel at the highest priority, so a left click does nothing
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

-- Remove markup and outer spaces, then lowercase, so menu text compares reliably
local function normalize(value)
    return string.lower((tostring(value or ""):gsub("<[^>]->", "")):match("^%s*(.-)%s*$"))
end

-- Add one entry and return where the host put it, or nil when it cannot be found
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

-- Add entries at the lowest priority, in order, just above a Cancel at the bottom, so the
-- default stays as it was. An entry that cannot be found, or a default that moved, makes
-- Cancel the default, so a left click runs nothing unplaced
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

-- Make an entry the left-click default. When Cancel already is, something guarded the
-- menu, so the entry goes low instead; one that cannot be found makes Cancel the default
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
