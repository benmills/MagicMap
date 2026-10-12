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
-- While you move, the client seems to move its blips in steps, so a
-- measure can be a few yards off: hits are matched more loosely (LAG), a
-- blip measured within half a square of one of its name is that one, and
-- what was measured on the move is measured again once you've stood
-- still for SETTLE seconds.
local LAG = 8           -- yd
local SETTLE = 0.5      -- s
local NEAR_OURS = 8     -- yd: a blip this close to one of our own pins is that pin's
local TILE_YARDS = ns.TILE_YARDS

local blips = {}        -- { name, north, west, inst, seen, rough (measured on the move) }
local grid, gridW, gridH, gridHalf = {}, nil, nil, nil
local HALF, STEP        -- this frame, in Minimap units: HALF_PX over its scale, and the grid spacing
local sweep = { i = 1, id = 1 }
local changed = false
local g = {}            -- this frame: left, bottom, scale (screen), w, h, u (yd per unit), north, west, inst, moving

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
	gridW, gridH, gridHalf = w, h, HALF
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
			local slack = HALF + 0.5 + (g.moving and LAG / g.u or 0)
			if math.abs(x - bx) <= slack and math.abs(y - by) <= slack then
				b.seen, any = sweep.id, true
			end
		end
	end
	return any
end

-- A record of what the sensor did (MagicMapDB.blipLog, the last LOG_SIZE
-- lines), for working out in-game surprises like copies; /mm blips lists
-- what it knows now.
local LOG_SIZE = 400
local db
local function Log(fmt, ...)
	if not db then return end
	local log = db.blipLog or {}
	db.blipLog = log
	log[#log + 1] = ("%.2f %s"):format(GetTime(), fmt:format(...))
	if #log > LOG_SIZE * 1.5 then -- (trimmed now and then, not shifted every line)
		local keep = {}
		for i = #log - LOG_SIZE + 1, #log do keep[#keep + 1] = log[i] end
		db.blipLog = keep
	end
end

-- Where a blip is from you, in yards (east, north), for the log.
local function Rel(north, west)
	return ("%+.1fE %+.1fN"):format((g.west or 0) - west, north - (g.north or 0))
end

local function Add(name, x, y)
	local north, west = ToWorld(x, y)
	local same = g.moving and math.max(SAME, HALF * g.u) or SAME
	for _, b in ipairs(blips) do
		if b.name == name and b.inst == g.inst and (b.north - north) ^ 2 + (b.west - west) ^ 2 < same * same then
			b.seen = sweep.id
			if not g.moving or b.rough then -- (a still measure isn't spoilt by one on the move)
				Log("move %s %s -> %s%s", name, Rel(b.north, b.west), Rel(north, west), g.moving and " (moving)" or "")
				b.north, b.west, b.rough = north, west, g.moving -- (it walked)
				changed = true
			end
			return
		end
	end
	blips[#blips + 1] = { name = name, north = north, west = west, inst = g.inst, seen = sweep.id, rough = g.moving }
	Log("add %s %s%s; half %.2f units = %.1f yd", name, Rel(north, west), g.moving and " (moving)" or "", HALF, HALF * g.u)
	changed = true
end

-- Standing still: one blip measured on the move, measured again (each
-- tried once a sweep; one that doesn't answer where it should is left for
-- the sweep to drop).
local function Settle()
	for _, b in ipairs(blips) do
		if b.rough and b.inst == g.inst and b.settleTry ~= sweep.id then
			b.settleTry = sweep.id
			local bx, by = ToLocal(b)
			if Answers(bx, by, b.name) then
				local best, gap
				for _, m in ipairs(Locate(b.name, bx, by) or {}) do
					local d = (m[1] - bx) ^ 2 + (m[2] - by) ^ 2
					if not gap or d < gap then best, gap = m, d end
				end
				if best then
					local north, west = ToWorld(best[1], best[2])
					Log("settle %s %s -> %s", b.name, Rel(b.north, b.west), Rel(north, west))
					b.north, b.west, b.rough = north, west, false
					changed = true
				end
			end
			return
		end
	end
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
local ForgetUnseen -- forward: remembered blips it didn't see (below)

local function EndSweep()
	for i = #blips, 1, -1 do
		if blips[i].seen ~= sweep.id then
			Log("drop %s %s", blips[i].name, Rel(blips[i].north, blips[i].west))
			table.remove(blips, i)
			changed = true
		end
	end
	ForgetUnseen()
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
	g.u, g.inst = r / (w / 2), inst
	local now = GetTime()
	if not g.north or (north - g.north) ^ 2 + (west - g.west) ^ 2 > 0.0025 then g.movedAt = now end
	g.north, g.west = north, west
	g.moving = now - (g.movedAt or 0) < SETTLE
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
	-- (A new size, or the square's size refined by more than a little.)
	if g.w ~= gridW or g.h ~= gridH or math.abs(HALF - gridHalf) > 0.05 * gridHalf then BuildGrid(g.w, g.h) end
	if #grid == 0 then return end
	if sweep.i == 1 and sweep.rest and GetTime() < sweep.rest
		and (g.north - sweep.north) ^ 2 + (g.west - sweep.west) ^ 2 < MOVED * MOVED then
		return -- standing still: nothing new comes in over the edge
	end
	locates = 0
	Minimap:SetUsingSoftCursor(true)
	local ok, err = pcall(Sweep)
	if ok and not g.moving then ok, err = pcall(Settle) end
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
	{ 16, 136463 },    -- trainer (TRAINER; class trainers get CLASS_TRAINER)
	{ 16384, 136465 }, -- repair
}
local MAILBOX = 136459
local QUEST_GIVER = 132049 -- Interface\GossipFrame\AvailableQuestIcon: the "!"
local QUEST_ENDER = 132048 -- ActiveQuestIcon: the "?"
local TRAINER, CLASS_TRAINER = 136463, 136455
local CLASSES = { "Warrior", "Paladin", "Hunter", "Rogue", "Priest", "Shaman", "Mage", "Warlock", "Druid" }

local function HasFlag(flags, bit) return bit and flags and math.floor(flags / bit) % 2 == 1 end

-- The tracking icon for an NPC's flags and title, nil if it offers none.
local function ServiceIcon(flags, sub)
	local icon
	for _, s in ipairs(SERVICES) do
		if not icon and HasFlag(flags, s[1]) then icon = s[2] end
	end
	if icon == TRAINER and sub then
		for _, c in ipairs(CLASSES) do
			if sub:find(c, 1, true) then icon = CLASS_TRAINER end
		end
	end
	return icon
end

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
		-- Quest givers our own layers don't cover (they'd be skipped as ours).
		local icon = ServiceIcon(flags, sub) or (starts and QUEST_GIVER) or (ends and QUEST_ENDER) or nil
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

---------------------------------------------------------------------------
-- Away from you, where the sensor can't see: town services QuestieDB knows
-- (every NPC with a service flag, friendly to you, at each spawn), and
-- blips the sensor has seen before (kept with the rares in
-- MagicMapLandmarks, for what QuestieDB lacks, like mailboxes). Shown from
-- town scale in, only for the kinds Blizzard's tracking has on; within
-- the sensor's reach only what it sees now counts.
---------------------------------------------------------------------------

local REMOTE_MIN_ZOOM = 60 -- px per tile
local LIVE_YARDS = 220     -- around you, the sensor's word
local BUILD_PER_FRAME = 300 -- NPCs looked at each frame while the services are gathered

local services            -- instance -> list of { name, col, row, icon, sub }, once gathered
local gathering, gatherAgain -- the gathering in progress; when to try again after one found nothing
local GATHER_AGAIN = 30    -- s
local MAX_REMEMBERED = 300 -- blips kept per instance (the oldest go)
local NEAR_SAME = 30       -- yd: a remembered blip this close to a service of its name is that one

-- QuestieDB's zone IDs to uiMap IDs (its support data keeps them as Lua source).
local function AreaMaps(DB)
	local zone = DB.Support and DB.Support.Get and DB.Support.Get("ZoneDB")
	local p = zone and zone.private
	local out = {}
	for _, src in ipairs({ p and p.areaIdToUiMapId or false, p and p.areaIdToUiMapIdOverride or false }) do
		local fn = type(src) == "string" and loadstring(src)
		local ok, t = false, nil
		if fn then ok, t = pcall(fn) end
		if ok and type(t) == "table" then
			for k, v in pairs(t) do out[k] = v end
		end
	end
	return out
end

local function Read(fn, id)
	local ok, v = pcall(fn, id)
	if ok then return v end
end

local function Gather()
	local DB = LibQuestieDB
	local ids = DB and DB.Npc and DB.Npc.GetAllIds and Read(DB.Npc.GetAllIds)
	if type(ids) ~= "table" then return {} end
	local maps = AreaMaps(DB)
	local mine = UnitFactionGroup("player") == "Horde" and "H" or "A"
	local out = {}
	for i, id in ipairs(ids) do
		local flags = Read(DB.Npc.npcFlags, id)
		local icon = type(flags) == "number" and ServiceIcon(flags) -- (most NPCs stop here)
		local sub = icon and Read(DB.Npc.subName, id)
		icon = icon and ServiceIcon(flags, type(sub) == "string" and sub or nil)
		local friendly = icon and Read(DB.Npc.friendlyToFaction, id)
		if type(friendly) == "string" and friendly:find(mine, 1, true) then
			local name = Read(DB.Npc.name, id)
			for area, coords in pairs(Read(DB.Npc.spawns, id) or {}) do
				local uiMap = maps[area]
				for _, c in ipairs(uiMap and uiMap > 0 and coords or {}) do
					local inst, col, row
					if c[1] and c[1] >= 0 then inst, col, row = ns.MapToTile(uiMap, c[1] / 100, c[2] / 100) end
					if inst then
						out[inst] = out[inst] or {}
						table.insert(out[inst], { name = name, col = col, row = row, icon = icon, sub = type(sub) == "string" and sub or nil })
					end
				end
			end
		end
		if i % BUILD_PER_FRAME == 0 then coroutine.yield() end
	end
	return out
end

local gatherer = CreateFrame("Frame")
gatherer:Hide()
gatherer:SetScript("OnUpdate", ns.Timed("town services", function(self)
	local ok, result = coroutine.resume(gathering)
	if not ok or coroutine.status(gathering) == "dead" then
		self:Hide()
		gathering = nil
		if not ok then
			geterrorhandler()(result)
			services = {} -- (not tried again this session: it would fail again)
		elseif next(result) then
			services = result
		else
			gatherAgain = GetTime() + GATHER_AGAIN -- (QuestieDB not ready yet?)
		end
		ns.RefreshLayer("blips")
	end
end))

-- The tracking icons Blizzard's tracking has on now.
local function Tracked()
	local on = {}
	for i = 1, C_Minimap.GetNumTrackingTypes() or 0 do
		local info = C_Minimap.GetTrackingInfo(i)
		if info and info.active and info.texture then on[info.texture] = true end
	end
	if on[TRAINER] then on[CLASS_TRAINER] = true end -- (one switch for both kinds of trainer)
	return on
end

-- A town service QuestieDB has of this name near (col, row).
local function KnownService(inst, name, col, row)
	local reach = NEAR_SAME / TILE_YARDS
	for _, e in ipairs(services and services[inst] or {}) do
		if e.name == name and (e.col - col) ^ 2 + (e.row - row) ^ 2 < reach * reach then return true end
	end
	return false
end

-- A blip seen now, kept for when you're away (but those QuestieDB has
-- anyway); at most MAX_REMEMBERED an instance, the oldest going first.
local function Remember(b, icon)
	local store = MagicMapLandmarks
	if not store then return end
	local col, row = ns.WorldToTile(b.north, b.west)
	if KnownService(b.inst, b.name, col, row) then return end
	local key = "blip:" .. b.name .. ":" .. math.floor(b.north / 8 + 0.5) .. ":" .. math.floor(b.west / 8 + 0.5)
	store[b.inst] = store[b.inst] or {}
	local entries = store[b.inst]
	local e = entries[key]
	if e and e.t > time() - 3600 then return end
	if not e then
		local count, oldest = 0, nil
		for k, x in pairs(entries) do
			if x.kind == "blip" then
				count = count + 1
				if not oldest or x.t < entries[oldest].t then oldest = k end
			end
		end
		if count >= MAX_REMEMBERED then entries[oldest] = nil end
	end
	entries[key] = { kind = "blip", name = b.name, icon = icon,
		n = math.floor(b.north * 10 + 0.5) / 10, w = math.floor(b.west * 10 + 0.5) / 10, t = time() }
end

-- A sweep done: remembered blips well inside its reach that it didn't
-- see (of a kind it's tracking) are gone from there.
ForgetUnseen = function()
	local entries = MagicMapLandmarks and MagicMapLandmarks[g.inst]
	if not entries then return end
	local on = Tracked()
	local reach = 0.8 * LIVE_YARDS
	for key, e in pairs(entries) do
		if e.kind == "blip" and on[e.icon] and (e.n - g.north) ^ 2 + (e.w - g.west) ^ 2 < reach * reach then
			local seen = false
			for _, b in ipairs(blips) do
				if b.name == e.name and b.inst == g.inst and (b.north - e.n) ^ 2 + (b.west - e.w) ^ 2 < 15 * 15 then seen = true end
			end
			if not seen then
				Log("forget %s %s", e.name, Rel(e.n, e.w))
				entries[key] = nil
			end
		end
	end
end

local function Remote(list, mapID, skip)
	if not services and not gathering and LibQuestieDB and GetTime() >= (gatherAgain or 0) then
		gathering = coroutine.create(Gather)
		gatherer:Show()
	end
	local on = Tracked()
	local pn, pw = UnitPosition("player")
	local here = ns.Takeover.Sensing() and pn and not issecretvalue(pn)
	local pc, pr
	if here then pc, pr = ns.WorldToTile(pn, pw) end
	local reach = LIVE_YARDS / TILE_YARDS
	local function Add(name, col, row, icon, sub)
		if not on[icon] or skip[name] or (here and (col - pc) ^ 2 + (row - pr) ^ 2 < reach * reach) then return end
		ns.PinAtTile(list, mapID, col, row, { size = 14, minZoom = REMOTE_MIN_ZOOM, title = name,
			lines = { sub, "|cff808080Not in sight|r" }, icon = { texture = icon } })
	end
	for _, e in ipairs(services and services[mapID] or {}) do Add(e.name, e.col, e.row, e.icon, e.sub) end
	for _, e in pairs(MagicMapLandmarks and MagicMapLandmarks[mapID] or {}) do
		if e.kind == "blip" then
			local col, row = ns.WorldToTile(e.n, e.w)
			if not KnownService(mapID, e.name, col, row) then Add(e.name, col, row, e.icon) end
		end
	end
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
				local t = k.icon.texture
				if t and t ~= QUEST_GIVER and t ~= QUEST_ENDER and not b.rough then Remember(b, t) end
			end
		end
	end
	Remote(list, mapID, skip)
	return list
end

ns.AddPinLayer({ key = "blips", label = "Minimap blips", group = "places", default = true,
	tip = "What Blizzard's minimap tracks around you (herbs, ore, town services), drawn on the map." }, BlipPins)

-- The blips known now (only the tests read it).
ns.Blips = function() return blips end

ns.slash.blips = function()
	ns.Print(("blips: %d known, answer square %.2f screen units each way, %d log lines in MagicMapDB.blipLog (/reload to write them)")
		:format(#blips, HALF_PX, db and db.blipLog and #db.blipLog or 0))
	for _, b in ipairs(blips) do ns.Print(("  %s %s%s"):format(b.name, Rel(b.north, b.west), b.rough and " (rough)" or "")) end
	Log("/mm blips: %d known", #blips)
	for _, b in ipairs(blips) do Log("  known %s %s%s", b.name, Rel(b.north, b.west), b.rough and " (rough)" or "") end
end

ns.On("Loaded", function(savedDB) db = savedDB end)
