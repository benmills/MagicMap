-- Blizzard's minimap blips, drawn by us. Blizzard's Minimap is only a sensor
-- (MinimapTakeover keeps it invisible, at its widest zoom, north up): it
-- answers a pretend mouse anywhere on it (the controller's soft cursor,
-- Minimap:SetUsingSoftCursor) with the names of the blips under it, in the
-- same frame, whether or not it's drawn. Measured in game (2026-10-12): each
-- blip answers inside a square HALF_PX screen units each way from its
-- middle (7.84 Minimap units at scale 1.02), whatever the Minimap's size or
-- icon scale, exactly (no snapping to pixels); a probe
-- costs about 1.5 us on empty ground and 16 on a blip through C_TooltipInfo
-- (GameTooltip:SetMinimapMouseover costs ten times that).
--
-- So a grid STEP apart (just under a square's width: no blip fits between
-- its points) sweeps the Minimap, a few points a frame. A point naming
-- something no known blip explains gets that blip's middle from its square's
-- edges, halved in on, the same frame. Blips are kept in world yards: they
-- stay put as you move, and one no point of a whole sweep names is gone.
--
-- What each is comes from its name: herbs and ore, the mailbox, the
-- services QuestieDB knows NPCs by; anything else is a gold dot like
-- Blizzard's. What our other layers draw (party, quest givers, flight
-- masters, rares) isn't repeated.

local ADDON, ns = ...

local HALF_PX = 8.0     -- screen units a blip answers each way from its middle (measured; refined as blips are measured)
local GRID = 0.95       -- grid spacing, of a square's width: no blip fits between its points
local PER_FRAME = 24    -- grid points tried each frame
local MAX_LOCATES = 2   -- new blips measured each frame (about 40 probes each)
local HALVINGS = 8      -- an edge to a square's width / 2^8 (about 0.15 yd at the widest zoom)
local REST = 0.5        -- s between sweeps while you stand still (each read is a new table for the client to collect)
local MOVED = 1         -- yd you've moved since a sweep began that ends the rest
local SAME = 6          -- yd: a blip measured this close to a known one of its name is that one, moved
local NEAR_OURS = 8     -- yd: a blip this close to one of our own pins is that pin's
local TILE_YARDS = 1600 / 3

local blips = {}        -- { name, north, west, inst, seen }
local grid, gridKey = {}, nil
local HALF, STEP        -- this frame, in Minimap units: HALF_PX over its scale, and the grid spacing
local sweep = { i = 1, id = 1 }
local changed = false
local g = {}            -- this frame: left, bottom, scale (screen), w, h, u (yd per unit), north, west, inst

---------------------------------------------------------------------------
-- Probing
---------------------------------------------------------------------------

-- A tooltip line's names (one per row, markup stripped). The same few lines
-- come back all the time, so each is parsed once.
local parsed, parsedCount = {}, 0
local function NamesIn(text)
	local list = parsed[text]
	if not list then
		list = {}
		for part in text:gmatch("[^\n]+") do
			part = part:gsub("|A.-|a", ""):gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
			part = part:match("^%s*(.-)%s*$")
			if part ~= "" then list[#list + 1] = part end
		end
		if parsedCount >= 200 then parsed, parsedCount = {}, 0 end
		parsed[text], parsedCount = list, parsedCount + 1
	end
	return list
end

local names = {}
-- The names at (x, y), Minimap units from its bottom left: a reused list.
local function At(x, y)
	Minimap:UpdateMouseoverAtPoint((g.left + x) * g.scale, (g.bottom + y) * g.scale)
	wipe(names)
	local data = C_TooltipInfo.GetMinimapMouseover()
	if not data or issecretvalue(data) or issecretvalue(data.lines) then return names end
	for _, line in ipairs(data.lines or {}) do
		local text = line.leftText
		if text and not issecretvalue(text) then
			for _, n in ipairs(NamesIn(text)) do names[#names + 1] = n end
		end
	end
	return names
end

local function Answers(x, y, name)
	for _, n in ipairs(At(x, y)) do
		if n == name then return true end
	end
	return false
end

-- From (x, y), where `name` answers, how far it keeps answering going (dx, dy).
local function Edge(name, x, y, dx, dy)
	local inside, outside = 0, nil
	for k = 1, 4 do
		local d = k * 2 * HALF
		if not Answers(x + dx * d, y + dy * d, name) then
			outside = d
			break
		end
		inside = d
	end
	if not outside then return nil end
	for _ = 1, HALVINGS do
		local mid = (inside + outside) / 2
		if Answers(x + dx * mid, y + dy * mid, name) then inside = mid else outside = mid end
	end
	return (inside + outside) / 2
end

-- The middles along one axis: one square's, or where squares of the same
-- name overlap, the two at its ends.
local function Middles(lo, hi)
	if hi - lo <= 2.3 * HALF then return { (lo + hi) / 2 } end
	return { lo + HALF, hi - HALF }
end

-- The middles of the blips named `name` whose squares hold (x, y).
local function Locate(name, x, y)
	local r, l = Edge(name, x, y, 1, 0), Edge(name, x, y, -1, 0)
	local t, b = Edge(name, x, y, 0, 1), Edge(name, x, y, 0, -1)
	if not (r and l and t and b) then return nil end
	-- A lone square (not two of a name overlapping) tells its true size.
	local wide, tall = l + r, t + b
	if wide <= 2.3 * HALF and tall <= 2.3 * HALF and math.abs(wide - tall) < 0.1 * HALF then
		HALF_PX = HALF_PX + ((wide + tall) / 4 * g.scale - HALF_PX) / 4
	end
	local xs, ys = Middles(x - l, x + r), Middles(y - b, y + t)
	local out = {}
	-- Squares of a name overlapping give more than one candidate, some of
	-- them ghosts (an x from one, a y from another): all four corners of a
	-- real one answer.
	local check = #xs * #ys > 1
	local e = 0.75 * HALF -- (a middle can be off by up to 0.15 of it where overlaps read as one)
	for _, mx in ipairs(xs) do
		for _, my in ipairs(ys) do
			if not check or (Answers(mx - e, my - e, name) and Answers(mx + e, my - e, name)
				and Answers(mx - e, my + e, name) and Answers(mx + e, my + e, name)) then
				out[#out + 1] = { mx, my }
			end
		end
	end
	return out
end

---------------------------------------------------------------------------
-- Minimap units <-> world yards (north up, you in the middle)
---------------------------------------------------------------------------

local function ToWorld(x, y)
	return g.north + (y - g.h / 2) * g.u, g.west - (x - g.w / 2) * g.u
end

local function ToLocal(b)
	return g.w / 2 + (g.west - b.west) / g.u, g.h / 2 + (b.north - g.north) / g.u
end

---------------------------------------------------------------------------
-- Sweeping
---------------------------------------------------------------------------

local function BuildGrid(w, h)
	wipe(grid)
	STEP = GRID * 2 * HALF
	for x = STEP / 2, w, STEP do
		for y = STEP / 2, h, STEP do grid[#grid + 1] = { x, y } end
	end
	gridKey = w .. ":" .. h .. ":" .. HALF
	sweep.i = 1
end

-- Marks every known blip of `name` whose square holds (x, y) as seen (where
-- squares of a name overlap, a point there answers for all of them); false
-- if none does.
local function Explain(name, x, y)
	local any = false
	for _, b in ipairs(blips) do
		if b.name == name and b.inst == g.inst then
			local bx, by = ToLocal(b)
			if math.abs(x - bx) <= HALF + 0.5 and math.abs(y - by) <= HALF + 0.5 then
				b.seen, any = sweep.id, true
			end
		end
	end
	return any
end

local function Add(name, x, y)
	local north, west = ToWorld(x, y)
	for _, b in ipairs(blips) do
		if b.name == name and b.inst == g.inst and (b.north - north) ^ 2 + (b.west - west) ^ 2 < SAME * SAME then
			b.north, b.west, b.seen = north, west, sweep.id -- (it walked)
			changed = true
			return
		end
	end
	blips[#blips + 1] = { name = name, north = north, west = west, inst = g.inst, seen = sweep.id }
	changed = true
end

local locates = 0
local found = {}
local function Visit(x, y)
	local here = At(x, y)
	if #here == 0 then return end
	wipe(found)
	for i, n in ipairs(here) do found[i] = n end
	for _, name in ipairs(found) do
		if not Explain(name, x, y) and locates < MAX_LOCATES then
			locates = locates + 1
			for _, m in ipairs(Locate(name, x, y) or {}) do Add(name, m[1], m[2]) end
		end
	end
end

-- A whole sweep done: what none of its points named is gone.
local function EndSweep()
	for i = #blips, 1, -1 do
		if blips[i].seen ~= sweep.id then
			table.remove(blips, i)
			changed = true
		end
	end
	sweep.id = sweep.id + 1
	sweep.rest, sweep.north, sweep.west = GetTime() + REST, g.north, g.west
	if changed then
		changed = false
		ns.RefreshLayer("blips")
	end
end

local function Measure()
	local left, bottom = Minimap:GetLeft(), Minimap:GetBottom()
	local r = C_Minimap.GetViewRadius()
	local north, west, _, inst = UnitPosition("player")
	if not (left and r and north) or issecretvalue(r) or issecretvalue(north) then return false end
	local w, h = Minimap:GetSize()
	if w <= 0 then return false end
	g.left, g.bottom, g.scale, g.w, g.h = left, bottom, Minimap:GetEffectiveScale(), w, h
	g.u, g.north, g.west, g.inst = r / (w / 2), north, west, inst
	return true
end

-- A sweep cut short (combat, indoors, the layer off, another continent)
-- starts over, so none mixes two places.
local function Restart()
	if sweep.i ~= 1 then
		sweep.i = 1
		sweep.id = sweep.id + 1
	end
end

local function Sweep()
	for _ = 1, PER_FRAME do
		local p = grid[sweep.i]
		Visit(p[1], p[2])
		sweep.i = sweep.i + 1
		if sweep.i > #grid then
			sweep.i = 1
			EndSweep()
			return
		end
	end
end

local lastInst
local function Update()
	if not (ns.Takeover.Sensing() and ns.LayerEnabled("blips")) or InCombatLockdown() or not Measure() then
		Restart()
		return
	end
	if g.inst ~= lastInst then
		lastInst = g.inst
		Restart()
	end
	HALF = HALF_PX / g.scale
	if gridKey ~= g.w .. ":" .. g.h .. ":" .. HALF then BuildGrid(g.w, g.h) end
	if sweep.i == 1 and sweep.rest and GetTime() < sweep.rest
		and (g.north - sweep.north) ^ 2 + (g.west - sweep.west) ^ 2 < MOVED * MOVED then
		return -- standing still: nothing new comes in over the edge
	end
	locates = 0
	Minimap:SetUsingSoftCursor(true)
	local ok, err = pcall(Sweep)
	Minimap:SetUsingSoftCursor(false) -- (whatever happened: never left on)
	if not ok then error(err, 0) end
end

ns.frame:HookScript("OnUpdate", ns.Timed("minimap blips", Update))

---------------------------------------------------------------------------
-- What each is
---------------------------------------------------------------------------

local HERBS = {}
for _, n in ipairs({
	"Peacebloom", "Silverleaf", "Earthroot", "Mageroyal", "Briarthorn", "Stranglekelp", "Bruiseweed",
	"Wild Steelbloom", "Grave Moss", "Kingsblood", "Liferoot", "Fadeleaf", "Goldthorn", "Khadgar's Whisker",
	"Wintersbite", "Firebloom", "Purple Lotus", "Arthas' Tears", "Sungrass", "Blindweed", "Ghost Mushroom",
	"Gromsblood", "Golden Sansam", "Dreamfoil", "Mountain Silversage", "Plaguebloom", "Icecap", "Black Lotus",
	"Swiftthistle", "Bloodthistle",
}) do HERBS[n] = true end

local GOLD = { 1, 0.82, 0 }
-- Blizzard's tracking icons (Interface\Minimap\Tracking), by QuestieDB NPC
-- flag. Forever's data uses Classic's flag values (QuestieDB's
-- corrections/enum/expansions.lua; not exported), first match wins.
local SERVICES = {
	{ 128, 136458 },   -- innkeeper
	{ 256, 136453 },   -- banker
	{ 4096, 136452 },  -- auctioneer
	{ 8192, 136466 },  -- stable master
	{ 2048, 136454 },  -- battlemaster
	{ 16, 136463 },    -- trainer (class trainers below)
	{ 16384, 136465 }, -- repair
}
local MAILBOX = 136459
local QUEST_GIVER = 132049 -- Interface\GossipFrame\AvailableQuestIcon: the "!"
local QUEST_ENDER = 132048 -- ActiveQuestIcon: the "?"
local CLASS_TRAINER = 136455
local CLASSES = { "Warrior", "Paladin", "Hunter", "Rogue", "Priest", "Shaman", "Mage", "Warlock", "Druid" }

local function HasFlag(flags, bit) return bit and flags and math.floor(flags / bit) % 2 == 1 end

local function Npc(name)
	local DB = LibQuestieDB
	if not (DB and DB.Npc and DB.Npc.IdsByName) then return nil end
	local ok, ids = pcall(DB.Npc.IdsByName, name)
	local id = ok and ids and ids[1]
	if not id then return nil end
	local _, flags = pcall(DB.Npc.npcFlags, id)
	local _, sub = pcall(DB.Npc.subName, id)
	local _, starts = pcall(DB.Npc.questStarts, id)
	local _, ends = pcall(DB.Npc.questEnds, id)
	return type(flags) == "number" and flags or nil, type(sub) == "string" and sub or nil,
		type(starts) == "table" and #starts > 0, type(ends) == "table" and #ends > 0
end

local kinds = {} -- name -> { icon, size, lines }
local function Kind(name)
	local k = kinds[name]
	if k then return k end
	if name:find(" Vein$") or name:find(" Deposit$") then
		k = { icon = { atlas = "Professions_Tracking_Ore", color = { 0.8, 0.6, 0.4 } }, size = 14, lines = { "Mining" } }
	elseif HERBS[name] then
		k = { icon = { atlas = "Professions_Tracking_Herb", color = { 0.4, 0.9, 0.3 } }, size = 14, lines = { "Herbalism" } }
	elseif name == "Mailbox" then
		k = { icon = { texture = MAILBOX }, size = 14 }
	else
		local flags, sub, starts, ends = Npc(name)
		local icon
		for _, s in ipairs(SERVICES) do
			if not icon and HasFlag(flags, s[1]) then icon = s[2] end
		end
		-- Quest givers our own layers don't cover (they'd be skipped as ours).
		icon = icon or (starts and QUEST_GIVER) or (ends and QUEST_ENDER) or nil
		if icon == 136463 and sub then
			for _, c in ipairs(CLASSES) do
				if sub:find(c, 1, true) then icon = CLASS_TRAINER end
			end
		end
		k = { icon = icon and { texture = icon } or { color = GOLD }, size = icon and 14 or 10, lines = sub and { sub } or nil }
	end
	kinds[name] = k
	return k
end

---------------------------------------------------------------------------
-- The layer
---------------------------------------------------------------------------

-- Layers whose pins stand for a blip at their spot.
local OURS = { "quests", "offers", "flight", "rares", "dungeons", "corpse", "waypoint" }

local function Skipped()
	local skip = {}
	local me = UnitName("player")
	if me then skip[me] = true end
	for i = 1, GetNumGroupMembers() do
		local n = UnitName((IsInRaid() and "raid" or "party") .. i)
		if n and not issecretvalue(n) then skip[n] = true end
	end
	return skip
end

local function NearOurs(col, row)
	local reach = NEAR_OURS / TILE_YARDS
	for _, key in ipairs(OURS) do
		for _, e in ipairs(ns.LayerPins(key) or {}) do
			if e.col and math.abs(e.col - col) < reach and math.abs(e.row - row) < reach then return true end
		end
	end
	return false
end

local function BlipPins(mapID)
	local list = {}
	local skip = Skipped()
	for _, b in ipairs(blips) do
		if b.inst == mapID and not skip[b.name] then
			local col, row = ns.WorldToTile(b.north, b.west)
			if not NearOurs(col, row) then
				local k = Kind(b.name)
				ns.PinAtTile(list, mapID, col, row, { size = k.size, title = b.name, lines = k.lines, icon = k.icon })
			end
		end
	end
	return list
end

ns.AddPinLayer({ key = "blips", label = "Minimap blips", group = "places", default = true,
	tip = "What Blizzard's minimap tracks around you (herbs, ore, town services), drawn on the map." }, BlipPins)

-- The blips known now (only the tests read it).
ns.Blips = function() return blips end
