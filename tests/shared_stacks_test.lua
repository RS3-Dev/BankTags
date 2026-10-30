package.path = "./?.lua;./?/init.lua;" .. package.path

-- A tag lists one stackable item in several sections over Bank Core's shared stack:
-- every picture shows the bank's one stack and reaches it, and Remove from takes out
-- only the placement that was clicked
-- FAKE HOST: stand-in loader, components, and menus, not the game client

local Harness = require("tools/test_support/tags_harness")
local h = Harness.new("shared_stacks")
local host = h.bankHost
local VIAL = 227
local POTIONS = { 2436, 2440, 2442, 3040, 2444, 55316 }
local SECTIONS = { "Super Attack", "Super Strength", "Super Defense", "Super Magic",
    "Super Range", "Super Necromancy" }
local specs = {}
for index, potion in ipairs(POTIONS) do specs[index] = { potion, index, SECTIONS[index] } end
specs[#specs + 1] = { VIAL, 9000, "Vial of water" }
host:SetItems(specs)
-- A vial of water stacks in the bank: ObjStackType SOMETIMES
host.stackTypes = { [VIAL] = 0 }
host.itemLayer.interfaceID = 517
-- Tall enough to show all six sections at once
host.viewport:SetSize(448, 520)
h:LoadCore()
h:LoadTags()
local app = h:App()
local _, layout = h:OpenBank()
h:Tick(2)

-- Save the super sets tag: each section lists its potion and a vial of water
local TagLayouts = h:TagsModule("banktags/tags/tag_layouts")
assert(app.store:CreateTag("super sets"))
local rows = {}
for index, label in ipairs(SECTIONS) do
    rows[#rows + 1] = { kind = "label", text = label }
    rows[#rows + 1] = { kind = "row", slots = { TagLayouts.Item(POTIONS[index]), TagLayouts.Item(VIAL) } }
end
app.store.data.tags["super sets"].rows = rows
assert(app.store:Save())
app:Changed()
assert(app:ShowTag("super sets"))
h:Tick(2)

-- Hover each vial slot and describe its quantity, the stack beneath, and its menu
local REMOVE = "Remove from <col=f2c66d>Super Sets</col>"
local function vialSlots()
    local parts = {}
    for _, slot in ipairs(layout.pageState.view.slots) do
        if slot.objectID == VIAL then
            h:PointAtSlot(slot.position)
            local held = layout.itemHover.hoveredBankStack
            local sprite = nil
            for index, entry in ipairs(layout.itemHover.drawnPageItems) do
                if entry.layoutKey == slot.layoutKey then sprite = layout.pageDisplay.sprites[index] end
            end
            local menu = h:SlotMenu()
            local item = app.ext:GetMenuItem(menu)
            assert(held ~= nil and held.item == host:Item(VIAL), "slot " .. slot.position)
            assert(item.objectID == VIAL and item.interactive and Harness.Has(menu, REMOVE))
            parts[#parts + 1] = item.slot .. "=" .. sprite.associatedObjectQuantity
        end
    end
    return table.concat(parts, " ")
end
assert(vialSlots() == "2=9000 4=9000 6=9000 8=9000 10=9000 12=9000", vialSlots())

-- Removing the third section's vial through its own menu leaves the other five usable
h:PointAtSlot(6)
Harness.Choose(h:SlotMenu(), REMOVE)
h:Tick(2)
local saved = table.concat({ POTIONS[1], VIAL, POTIONS[2], VIAL, POTIONS[3], POTIONS[4], VIAL,
    POTIONS[5], VIAL, POTIONS[6], VIAL }, " ")
assert(h:Saved("super sets") == saved, h:Saved("super sets"))
assert(vialSlots() == "2=9000 4=9000 7=9000 9=9000 11=9000", vialSlots())

-- Removing the last vial takes out that placement only
h:PointAtSlot(11)
Harness.Choose(h:SlotMenu(), REMOVE)
h:Tick(2)
saved = table.concat({ POTIONS[1], VIAL, POTIONS[2], VIAL, POTIONS[3], POTIONS[4], VIAL,
    POTIONS[5], VIAL, POTIONS[6] }, " ")
assert(h:Saved("super sets") == saved, h:Saved("super sets"))
assert(vialSlots() == "2=9000 4=9000 7=9000 9=9000", vialSlots())

-- Bank Tags still reads one vial stack from the bank
local vials = 0
for _, item in ipairs(app.ext:GetBankItems()) do
    if item.objectID == VIAL then vials = vials + 1 end
end
assert(vials == 1)
assert(app.ext:Close())
print("shared_stacks_test: ok")
