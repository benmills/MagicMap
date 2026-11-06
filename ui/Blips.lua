-- Minimap blips on the map: Model.Known("blips") (sensed now), and Known("services") (Atlas's town
-- services: asking starts their gathering) and Known("remembered") (seen before) from zoom 60
-- (Blips.lua:625-650; laid out from a drift below it but zooming out, Engine.From, shown from it as the
-- zoom moves: Engine.At's minimum zoom) as the spike's pins (Blips.lua:423-437,
-- 641-661), on the pin store (ui/Pins.lua): an icon, the game's tracking texture or an atlas (a gathering
-- node's, Blizzard's HD one; else the classic Minimap\Tracking icon; else a dot of its colour, StylePin's
-- form (d); a vendor's, its kind's art or a file, the gossip sack: UI.Art.Icon), at 14 px; else a gold dot (d) at 10. A remembered one a sensed one stands for (its
-- key) is drawn once; while the sensor runs, none within its word around you (LIVE_YARDS: only what it sees now, Blips.lua:628-650). Laid out again
-- when either changes, or you cross a walk chunk while sensing. Tooltip: its name, then what it is (a
-- gathering node's profession, Blips.lua:427-429; an NPC's title, :436), and a service's or remembered one's
-- "Not in sight" (Blips.lua:642).
-- A herb or ore pin (a name Atlas knows as one: #21) wears two badges (#18; Settings > Resources > Badges, each shown
-- or not, and their size): at its top left its difficulty, by your skill (Model.skills: Herbalism's or Mining's) against
-- the node's (Atlas.NodeSkill), the game's skill-up colours: red under it (you can't gather it yet), orange under it + 25,
-- yellow under + 50, green under + 100, else grey (classic's gathering thresholds); none for a node whose skill isn't
-- known (Forever's own herbs) or before your skills are; at its bottom left the node's letter (Atlas.NodeLetter: P for
-- Peacebloom, T for Rich Thorium Vein).
-- Their types (Settings > Pins, ui/PinTypes.lua), one a kind of Atlas.BLIP_ART: its services (Services), gathering nodes
-- (Resources) and vendors (Vendors), each its icon's alternatives, Blizzard's (the map's HD art for a tracking texture,
-- the classic tracking texture for a vendor's atlas); a quest giver's "!" and "?" are the quests' (ui/Quests.lua); the
-- gold dot, and a tracking icon of no kind MagicMap knows, Other's. A pin's type is its icon's (TYPE).

local _, ns = ...
local UI, Model = ns.UI, ns.Model

local ICON, DOT = 14, 10 -- px: an icon's; the gold dot's (Blips.lua:436)
local GOLD = { 1, 0.82, 0 } -- Blips.lua:373
-- A gathering node's colour (its dot, when the client lacks its atlas) and its line (Blips.lua:427-429).
local COLOR = { Professions_Tracking_Ore = { 0.8, 0.6, 0.4 }, Professions_Tracking_Herb = { 0.4, 0.9, 0.3 } }
local LINE = { Professions_Tracking_Ore = "Mining", Professions_Tracking_Herb = "Herbalism" }
local AWAY = "|cff808080Not in sight|r" -- Blips.lua:642
local REMOTE_ZOOM = 60 -- px a tile: remembered ones from here (Blips.lua REMOTE_MIN_ZOOM)
local REACH = 220 / ns.Atlas.TILE_YARDS -- tiles: around you, the sensor's word (Blips.lua:480 LIVE_YARDS)
local CHUNKS = ns.Atlas.Walk.CHUNKS

-- The badges (#18): the skill-up colours (the client's QuestDifficultyColors and trade skill colours) by how far your
-- skill is past the node's; what's shown, and their size.
local GATHER = { [ns.Atlas.BlipArt("herb")] = "herb", [ns.Atlas.BlipArt("ore")] = "ore" }
local RED, ORANGE, YELLOW = { 1, 0.1, 0.1 }, { 1, 0.5, 0.25 }, { 1, 1, 0 }
local GREEN, GREY = { 0.25, 0.75, 0.25 }, { 0.5, 0.5, 0.5 }
local STEPS = { { 0, RED }, { 25, ORANGE }, { 50, YELLOW }, { 100, GREEN } } -- skill under the node's + n: this colour
local function Difficulty(have, need)
	for _, s in ipairs(STEPS) do
		if have < need + s[1] then return s[2] end
	end
	return GREY
end
local badges = { difficulty = true, letter = true, size = 1 }
local looks, badgeRev = {}, 0
local function Badges(name)
	return function(v)
		if badges[name] == v then return end
		badges[name], badgeRev = v, badgeRev + 1
		looks = {} -- (each made again with them)
	end
end
UI.Feel.Add("resources", "Badges", {
	{ key = "resources.difficulty", kind = "toggle", label = "Difficulty", default = badges.difficulty,
		apply = Badges("difficulty"), tip = "A dot at a herb's or ore's top left, by your skill against the node's: "
			.. "red you can't gather it yet, then orange, yellow and green as it gets easier, grey when it no longer "
			.. "raises your skill. None on a node whose skill isn't known." },
	{ key = "resources.letter", kind = "toggle", label = "Letter", default = badges.letter, apply = Badges("letter"),
		tip = "The node's first letter at its bottom left: P for Peacebloom, C for Copper Vein, T for any Thorium vein." },
	{ key = "resources.badgeSize", kind = "slider", label = "Badge size", min = 0.6, max = 1.6, step = 0.1, pct = true,
		default = badges.size, apply = Badges("size"), tip = "The size of the dot and the letter." },
})

-- The pin types: a kind's art -> its type (Atlas.BLIP_ART's kind; a quest giver's the quests'); each kind's icons, the
-- first today's.
local FAMILY = { service = "services", gather = "resources", vendor = "vendors" }
local QUEST = { questgiver = "offer", questender = "turnin" } -- (ui/Quests.lua's types)
local FIRST = { service = "Tracking icon", gather = "Map icon", vendor = "Map icon" }
local ALT = { -- Blizzard's other art for a kind: the map's HD icons (ObjectIconsAtlas), the classic tracking textures
	innkeeper = { { "Map icon", "A:innkeeper" } }, banker = { { "Map icon", "A:banker" } },
	auctioneer = { { "Map icon", "A:auctioneer" } }, stablemaster = { { "Map icon", "A:stablemaster" } },
	battlemaster = { { "Map icon", "A:battlemaster" } }, trainer = { { "Map icon", "A:profession" } },
	classtrainer = { { "Map icon", "A:class" } }, repair = { { "Map icon", "A:repair" } }, mailbox = { { "Map icon", "A:mailbox" } },
	flightmaster = { { "Map icon", "A:flightmaster" }, { "Boot", "A:flightpath" } },
	herb = { { "Sparkling", "A:professions_tracking_herb_special" }, { "Find Herbs", "133939" } },
	ore = { { "Sparkling", "A:professions_tracking_ore_special" }, { "Find Minerals", "136025" } },
	food = { { "Tracking icon", "136457" } }, reagents = { { "Tracking icon", "136464" } },
	poisons = { { "Tracking icon", "136462" } }, ammunition = { { "Tracking icon", "136451" } },
}
local TYPE = {}
for _, a in ipairs(ns.Atlas.BLIP_ART) do
	local kind, art, name, group = a[1], a[2], a[3], a[4]
	TYPE[art] = QUEST[kind] or kind
	if FAMILY[group] then
		local file = type(art) == "number" or art:find("\\", 1, true) -- (a FileDataID or a path: a texture; else an atlas)
		local icon = file and { texture = art } or { atlas = art, color = COLOR[art] }
		local icons
		if ALT[kind] then
			icons = { { FIRST[group], file and tostring(art) or "A:" .. art } }
			for _, o in ipairs(ALT[kind]) do icons[#icons + 1] = o end
		end
		UI.PinTypes.Add({ id = kind, family = FAMILY[group], name = name, look = { size = ICON, icon = icon }, icons = icons,
			groups = true, tip = name .. ": the Minimap's blip, and where Blizzard's tracking shows it." })
	end
end
UI.PinTypes.Add({ id = "dot", family = "other", name = "Unknown blip", look = { size = DOT, icon = { color = GOLD } }, groups = true,
	tip = "A gold dot: a Minimap blip whose name MagicMap doesn't know." })
UI.PinTypes.Add({ id = "tracking", family = "other", name = "Other tracking",
	look = { size = ICON, icon = { texture = "Interface\\Icons\\Ability_Tracking" } },
	groups = true, tip = "A blip Blizzard's tracking draws with an icon of a kind MagicMap doesn't list (its own art)." })

-- StylePin's looks, one an icon (Blips.lua:423-437), a gathering node's one a letter and difficulty too.
local DOT_LOOK = { size = DOT, icon = { color = GOLD }, type = "dot" }
local function Look(icon, name)
	if not icon then return DOT_LOOK end
	local k, badge = icon.texture or icon.atlas, nil
	local kind = name and icon.atlas and GATHER[icon.atlas]
	if kind then
		local need, skills = ns.Atlas.NodeSkill(name), Model.skills
		local color = badges.difficulty and need and skills and Difficulty(skills[kind], need) or nil
		local letter = badges.letter and ns.Atlas.NodeLetter(name) or nil
		if color or letter then
			badge = { color = color, letter = letter, scale = badges.size }
			k = k .. "|" .. (letter or "") .. "|" .. (color and table.concat(color, ",") or "")
		end
	end
	local look = looks[k]
	if not look then
		local art = icon.texture and { texture = icon.texture } or UI.Art.Icon(icon.atlas)
		art.color = icon.color or COLOR[icon.atlas]
		look = { size = ICON, icon = art, badge = badge, type = TYPE[icon.texture or icon.atlas] or "tracking" }
		looks[k] = look
	end
	return look
end
-- A rev that moves with the badges: their settings, your skills.
local skills, skillsRev = nil, 0
local function BadgeRev()
	if Model.skills ~= skills then skills, skillsRev = Model.skills, skillsRev + 1 end
	return badgeRev + skillsRev
end

-- A remembered one's "Not in sight" follows its line, as the spike read { sub, "Not in sight" } with
-- ipairs: with no line, neither (Blips.lua:641-642, Layers.lua:298).
local function Lines(b)
	local line = b.text or b.icon and LINE[b.icon.atlas]
	if b.live then return b.name, line end
	return b.name, line, line and AWAY
end

-- You while the sensor runs, by walk chunk (false: not sensing), and a rev that moves with it.
local here, hereRev = false, 0
local function Here()
	local m, you = Model.minimap, Model.you
	local key = m and m.sensing and you.col and not you.stale and math.floor(you.col * CHUNKS) * 4096 + math.floor(you.row * CHUNKS)
		or false
	if key ~= here then here, hereRev = key, hereRev + 1 end
	return hereRev
end

-- Not within the sensor's word around you (you: false while it doesn't run).
local function Away(b, you)
	local p = b.pos
	return not (you and (p.col - you.col) ^ 2 + (p.row - you.row) ^ 2 < REACH * REACH)
end

local carried = {} -- keys of remembered ones a sensed one stands for
UI.Blips = UI.Pins.Layer("blips", 12, function(put, inst, _, want)
	local live, seen = Model.Known("blips"), Model.Known("remembered")
	for k in pairs(carried) do carried[k] = nil end
	for _, b in ipairs(live) do
		carried[b.key] = true
		put(b, Look(b.icon, b.name))
	end
	if not want(REMOTE_ZOOM) then return end
	local you = here and Model.you.inst == inst and Model.you
	for _, b in ipairs(Model.Known("services")) do
		if Away(b, you) then put(b, Look(b.icon, b.name), REMOTE_ZOOM) end
	end
	for _, b in ipairs(seen) do
		if not carried[b.key] and Away(b, you) then put(b, Look(b.icon, b.name), REMOTE_ZOOM) end
	end
end, function()
	return select(2, Model.Known("blips")) + select(2, Model.Known("remembered")) + select(2, Model.Known("services"))
		+ Here() + BadgeRev()
end, { lines = Lines, cluster = true })
