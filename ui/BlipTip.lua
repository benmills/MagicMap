-- Blizzard's blips' tooltips, ours (the overlay: game/Minimap.lua). While a blip is under the cursor, the names Game
-- read there (obs.minimap.names: stacked blips each) in our pins' look (ui/Pins.lua's Fill): each a title, a gathering
-- node's (Atlas.NodeKind: a herb or an ore, by name) led by the icon of what it gives (Atlas.NodeIcon) and in the
-- colour of your skill against its (Model.skills, Atlas.NodeSkill: the client's skill-up colours, red you can't gather
-- it yet, then orange, yellow, green, grey when it no longer raises your skill; white where either isn't known), its
-- profession under it. At the cursor, as Blizzard's; rebuilt only when the names (a new table) or your skills change.
-- None while a popup stands (as the pins' tooltips: ui/Pins.lua).

local _, ns = ...
local UI, Model, Runtime, Atlas = ns.UI, ns.Model, ns.Runtime, ns.Atlas
local Tip, Window = UI.Tip, UI.Window

local MARK = 18 -- px: the item icon before a node's name (its border cropped, as the bags show it)
local LINE = { herb = "Herbalism", ore = "Mining" }
local WHITE = { 1, 1, 1 }
local RED, ORANGE, YELLOW = { 1, 0.1, 0.1 }, { 1, 0.5, 0.25 }, { 1, 1, 0 }
local GREEN, GREY = { 0.25, 0.75, 0.25 }, { 0.5, 0.5, 0.5 }
local STEPS = { { 0, RED }, { 25, ORANGE }, { 50, YELLOW }, { 100, GREEN } } -- skill under the node's + n: this colour

local function Difficulty(have, need)
	for _, s in ipairs(STEPS) do
		if have < need + s[1] then return s[2] end
	end
	return GREY
end

local function Fill(tip, name)
	local kind = Atlas.NodeKind(name)
	local icon, need, skills = kind and Atlas.NodeIcon(name), kind and Atlas.NodeSkill(name), Model.skills
	local c = need and skills and Difficulty(skills[kind], need) or WHITE
	local mark = icon and ("|T" .. icon .. ":" .. MARK .. ":" .. MARK .. ":0:0:64:64:5:59:5:59|t  ") or ""
	tip:AddLine(mark .. name, c[1], c[2], c[3])
	Tip.Title(Tip.Last(tip))
	if kind then Tip.Fact(tip, LINE[kind]) end
end

local shown, skills -- the names and skills drawn (nil: none of ours up)
Runtime.Step("ui", "map: blip tooltip", function()
	local mm = Model.minimap
	local names = mm and mm.names
	if names and UI.Popup.IsOpen() then names = nil end
	if names == shown and Model.skills == skills then return end
	shown, skills = names, Model.skills
	if not names then
		if GameTooltip:IsOwned(Window.view) then GameTooltip:Hide() end
		return
	end
	GameTooltip:SetOwner(Window.view, "ANCHOR_CURSOR")
	for _, name in ipairs(names) do Fill(GameTooltip, name) end
	GameTooltip:Show()
end, { shownOnly = Window.frame })
