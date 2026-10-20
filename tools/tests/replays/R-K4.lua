-- K4: Data/ goes stale between Forever builds. CONTAINED: game/Validate.lua compares Atlas with the
-- live client as you travel (/mm check log: a sample every 2 s) and logs the mismatches. The logger
-- judges as /mm check does (one Sample): in Orgrimmar, the login moment before the client knows the
-- zone (zone text "", real zone text nil, best map the continent) and a city WMO's own subzone (Valley
-- of Strength, outdoors and indoors: terrain chunks don't carry it) are info, not drift (9eb08fe). A real
-- mismatch is still logged; the log is one build's (the earlier builds' Valley of Strength read as
-- e50e7d5's in sessions #13-#22); a sample makes next to nothing (8 KB each, all session, before).
local T = ...
local SAVED = "MagicMap2DB.validation = { _v = %d, on = true, version = %q, samples = 9, counts = { subzone = 5 },"
	.. " log = { { t = 1, inst = 1, col = 40.09, row = 28.853, kind = 'subzone', atlas = '', game = 'Valley of Strength' } },"
	.. " dropped = 0 }"
local sim, ns = T.Boot(T.TEST_UI .. "; " .. string.format(SAVED, 1, "cd0c82c"))
local db = MagicMap2DB.validation
assert(db.version == "unstamped" and #db.log == 0 and next(db.counts) == nil and db.samples == 0 and db.on,
	"another build's log is cleared at load, logging left on")

-- Orgrimmar as the client has it (the sim's maps made Atlas's), you in the Valley of Strength (the log's spot).
for _, id in ipairs({ 1414, 1411, 1454 }) do
	local r, m = ns.Atlas.MapRect(id), ns.Atlas.UiMap(id)
	sim.maps[id] = { m.name, m.mapType, m.parent, r.inst, r.col0, r.row0, r.col1, r.row1 }
end
sim.player.inst, sim.player.col, sim.player.row = 1, 40.09, 28.853
sim.subzone, sim.indoors = "Valley of Strength", false
local zoneText, realText, best = GetZoneText, GetRealZoneText, C_Map.GetBestMapForUnit

-- The login moment: the client doesn't know the zone yet.
GetZoneText, GetRealZoneText = function() return "" end, function() return nil end
C_Map.GetBestMapForUnit = function() return 1414 end
sim.Run(4.5)
GetZoneText, GetRealZoneText, C_Map.GetBestMapForUnit = zoneText, realText, best
-- Then known: walking the valley outdoors, and indoors. What a sample makes, from the second on (the
-- first fills caches), the sim's API apart (its map calls and strsplit make tables; the client's, a vector).
local mock, k0 = 0, 0
local function Done(...) mock = mock + collectgarbage("count") - k0; return ... end
local function Free(fn) return function(...) k0 = collectgarbage("count"); return Done(fn(...)) end end
UnitPosition, GetZoneText, GetRealZoneText, strsplit = Free(UnitPosition), Free(zoneText), Free(realText), Free(strsplit)
C_Map.GetBestMapForUnit, C_Map.GetPlayerMapPosition = Free(best), Free(C_Map.GetPlayerMapPosition)
sim.Run(2.5)
local perf = ns.Runtime.Perf()["validate.log"]
collectgarbage("collect"); collectgarbage("stop")
local kb0, n0 = perf.kb, perf.kbN
mock = 0
sim.Run(2)
sim.indoors = true
sim.Run(4.5)
collectgarbage("restart")
local samples, each = db.samples, (perf.kb - kb0 - mock) / (perf.kbN - n0)
assert(samples >= 6 and #db.log == 0 and next(db.counts) == nil,
	string.format("%d samples, %d logged: %s", samples, #db.log, db.log[1] and (db.log[1].kind .. ": " .. db.log[1].game) or ""))
T.Print("K4: %d samples in Orgrimmar, none logged; a sample makes %.0f B (%d measured)", samples, each * 1024, perf.kbN - n0)
assert(perf.kbN - n0 >= 3 and each <= 0.05)
GetZoneText = zoneText

-- /mm check says the same: those facts are INFO, nothing fails.
local n = #sim.prints
sim.Slash("/mm check")
local said = table.concat(sim.prints, "\n", n + 1)
assert(said:find("INFO|r subzone %(indoors%): atlas  | game Valley of Strength") and said:find("all pass"), said)

-- A real mismatch is logged: the client names another zone here.
GetZoneText = function() return "Durotar" end
sim.Run(2.5)
GetZoneText = zoneText
assert(#db.log == 1 and db.log[1].kind == "zone text" and db.log[1].atlas == "Orgrimmar" and db.log[1].game == "Durotar")
assert(#T.Errors(sim, ns) == 0, table.concat(T.Errors(sim, ns), "\n"))

-- This build's log survives a /reload.
sim = T.Boot(T.TEST_UI .. "; " .. string.format(SAVED, 2, "unstamped"))
assert(#MagicMap2DB.validation.log == 1 and MagicMap2DB.validation.counts.subzone == 5)
