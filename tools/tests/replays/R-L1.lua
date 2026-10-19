-- L1: quest areas drawn offset and squashed: the client draws a blob into its frame's rect as
-- it stood at DrawBlob, and lays a moved frame out only at the frame's end. MOVED (into Game's
-- sensor: Inside(quest, col, row) hit-tests the client's blobs), and bounded there: each quest on
-- a hidden QuestPOI frame of its own that never moves, drawn when first asked (nil: can't tell
-- yet) and again the next frame, into its rect. From then on right whatever the map does (a zoom,
-- a pan), where areas overlap too, drawn again only after QUEST_POI_UPDATE; 27 quests asked twice
-- each in ≤ 2 ms a frame (CALL_MS). Model asks through the oracles Game hands it; the quests come
-- from obs.quests (areaMap, pin), as game/parts/Quests.lua hands them. Then /mma check inside.
local T = ...
local sim, ns = T.Shown()
local A, Game, Model, Runtime = ns.Atlas, ns.Game, ns.Model, ns.Runtime
local MAP, R = 1429, 0.06 -- Elwynn; each area a circle (Sim.blobShapes, normalized)

local quests, probes, want, early = {}, {}, {}, {}
local function Quest(id, x, y, shape)
	sim.blobShapes[id] = shape
	local inst, col, row = A.MapToTile(MAP, x, y)
	quests[#quests + 1] = { id = id, title = "Quest " .. id, complete = false, followed = false, objectives = {},
		areaMap = MAP, pin = { inst = inst, col = col, row = row } }
end
local function Probe(id, x, y, answer)
	local _, col, row = A.MapToTile(MAP, x, y)
	probes[#probes + 1] = { id, col, row }
	want[#want + 1] = answer == nil and "-" or answer and "1" or "0"
	early[#early + 1] = id == 1001 and want[#want] or "-"
end
for i = 1, 25 do
	local x, y = 0.1 + (i - 1) % 5 * 0.2, 0.1 + math.floor((i - 1) / 5) * 0.2
	Quest(1000 + i, x, y, { x, y, R })
	Probe(1000 + i, x, y, true)
	Probe(1000 + i, x + 1.5 * R, y, false)
end
Quest(2000, 0.1, 0.1, nil) -- the game draws it no area: its pin is in 1001's, on another frame
Probe(2000, 0.1, 0.1, nil)
Quest(2001, 0.1 + R, 0.1, { 0.1 + R, 0.1, R }) -- overlapping 1001's
Probe(2001, 0.1 + 0.5 * R, 0.1, true)
Probe(1001, 0.1 + 0.5 * R, 0.1, true)
Probe(3000, 0.5, 0.5, nil) -- not in the log
want, early = table.concat(want), table.concat(early)

Game.Part("quests", function() return quests end) -- on change only: the same table, nothing new
local log, asking = {}, false
Model.Part(function(_, oracles)
	if not asking then return end
	local got, t0, draws = {}, debugprofilestop(), sim.calls.DrawBlob or 0
	for i, p in ipairs(probes) do
		local answer = oracles.Inside(p[1], p[2], p[3])
		got[i] = answer == nil and "-" or answer and "1" or "0"
	end
	log[#log + 1] = { got = table.concat(got), ms = debugprofilestop() - t0, draws = (sim.calls.DrawBlob or 0) - draws }
end)
asking = true
local function Frames(n)
	local from = #log + 1
	for _ = 1, n do sim.Step() end
	return log[from], log[#log]
end

-- Model asked the sim's quest 60 before this log took its place: 1001, first asked, takes the frame
-- 60 left, laid out already, so it answers at once; every other quest nil until drawn again.
local first, second = Frames(2)
T.Print("L1: first frame %s (%d drawn), next %s (%d drawn)", first.got, first.draws, second.got, second.draws)
assert(first.got == early and first.draws == 27, "nil before layout: " .. first.got .. " (want " .. early .. ")")
assert(second.got == want and second.draws == 26, "right after: " .. second.got .. " (want " .. want .. ")")
local _, still = Frames(5)
assert(still.got == want and still.draws == 0, "cached per quest")

local mark = #log
sim.Wheel(ns.UI.Window.view, 1) -- the map zooms and pans: Game's frames don't move
sim.Run(0.3)
sim.Drag(ns.UI.Window.view, 120, -80)
sim.Run(0.3)
assert(#log > mark + 30)
for i = mark + 1, #log do assert(log[i].got == want and log[i].draws == 0, "a zoom and a pan change nothing") end

sim.FireEvent("QUEST_POI_UPDATE")
local redrawn, after = Frames(3)
assert(redrawn.got == want and redrawn.draws == 27 and after.draws == 0, "drawn again once after QUEST_POI_UPDATE, right at once")

local slowest = 0
for _, f in ipairs(log) do slowest = math.max(slowest, f.ms) end
T.Print("L1: %d frames, slowest %.3f ms for %d asks", #log, slowest, #probes)
assert(slowest <= Runtime.CALL_MS)

-- Unseen: under a holder at alpha 0, never taking the mouse.
for _, f in ipairs(sim.Frames()) do
	if f:GetObjectType() == "QuestPOIFrame" then assert(f:GetEffectiveAlpha() == 0 and not f:IsMouseEnabled()) end
end

-- /mma check inside, standing in quest 60's area (the sim's log: 60 in progress, 62 to turn in).
asking = false
local p = sim.player
local px, py = A.TileToMap(MAP, p.col, p.row)
sim.blobShapes[60] = { 0.35, 0.55, math.sqrt((px - 0.35) ^ 2 + (py - 0.55) ^ 2) + 0.02 } -- its pin and you
sim.prints = {}
sim.Slash("/mma check inside")
sim.Run(0.1)
local out = table.concat(sim.prints, "\n")
T.Print("%s", out)
assert(out:find("2 quests here") and out:find("inside|r  Kobold Candles (60, map 1429)", 1, true)
	and out:find("no area|r  The Fargodeep Mine (62, map 1429)", 1, true), out)
local errs = T.Errors(sim, ns)
assert(#errs == 0, table.concat(errs, "\n"))
