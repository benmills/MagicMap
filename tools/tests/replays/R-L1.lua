-- L1: quest areas drawn offset and squashed: the client draws a blob into its frame's rect as
-- it stood at DrawBlob, and lays a moved frame out only at the frame's end. MOVED (into Game's
-- sensor: Inside(quest, col, row) hit-tests the client's blobs), and bounded there: each quest on
-- a hidden QuestPOI frame of its own that never moves, drawn when first asked (nil: can't tell
-- yet) and again the next frame, into its rect. From then on right whatever the map does (a zoom,
-- a pan), where areas overlap too, drawn again only after QUEST_POI_UPDATE; 27 quests asked twice
-- each in ≤ 2 ms a frame (CALL_MS). Model asks through the oracles Game hands it; the quests come
-- from obs.quests (areaMap, pin), as game/parts/Quests.lua hands them. Then UI's (M2.4: ui/Areas.lua):
-- the same areas drawn on the map, one frame a map and style, each drawn as it's laid out and again the
-- next frame, the layer shown only then, every quest's blob in the rect its frame is laid out in; out of
-- sight while a zoom moves, the same where it lands. Then /mm check inside.
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
	early[#early + 1] = "-"
end
for i = 1, 25 do
	local x, y = 0.1 + (i - 1) % 5 * 0.2, 0.1 + math.floor((i - 1) / 5) * 0.2
	Quest(1000 + i, x, y, { x, y, R })
	Probe(1000 + i, x, y, true)
	Probe(1000 + i, x + 1.5 * R, y, false)
end
Quest(2000, 0.1, 0.1, nil) -- the game draws it no area: false, though its pin is in 1001's (another frame)
Probe(2000, 0.1, 0.1, false)
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

-- Nothing asked before this log: every quest nil on the first frame (each drawn now, laid out at the
-- frame's end), and right on the next.
local first, second = Frames(2)
T.Print("L1: first frame %s (%d drawn), next %s (%d drawn)", first.got, first.draws, second.got, second.draws)
assert(first.got == early and first.draws == 27, "nil before layout: " .. first.got .. " (want " .. early .. ")")
assert(second.got == want and second.draws == 27, "right after: " .. second.got .. " (want " .. want .. ")")
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

-- Game's unseen: under a holder at alpha 0, never taking the mouse (UI's, on the map: never the mouse).
local view = ns.UI.Window.view
local function OnMap(f)
	while f and f ~= view do f = f:GetParent() end
	return f == view
end
for _, f in ipairs(sim.Frames()) do
	if f:GetObjectType() == "QuestPOIFrame" then assert((OnMap(f) or f:GetEffectiveAlpha() == 0) and not f:IsMouseEnabled()) end
end

-- UI's: one frame for the 27 (a map, a style), each quest's blob drawn into its rect as laid out whenever
-- the layer shows: after the pan above (a drawing moves with its frame), and out of sight from the wheel
-- till the zoom lands, drawn twice there.
local S, Areas = sim.state, ns.UI.Areas.layer
local function Right()
	local p, n = Areas.front.pools.blob, 0
	for i = 1, p.n do
		local laid = S[p[i]].laid
		for _, d in pairs(S[p[i]].blobs or {}) do
			n = n + 1
			if not (laid and d[1] == laid[1] and d[2] == laid[2] and d[3] == laid[3] and d[4] == laid[4]) then return false, n end
		end
	end
	return true, n
end
assert(Right(), "a pan: drawn where it's laid out")
local draws, hid, back = sim.calls.DrawBlob, 0, nil
sim.Wheel(view, 1)
sim.cursorX, sim.cursorY = 0, 0 -- (off the map: no area lit, drawn again on top)
for i = 1, 60 do
	sim.Step()
	if Areas.frame:GetAlpha() > 0 then
		back = back or i
		assert(Right(), "shown: drawn where it's laid out")
	else
		hid = hid + 1
	end
end
local ok, n = Right()
T.Print("L1 (UI): out of sight %d frames of a zoom, shown again at frame %d, %d draws", hid, back, sim.calls.DrawBlob - draws)
assert(back and hid == back - 1 and ok and n == 27 and Areas.front.pools.blob.n == 1, "one frame, the 27, right")
assert(sim.calls.DrawBlob - draws == 2 * 27, "drawn twice where it lands")

-- /mm check inside, standing in quest 60's area (the sim's log: 60 in progress, 62 to turn in).
asking = false
local p = sim.player
local px, py = A.TileToMap(MAP, p.col, p.row)
sim.blobShapes[60] = { 0.35, 0.55, math.sqrt((px - 0.35) ^ 2 + (py - 0.55) ^ 2) + 0.02 } -- its pin and you
local n = #sim.prints
sim.Slash("/mm check inside")
sim.Run(0.1)
local out = table.concat(sim.prints, "\n", n + 1)
T.Print("%s", out)
assert(out:find("2 quests here") and out:find("inside|r  Kobold Candles (60, map 1429)", 1, true)
	and out:find("no area at its pin|r  The Fargodeep Mine (62, map 1429)", 1, true), out)
local errs = T.Errors(sim, ns)
assert(#errs == 0, table.concat(errs, "\n"))
