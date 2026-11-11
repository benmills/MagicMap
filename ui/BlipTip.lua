-- Blizzard's blips' tooltips, ours (the overlay: game/Minimap.lua). While a blip is under the cursor, the names Game
-- read there (obs.minimap.names: stacked blips each) in our pins' look (ui/Pins.lua's Fill): each a title, then what it
-- is in a muted gold (Tip.Sub), then its quests.
--   A gathering node's (Atlas.NodeKind: a herb or an ore, by name): led by the icon of what it gives (Atlas.NodeIcon), in
--     the colour of your skill against it (Model.skills, Atlas.NodeSkill: the client's skill-up colours, red you can't
--     gather it yet, then orange, yellow, green, grey when it no longer raises your skill; white where either isn't
--     known), the skill it needs in a pill of that colour beside it (Tip.Pilled, as a quest's level); its profession
--     under it.
--   An npc's (Atlas: the one of that name, exactly, that gives or takes a quest of yours, else one with a title): white,
--     its title (subName: "General Goods") under it, then the quests it has for you, each in its difficulty's colour
--     (Model.QuestColor) after its mark: "!" one to pick up (Known("offers")), "?" one of yours done to turn in.
--   Any other: its name alone.
-- At the cursor, as Blizzard's; rebuilt only when the names (a new table), your skills or the quests change. None
-- while a popup stands (as the pins' tooltips: ui/Pins.lua).

local _, ns = ...
local UI, Model, Runtime, Atlas = ns.UI, ns.Model, ns.Runtime, ns.Atlas
local Tip, Window = UI.Tip, UI.Window

local MARK = 18 -- px: the item icon before a node's name (its border cropped, as the bags show it)
local QMARK = 14 -- px: a quest's "!" or "?"
local ARROW = 11 -- px: a blip above or below you, its arrow over the icon's bottom right (after the name if none)
local LINE = { herb = "Herbalism", ore = "Mining" }
local WHITE = { 1, 1, 1 }
local RED, ORANGE, YELLOW = { 1, 0.1, 0.1 }, { 1, 0.5, 0.25 }, { 1, 1, 0 }
local GREEN, GREY = { 0.25, 0.75, 0.25 }, { 0.5, 0.5, 0.5 }
local STEPS = { { 0, RED }, { 25, ORANGE }, { 50, YELLOW }, { 100, GREEN } } -- skill under the node's + n: this colour
local OFFER, TURN_IN = "questnormal", "questturnin" -- the Minimap's own "!" and "?"
local NONE = {}

local function Difficulty(have, need)
	for _, s in ipairs(STEPS) do
		if have < need + s[1] then return s[2] end
	end
	return GREY
end

-- The arrow (mark: a blip above or below you) on the title just added: over its icon's bottom right, else after it.
local function Arrow(tip, mark, iconed)
	if mark == "" then return end
	local fs = Tip.Region(tip, "TextLeft" .. tip:NumLines())
	if iconed and fs and Tip.Badge(tip, mark, fs, MARK - ARROW / 2 + 1, -MARK / 2 + ARROW / 2 - 1, ARROW) then return end
	if fs then fs:SetText(fs:GetText() .. " " .. mark) end
end

local function Node(tip, name, kind, arrow)
	local icon, need, skills = Atlas.NodeIcon(name), Atlas.NodeSkill(name), Model.skills
	local c = need and skills and Difficulty(skills[kind], need) or WHITE
	local mark = icon and ("|T" .. icon .. ":" .. MARK .. ":" .. MARK .. ":0:0:64:64:5:59:5:59|t  ") or ""
	if need then
		Tip.Pilled(tip, mark .. name, need, c)
	else
		tip:AddLine(mark .. name, c[1], c[2], c[3])
		Tip.Title(Tip.Last(tip))
	end
	Arrow(tip, arrow, icon ~= nil)
	Tip.Sub(tip, LINE[kind])
end

-- The quests to pick up (by id: its name) and of yours done (by id: true), from Known.
local offered, done = {}, {}
local function Quests()
	offered, done = {}, {}
	for _, e in ipairs(Model.Known("offers")) do offered[e.quest] = e.name end
	for _, e in ipairs(Model.Known("quests")) do
		if e.complete then done[e.quest] = e.name end
	end
end

local function Ours(npc)
	for _, id in ipairs(npc.questStarts or NONE) do
		if offered[id] then return true end
	end
	for _, id in ipairs(npc.questEnds or NONE) do
		if done[id] then return true end
	end
	return false
end

-- The npcs of exactly this name (Atlas.Find scans every name: once a name).
local named = {}
local function Npcs(name)
	local list = named[name]
	if not list then
		list = {}
		for _, id in ipairs(Atlas.Find("npc", name)) do
			local npc = Atlas.Npc(id)
			if not (npc and npc.name == name) then break end -- exact matches come first
			list[#list + 1] = npc
		end
		named[name] = list
	end
	return list
end

local function Pick(name)
	local titled
	for _, npc in ipairs(Npcs(name)) do
		if Ours(npc) then return npc end
		titled = titled or npc.subName and npc.subName ~= "" and npc
	end
	return titled
end

local function Line(tip, id, title, atlas)
	local q = Atlas.Quest(id)
	local c = q and q.level and q.level > 0 and Model.QuestColor(q.level) or WHITE
	tip:AddLine("|A:" .. atlas .. ":" .. QMARK .. ":" .. QMARK .. "|a " .. title, c[1], c[2], c[3])
end

local function Npc(tip, name, npc, arrow)
	tip:AddLine(name, 1, 1, 1)
	Tip.Title(Tip.Last(tip))
	Arrow(tip, arrow, false)
	if npc.subName and npc.subName ~= "" then Tip.Sub(tip, npc.subName) end
	for _, id in ipairs(npc.questEnds or NONE) do
		if done[id] then Line(tip, id, done[id], TURN_IN) end
	end
	for _, id in ipairs(npc.questStarts or NONE) do
		if offered[id] then Line(tip, id, offered[id], OFFER) end
	end
end

local function Fill(tip, name, arrow)
	local kind = Atlas.NodeKind(name)
	if kind then return Node(tip, name, kind, arrow) end
	local npc = Pick(name)
	if npc then return Npc(tip, name, npc, arrow) end
	tip:AddLine(name, 1, 1, 1)
	Tip.Title(Tip.Last(tip))
	Arrow(tip, arrow, false)
end

local shown, skills, revs -- the names, skills and quests drawn (nil: none of ours up)
Runtime.Step("ui", "map: blip tooltip", function()
	local mm = Model.minimap
	local names = mm and mm.names
	if names and UI.Popup.IsOpen() then names = nil end
	local o, q = select(2, Model.Known("offers")), select(2, Model.Known("quests"))
	local rev = o * 1e6 + q
	if names == shown and Model.skills == skills and rev == revs then return end
	shown, skills, revs = names, Model.skills, rev
	if not names then
		if GameTooltip:IsOwned(Window.view) then GameTooltip:Hide() end
		return
	end
	Quests()
	GameTooltip:SetOwner(Window.view, "ANCHOR_CURSOR")
	local marks = mm.marks or NONE
	for i, name in ipairs(names) do Fill(GameTooltip, name, marks[i] or "") end
	GameTooltip:Show()
end, { shownOnly = Window.frame })
