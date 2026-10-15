-- G7: tooltips, Game's half (game/Tooltip.lua: GameTooltip's one hide path). MOVED: owners still
-- share GameTooltip, but Game hides its own only through Game.HideTooltip(owner), while that owner
-- has it, and each frame when its owner can't be seen: a tip neither lingers on a hidden owner nor
-- is taken from another. Here the minimap button's tip (shown on hover, built once a hover; leave
-- or a drag hides it, but not another owner's), another addon's on a hidden anchor (kept), a tip on
-- a widget in the map window (the window hidden: UI's own goes with it) and the button's (the
-- takeover taking the button away: gone). UI's tiny tips (hover 0.35 s, leave, a menu, 2.5 s):
-- test_chrome.py; quest areas' (one build a hover) come with M2.4.
local T = ...
local sim, ns = T.Boot()
sim.Run(1)
local button
for _, f in ipairs(sim.Frames()) do
	for _, r in ipairs({ f:GetRegions() }) do
		if r.GetTexture and r:GetTexture() == [[Interface\Icons\INV_Misc_Map_01]] then button = f end
	end
end
local tip, built = GameTooltip, 0
tip.SetOwner = function(self, ...) built = built + 1; return getmetatable(self).__index.SetOwner(self, ...) end

sim.MoveCursorTo(button)
sim.FireScript(button, "OnEnter", false)
sim.Run(0.5)
assert(tip:IsShown() and tip:IsOwned(button) and built == 1, "hovered: its tip, built once")
sim.FireScript(button, "OnLeave", false)
assert(not tip:IsShown(), "left: gone")

sim.FireScript(button, "OnEnter", false) -- then another owner takes it (Blizzard's Minimap hover)
tip:SetOwner(UIParent, "ANCHOR_CURSOR")
tip:Show()
sim.FireScript(button, "OnLeave", false)
sim.Step()
assert(tip:IsShown() and tip:IsOwned(UIParent), "another owner's: kept")
tip:Hide()

sim.FireScript(button, "OnEnter", false)
sim.Drag(button, 0, 30)
assert(not tip:IsShown(), "dragged: gone")

local anchor = CreateFrame("Frame", nil, UIParent) -- another addon's tip on its hidden anchor
anchor:Hide()
tip:SetOwner(anchor, "ANCHOR_NONE")
tip:SetPoint("CENTER")
tip:Show()
sim.Step()
assert(tip:IsShown() and tip:IsOwned(anchor), "another's on a hidden owner: kept")
tip:Hide()

sim.Slash("/mma map") -- a widget in the window (a pin, UI's) owns it; the window hides
sim.Run(3)
local pin = CreateFrame("Frame", nil, ns.UI.Window.view)
pin:SetSize(10, 10)
pin:SetPoint("CENTER")
tip:SetOwner(pin, "ANCHOR_RIGHT")
tip:AddLine("pin")
tip:Show()
sim.Step()
assert(tip:IsShown(), "kept while its owner shows")
sim.Slash("/mma map")
sim.Step()
assert(not tip:IsShown(), "window hidden: gone")

sim.Run(0.2) -- the button's tip, then the map shown: the takeover takes the button, and its tip
sim.FireScript(button, "OnEnter", false)
sim.Slash("/mma map")
sim.Step()
assert(not button:IsVisible() and not tip:IsShown(), "taken away: gone")
T.Print("G7: %d SetOwner calls over the scenario", built)
local errs = T.Errors(sim, ns)
assert(#errs == 0, table.concat(errs, "\n"))
