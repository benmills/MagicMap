-- The replays' harness T (test_spike_bugs.py; tools/sim.py's harness(), Client.T): T.Boot / T.Shown,
-- sim.load / a shown map, in the replay's own Lua; the rest, the helpers the replays share. T.Print
-- writes to the test's output (the sim's print is chat). Called with the tests' folder, the TOC's
-- files that exist, say, skip and TEST_UI.
local tests, files, say, skip, TEST_UI = ...
local T = { Print = function(...) say(string.format(...)) end, Skip = skip, TEST_UI = TEST_UI }

-- A simulated client with MagicMapAtlas loaded and logged in: Sim, ns.
-- saved: Lua source for the SavedVariables (MagicMapAtlasDB = ...) found at load (default
-- T.TEST_UI: tools/sim.py's window, hidden at login).
-- T.simFrames: the client's own frames, made before ours. On the counted clock (Sim.Counted).
function T.Boot(saved)
	local sim = assert(loadfile(tests .. "/wowsim.lua"))()
	sim.Counted()
	local line = CreateFrame("Frame"):CreateLine() -- (T.Anchors: the class's methods)
	T.simFrames = #sim.Frames()
	local ns = {}
	for _, path in ipairs(files) do -- what exists (test_luacheck flags what's missing)
		local chunk, err = loadfile(path)
		if not chunk then error(err, 0) end
		sim.Call("loading " .. path:match("[^/]+/[^/]+$"), chunk, "MagicMapAtlas", ns)
	end
	assert(loadstring(saved or TEST_UI))()
	T.Anchors(sim, ns, line)
	sim.FireEvent("ADDON_LOADED", "MagicMapAtlas")
	sim.FireEvent("PLAYER_LOGIN")
	sim.FireEvent("PLAYER_ENTERING_WORLD", true, false)
	local step = sim.Step
	sim.Step = function(elapsed)
		step(elapsed)
		T.Invariants(sim, ns)
	end
	return sim, ns
end

-- The map's anchors under its view, checked as they're set (SetPoint, a region's and a frame's: the
-- canvases; Line:SetStartPoint and SetEndPoint): no offset past LIMIT px (the tear's suspect,
-- docs/v1-plan.md §2), a scaled frame's (its offsets are in its own units) times its scale: what it
-- moves on the screen, and the client's error with it. Not the sockets' (ui/Sockets.lua: Game hosts
-- other addons' pins on them, tile (0, 0) at their TOPLEFT, up to ~51,000 px at zoom 800; a pin far
-- from the view stays far whatever the origin: hosting fewer, near the view, is M4.2's continent
-- filter and M4.4's; the minimap socket's around you), nor a held canvas scaled past 1.4 (Engine's
-- BAND_HI): a layout from further out while the zoom comes in (borders, a crossfade's old canvas), its
-- origin's offset growing with its scale until it's laid out again (R-P1: 35,034 px at 45x, the wheel's
-- 16 notches in from 16 after a flick out about a corner), as the spike's PlaceCanvas (Layers.lua:142-156),
-- the client's error still a thousandth of a pixel there (the ground's, past 1.4 while a zoom in
-- outruns its layout, is held to the limit: 2,869 px at most, 2.3x, in R-P1). And no
-- texture, mask or line on the map snapping to the pixel grid (the map moves by fractions of a pixel;
-- font strings excepted: docs/v1-plan.md M1 exit). line: a Line, for its class's methods. (The checks
-- here and in T.Invariants make no garbage and no widget calls: R-P3 measures our frames.)
local LIMIT = 4096
local UNSNAPPED = { Texture = true, MaskTexture = true, Line = true }
local held = {} -- a held layer's canvases (Engine's "hold")
function T.Anchors(sim, ns, line)
	local S, view, socket, mini = sim.state, ns.UI.Window.view, ns.UI.Sockets.world.frame, ns.UI.Sockets.minimap.frame
	for _, l in ipairs(ns.UI.Engine.layers) do
		if l.zoom == "hold" then
			for _, c in ipairs(l.canvases) do held[c] = true end
		end
	end
	local function Check(o, what, x, y)
		local p = o
		while p and p ~= view and p ~= socket and p ~= mini do p = S[p].parent end
		if p == view and (math.abs(x) > LIMIT or math.abs(y) > LIMIT) then
			error(string.format("%s of %.0f, %.0f px on a %s", what, x, y, S[o].type), 2)
		end
		if p == view and UNSNAPPED[S[o].type] and not (S[o].snap == false and S[o].bias == 0) then
			error(string.format("a %s on the map snaps to the pixel grid", S[o].type), 2)
		end
	end
	local frames, lines = getmetatable(view).__index, getmetatable(line).__index
	for _, m in ipairs({ getmetatable(frames).__index, frames }) do -- (a frame's own: the sim's combat check)
		local setPoint = rawget(m, "SetPoint")
		m.SetPoint = function(self, point, ...)
			setPoint(self, point, ...)
			local k = S[self].scale -- (a region's: 1)
			for _, e in ipairs(S[self].points) do
				if e.point == point and (k <= 1.4 or not held[self]) then Check(self, "an offset", e.x * k, e.y * k) end
			end
		end
	end
	for _, name in ipairs({ "SetStartPoint", "SetEndPoint" }) do
		local fn, key = lines[name], name == "SetStartPoint" and "startPoint" or "endPoint"
		lines[name] = function(self, ...)
			fn(self, ...)
			local e = S[self][key]
			Check(self, "a line's end", e[3], e[4])
		end
	end
end

-- What holds after every frame of every replay (checked as it ends): no protected
-- call made in combat (spike-bugs K2), and no Blizzard Minimap art showing while the takeover
-- has the Minimap (its cluster hidden, or faded while combat keeps it shown; the Minimap itself, ours
-- away from the cluster: unseen, its ground textures off). The map (M1.3, with T.Anchors): a layer shows
-- one canvas at most outside a timed crossfade (D1: drawn twice); at rest (Engine.pending false), every
-- layer shown on the one origin.
-- One pin a thing a frame: on each pin layer shown, no key twice among its shown pins; and no quest both
-- a quest's pin and an offer's (one key each: "quest:<id>"). Tables kept, emptied each frame (no garbage).
local pinKeys = {} -- layer -> { key -> true }
local function OnePin(E, S)
	for _, l in ipairs(E.layers) do
		local seen = pinKeys[l.name]
		if seen then
			for k in pairs(seen) do seen[k] = nil end
		end
		local c = l.zoom == "pin" and l.on and l.front
		local p = c and S[c].alpha > 0 and c.pools.pin
		for i = 1, p and p.n or 0 do
			if S[p[i]].shown then
				if not seen then
					seen = {}
					pinKeys[l.name] = seen
				end
				local key = p.keys[i]
				if seen[key] then error(l.name .. ": " .. key .. " twice in a frame") end
				seen[key] = true
			end
		end
	end
	local quests, offers = pinKeys.quests, pinKeys.offers
	if not (quests and offers) then return end
	for key in pairs(quests) do
		if offers[key] then error(key .. ": a quest's pin and an offer's in a frame") end
	end
end

function T.Invariants(sim, ns)
	local c = sim.protectedCalls[1]
	assert(c == nil, c and ("a protected call in combat: " .. c.call .. c.stack))
	local engaged = ns.Game.minimap.engaged
	assert(not (engaged and MinimapCluster:IsVisible() and MinimapCluster:GetEffectiveAlpha() > 0),
		"Blizzard's minimap cluster showing while engaged")
	assert(not (engaged and (Minimap:GetEffectiveAlpha() > 0 or C_Minimap.GetDrawGroundTextures())),
		"Blizzard's minimap showing while engaged")
	local E, S = ns.UI.Engine, sim.state
	local rest = not E.pending and S[ns.UI.Window.frame].shown
	for _, l in ipairs(E.layers) do
		if S[l.canvases[1]].alpha > 0 and S[l.canvases[2]].alpha > 0 and not l.fade then error(l.name .. ": two canvases shown") end
		for _, c in ipairs(l.canvases) do -- (scaled since its anchor was set: T.Anchors' limit, as it ends the frame)
			local k, e = S[c].scale, S[c].points[1]
			if e and (k <= 1.4 or not held[c]) and math.max(math.abs(e.x), math.abs(e.y)) * k > LIMIT then
				error(string.format("%s: a canvas's offset of %.0f, %.0f px, scaled %.2f", l.name, e.x * k, e.y * k, k))
			end
		end
		if rest and l.on and l.front and (l.front.ox ~= E.ox or l.front.oy ~= E.oy) then
			error(l.name .. ": off the shared origin at rest")
		end
	end
	OnePin(E, S)
end

-- Booted, the map open and past its first-open grace (2 s).
function T.Shown(saved, seconds)
	local sim, ns = T.Boot(saved)
	sim.Run(1)
	sim.Slash("/mma toggle")
	sim.Run(seconds or 3)
	return sim, ns
end

-- The sim's errors and Runtime's, as strings.
function T.Errors(sim, ns)
	local out = {}
	for _, e in pairs(sim.errors) do out[#out + 1] = tostring(e) end
	for _, e in pairs(ns.Runtime.errors) do out[#out + 1] = e.name .. ": " .. tostring(e.err) end
	return out
end

function T.Layer(ns, name)
	for _, l in ipairs(ns.UI.Engine.layers) do
		if l.name == name then return l end
	end
end

-- The layer shows a layout at the camera's zoom on the map shown, covering the view.
function T.Fresh(ns, lay)
	local m, c = ns.UI.Camera, lay.front
	if c == nil or c.zoom ~= m.cam.zoom or c.inst ~= m.inst then return false end
	if c.none then return true end -- nothing to draw at this zoom anywhere
	local w, h = ns.UI.Window.Size()
	local cam, r = m.cam, c.region
	return r[1] <= cam.cx - w / 2 / cam.zoom and r[3] >= cam.cx + w / 2 / cam.zoom
		and r[2] <= cam.cy - h / 2 / cam.zoom and r[4] >= cam.cy + h / 2 / cam.zoom
end

-- A table's values, as a list.
function T.Values(t)
	local out = {}
	for _, v in pairs(t) do out[#out + 1] = v end
	return out
end

-- Regions in use on the layer's shown canvas.
function T.Live(lay)
	local n = 0
	if lay.front ~= nil then
		for _, p in pairs(lay.front.pools) do n = n + p.n end
	end
	return n
end

-- Times Runtime caught an error from name.
function T.Errs(ns, name)
	for _, e in pairs(ns.Runtime.errors) do
		if e.name == name then return e.n end
	end
	return 0
end

-- Measure our frame alone: wraps Runtime's OnUpdate (the one OnUpdate the addon set) to sum
-- the Lua heap's growth and widget calls inside it. Returns a reader: frames, KB, calls, and
-- the last frame's KB and ms (debugprofilestop's: the sim's clock).
function T.Ours(sim)
	local m = { n = 0, kb = 0, calls = 0, last = 0, ms = 0 }
	for _, f in ipairs(sim.Frames()) do
		local s = sim.state[f].scripts.OnUpdate
		if s and f ~= Minimap then
			local fn = s.main
			s.main = function(...)
				local k0, c0, t0 = collectgarbage("count"), sim.callTotal, debugprofilestop()
				fn(...)
				m.ms, m.last = debugprofilestop() - t0, collectgarbage("count") - k0
				m.n, m.kb, m.calls = m.n + 1, m.kb + m.last, m.calls + sim.callTotal - c0
			end
		end
	end
	return function() return m.n, m.kb, m.calls, m.last, m.ms end
end

return T
