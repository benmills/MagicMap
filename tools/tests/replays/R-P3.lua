-- P3: per-frame garbage and idle work. MOVED (now measured): our frame's Lua allocation and widget
-- calls, idle and dragging, inside Runtime's frame; and Runtime's frame stats report it.
local T = ...
local sim, ns = T.Shown()
sim.CountCalls()
local read = T.Ours(sim)
local function Run(n, view)
	collectgarbage("collect"); collectgarbage("stop")
	if view then
		sim.MoveCursorTo(view); sim.buttonsDown.LeftButton = true
		sim.FireScript(view, "OnMouseDown", "LeftButton")
	end
	for _ = 1, n do
		if view then sim.cursorX = sim.cursorX + 1 end
		sim.Step()
	end
	if view then sim.buttonsDown.LeftButton = nil; sim.FireScript(view, "OnMouseUp", "LeftButton") end
	collectgarbage("restart")
end
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
Walk(ns.UI.Map.frame)
Run(120, nil)
local n, kb, calls = read()
local idle = { kb / n, sets.v / n }
Run(120, ns.UI.Map.view)
local n2, kb2, calls2 = read()
local drag = { (kb2 - kb) / (n2 - n), (calls2 - calls) / (n2 - n) }
T.Print("P3: our frame idle %.0f B, %.1f setter calls on the map's widgets (%.1f widget calls in all, getters and "
	.. "the Minimap sensor's included); dragging %.0f B, %.1f widget calls", idle[1] * 1024, idle[2], calls / n,
	drag[1] * 1024, drag[2])
assert(idle[1] <= 0.1 and drag[1] <= 0.1) -- KB a frame: no table a frame (the drag step's camera was ~0.2)
assert(idle[2] == 0) -- standing still: the arrow and the canvases are left alone
local stats = ns.Runtime.FrameStats()
T.Print("P3: FrameStats: %d frames measured, p95 %s KB/frame, max %s KB/frame, %s KB/s",
	stats.kbFrames, tostring(stats.kbFrameP95), tostring(stats.kbFrameMax), tostring(stats.kbPerSec))
assert(stats.kbFrames > 0 and stats.kbFrameP95 ~= nil and stats.kbPerSec ~= nil)
sim.FireEvent("PLAYER_LOGOUT")
local perf = MagicMapAtlasDB.telemetry.sessions[1].perf
assert(perf.kbPerSec == stats.kbPerSec and perf.kbFrameP95 ~= nil)
assert(#T.Errors(sim, ns) == 0)
