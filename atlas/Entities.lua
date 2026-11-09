-- NPCs, objects, items and quests (Data/Npcs, Objects, Items, Quests:
-- from QuestieDB: NOTICE.md; Data/ItemIcons from the Item DB2), and the static
-- joins between them. No player state here. Without a Data file: as if it were empty.

local _, ns = ...
local Atlas = ns.Atlas or {}; ns.Atlas = Atlas
local Data = ns.Data -- the generated datasets (Data/*.lua; atlas/Coords.lua)

local NONE = {}

local SERVICES = { -- npcFlags bit -> service
	{ 2, "questgiver" }, { 4, "vendor" }, { 8, "flightmaster" }, { 16, "trainer" },
	{ 128, "innkeeper" }, { 256, "banker" }, { 2048, "battlemaster" }, { 4096, "auctioneer" },
	{ 8192, "stablemaster" }, { 16384, "repair" },
}

local function Services(flags)
	local out = {}
	for _, s in ipairs(SERVICES) do
		if flags and flags % (s[1] * 2) >= s[1] then out[#out + 1] = s[2] end -- bit s[1] set
	end
	return out
end

local NAMED = {
	npc = function(id, r)
		return { id = id, name = r[1], subName = r[2], minLevel = r[3], maxLevel = r[4], rank = r[5],
			faction = r[6], flags = r[7] or 0, services = Services(r[7]), questStarts = r[8] or NONE,
			questEnds = r[9] or NONE, spawns = r[10] or NONE, instances = r[11] or NONE }
	end,
	object = function(id, r)
		return { id = id, name = r[1], kind = r[2], questStarts = r[3] or NONE, questEnds = r[4] or NONE,
			spawns = r[5] or NONE, instances = r[6] or NONE }
	end,
	item = function(id, r)
		return { id = id, name = r[1], icon = (Data.ItemIcons or NONE)[id], npcDrops = r[2] or NONE,
			objectDrops = r[3] or NONE, itemDrops = r[4] or NONE, vendors = r[5] or NONE,
			startQuest = r[6], class = r[7], subClass = r[8], requiredLevel = r[9] }
	end,
	quest = function(id, r)
		local s, f, objectives = r[7] or NONE, r[8] or NONE, {}
		for i, o in ipairs(r[9] or NONE) do objectives[i] = { kind = o[1], id = o[2], text = o[3] } end
		local t = r[18]
		return { id = id, name = r[1], level = r[2], requiredLevel = r[3], faction = r[4], races = r[5],
			classes = r[6], startedBy = { npcs = s[1] or NONE, objects = s[2] or NONE, items = s[3] or NONE },
			finishedBy = { npcs = f[1] or NONE, objects = f[2] or NONE }, objectives = objectives,
			objectivesText = r[10] or NONE, zone = r[11], sort = r[12], preQuestSingle = r[13] or NONE,
			preQuestGroup = r[14] or NONE, exclusiveTo = r[15] or NONE, nextQuest = r[16],
			breadcrumbFor = r[17], triggerEnd = t and { text = t[1], spawns = t[2] or NONE } }
	end,
}

-- A row as stored: a string of its table (Data/*.lua since format 2: a string costs about its length, a
-- table of tables about four times as much), decoded when asked for; a table as it is (tests' stubs).
local function Decode(r)
	if type(r) == "string" then return assert(loadstring("return " .. r))() end
	return r
end

local function Rows(kind)
	local rows
	if kind == "npc" then rows = Data.Npcs
	elseif kind == "object" then rows = Data.Objects
	elseif kind == "item" then rows = Data.Items
	else rows = Data.Quests end
	return rows or NONE
end

local cache = { npc = {}, object = {}, item = {}, quest = {} } -- [kind][id] = named row | false
local function Get(kind, id)
	local e = cache[kind][id]
	if e == nil then
		local r = Rows(kind)[id]
		e = r and NAMED[kind](id, Decode(r)) or false
		cache[kind][id] = e
	end
	return e or nil
end

function Atlas.Npc(id) return Get("npc", id) end
function Atlas.Object(id) return Get("object", id) end
function Atlas.Item(id) return Get("item", id) end
function Atlas.Quest(id) return Get("quest", id) end

-- Where each objective can be done, in objective order: the npcs and objects
-- to kill, use or loot (an item: those that drop or sell it). A quest Atlas lacks: none.
function Atlas.QuestSources(questID)
	local out, q = {}, Atlas.Quest(questID)
	for i, o in ipairs(q and q.objectives or NONE) do
		local src, e = {}, nil
		if o.kind == "monster" or o.kind == "killcredit" then
			e = Atlas.Npc(o.id)
			src[1] = { kind = "npc", id = o.id }
		elseif o.kind == "object" then
			e = Atlas.Object(o.id)
			src[1] = { kind = "object", id = o.id }
		elseif o.kind == "item" then
			e = Atlas.Item(o.id)
			if e then
				for _, id in ipairs(e.npcDrops) do src[#src + 1] = { kind = "npc", id = id } end
				for _, id in ipairs(e.objectDrops) do src[#src + 1] = { kind = "object", id = id } end
				for _, id in ipairs(e.vendors) do src[#src + 1] = { kind = "npc", id = id } end
			end
		end
		out[i] = { kind = o.kind, id = o.id, text = o.text, name = e and e.name, sources = src }
	end
	return out
end

-- Spawn index: [kind][inst][tile key] = { id, col, row, id, col, row, ... }.
local SPAWNS = { npc = 10, object = 5 } -- spawns' index in the row
local spawnIndex = { npc = {}, object = {} }
local function SpawnIndex(kind, inst, step)
	local index = spawnIndex[kind][inst]
	if not index then
		index = {}
		local at, n = SPAWNS[kind], 0
		for id, r in pairs(Rows(kind)) do
			n = n + 1
			if step and n % 128 == 0 then step() end
			r = Decode(r) -- (the demo's: every row, once a map)
			local pts = r[at] and r[at][inst]
			if pts then
				for i = 1, #pts, 2 do
					local col, row = pts[i], pts[i + 1]
					local key = math.floor(col) * 64 + math.floor(row)
					local b = index[key]
					if not b then
						b = {}
						index[key] = b
					end
					b[#b + 1], b[#b + 2], b[#b + 3] = id, col, row
				end
			end
		end
		spawnIndex[kind][inst] = index
	end
	return index
end

-- Spawns of kind "npc" | "object" inside the tile-space box, as { id, col, row }.
-- The first call per kind and inst indexes every row: step(), if given, is called
-- every 128 rows so a caller can spread it over frames (as Atlas.Rares).
function Atlas.SpawnsIn(kind, inst, c0, r0, c1, r1, filter, step)
	local index, out = SpawnIndex(kind, inst, step), {}
	for c = math.floor(c0), math.floor(c1) do
		for r = math.floor(r0), math.floor(r1) do
			local b = index[c * 64 + r]
			if b then
				for i = 1, #b, 3 do
					local id, col, row = b[i], b[i + 1], b[i + 2]
					if col >= c0 and col <= c1 and row >= r0 and row <= r1 and (not filter or filter(id)) then
						out[#out + 1] = { id = id, col = col, row = row }
					end
				end
			end
		end
	end
	return out
end

-- Rare (rank 4) and rare-elite (rank 2) NPCs' spawn points on inst, as
-- { id, name, rank, minLevel, maxLevel, col, row }, in a stable order (npc id, then spawn).
-- A full pass over the NPCs the first time per inst (then cached): step(), if
-- given, is called every few rows so a caller can spread it over frames.
local rares = {} -- [inst] = list
function Atlas.Rares(inst, step)
	local list = rares[inst]
	if list then return list end
	local lists = Data.Npcs and Data.NpcLists
	local ids = {}
	for _, id in ipairs(lists and lists.rare[inst] or NONE) do ids[#ids + 1] = id end -- (Data/Npcs.lua's NpcLists)
	table.sort(ids)
	list = {}
	for _, id in ipairs(ids) do
		local r = Decode(Data.Npcs[id])
		local pts = r[10][inst]
		for i = 1, #pts, 2 do
			list[#list + 1] = { id = id, name = r[1], rank = r[5], minLevel = r[3], maxLevel = r[4],
				col = pts[i], row = pts[i + 1] }
		end
		if step then step() end
	end
	rares[inst] = list
	return list
end

-- Names per kind, lowercased: { ids, lower } (in the rows' order). The first call per
-- kind walks every row: step(), if given, is called every 128 rows.
local names = {}
local function Names(kind, step)
	local n = names[kind]
	if not n then
		n = { ids = {}, lower = {} }
		for id, r in pairs(Rows(kind)) do
			local i = #n.ids + 1
			-- (a row's name is its first string: read off the stored string without decoding the rest)
			local name = type(r) == "string" and Decode(r:match('^{(".-[^\\]")[,}]') or '""') or r[1]
			n.ids[i], n.lower[i] = id, name:lower()
			if step and i % 128 == 0 then step() end
		end
		names[kind] = n
	end
	return n
end

-- ids of kind whose name contains text (any case), exact matches first, each by id.
-- Every name is looked at: step(), if given, is called every 128.
function Atlas.Find(kind, text, limit, step)
	local n, t = Names(kind, step), text:lower()
	local exact, partial = {}, {}
	for i, name in ipairs(n.lower) do
		if name == t then
			exact[#exact + 1] = n.ids[i]
		elseif name:find(t, 1, true) then
			partial[#partial + 1] = n.ids[i]
		end
		if step and i % 128 == 0 then step() end
	end
	table.sort(exact)
	table.sort(partial)
	for _, id in ipairs(partial) do exact[#exact + 1] = id end
	if limit then
		for i = #exact, limit + 1, -1 do exact[i] = nil end
	end
	return exact
end

-- Gathering nodes by name, enUS (the spike's Blips.lua:364-371, 423-426; docs/v1-non-goals.md: enUS only).
local HERBS = {}
for _, n in ipairs({
	"Peacebloom", "Silverleaf", "Earthroot", "Mageroyal", "Briarthorn", "Stranglekelp", "Bruiseweed",
	"Wild Steelbloom", "Grave Moss", "Kingsblood", "Liferoot", "Fadeleaf", "Goldthorn", "Khadgar's Whisker",
	"Wintersbite", "Firebloom", "Purple Lotus", "Arthas' Tears", "Sungrass", "Blindweed", "Ghost Mushroom",
	"Gromsblood", "Golden Sansam", "Dreamfoil", "Mountain Silversage", "Plaguebloom", "Icecap", "Black Lotus",
	"Swiftthistle", "Bloodthistle",
	-- Forever's own: its starter-zone nodes (QuestieDB's Forever objects, hundreds of spawns) and its new herbs (the
	-- client's Item table: Trade Goods, Herb).
	"Stunted Silverleaf", "Wilted Peacebloom", "Hive Thistle", "Demonsage", "Death Lotus", "Marefoil", "Stranglevine",
}) do HERBS[n] = true end
-- A herb's name with a word before it ("Wilted Peacebloom"): one too.
local function Herb(name)
	if HERBS[name] then return true end
	local last = name:match("^%a[%a']* (.+)$")
	return last ~= nil and HERBS[last] == true
end
-- Mining nodes not named "... Vein" or "... Deposit".
local ORES = { ["Chunk of Amber"] = true, ["Large Chunk of Amber"] = true, ["Small Obsidian Chunk"] = true,
	["Large Obsidian Chunk"] = true }

-- The skill each node takes (Herbalism's or Mining's), classic's: every one is a Herbalism (lock type 2) or Mining
-- (3) skill in the client's Lock table (Lock.db2, 1.60.1.70790). Not here (Forever's own herbs, its starter nodes,
-- amber, Swiftthistle, Bloodthistle): not known, so no difficulty colour (ui/BlipTip.lua) rather than a guess.
local SKILL = {
	Peacebloom = 1, Silverleaf = 1, Earthroot = 15, Mageroyal = 50, Briarthorn = 70, Stranglekelp = 85,
	Bruiseweed = 100, ["Wild Steelbloom"] = 115, ["Grave Moss"] = 120, Kingsblood = 125, Liferoot = 150,
	Fadeleaf = 160, Goldthorn = 170, ["Khadgar's Whisker"] = 185, Wintersbite = 195, Firebloom = 205,
	["Purple Lotus"] = 210, ["Arthas' Tears"] = 220, Sungrass = 230, Blindweed = 235, ["Ghost Mushroom"] = 245,
	Gromsblood = 250, ["Golden Sansam"] = 260, Dreamfoil = 270, ["Mountain Silversage"] = 280, Plaguebloom = 285,
	Icecap = 290, ["Black Lotus"] = 300,
	["Copper Vein"] = 1, ["Tin Vein"] = 65, ["Incendicite Mineral Vein"] = 65, ["Silver Vein"] = 75,
	["Ooze Covered Silver Vein"] = 75, ["Lesser Bloodstone Deposit"] = 75, ["Iron Deposit"] = 125,
	["Indurium Mineral Vein"] = 150, ["Gold Vein"] = 155, ["Ooze Covered Gold Vein"] = 155, ["Mithril Deposit"] = 175,
	["Ooze Covered Mithril Deposit"] = 175, ["Truesilver Deposit"] = 230, ["Ooze Covered Truesilver Deposit"] = 230,
	["Dark Iron Deposit"] = 230, ["Small Thorium Vein"] = 245, ["Ooze Covered Thorium Vein"] = 245,
	["Rich Thorium Vein"] = 275, ["Ooze Covered Rich Thorium Vein"] = 275, ["Hakkari Thorium Vein"] = 275,
	["Small Obsidian Chunk"] = 305, ["Large Obsidian Chunk"] = 310,
}
-- The skill a gathering node of this name takes, or nil: not known.
function Atlas.NodeSkill(name) return SKILL[name] end

-- The icon of what a node gives (the herb, the ore: the item's icon, Item.db2's IconFileDataID, 1.60.1.70790), the
-- icon players know it by; a herb's by its own name or its last words ("Wilted Peacebloom": Peacebloom's), an ore
-- node's by its own. Not here (Forever's own herbs, amber): none.
local ORE = { copper = 134566, tin = 134579, iron = 134572, silver = 135242, gold = 134571, mithril = 134576,
	truesilver = 134580, thorium = 134578, darkIron = 134575, incendicite = 134577, bloodstone = 134577,
	indurium = 134575 }
local ICON = {
	Peacebloom = 133939, Silverleaf = 134190, Earthroot = 134187, Mageroyal = 133436, Briarthorn = 134412,
	Stranglekelp = 134191, Bruiseweed = 134181, ["Wild Steelbloom"] = 133938, ["Grave Moss"] = 133849,
	Kingsblood = 134183, Liferoot = 134413, Fadeleaf = 134193, Goldthorn = 134196, ["Khadgar's Whisker"] = 134188,
	Wintersbite = 133940, Firebloom = 134200, ["Purple Lotus"] = 134198, ["Arthas' Tears"] = 134194,
	Sungrass = 134199, Blindweed = 134195, ["Ghost Mushroom"] = 134529, Gromsblood = 134197,
	["Golden Sansam"] = 134221, Dreamfoil = 134204, ["Mountain Silversage"] = 134215, Plaguebloom = 134219,
	Icecap = 134212, ["Black Lotus"] = 134202,
	["Copper Vein"] = ORE.copper, ["Tin Vein"] = ORE.tin, ["Incendicite Mineral Vein"] = ORE.incendicite,
	["Silver Vein"] = ORE.silver, ["Ooze Covered Silver Vein"] = ORE.silver,
	["Lesser Bloodstone Deposit"] = ORE.bloodstone, ["Iron Deposit"] = ORE.iron,
	["Indurium Mineral Vein"] = ORE.indurium, ["Gold Vein"] = ORE.gold, ["Ooze Covered Gold Vein"] = ORE.gold,
	["Mithril Deposit"] = ORE.mithril, ["Ooze Covered Mithril Deposit"] = ORE.mithril,
	["Truesilver Deposit"] = ORE.truesilver, ["Ooze Covered Truesilver Deposit"] = ORE.truesilver,
	["Dark Iron Deposit"] = ORE.darkIron, ["Small Thorium Vein"] = ORE.thorium,
	["Ooze Covered Thorium Vein"] = ORE.thorium, ["Rich Thorium Vein"] = ORE.thorium,
	["Ooze Covered Rich Thorium Vein"] = ORE.thorium, ["Hakkari Thorium Vein"] = ORE.thorium,
	["Small Obsidian Chunk"] = 134455, ["Large Obsidian Chunk"] = 135241,
}
-- The file ID of the icon a gathering node of this name gives, or nil.
function Atlas.NodeIcon(name)
	local i = ICON[name]
	if i then return i end
	local last = name:match("^%a[%a']* (.+)$")
	return last and ICON[last]
end

-- What a gathering node's name is: "herb" or "ore" (by name alone, enUS), or nil: no node MagicMap knows (a blip's
-- tooltip, ui/BlipTip.lua).
function Atlas.NodeKind(name)
	if Herb(name) then return "herb" end
	if ORES[name] or name:find(" Vein$") or name:find(" Deposit$") then return "ore" end
end

-- The client's art for the quest blips' kinds, as the Minimap draws them: { kind, art, name, group }, the HD "!" and
-- "?" (Blips.lua:387-388): ui/Quests.lua's quests to pick up and to turn in.
Atlas.BLIP_ART = {
	{ "questgiver", "questnormal", "Quest giver", "quest" }, { "questender", "questturnin", "Quest ender", "quest" },
}
local blipArt = {}
for _, a in ipairs(Atlas.BLIP_ART) do blipArt[a[1]] = a end
-- A blip kind's art and its group (nil: none).
function Atlas.BlipArt(kind)
	local a = kind and blipArt[kind]
	if a then return a[2], a[4] end
end
