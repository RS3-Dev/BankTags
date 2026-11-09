-- Choose a tag icon by searching items

local debugLog = require("resources/core/debug_log").Write
local Catalog = require("resources/tags/catalog")
local objectFromID = require("resources/core/object_config").FromID
local Text = require("resources/core/text")
local Theme = require("resources/ui/theme")
local trim = Text.trim

local SpritePicker = {}
SpritePicker.__index = SpritePicker

local WIDTH = 392
local HEIGHT = 340
local MARGIN = 14
local CONTENT_WIDTH = WIDTH - 16
local CONTROL_WIDTH = CONTENT_WIDTH - MARGIN * 2
local BUTTON_WIDTH = 72
local CONTROL_GAP = 8
local FIELD_WIDTH = CONTROL_WIDTH - BUTTON_WIDTH - CONTROL_GAP
local COLUMNS = 8
local ROWS = 5
local SLOT_SIZE = 40
local SLOT_GAP = 4
local GRID_WIDTH = COLUMNS * SLOT_SIZE + (COLUMNS - 1) * SLOT_GAP
local GRID_X = math.floor((CONTENT_WIDTH - GRID_WIDTH) / 2)

local MUTED = 0xA99F8AFF
local ERROR = Theme.ERROR_TEXT

-- Create the tag icon picker
function SpritePicker.new(parent, options)
    local self = setmetatable({
        bankItems = options.bankItems,
        onSelect = options.onSelect,
        hitTargets = {},
        tooltips = {},
    }, SpritePicker)

    self.window = prettyui.Window.new(parent, {
        title = "Choose Tag Sprite",
        x = -math.floor(WIDTH / 2),
        y = -math.floor(HEIGHT / 2),
        xAnchor = 0.5,
        yAnchor = 0.5,
        width = WIDTH,
        height = HEIGHT,
        minWidth = WIDTH,
        maxWidth = WIDTH,
        minHeight = HEIGHT,
        maxHeight = HEIGHT,
        scrollable = false,
    })

    local content = self.window.content
    self.field = prettyui.TextField.new(content, {
        x = MARGIN,
        y = 10,
        width = FIELD_WIDTH,
        height = 30,
        maxLength = 80,
        placeholder = "Search item names...",
        onSubmit = function(_, value) self:RunSearch(value) end,
    })
    -- Search using the text currently entered
    self.button = prettyui.SimpleButton.new(content, "Search", function()
        self:RunSearch(self.field:GetText())
    end, {
        x = MARGIN + FIELD_WIDTH + CONTROL_GAP,
        y = 13,
        width = BUTTON_WIDTH,
        height = 24,
    })
    self.status = prettyui.Text.new(content, {
        text = Catalog.IsFull() and "Search and click an item to use its runtime sprite."
            or Catalog.LIMITED_HINT,
        x = MARGIN,
        y = 41,
        width = CONTROL_WIDTH,
        height = 26,
        colour = MUTED,
        font = id.Font.MUSEO_SANS_11PT_REGULAR,
        maxLines = 2,
        alignHorizontal = ui.AlignMode.CENTRE,
    })
    self.grid = prettyui.ItemGrid.new(content, {}, {
        x = GRID_X,
        y = 68,
        columns = COLUMNS,
        rows = ROWS,
        slotGap = SLOT_GAP,
        itemInset = 4,
        dragDrop = false,
    })
    return self
end

-- Show a status message in the picker
function SpritePicker:SetStatus(message, colour)
    if self.status == nil then return end
    self.status.content = tostring(message or "")
    self.status.rgba = colour or MUTED
end

-- Remove the previous result controls
function SpritePicker:ClearInteractions()
    for _, tooltip in ipairs(self.tooltips) do pcall(function() tooltip:Destroy() end) end
    for _, hit in ipairs(self.hitTargets) do pcall(function() hit:Destroy() end) end
    self.tooltips = {}
    self.hitTargets = {}
end

-- Show result rows, each choosing its item icon
function SpritePicker:ShowResults(results, totalMatches, limited)
    self:ClearInteractions()
    local entries = {}
    local visibleResults = {}
    for _, result in ipairs(results) do
        local object = objectFromID(result.objectId)
        if object ~= nil then
            entries[#entries + 1] = {
                object = object,
                tooltip = nil,
            }
            visibleResults[#visibleResults + 1] = result
        end
        if #entries >= 40 then break end
    end
    self.grid:SetObjects(entries)

    for index, result in ipairs(visibleResults) do
        local slot = self.grid:GetSlot(index)
        if slot ~= nil then
            local hit = ui.Layer.new(slot.root)
            hit:SetSize(SLOT_SIZE, SLOT_SIZE)
            hit.clickthrough = false
            hit:MoveToFront()
            local tooltipText = tostring(result.displayName)
            local tooltip = prettyui.Tooltip.attach(slot.root, self.grid.root, tooltipText)
            -- Show the hovered search item's name
            hit:Subscribe(ui.Hook.ONMOUSEOVER, function()
                tooltip:Show()
                return true
            end)
            -- Hide the name when the pointer leaves
            hit:Subscribe(ui.Hook.ONMOUSELEAVE, function()
                tooltip:Hide()
                return true
            end)
            -- Choose the item icon and close the picker
            hit:Subscribe(ui.Hook.ONCLICK, function()
                if self.onSelect ~= nil then self.onSelect(result) end
                if self.window ~= nil then self.window:Close() end
                return false
            end)
            self.hitTargets[#self.hitTargets + 1] = hit
            self.tooltips[#self.tooltips + 1] = tooltip
        end
    end

    if totalMatches == 0 then
        self:SetStatus(limited and ("No matches. " .. Catalog.LIMITED_HINT) or "No matching display names.", MUTED)
    else
        self:SetStatus(limited and Catalog.LIMITED_HINT or "")
    end
end

-- Search items and refresh the choices
function SpritePicker:RunSearch(value)
    local query = trim(value)
    if query == "" then
        self:ClearInteractions()
        self.grid:SetObjects({})
        self:SetStatus("Enter an item display name.", ERROR)
        return
    end
    self:SetStatus("Searching...", MUTED)
    local ok, results, totalMatches, limited = pcall(Catalog.Find, query, 40, self.bankItems())
    if not ok then
        self:ClearInteractions()
        self.grid:SetObjects({})
        self:SetStatus("Items could not be searched.", ERROR)
        debugLog("Bank Tags item search failed: ", results)
        return
    end
    self:ShowResults(results, totalMatches, limited)
end

-- Show the picker window
function SpritePicker:Show()
    self.window:Show()
end

-- Destroy the result controls and picker window
function SpritePicker:Destroy()
    self:ClearInteractions()
    if self.grid ~= nil then self.grid:Destroy() end
    if self.button ~= nil then self.button:Destroy() end
    if self.field ~= nil then self.field:Destroy() end
    if self.status ~= nil then self.status:Destroy() end
    if self.window ~= nil then self.window:Destroy() end
    self.grid = nil
    self.button = nil
    self.field = nil
    self.status = nil
    self.window = nil
    self.onSelect = nil
    self.bankItems = nil
end

return SpritePicker
