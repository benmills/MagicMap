-- GameTooltip's one hide path (spike-bugs G7: several owners showed it, none hid it right, so
-- tips lingered and fought). Whoever shows it on an owner hides it with Game.HideTooltip(owner):
-- only while that owner still has it (another may have taken it since). And each frame, after
-- the other apply steps, one whose owner can't be seen any more goes: the window hidden, the
-- takeover taking the Minimap and what hangs on it (the button) away.

local _, ns = ...
local Game = ns.Game

function Game.HideTooltip(owner)
	if GameTooltip:IsOwned(owner) then GameTooltip:Hide() end
end

Game.Apply("tooltip", function()
	if not GameTooltip:IsShown() then return end
	local owner = GameTooltip:GetOwner()
	if owner and not owner:IsVisible() then GameTooltip:Hide() end
end)
