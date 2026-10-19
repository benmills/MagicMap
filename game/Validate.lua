-- Validate Atlas against the live client where you stand: stale Data (K4) shows as FAILs.
-- What holds offline is tools/tests/test_atlas.py's; load cost is /mma perf load's.
--   /mma check         Atlas vs the client here: PASS / FAIL per fact, and (on demand only, not
--                      logged) the map rects up from here and the continent's flight points
--   /mma check log     toggle logging mismatches every 2 s as you travel (MagicMapAtlasDB.validation);
--                      the log is this build's: another build's is cleared at load
--   /mma check report  the log, by kind;  /mma check clear  empties it
-- Both judge alike (Sample): the client not knowing yet, or a WMO's own subzone, is info, not drift.

local ADDON, ns = ...
local Atlas, Runtime, Game = ns.Atlas, ns.Runtime, ns.Game

local YD = 1 / Atlas.TILE_YARDS -- one yard in tiles
local TOL = {
	edge = 5 * YD, -- area / zone: the client's answer within 5 yd counts (chunk edges, ~33 yd chunks)
	pos = 3 * YD,  -- map position -> tile vs UnitPosition
	rect = 1 * YD,  -- map rect corners (Data rounds to ~0.5 yd)
	taxi = 20 * YD, -- flight point on the continent map vs TaxiNodes
}
local EVERY, MAX_LOG = 2, 1000 -- logger: seconds per sample, entries kept
local VERSION = C_AddOns.GetAddOnMetadata(ADDON, "Version") -- the build's (tools/install.py stamps it)
local ZONE = Enum.UIMapType.Zone
local GREEN, RED, GREY = "|cff60ff60", "|cffff6060", "|cff999999"

local function Dist(c1, r1, c2, r2) return math.sqrt((c1 - c2) ^ 2 + (r1 - r2) ^ 2) end
local function Yd(d) return string.format("%.1f yd", d / YD) end

local function Count(t)
	local n = 0
	for _ in pairs(t or {}) do n = n + 1 end
	return n
end

-- /mma check -------------------------------------------------------------------------------

-- The client's map info, once a map (the client makes a table each call).
local infos = {}
local function Info(id)
	local i = infos[id]
	if i == nil then
		i = C_Map.GetMapInfo(id) or false
		infos[id] = i
	end
	return i or nil
end

-- The zone uiMap above a map: dungeon / micro / orphan maps climb to their zone.
local function ZoneMap(id)
	local info = id and Info(id)
	while info and info.mapType > ZONE and info.parentMapID > 0 do info = Info(info.parentMapID) end
	return info and info.mapID
end

-- f(col, row) at the spot, or within tol of it (4 ways), equals want.
local AROUND = { 1, 0, -1, 0, 0, 1, 0, -1 }
local function Near(f, col, row, tol, want)
	if f(col, row) == want then return true end
	for i = 1, #AROUND, 2 do
		if f(col + AROUND[i] * tol, row + AROUND[i + 1] * tol) == want then return true end
	end
	return false
end

-- What Atlas says at (c, r) on the instance sampled (inst): the zone's uiMap, the zone's name, the
-- subzone's ("" where the area is the zone itself).
local inst
local function ZoneMapAt(c, r)
	local id = Atlas.AreaAt(inst, c, r)
	local a = id and Atlas.Area(id)
	return a and Atlas.Area(a.zone).uiMap
end
local function ZoneName(c, r)
	local id = Atlas.AreaAt(inst, c, r)
	return id and Atlas.Area(Atlas.Area(id).zone).name
end
local function SubName(c, r)
	local id = Atlas.AreaAt(inst, c, r)
	local a = id and Atlas.Area(id)
	return a and (a.zone == id and "" or a.name)
end
local function MapName(id)
	local m = id and Atlas.UiMap(id)
	return m and (id .. " " .. m.name) or id
end

-- Results: { kind, ok, atlas, game } (ok nil: info, not counted), in rows every sample reuses: the
-- logger samples every 2 s all session, so one makes next to nothing (a sample made ~8 KB, the
-- logger 3.4 KB/s of garbage in sessions #13-#22). A row lasts until the next sample.
local out, rows = {}, {}
local function Unless(no, ok) if no then return nil end return ok end
local function R(kind, ok, atlas, game)
	local n = #out + 1
	local r = rows[n] or {}
	rows[n], out[n] = r, r
	r.kind, r.ok, r.atlas, r.game = kind, ok, tostring(atlas), tostring(game)
end

-- Facts at the player's position: cheap enough for the logger. Returns results, inst, col, row, best.
-- verbose: what passed is written out too (/mma check's), else only what failed.
local function Sample(verbose)
	wipe(out)
	local north, west, _, i = UnitPosition("player")
	if not north then
		R("position", nil, "-", "UnitPosition: none here (instance)")
		return out
	end
	inst = i
	local col, row = Atlas.WorldToTile(north, west)
	local best = C_Map.GetBestMapForUnit("player")
	local zoneMap = ZoneMap(best)
	-- The client not knowing yet (entering a zone, or at login: its text "", its best map the continent)
	-- is no answer: info, not a mismatch (sessions #8, #9 in Orgrimmar).
	local mapKnown = zoneMap and Info(zoneMap).mapType >= ZONE
	R("zone map", Unless(not mapKnown, Near(ZoneMapAt, col, row, TOL.edge, zoneMap)), MapName(ZoneMapAt(col, row)),
		zoneMap and (zoneMap .. " " .. Info(zoneMap).name))

	local zoneName = ZoneName(col, row)
	local text, real = GetZoneText(), GetRealZoneText()
	R("zone text", Unless((text or "") == "", Near(ZoneName, col, row, TOL.edge, text)), zoneName, text)
	R("real zone text", Unless((real or "") == "", Near(ZoneName, col, row, TOL.edge, real)), zoneName, real)

	-- Subzone: the area under you unless it's the zone itself ("" then). Where the terrain's chunk is the
	-- zone and the client names a subzone, it's a WMO's own area (a city's: Orgrimmar's Valley of
	-- Strength; indoors, a building's), which terrain chunks don't carry: info, not drift.
	local sub, ours = GetSubZoneText(), SubName(col, row)
	R(IsIndoors() and "subzone (indoors)" or "subzone", Unless(ours == "" and sub ~= "", Near(SubName, col, row, TOL.edge, sub)),
		ours, sub)

	-- uiMap position -> tile vs UnitPosition.
	local pos = best and C_Map.GetPlayerMapPosition(best, "player")
	if pos then
		local i2, c2, r2 = Atlas.MapToTile(best, pos.x, pos.y)
		local d = c2 and Dist(c2, r2, col, row)
		local ok = i2 == inst and d < TOL.pos
		if verbose or not ok then
			R("MapToTile", ok, c2 and string.format("%d %.3f %.3f (%s off)", i2, c2, r2, Yd(d)),
				string.format("%d %.3f %.3f", inst, col, row))
		else
			R("MapToTile", ok, "", "")
		end
	end

	-- Walk grid: standing on the ground means the chunk isn't blocked.
	local gc, gr = math.floor(col * Atlas.Walk.CHUNKS), math.floor(row * Atlas.Walk.CHUNKS)
	local class = Atlas.Walk.Cell(inst, gc, gr)
	if IsFlying() or IsFalling() or UnitOnTaxi("player") then
		R("walk", nil, class, "airborne: not checked")
	elseif IsSwimming() then
		R("walk (swimming)", nil, class, "swimming (2 = deep water)")
	else
		R("walk", class ~= 0, class, "on ground: not blocked (0)")
	end

	-- Target: npc id from its GUID; Atlas knows it, by the same name.
	local guid = UnitGUID("target")
	local unitType, _, _, _, _, npcID = strsplit("-", guid or "")
	if unitType == "Creature" or unitType == "Vehicle" then
		local npc = Atlas.Npc(tonumber(npcID))
		R("target npc", npc and npc.name == UnitName("target"), npc and (npc.id .. " " .. npc.name) or (npcID .. " none"),
			npcID .. " " .. UnitName("target"))
	end
	return out, inst, col, row, best
end

-- uiMap rects: Atlas.MapRect vs the client's corners, for the best map and its parents.
local function Rects(best)
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
				R("MapRect " .. id, rect.inst == i0 and d < TOL.rect, string.format("%d %.3f %.3f %.3f %.3f (%s off)",
					rect.inst, rect.col0, rect.row0, rect.col1, rect.row1, Yd(d)), game)
			else
				R("MapRect " .. id, false, "none", game)
			end
		end
		id = Info(id).parentMapID
	end
end

-- Flight points: the client's nodes on the continent map vs Atlas.FlightPoints (by nodeID).
local function Flights(inst)
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
			R("flight " .. n.nodeID, false, f and string.format("%s %.3f %.3f (%s off)", f.name, f.col, f.row, Yd(d)) or "none",
				string.format("%s %.3f %.3f", n.name, c, r))
		end
		atlas[n.nodeID] = nil
	end
	R("flight points", ok == #nodes, ok .. " of " .. #nodes .. " match", #nodes .. " on map " .. continent)
	R("flight points (Atlas only)", nil, Count(atlas), "other faction or not on this map")
end

local function Show(r)
	local tag = r.ok == nil and GREY .. "INFO|r" or r.ok and GREEN .. "PASS|r" or RED .. "FAIL|r"
	print(string.format("  %s %s: atlas %s | game %s", tag, r.kind, r.atlas, r.game))
end

-- The logger --------------------------------------------------------------------------------

local db       -- MagicMapAtlasDB.validation: { on, version, samples, counts = { kind = n }, log = { entry, ... }, dropped }
local timer
local seen = {} -- kind|atlas|game|chunk logged this session: log each once per place

local function Log()
	local results, at, col, row = Sample()
	db.samples = db.samples + 1
	if not col then return end
	for _, r in ipairs(results) do
		if r.ok == false then
			db.counts[r.kind] = (db.counts[r.kind] or 0) + 1
			local key = table.concat({ r.kind, r.atlas, r.game, math.floor(col * 16), math.floor(row * 16) }, "|")
			if not seen[key] then
				seen[key] = true
				if #db.log < MAX_LOG then
					db.log[#db.log + 1] = { t = time(), inst = at, col = math.floor(col * 1000 + 0.5) / 1000,
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

-- The log is one build's: what another logged (before a fix to what counts as drift, or to Data) would
-- read as this one's (sessions #13-#22 showed e50e7d5's empty log under earlier builds' Valley of Strength).
Game.Load("validation", function(saved)
	db = saved
	if db.version ~= VERSION then
		Clear()
		db.version = VERSION
	end
	if db.on then Start() end
end, { version = 2, defaults = { on = false, version = "", samples = 0, counts = {}, log = {}, dropped = 0 } })

local function Report()
	Game.Print(string.format("validation log (build %s): %s, %d samples, %d logged (%d over the cap)",
		db.version, db.on and "on" or "off", db.samples, #db.log, db.dropped))
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
		local results, at, col, row, best = Sample(true)
		if col then
			Game.Print(string.format("check at inst %d, %.3f %.3f (best map %s)", at, col, row, tostring(best)))
			Rects(best)
			Flights(at)
		end
		local fails = 0
		for _, r in ipairs(results) do
			Show(r)
			if r.ok == false then fails = fails + 1 end
		end
		Game.Print(fails == 0 and GREEN .. "all pass|r" or RED .. fails .. " failing|r")
	end
end)
