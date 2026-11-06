-- tooltip (types/view.lua MM.CmdTooltip): GameTooltip's own content for a game thing, on UI's owner.
-- member: a group member's tooltip, its name in its class's colour, level and class, dead
-- (Layers.lua:677-688); button: a Minimap button's own (game/MinimapButtons.lua Game.ButtonTooltip: the gear's Minimap
-- buttons rows); owner false hides it again.

local _, ns = ...
local Game = ns.Game

local DEAD = "|cff808080Dead|r"

local shown -- the owner a member's tooltip was shown on

local function Unit(id)
	local raid = IsInRaid()
	for i = 1, GetNumGroupMembers() do
		local unit = (raid and "raid" or "party") .. i
		if UnitGUID(unit) == id then return unit end
	end
end

local function Member(owner, anchor, id)
	local unit = Unit(id)
	if not unit then return end
	Game.Tooltip(owner, anchor or "ANCHOR_CURSOR")
	shown = owner
	local className, class = UnitClass(unit)
	local c, level = RAID_CLASS_COLORS[class], UnitLevel(unit)
	GameTooltip:AddLine(UnitName(unit), c.r, c.g, c.b)
	if level > 0 then GameTooltip:AddLine(LEVEL .. " " .. level .. " " .. className, 1, 1, 1) end -- (-1: too high to tell)
	if UnitIsDeadOrGhost(unit) then GameTooltip:AddLine(DEAD) end
	GameTooltip:Show()
end

Game.Handle("tooltip", function(c)
	if c.owner == false then
		if shown then Game.HideTooltip(shown) end
		Game.ButtonTooltip(false)
	elseif c.member then
		Member(c.owner, c.anchor, c.member)
	elseif c.button then
		Game.ButtonTooltip(c.owner, c.anchor, c.button)
	end
end)
