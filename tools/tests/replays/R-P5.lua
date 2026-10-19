-- P5: quest areas lagged and drifted while zooming: the client's blob art doesn't follow a scaled
-- canvas. PREVENTED as the spike's 1.0 does it (Layers.lua:2032-2043): UI's areas (ui/Areas.lua) are
-- out of sight while the zoom moves, laid out where it's headed once the wheel stops, and shown again
-- only once each is drawn twice (as laid out, and the next frame: L1) at the zoom it lands at. So each
-- frame a quest's area is unseen, or drawn on its pin (within 1 px); Game's sensor frames, never seen.
-- A quest whose area is a circle about its pin (Sim.blobShapes), 8 wheel notches in over 0.5 s, then
-- 4 out, following you.
local T = ...
local sim, ns = T.Shown()
local S, Areas, view = sim.state, ns.UI.Areas.layer, ns.UI.Window.view
local X, Y = 0.35, 0.55 -- quest 60's pin on Elwynn (the sim's log)
sim.blobShapes[60] = { X, Y, 0.04 }

local function OnMap(f)
	while f and f ~= view do f = f:GetParent() end
	return f == view
end
local function Pin()
	local p = T.Layer(ns, "quests").front.pools.pin
	return p[p.at["quest:60"]]
end

-- Each frame: seen (the areas' frame and the blob's), and how far its circle's centre is from the pin's.
local frames, seen, worst, zoomed = 0, 0, 0, 0
local function Check(z)
	frames = frames + 1
	for _, f in ipairs(sim.Frames()) do
		if f:GetObjectType() == "QuestPOIFrame" and not OnMap(f) then assert(f:GetEffectiveAlpha() == 0, "Game's: unseen") end
	end
	local p = Areas.front and Areas.front.pools.blob
	local f = p and p[1]
	local d = f and S[f].blobs and S[f].blobs[60]
	if not (d and f:GetEffectiveAlpha() > 0 and f:IsVisible()) then return end
	assert(ns.UI.Camera.cam.zoom == z, "unseen while the zoom moves")
	seen = seen + 1
	local l, b, w, h = sim.Rect(Pin())
	local off = math.max(math.abs(d[1] + X * d[3] - (l + w / 2)), math.abs(d[2] + (1 - Y) * d[4] - (b + h / 2)))
	worst = math.max(worst, off)
	assert(off <= 1, string.format("frame %d: the area %.2f px off its pin", frames, off))
end

local function Frames(n)
	for _ = 1, n do
		local z = ns.UI.Camera.cam.zoom
		sim.Step()
		if ns.UI.Camera.cam.zoom ~= z then zoomed = zoomed + 1 end
		Check(z)
	end
end
Frames(2)
assert(seen == 2, "shown at rest, on its pin")
for _ = 1, 8 do
	sim.Wheel(view, 1)
	Frames(4)
end
Frames(60)
for _ = 1, 4 do
	sim.Wheel(view, -1)
	Frames(2)
end
Frames(60)
T.Print("P5: %d frames, the zoom moving in %d, the area seen in %d, at most %.3f px off its pin", frames, zoomed, seen, worst)
assert(zoomed > 30 and seen > 60, "seen at rest")
local errs = T.Errors(sim, ns)
assert(#errs == 0, table.concat(errs, "\n"))
