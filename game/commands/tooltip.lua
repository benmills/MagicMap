-- tooltip (types/view.lua MM.CmdTooltip): GameTooltip's own content for a game thing, on UI's owner.
-- member: a group member's tooltip, its name in its class's colour, level and class, dead
-- (Layers.lua:677-688); owner false hides it again. npc, with line: on that line of the tooltip
-- the owner has (UI's: a quest's mobs), the NPC's portrait over a dark disc in place of the
-- line's icon, once Game has met it (QuestInfo.lua:270-296); else the line keeps UI's icon.
-- The game draws a portrait only from a unit that's there: each creature's is drawn as it's met
-- (your mouseover, target, nameplates), at most 300 a session (QuestInfo.lua:132-166), and taken
-- back off the tooltip when it hides or clears.

local _, ns = ...
local Game, Runtime = ns.Game, ns.Runtime

local PORTRAIT, MAX = 14, 300 -- px; portraits a session (QuestInfo.lua:137-138)
local CIRCLE = "Interface\\CharacterFrame\\TempPortraitAlphaMask" -- UI.lua:6
local DISC = string.format("|T%s:%d:%d:0:0:64:64:0:64:0:64:0:0:0|t", CIRCLE, PORTRAIT, PORTRAIT) -- QuestInfo.lua:181
local DEAD = "|cff808080Dead|r"

local holder = CreateFrame("Frame")
holder:Hide()
local probe = holder:CreateFontString() -- measures a line's text before its icon
local portraits, count = {}, 0 -- NPC ID -> texture
local lent = {} -- portraits on the tooltip now
local shown -- the owner a member's tooltip was shown on

local function NpcID(unit)
	local guid = UnitGUID(unit)
	if not guid or issecretvalue(guid) then return nil end
	local kind, _, _, _, _, id = strsplit("-", guid)
	return (kind == "Creature" or kind == "Vehicle") and tonumber(id) or nil
end

local function Capture(unit)
	local id = NpcID(unit)
	if not id or portraits[id] or count >= MAX then return end
	local tex = holder:CreateTexture(nil, "OVERLAY")
	SetPortraitTexture(tex, unit)
	tex:SetSize(PORTRAIT, PORTRAIT)
	tex:Hide() -- shown: on the tooltip
	portraits[id], count = tex, count + 1
end
Runtime.On("UPDATE_MOUSEOVER_UNIT", "game.portraits", function() Capture("mouseover") end)
Runtime.On("PLAYER_TARGET_CHANGED", "game.portraits", function() Capture("target") end)
Runtime.On("NAME_PLATE_UNIT_ADDED", "game.portraits", function(_, unit) Capture(unit) end)

local function Return()
	for i = #lent, 1, -1 do
		lent[i]:Hide()
		lent[i] = nil
	end
end
GameTooltip:HookScript("OnHide", Return)
GameTooltip:HookScript("OnTooltipCleared", Return)

local function Portrait(owner, npc, line)
	local tex = portraits[npc]
	if not tex or tex:IsShown() or not GameTooltip:IsOwned(owner) then return end
	local fs = GameTooltip:GetLeftLine(line)
	local text = fs:GetText()
	local at = text:find("|T", 1, true)
	fs:SetText(text:sub(1, at - 1) .. DISC .. text:sub(text:find("|t", at, true) + 2))
	probe:SetFont(fs:GetFont())
	probe:SetText(text:sub(1, at - 1))
	tex:SetParent(GameTooltip)
	tex:SetDrawLayer("OVERLAY", 7)
	tex:ClearAllPoints()
	tex:SetPoint("LEFT", fs, "LEFT", probe:GetStringWidth(), 0)
	tex:Show()
	lent[#lent + 1] = tex
end

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
	elseif c.member then
		Member(c.owner, c.anchor, c.member)
	elseif c.npc then
		Portrait(c.owner, c.npc, c.line)
	end
end)
