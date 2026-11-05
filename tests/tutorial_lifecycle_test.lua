package.path = "./?.lua;./?/init.lua;" .. package.path

-- Exercise the title-bar X and recovery after interrupted tutorial teardown
-- FAKE HOST: model PrettyUI's onClose-before-destroy order and strict window lifetime
local Harness = require("tools/test_support/tags_harness")
local h = Harness.new("tutorial_lifecycle")
h.bankHost:SetItems({ { 385, 20, "Shark" } })
local newWindow = prettyui.Window.new
prettyui.Window.new = function(parent, options)
    local window = newWindow(parent, options)
    local destroy = window.Destroy
    window.destroyCalls = 0
    function window:Destroy()
        assert(self.root ~= nil, "the window must be destroyed only once")
        self.destroyCalls = self.destroyCalls + 1
        destroy(self)
        self.root, self.content = nil, nil
    end
    window.closeButton = ui.Sprite.new(window.root)
    window.closeButton:Subscribe(ui.Hook.ONCLICK, function()
        window:Close()
        return false
    end)
    return window
end
h:LoadCore()
h:LoadTags()
local app = h:App()
assert(app.store:CreateTag("melee"))
h:OpenBank()
h:Tick(2)
local tour = app.tutorial

-- X finishes PrettyUI's Close method; the callback must not destroy its window first
tour:Start()
local window, frame, owner = tour.window, tour.window.root, tour.root
window.closeButton.hooks.click()
assert(not tour.active and tour.window == nil and frame.destroyed)
assert(window.destroyCalls == 1)
assert(owner.hidden, "the highlight and arrow disappear with the window")
assert(h.bankHost.callbacks.banktags_tutorial == nil)

-- Starting again releases the hidden owner left by the X callback
tour:Start()
assert(owner.destroyed)
owner, frame = tour.root, tour.window.root
tour.buttons[1].Destroy = function() error("Attempting to use a dead UI component") end
tour:Stop(false)
assert(owner.destroyed and frame.destroyed and tour.root == nil)
tour:Stop(false)

-- An earlier failed Stop may already have marked the guide inactive
tour:Start()
owner, frame = tour.root, tour.window.root
tour.active = false
tour:Stop(false)
assert(owner.destroyed and frame.destroyed and tour.window == nil)

-- A normal reload releases an open guide and all of its overlays
tour:Start()
owner = tour.root
h.host:Reload("banktags", { shutdown = true })
assert(owner.destroyed and not tour.active)
h:Tick(2)
app, tour = h:App(), h:App().tutorial

-- The retained native owner also recovers UI if the old session reference was lost
tour:Start()
owner = tour.root
rawset(h.tags.env._G, "__banktags_session", nil)
h.host:Reload("banktags")
h:Tick(2)
assert(owner.destroyed and h.bankHost.callbacks.banktags_tutorial == nil)
assert(not h:App().tutorial.active)

print("tutorial_lifecycle_test: ok")
