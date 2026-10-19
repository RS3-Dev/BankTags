-- Lay saved rows and labels out on a bank grid of any width

local TagRules = require("banktags/tags/tag_rules")

local TagLayouts = {}

-- Width used when a caller gives none
local DEFAULT_COLUMNS = 10

-- Return a new empty slot
local function blank()
    return { kind = "blank" }
end

-- Check whether a slot is empty and reserves no item
function TagLayouts.IsOpen(slot)
    return type(slot) == "table" and slot.kind == "blank" and slot.dormant == nil
end

-- Check whether a row holds no items or reserved positions
local function rowIsEmpty(entry)
    for _, slot in ipairs(entry.slots) do
        if not TagLayouts.IsOpen(slot) then return false end
    end
    return true
end

-- Trim trailing open slots and trailing empty rows
function TagLayouts.Trim(entries)
    for _, entry in ipairs(entries) do
        if entry.kind == "row" then TagRules.trimTrailingLayoutBlanks(entry.slots) end
    end
    while #entries > 0 and entries[#entries].kind == "row" and #entries[#entries].slots == 0 do
        entries[#entries] = nil
    end
    return entries
end

-- Lay entries out at a column count, wrapping long rows
function TagLayouts.Render(entries, columns)
    columns = math.max(1, math.tointeger(tonumber(columns)) or DEFAULT_COLUMNS)
    local view = { columns = columns, slots = {}, labels = {}, cells = {}, starts = {}, lines = 0 }
    local line = 0
    for index, entry in ipairs(entries or {}) do
        view.starts[index] = line
        if entry.kind == "label" then
            view.labels[#view.labels + 1] = { row = line, text = entry.text, entry = index }
            for cell = 1, columns do view.slots[line * columns + cell] = blank() end
            line = line + 1
        else
            local count = math.max(1, math.ceil(#entry.slots / columns))
            for position = 1, count * columns do
                local gridIndex = line * columns + position
                view.slots[gridIndex] = entry.slots[position] or blank()
                view.cells[gridIndex] = { entry = index, position = position }
            end
            line = line + count
        end
    end
    view.lines = line
    return view
end

-- Find the entry a new entry should precede to start at a line
function TagLayouts.EntryAtLine(view, entries, line)
    for index = 1, #entries do
        local nextStart = view.starts[index + 1] or view.lines
        if line < nextStart then return index end
    end
    return #entries + 1
end

-- Check whether an entry is a row with nothing in it
function TagLayouts.IsEmptyRow(entry)
    return entry ~= nil and entry.kind == "row" and rowIsEmpty(entry)
end

-- List every slot in a layout's rows, in order
function TagLayouts.RowSlots(entries)
    local slots = {}
    for _, entry in ipairs(entries or {}) do
        if entry.kind == "row" then
            for _, slot in ipairs(entry.slots) do slots[#slots + 1] = slot end
        end
    end
    return slots
end

-- Find the first open slot after a position, or nil
function TagLayouts.FirstOpenSlot(entries, afterEntry, afterPosition)
    afterEntry = afterEntry or 0
    afterPosition = afterPosition or 0
    for pass = 1, 2 do
        for index, entry in ipairs(entries) do
            if entry.kind == "row" then
                for position, slot in ipairs(entry.slots) do
                    local after = index > afterEntry
                        or (index == afterEntry and position > afterPosition)
                    if (pass == 1) == after and TagLayouts.IsOpen(slot) then
                        return index, position
                    end
                end
            end
        end
    end
    return nil, nil
end

-- Add a slot to the end of the last row
function TagLayouts.AppendToLastRow(entries, slot)
    local last = entries[#entries]
    if last == nil or last.kind ~= "row" then
        last = { kind = "row", slots = {} }
        entries[#entries + 1] = last
    end
    last.slots[#last.slots + 1] = slot
    return #entries, #last.slots
end

return TagLayouts
