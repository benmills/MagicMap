-- Validate Atlas against the live client (a spike: read it, run it, delete it when Atlas holds).
--   /mma atlas         load cost, dataset counts, first-use index builds
--   /mma check         Atlas vs the client where you stand: PASS / FAIL per fact
--   /mma check log     toggle logging mismatches every 2 s as you travel (MagicMapAtlasDB.validation)
--   /mma check report  the log, by kind;  /mma check clear  empties it

local ADDON, ns = ...
local Atlas, Runtime, Game = ns.Atlas, ns.Runtime, ns.Game
local D = Atlas.Data -- the raw datasets, for counts

local YD = 1 / Atlas.TILE_YARDS -- one yard in tiles
local TOL = {
	edge = 5 * YD,  -- area / zone: the client's answer within 5 yd counts (chunk edges, ~33 yd chunks)
	pos = 3 * YD,   -- map position -> tile vs UnitPosition
	rect = 1 * YD,  -- map rect corners (Data rounds to ~0.5 yd)
	taxi = 20 * YD, -- flight point on the continent map vs TaxiNodes
}
local EVERY, MAX_LOG = 2, 1000 -- logger: seconds per sample, entries kept
local ZONE = Enum.UIMapType.Zone
local GREEN, RED, GREY = "|cff60ff60", "|cffff6060", "|cff999999"

local function Dist(c1, r1, c2, r2) return math.sqrt((c1 - c2) ^ 2 + (r1 - r2) ^ 2) end
local function Yd(d) return string.format("%.1f yd", d / YD) end

local function Count(t)
	local n = 0
	for _ in pairs(t or {}) do n = n + 1 end
	return n
end

-- /mma atlas -------------------------------------------------------------------------------

local builds -- first-use index builds, measured on the first /mma atlas: { line, ... }

local function Time(label, fn)
	local m0, t0 = collectgarbage("count"), debugprofilestop()
	fn()
	return string.format("  %-34s %8.1f ms %8.0f KB", label, debugprofilestop() - t0, collectgarbage("count") - m0)
end

local function Builds(inst)
	local out = {}
	out[#out + 1] = Time("area grid: decode every tile", function()
		for key in pairs(D.AreaGrid and D.AreaGrid[inst] or {}) do Atlas.AreaAt(inst, math.floor(key / 64) + 0.5, key % 64 + 0.5) end
	end)
	out[#out + 1] = Time("walk grid: decode every tile", function()
		for key in pairs(D.Walk and D.Walk[inst] or {}) do Atlas.Walk.Cell(inst, math.floor(key / 64) * 16, key % 64 * 16) end
	end)
	out[#out + 1] = Time("ZoneLevels (all zones)", function() Atlas.ZoneLevels(12) end)
	out[#out + 1] = Time("Labels(" .. inst .. ")", function() Atlas.Labels(inst) end)
	if D.Npcs then
		out[#out + 1] = Time("SpawnsIn npc (index inst)", function() Atlas.SpawnsIn("npc", inst, 0, 0, 1, 1) end)
		out[#out + 1] = Time("SpawnsIn object (index inst)", function() Atlas.SpawnsIn("object", inst, 0, 0, 1, 1) end)
		out[#out + 1] = Time("Find npc (names)", function() Atlas.Find("npc", "wolf", 10) end)
		out[#out + 1] = Time("Find item (names)", function() Atlas.Find("item", "wolf", 10) end)
		out[#out + 1] = Time("Find quest (names)", function() Atlas.Find("quest", "wolf", 10) end)
		out[#out + 1] = Time("NpcsByName", function() Atlas.NpcsByName("Hogger") end)
	end
	return out
end

Game.Slash("atlas", "Atlas load cost, data counts and first-use index builds", function()
	local b = Runtime.boot
	UpdateAddOnMemoryUsage()
	Game.Print(string.format("Data + Atlas loaded in %.0f ms, %.0f KB Lua; %s now uses %.0f KB",
		b.loaded.t - b.t0, b.loaded.mem - b.mem0, ADDON, GetAddOnMemoryUsage(ADDON)))
	local tiles, grid, walk = 0, 0, 0
	for inst, m in pairs(D.Tiles and D.Tiles.maps or {}) do
		tiles = tiles + Count(m.tiles)
		grid, walk = grid + Count(D.AreaGrid and D.AreaGrid[inst]), walk + Count(D.Walk and D.Walk[inst])
	end
	local P = D.Places or {}
	print(string.format("  maps %d, tiles %d, area grid tiles %d, walk tiles %d, sea maps %d",
		Count(D.Tiles and D.Tiles.maps), tiles, grid, walk, Count(D.Sea and D.Sea.maps)))
	print(string.format("  uiMaps %d, areas %d, flight points %d, taxi paths %d, POIs %d, dungeons %d, item icons %d",
		Count(D.UiMaps), Count(D.Areas), Count(P.flight), #(P.taxiPaths or {}), Count(P.pois), Count(P.dungeons),
		Count(D.ItemIcons)))
	if D.Npcs then
		print(string.format("  QuestieDB data: npcs %d, objects %d, items %d, quests %d", Count(D.Npcs),
			Count(D.Objects), Count(D.Items), Count(D.Quests)))
	else
		print(RED .. "  QuestieDB data not loaded|r (Data/Npcs, Objects, Items, Quests: tools/gen_questie.py)")
	end
	local _, _, _, inst = UnitPosition("player")
	builds = builds or Builds(inst or 0)
	print("  first use (on the first /mma atlas; anything built earlier shows ~0):")
	for _, line in ipairs(builds) do print(line) end
end)

-- /mma check -------------------------------------------------------------------------------

-- The zone uiMap above a map: dungeon / micro / orphan maps climb to their zone.
local function ZoneMap(id)
	local info = id and C_Map.GetMapInfo(id)
	while info and info.mapType > ZONE and info.parentMapID > 0 do info = C_Map.GetMapInfo(info.parentMapID) end
	return info and info.mapID
end

-- f(col, row) at the spot, or within tol of it (4 ways), equals want.
local function Near(f, col, row, tol, want)
	if f(col, row) == want then return true end
	for _, d in ipairs({ { tol, 0 }, { -tol, 0 }, { 0, tol }, { 0, -tol } }) do
		if f(col + d[1], row + d[2]) == want then return true end
	end
	return false
end

local function AreaName(id) local a = id and Atlas.Area(id); return a and a.name end

-- Results: { kind, ok, atlas, game } (ok nil: info, not counted).
local function R(out, kind, ok, atlas, game)
	out[#out + 1] = { kind = kind, ok = ok, atlas = tostring(atlas), game = tostring(game) }
end

-- Facts at the player's position: cheap enough for the logger. Returns results, inst, col, row.
local function Sample()
	local out = {}
	local north, west, _, inst = UnitPosition("player")
	if not north then
		R(out, "position", nil, "-", "UnitPosition: none here (instance)")
		return out
	end
	local col, row = Atlas.WorldToTile(north, west)
	local best = C_Map.GetBestMapForUnit("player")
	local zoneMap = ZoneMap(best)
	local z = Atlas.ZoneAt(inst, col, row)
	local ZoneAtMap = function(c, r) local zz = Atlas.ZoneAt(inst, c, r); return zz and zz.mapID end
	R(out, "zone map", Near(ZoneAtMap, col, row, TOL.edge, zoneMap),
		z and (z.mapID .. " " .. z.name), zoneMap and (zoneMap .. " " .. C_Map.GetMapInfo(zoneMap).name))

	local ZoneName = function(c, r) local id = Atlas.AreaAt(inst, c, r); return id and AreaName(Atlas.Area(id).zone) end
	local zoneName = ZoneName(col, row)
	R(out, "zone text", Near(ZoneName, col, row, TOL.edge, GetZoneText()), zoneName, GetZoneText())
	R(out, "real zone text", Near(ZoneName, col, row, TOL.edge, GetRealZoneText()), zoneName, GetRealZoneText())

	-- Subzone: the area under you unless it's the zone itself ("" then). Indoors the client may name a WMO area.
	local SubName = function(c, r)
		local id = Atlas.AreaAt(inst, c, r)
		local a = id and Atlas.Area(id)
		return a and (a.zone == id and "" or a.name)
	end
	local sub = GetSubZoneText()
	R(out, IsIndoors() and "subzone (indoors)" or "subzone", Near(SubName, col, row, TOL.edge, sub), SubName(col, row), sub)

	-- uiMap position -> tile vs UnitPosition.
	local pos = best and C_Map.GetPlayerMapPosition(best, "player")
	if pos then
		local i2, c2, r2 = Atlas.MapToTile(best, pos.x, pos.y)
		local d = c2 and Dist(c2, r2, col, row)
		R(out, "MapToTile", i2 == inst and d < TOL.pos, c2 and string.format("%d %.3f %.3f (%s off)", i2, c2, r2, Yd(d)),
			string.format("%d %.3f %.3f", inst, col, row))
	end

	-- Walk grid: standing on the ground means the chunk isn't blocked.
	local gc, gr = math.floor(col * Atlas.Walk.CHUNKS), math.floor(row * Atlas.Walk.CHUNKS)
	local class = Atlas.Walk.Cell(inst, gc, gr)
	if IsFlying() or IsFalling() or UnitOnTaxi("player") then
		R(out, "walk", nil, class, "airborne: not checked")
	elseif IsSwimming() then
		R(out, "walk (swimming)", nil, class, "swimming (2 = deep water)")
	else
		R(out, "walk", class ~= 0, class, "on ground: not blocked (0)")
	end

	-- Target: npc id from its GUID; Atlas knows it, by the same name.
	local guid = UnitGUID("target")
	local unitType, _, _, _, _, npcID = strsplit("-", guid or "")
	if unitType == "Creature" or unitType == "Vehicle" then
		local npc = Atlas.Npc(tonumber(npcID))
		R(out, "target npc", npc and npc.name == UnitName("target"), npc and (npc.id .. " " .. npc.name) or (npcID .. " none"),
			npcID .. " " .. UnitName("target"))
	end
	return out, inst, col, row, best
end

-- uiMap rects: Atlas.MapRect vs the client's corners, for the best map and its parents.
local function Rects(out, best)
	local id = best
	while id and id > 0 do
		local rect = Atlas.MapRect(id)
		local i0, v0 = C_Map.GetWorldPosFromMapPos(id, CreateVector2D(0, 0))
		local _, v1 = C_Map.GetWorldPosFromMapPos(id, CreateVector2D(1, 1))
		if v0 then
			local c0, r0 = Atlas.WorldToTile(v0.x, v0.y)
			local c1, r1 = Atlas.WorldToTile(v1.x, v1.y)
			local game = string.format("%d %.3f %.3f %.3f %.3f", i0, c0, r0, c1, r1)
			if rect then
				local d = math.max(Dist(rect.col0, rect.row0, c0, r0), Dist(rect.col1, rect.row1, c1, r1))
				R(out, "MapRect " .. id, rect.inst == i0 and d < TOL.rect, string.format("%d %.3f %.3f %.3f %.3f (%s off)",
					rect.inst, rect.col0, rect.row0, rect.col1, rect.row1, Yd(d)), game)
			else
				R(out, "MapRect " .. id, false, "none", game)
			end
		end
		id = C_Map.GetMapInfo(id).parentMapID
	end
end

-- Flight points: the client's nodes on the continent map vs Atlas.FlightPoints (by nodeID).
local function Flights(out, inst)
	local continent = Atlas.Continent(inst)
	if not continent then return end
	local atlas = {}
	for _, f in ipairs(Atlas.FlightPoints(inst)) do atlas[f.id] = f end
	local nodes, ok = C_TaxiMap.GetTaxiNodesForMap(continent) or {}, 0
	for _, n in ipairs(nodes) do
		local f = atlas[n.nodeID]
		local _, c, r = Atlas.MapToTile(continent, n.position.x, n.position.y)
		local d = f and Dist(f.col, f.row, c, r)
		if f and f.name == n.name and d < TOL.taxi then
			ok = ok + 1
		else
			R(out, "flight " .. n.nodeID, false, f and string.format("%s %.3f %.3f (%s off)", f.name, f.col, f.row, Yd(d)) or "none",
				string.format("%s %.3f %.3f", n.name, c, r))
		end
		atlas[n.nodeID] = nil
	end
	R(out, "flight points", ok == #nodes, ok .. " of " .. #nodes .. " match", #nodes .. " on map " .. continent)
	R(out, "flight points (Atlas only)", nil, Count(atlas), "other faction or not on this map")
end

local function Show(r)
	local tag = r.ok == nil and GREY .. "INFO|r" or r.ok and GREEN .. "PASS|r" or RED .. "FAIL|r"
	print(string.format("  %s %s: atlas %s | game %s", tag, r.kind, r.atlas, r.game))
end

-- The logger --------------------------------------------------------------------------------

local db       -- MagicMapAtlasDB.validation: { on, samples, counts = { kind = n }, log = { entry, ... }, dropped }
local timer
local seen = {} -- kind|atlas|game|chunk logged this session: log each once per place

local function Log()
	local results, inst, col, row = Sample()
	db.samples = db.samples + 1
	if not col then return end
	for _, r in ipairs(results) do
		if r.ok == false then
			db.counts[r.kind] = (db.counts[r.kind] or 0) + 1
			local key = table.concat({ r.kind, r.atlas, r.game, math.floor(col * 16), math.floor(row * 16) }, "|")
			if not seen[key] then
				seen[key] = true
				if #db.log < MAX_LOG then
					db.log[#db.log + 1] = { t = time(), inst = inst, col = math.floor(col * 1000 + 0.5) / 1000,
						row = math.floor(row * 1000 + 0.5) / 1000, kind = r.kind, atlas = r.atlas, game = r.game }
				else
					db.dropped = (db.dropped or 0) + 1
				end
			end
		end
	end
end

local function Start() timer = Runtime.Every(EVERY, "validate.log", Log) end

local function Clear()
	db.samples, db.counts, db.log, db.dropped = 0, {}, {}, 0
	seen = {}
end

Game.Load("validation", function(saved)
	db = saved
	if not db.log then Clear() end
	if db.on then Start() end
end)

local function Report()
	Game.Print(string.format("validation log: %s, %d samples, %d logged (%d over the cap)",
		db.on and "on" or "off", db.samples, #db.log, db.dropped))
	local kinds = {}
	for kind, n in pairs(db.counts) do kinds[#kinds + 1] = { kind, n } end
	table.sort(kinds, function(a, b) return a[2] > b[2] end)
	for _, k in ipairs(kinds) do print(string.format("  %-20s %5d failing samples", k[1], k[2])) end
	-- The commonest pairs: what Atlas said vs the game, over places.
	local byPair, list = {}, {}
	for _, e in ipairs(db.log) do
		local key = e.kind .. ": atlas " .. e.atlas .. " | game " .. e.game
		if not byPair[key] then byPair[key] = { key, 0, e }; list[#list + 1] = byPair[key] end
		byPair[key][2] = byPair[key][2] + 1
	end
	table.sort(list, function(a, b) return a[2] > b[2] end)
	for i = 1, math.min(10, #list) do
		local p = list[i]
		print(string.format("  x%-4d %s  (e.g. inst %d %.2f %.2f)", p[2], p[1], p[3].inst, p[3].col, p[3].row))
	end
end

Game.Slash("check", "Atlas vs the client here; check log | report | clear", function(args)
	if args == "log" then
		db.on = not db.on
		if db.on then Start() else Runtime.Cancel(timer) end
		Game.Print("validation log " .. (db.on and "on: every " .. EVERY .. " s" or "off"))
	elseif args == "report" then
		Report()
	elseif args == "clear" then
		Clear()
		Game.Print("validation log cleared")
	else
		local out, inst, col, row, best = Sample()
		if col then
			Game.Print(string.format("check at inst %d, %.3f %.3f (best map %s)", inst, col, row, tostring(best)))
			Rects(out, best)
			Flights(out, inst)
		end
		local fails = 0
		for _, r in ipairs(out) do
			Show(r)
			if r.ok == false then fails = fails + 1 end
		end
		Game.Print(fails == 0 and GREEN .. "all pass|r" or RED .. fails .. " failing|r")
	end
end)
