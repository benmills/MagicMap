-- P3: per-frame garbage and idle work. CONTAINED (measured and budgeted): our frame's Lua allocation and widget
-- calls, idle, walking (following you, the title and arrow with you) and dragging, inside
-- Runtime's frame; and Runtime's frame stats report it.
local T = ...
local sim, ns = T.Shown(nil, 10) -- past telemetry's one full collect (ourKBLoad, 10 s after login)
local read = T.Ours(sim)
-- Setters on the map's widgets (re-applying unchanged state is the spike's P3); getters are cheap.
local sets = { v = 0 }
local SETTERS = { "SetPoint", "SetAllPoints", "ClearAllPoints", "SetScale", "SetSize", "SetRotation",
	"SetAlpha", "SetDesaturated", "Show", "Hide", "SetShown", "SetText", "SetTexture", "SetColorTexture",
	"SetVertexColor", "SetStartPoint", "SetEndPoint", "SetThickness", "SetTexCoord" }
local function Walk(w)
	for _, name in ipairs(SETTERS) do
		local fn = w[name]
		if fn then w[name] = function(...) sets.v = sets.v + 1; return fn(...) end end
	end
	for _, c in ipairs(sim.state[w].children or {}) do Walk(c) end
	for _, r in ipairs(sim.state[w].regions or {}) do Walk(r) end
end
Walk(ns.UI.Window.frame)
-- n frames measured, each after each(): KB, setter calls and widget calls a frame, and the frames' KB.
-- A full collect first (what came before isn't theirs), then a frame unmeasured: the collect shrank
-- the Lua stacks, and the first frame after it grows them back (2-6 KB, once a collect cycle, not
-- each frame: it was a third of the walking figure, more or less by where the deepest call fell).
-- Deep grows the main stack back first: a frame's deepest call can fall later (a timer's, by the
-- counted clock), and its regrowth (4 KB: 250 slots) counted as that frame's garbage (M1.4: 1 run in 4,
-- strict).
local function Deep(n) if n > 0 then return Deep(n - 1) + 1 end return 0 end
local function Run(n, each)
	collectgarbage("collect"); collectgarbage("stop")
	Deep(300)
	if each then each() end
	sim.Step()
	local n0, kb0, calls0 = read()
	local s0, kbs = sets.v, {}
	for i = 1, n do
		if each then each() end
		sim.Step()
		kbs[i] = select(4, read())
	end
	collectgarbage("restart")
	local n1, kb1, calls1 = read()
	return (kb1 - kb0) / (n1 - n0), (sets.v - s0) / (n1 - n0), (calls1 - calls0) / (n1 - n0), kbs
end
local idle = { Run(120) }
sim.player.facing, sim.player.speed = 3 * math.pi / 2, 7 -- walking east, followed
local walk = Run(120)
sim.player.speed = 0
-- Dragging, once it is one: pressed and moved past a click's slop first (the drag's start, once:
-- its trace, follow off, Focus and the saved centre made), then a frame each pixel.
local view = ns.UI.Window.view
sim.MoveCursorTo(view); sim.buttonsDown.LeftButton = true
sim.FireScript(view, "OnMouseDown", "LeftButton")
for _ = 1, 10 do sim.cursorX = sim.cursorX + 1; sim.Step() end
assert(ns.UI.Motion.Dragging())
local drag = { Run(120, function() sim.cursorX = sim.cursorX + 1 end) }
sim.buttonsDown.LeftButton = nil; sim.FireScript(view, "OnMouseUp", "LeftButton")
T.Print("P3: our frame idle %.0f B, %.1f setter calls on the map's widgets (%.1f widget calls in all, getters and "
	.. "the overlay's included); walking %.0f B; dragging %.0f B, %.1f widget calls", idle[1] * 1024, idle[2],
	idle[3], walk * 1024, drag[1] * 1024, drag[3])
-- KB a frame: no table a frame (the drag step's camera was ~0.2; the title's zone walking, ~0.13).
assert(idle[1] <= 0.1 and walk <= 0.1 and drag[1] <= 0.1)
assert(idle[2] == 0) -- standing still: the arrow and the canvases are left alone

local stats = ns.Runtime.FrameStats()
T.Print("P3: FrameStats: %d frames measured, p95 %s KB/frame, max %s KB/frame, %s KB/s",
	stats.kbFrames, tostring(stats.kbFrameP95), tostring(stats.kbFrameMax), tostring(stats.kbPerSec))
assert(stats.kbFrames > 0 and stats.kbFrameP95 ~= nil and stats.kbPerSec ~= nil)
sim.FireEvent("PLAYER_LOGOUT")
local perf = MagicMap2DB.telemetry.sessions[1].perf
assert(perf.kbPerSec == stats.kbPerSec and perf.kbFrameP95 ~= nil)
assert(#T.Errors(sim, ns) == 0)
