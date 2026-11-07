-- GameTooltip's one hide path for Game's tips (spike-bugs G7: several owners showed it, none hid it
-- right, so tips lingered and fought). Game shows it with Game.Tooltip(owner, anchor) and hides it
-- with Game.HideTooltip(owner): only while that owner still has it (another may have taken it
-- since). And each frame, after the other apply steps, one of Game's whose owner can't be seen any
-- more goes: the takeover taking the Minimap and what hangs on it (the button) away. Anyone else's
-- is theirs, hidden owner or not (Blizzard's and other addons' anchors often are; UI hides its own
-- with the window: ui/Window.lua).

local _, ns = ...
local Game, Runtime = ns.Game, ns.Runtime

local GREY = 0x9d / 255 -- the map's tips' one grey for facts (ui/Tip.lua's DIM)

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

-- A fact under a Game tip's title, in the map's tips' look (ui/Tip.lua's Fact): small, grey; its font back when the
-- tooltip hides or clears.
local small = {} -- fs -> its font before
local Restore = Runtime.Wrap("game: tip fonts", function()
	for fs, font in pairs(small) do
		fs:SetFontObject(font)
		small[fs] = nil
	end
end)
GameTooltip:HookScript("OnHide", Restore)
GameTooltip:HookScript("OnTooltipCleared", Restore)
function Game.TooltipFact(text)
	GameTooltip:AddLine(text, GREY, GREY, GREY)
	local name = GameTooltip:GetName() .. "TextLeft" .. GameTooltip:NumLines()
	for _, r in ipairs({ GameTooltip:GetRegions() }) do
		if r:GetName() == name then
			if not small[r] then small[r] = r:GetFontObject() end
			r:SetFontObject(GameTooltipTextSmall)
		end
	end
end
