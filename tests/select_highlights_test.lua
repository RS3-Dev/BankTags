package.path = "./?.lua;./?/init.lua;" .. package.path

-- Select mode owns native sprite highlights, including rebuilt and repeated stacks
-- FAKE HOST: the component properties are recorded, not drawn by the game client
local Harness = require("tools/test_support/tags_harness")
local h = Harness.new("select_highlights")
local host = h.bankHost
host:SetItems({ { 4151, 0, "Abyssal whip" }, { 4151, 1 }, { 4151, 1 }, { 385, 20, "Shark" } })
host.itemLayer.interfaceID = 517

local function ownLooks()
    for index, item in ipairs(host.items) do
        item.outlineWidth, item.shadowRGBA = index, 0x11111100 + index
    end
end
ownLooks()
h:LoadCore()
h:LoadTags()
local app = h:App()
local _, layout = h:OpenBank()
h:Tick(2)
assert(app.store:CreateTag("melee"))
assert(app.store:CreateTag("food"))
assert(app.store:AddTag("melee", 4151))
assert(app.store:AddTag("food", 385))
app:Changed()

local GOLD = 0xF2C66DFF
local function highlighted(index) return host.items[index].shadowRGBA == GOLD end
local function restored(items)
    for index, item in ipairs(items) do
        assert(item.outlineWidth == index and item.shadowRGBA == 0x11111100 + index,
            "select mode must restore each sprite's original look")
    end
end

-- Existing tag members are outlined, stocked copies before an earlier placeholder
assert(app.select:Start("melee"))
assert(not highlighted(1) and highlighted(2) and not highlighted(3) and not highlighted(4))
assert(host.items[2].outlineWidth == 2)
app.select:Picked(app.select.session, 4151)
assert(highlighted(2) and highlighted(3) and not highlighted(1))
assert(host.items[3].outlineWidth == 3, "a stronger native outline must be kept")
app.select:Picked(app.select.session, 4151)
assert(highlighted(1) and highlighted(2) and highlighted(3))

-- A removal refreshes membership immediately; renaming keeps the same session
assert(app:RemoveFromTag("melee", app.store:GetTaggedItems("melee")[1].layoutKey))
assert(not highlighted(1) and highlighted(2) and highlighted(3))
assert(app.store:UpdateTag("melee", "weapons"))
app:Renamed("melee", "weapons")
assert(app.select:Tag() == "weapons" and highlighted(2) and highlighted(3))
assert(app.select:Start("food"))
assert(not highlighted(1) and not highlighted(2) and not highlighted(3) and highlighted(4))

-- A native wrapper rebuild is noticed without any Bank Core inventory callback
local oldItems = host.items
host:Rebuild()
ownLooks()
h:Tick(10)
restored(oldItems)
assert(highlighted(4) and not highlighted(2))
assert(app.select:Stop())
restored(host.items)

-- A refused page leaves select mode and its outlines active
assert(app.select:Start("weapons"))
layout:SetNativeViewAll(false)
assert(not app:ShowTag("weapons"))
assert(app.select:Tag() == "weapons" and highlighted(2))
layout:SetNativeViewAll(true)

-- Opening a tag restores native looks before Core copies them into its page
assert(app:ShowTag("weapons"))
assert(app.select:Tag() == nil)
restored(host.items)
assert(#layout.pageDisplay.sprites > 0)
for _, sprite in ipairs(layout.pageDisplay.sprites) do
    assert(sprite.shadowRGBA ~= GOLD, "select highlights must not leak into page sprites")
end
assert(app.ext:Close())

-- Deleting the selected tag, closing the bank, and unloading release the visuals
assert(app.select:Start("food"))
assert(app.store:DeleteTag("food"))
app:Changed()
assert(app.select:Tag() == nil)
restored(host.items)
assert(app.select:Start("weapons"))
h:CloseBank()
restored(host.items)
assert(not app.nativeItems.running and app.select:Tag() == nil)
h:OpenBank()
h:Tick(2)
assert(app.nativeItems.running)
assert(app.select:Start("weapons"))
h.host:Unload("banktags")
restored(host.items)
assert(not app.nativeItems.running)

print("select_highlights_test: ok")
