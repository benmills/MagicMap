-- GameTooltip's one hide path for Game's tips (spike-bugs G7: several owners showed it, none hid it
-- right, so tips lingered and fought). Game shows it with Game.Tooltip(owner, anchor) and hides it
-- with Game.HideTooltip(owner): only while that owner still has it (another may have taken it
-- since). And each frame, after the other apply steps, one of Game's whose owner can't be seen any
-- more goes: the takeover taking the Minimap and what hangs on it (the button) away. Anyone else's
-- is theirs, hidden owner or not (Blizzard's and other addons' anchors often are; UI hides its own
-- with the window: ui/Window.lua).

local _, ns = ...
local Game = ns.Game

local ours = setmetatable({}, { __mode = "k" }) -- the owners Game showed it on

function Game.Tooltip(owner, anchor)
	ours[owner] = true
	GameTooltip:SetOwner(owner, anchor)
end

function Game.HideTooltip(owner)
	if GameTooltip:IsOwned(owner) then GameTooltip:Hide() end
end

Game.Apply("tooltip", function()
	if not GameTooltip:IsShown() then return end
	local owner = GameTooltip:GetOwner()
	if owner and ours[owner] and not owner:IsVisible() then GameTooltip:Hide() end
end)
