"""Zooming and panning as the MVP does them (the spike, ~/code/MagicMap, which the user plays every day:
D4). tools/tests/spike_camera.lua is the spike's camera ported as it is; each stream of input here (single
notches, fast scrolls, a trackpad's burst, the wheel following and not, drags, a press mid-chase, grow
and shrink mid-zoom, a walk) goes to it and to ours, and ours must take the same path frame by frame:
the centre, the zoom, follow, and where it's headed (Goal). Then what you see on those streams, each frame
on the priced clock (LOOK): the spike lays its tiles out every frame (Core.lua RenderTiles), so its ground
is never short; ours scales a layout, and lays out where a zoom out is headed so it isn't either.

  .venv/bin/python -m pytest tools/tests/test_feel.py -s   # prints each stream's summary
"""
import os

from test_addon import TESTS, boot, errors

DRIVER = r"""
local sim, ns, refPath = ...
local UI = ns.UI
local W, M, C, Controls = UI.Window, UI.Motion, UI.Camera, UI.Controls
local view, frame = W.view, W.frame
local TILE = 1600 / 3 -- yards (Core.lua:9)

-- What the spike's camera reads of the world: the sim's, as ours reads it.
local env = {}
function env.Size() return W.Size() end
function env.Cursor() return W.Cursor() end
function env.Screen()
	local x, y = GetCursorPosition()
	local s = view:GetEffectiveScale()
	return x / s, y / s
end
function env.Down() return IsMouseButtonDown("LeftButton") end
function env.Over() return frame:IsMouseOver() end
function env.Player()
	local north, west, _, inst = UnitPosition("player")
	if not north then return nil end
	return 32 - west / TILE, 32 - north / TILE, inst -- Core.lua:65-67
end
function env.Grown() -- MinimapMode.lua:156-170
	local k = UIParent:GetEffectiveScale() / frame:GetEffectiveScale()
	local w, h = UIParent:GetWidth() * k * 0.7, UIParent:GetHeight() * k * 0.7
	return w - (frame:GetWidth() - view:GetWidth()), h - (frame:GetHeight() - view:GetHeight())
end
function env.ZoneRect() -- MinimapMode.lua:135-145, on Atlas's maps
	local A = ns.Atlas
	local m = A.UiMap(C_Map.GetBestMapForUnit("player"))
	while m and m.mapType > 3 and m.parent do m = A.UiMap(m.parent) end
	local r = m and A.MapRect(m.id)
	return r and r.inst == C.inst and r or nil
end
local R = assert(loadfile(refPath))(env)

-- Input, to both: the spike's handlers are the ones its widgets ran.
local A = {}
function A.Wheel(d, fx, fy)
	sim.MoveCursorTo(view, fx or 0.5, fy or 0.5)
	sim.FireScript(view, "OnMouseWheel", d)
	R.Wheel(d)
end
function A.Button(d)
	sim.FireScript(d > 0 and Controls.zoomIn or Controls.zoomOut, "OnClick", "LeftButton", false)
	R.ZoomStep(d)
end
function A.Follow()
	local on = not R.state.follow
	sim.FireScript(Controls.follow, "OnClick", "LeftButton", false)
	R.SetFollow(on, true)
end
function A.Mode()
	sim.FireScript(Controls.mode, "OnClick", "LeftButton", false)
	R.Toggle()
end
function A.Press(fx, fy)
	sim.MoveCursorTo(view, fx or 0.5, fy or 0.5)
	sim.buttonsDown.LeftButton = true
	sim.FireScript(view, "OnMouseDown", "LeftButton")
	R.Press()
end
function A.Move(dx, dy) sim.cursorX, sim.cursorY = sim.cursorX + dx, sim.cursorY + dy end
function A.Release()
	sim.buttonsDown.LeftButton = nil
	sim.FireScript(view, "OnMouseUp", "LeftButton")
	R.Release()
end
function A.Away() sim.cursorX, sim.cursorY = 5, 5 end -- off the window
function A.Walk(speed, facing) sim.player.speed, sim.player.facing = speed, facing or sim.player.facing end

-- Frames, each checked once it has run: ours against the spike's.
local out = { frames = 0, worst = 0 }
local function Off(a, b) return math.abs(a - b) end
function A.Frames(n, dt)
	for _ = 1, n do
		dt = dt or 1 / 60
		sim.Step(dt)
		R.Update(dt)
		out.frames = out.frames + 1
		local cam, s = C.cam, R.state
		local gz, gx, gy = M.Goal()
		local rx, ry = R.GoalCenter()
		local off = math.max(Off(cam.cx, s.cx), Off(cam.cy, s.cy), Off(math.log(cam.zoom), math.log(s.zoom)),
			Off(math.log(gz), math.log(R.GoalZoom())), Off(gx, rx), Off(gy, ry))
		out.worst = math.max(out.worst, off)
		if A.onFrame then A.onFrame() end
		if (off > 1e-9 or C.follow ~= s.follow) and not out.first then
			out.first = string.format("frame %d: ours %.6f, %.6f z%.4f follow %s goal z%.4f %.6f, %.6f;"
				.. " the spike's %.6f, %.6f z%.4f follow %s goal z%.4f %.6f, %.6f", out.frames, cam.cx, cam.cy,
				cam.zoom, tostring(C.follow), gz, gx, gy, s.cx, s.cy, s.zoom, tostring(s.follow), R.GoalZoom(), rx, ry)
		end
	end
end
function A.Run(seconds) A.Frames(math.floor(seconds * 60 + 0.5)) end

-- Start the spike's where ours stands.
local cam = C.cam
R.Sync(cam.cx, cam.cy, cam.zoom, C.follow, C.inst)
return A, out, R
"""

# The streams: Lua over A (the driver's input and frames). Each runs on a client of its own, the map open
# and following you at zoom 96 (test_addon.py's window, 720x520).
STREAMS = {
    "notches following": """
        for _, d in ipairs({ 1, 1, -1, 1, -1, -1, -1 }) do A.Wheel(d, 0.2, 0.3); A.Run(0.5) end""",
    "notches free, then the idle return": """
        A.Follow() -- off
        for _, d in ipairs({ 1, 1, -1, 1, -1 }) do A.Wheel(d, 0.2, 0.3); A.Run(0.5) end
        A.Away(); A.Run(7)""",
    "a fast scroll": """
        A.Follow()
        for i = 1, 8 do A.Wheel(1, 0.7, 0.6); A.Frames(2) end
        A.Frames(20)
        for i = 1, 12 do A.Wheel(-1, 0.3, 0.2); A.Frames(1) end
        A.Run(1)""",
    "a trackpad's burst": """
        A.Follow()
        for i = 1, 20 do A.Wheel(i % 3 == 0 and 0.2 or 1, 0.4, 0.4); A.Frames(1) end
        A.Run(0.5)
        for i = 1, 20 do A.Wheel(-0.25, 0.6, 0.5); A.Frames(1) end
        A.Run(1)""",
    "the wheel following, then free mid-chase": """
        for i = 1, 3 do A.Wheel(1, 0.8, 0.8); A.Frames(2) end
        A.Frames(4); A.Follow(); A.Frames(30)
        for i = 1, 3 do A.Wheel(-1, 0.8, 0.8); A.Frames(3) end
        A.Run(0.5); A.Follow(); A.Run(1)""",
    "drags": """
        A.Press(0.5, 0.5); A.Move(3, -2); A.Frames(5); A.Release(); A.Frames(5) -- a click
        A.Press(0.4, 0.6)
        for i = 1, 30 do A.Move(i % 4, -2); A.Frames(1) end
        A.Release(); A.Run(1)
        A.Press(0.6, 0.4)
        for i = 1, 20 do A.Move(-4, 3); A.Wheel(i % 5 == 0 and 1 or 0.5, 0.6, 0.4); A.Frames(1) end -- the wheel mid-drag
        A.Release(); A.Run(1)""",
    "a press mid-chase": """
        A.Follow()
        for i = 1, 3 do A.Wheel(1, 0.3, 0.7); A.Frames(1) end
        A.Frames(5); A.Press(0.3, 0.7); A.Frames(3); A.Release(); A.Run(0.5)
        for i = 1, 3 do A.Wheel(-1, 0.6, 0.6); A.Frames(1) end
        A.Frames(4); A.Press(0.6, 0.6); A.Move(10, 0); A.Frames(4); A.Release(); A.Run(0.5)
        A.Button(1); A.Frames(3); A.Button(1); A.Frames(30)""",
    "grow and shrink mid-zoom": """
        A.Wheel(1, 0.5, 0.5); A.Frames(5); A.Mode(); A.Frames(4)
        A.Wheel(-1, 0.3, 0.3); A.Frames(3); A.Wheel(-1, 0.3, 0.3); A.Run(1)
        A.Wheel(1, 0.7, 0.7); A.Frames(6); A.Mode(); A.Frames(5); A.Wheel(1, 0.5, 0.5); A.Run(1)
        A.Mode(); A.Run(0.1); A.Mode(); A.Run(1)""",
    "a walk, following and zooming": """
        A.Walk(7, 1.2)
        for _, d in ipairs({ 1, 1, 1, -1, -1 }) do A.Wheel(d, 0.1, 0.9); A.Run(0.3) end
        A.Walk(7, 4); A.Button(-1); A.Run(1); A.Walk(0); A.Run(0.5)""",
}


# What you see each frame, on the same streams: every layer drawn where the camera puts it (a canvas's origin
# tile where the camera shows that tile, at the camera's zoom; each tile's art on its tile; a moved name or pin
# on its spot), your arrow on you, each layer's layout covering the view, and no layer gone and back.
LOOK = r"""
local sim, ns, A = ...
local UI, S = ns.UI, sim.state
local W, C, E = UI.Window, UI.Camera, UI.Engine
local view, vs = W.view, W.view:GetEffectiveScale()
local look = { frames = 0, layers = {}, arrow = 0 }
local vl, vb, vw, vh -- the view on the screen, this frame

-- A map point on the screen at the camera (the sim's units, y up).
local function Proj(col, row)
	local cam, w, h = C.cam, W.Size()
	return vl + ((col - cam.cx) * cam.zoom + w / 2) * vs, vb + vh - ((row - cam.cy) * cam.zoom + h / 2) * vs
end
-- A region's first anchor on the screen, as the sim resolves it.
local function Anchor(o)
	local p = S[o].points[1]
	local l, b, _, h = sim.Rect(p.rel or S[o].parent)
	local s = o:GetEffectiveScale()
	return l + p.x * s, b + h + p.y * s
end
local function OnView(x, y) return x >= vl and x <= vl + vw and y >= vb and y <= vb + vh end
local function Off(x, y, ex, ey) return math.max(math.abs(x - ex), math.abs(y - ey)) end

-- The share of the view a canvas's laid out region leaves out.
local function Uncovered(c)
	local cam, w, h = C.cam, W.Size()
	local hw, hh, r = w / 2 / cam.zoom, h / 2 / cam.zoom, c.region
	local x0, x1 = math.max(cam.cx - hw, r[1]), math.min(cam.cx + hw, r[3])
	local y0, y1 = math.max(cam.cy - hh, r[2]), math.min(cam.cy + hh, r[4])
	return 1 - math.max(0, x1 - x0) * math.max(0, y1 - y0) / (4 * hw * hh)
end

local function Canvas(r, l, k)
	local x, y = Anchor(k)
	local ex, ey = Proj(k.ox, k.oy)
	r.off = math.max(r.off, Off(x, y, ex, ey), math.abs(k.zoom * k:GetEffectiveScale() - C.cam.zoom * vs))
	local art = l.name == "tiles" and k.pools.art
	for i = 1, art and art.n or 0 do
		local key = art.keys[i]
		local tx, ty = Proj(math.floor(key / 64), key % 64)
		if OnView(tx, ty) then
			local al, ab, _, ah = sim.Rect(art[i])
			r.tile = math.max(r.tile, Off(al, ab + ah, tx, ty))
		end
	end
end

local function Moved(r, k)
	for _, p in pairs(k.pools) do
		for i = 1, p.n do
			local o = p[i]
			local ex, ey = Proj(o.acol, o.arow)
			ex, ey = ex + o.adx * vs, ey - o.ady * vs
			if OnView(ex, ey) then
				local x, y = Anchor(o)
				r.off = math.max(r.off, Off(x, y, ex, ey))
			end
		end
	end
end

function A.onFrame()
	look.frames = look.frames + 1
	vl, vb, vw, vh = sim.Rect(view)
	for _, l in ipairs(E.layers) do
		local r = look.layers[l.name]
		if not r then
			r = { off = 0, tile = 0, uncovered = 0, worst = 0, back = 0 }
			look.layers[l.name] = r
		end
		local c, from = l.front, l.fade and l.fade.from
		local live = 0
		for _, p in pairs(c and c.pools or {}) do live = live + p.n end
		local shows = l.on and c and (c.alpha > 0 and live > 0 or from and from.alpha > 0) or false
		if r.shows == false and shows and r.had then r.back = r.back + 1 end
		r.had, r.shows = r.had or shows, shows
		if l.on and c and not c.none then
			local u = Uncovered(c)
			if from then u = math.min(u, Uncovered(from)) end
			if u > 1e-9 then r.uncovered, r.worst = r.uncovered + 1, math.max(r.worst, u) end
		end
		for _, k in ipairs({ c or false, from or false }) do
			if k and k.alpha > 0 then
				if l.zoom == "move" then Moved(r, k) else Canvas(r, l, k) end
			end
		end
	end
	local arrow, you = UI.You.arrow, ns.Model.you
	if arrow:IsShown() then
		local ex, ey = Proj(you.col, you.row)
		if OnView(ex, ey) then
			local x, y = Anchor(arrow)
			look.arrow = math.max(look.arrow, Off(x, y, ex, ey))
		end
	end
end
return look
"""


def run_stream(name, look=False):
    """A stream on a client of its own; look: LOOK each frame, on the priced clock past the graces."""
    L, sim, ns = boot()
    sim.Slash("/mma toggle")
    sim.Run(3)
    A, out, R = L.execute(DRIVER, sim, ns, os.path.join(TESTS, "spike_camera.lua"))
    if look:
        look = L.execute(LOOK, sim, ns, A)
        sim.Price(True)
        sim.Run(2.5)  # past login's grace (5 s)
    L.execute("local A = ...\n" + STREAMS[name], A)
    return L, sim, ns, out, look


def test_camera_as_spike():
    """Each stream: ours on the spike's path every frame (centre, zoom, follow, goal), within 1e-9."""
    for name in STREAMS:
        L, sim, ns, out, look = run_stream(name)
        print(f"{name}: {out.frames} frames, worst {out.worst:.2e}")
        assert out.first is None, f"{name}: {out.first}"
        assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


def test_zoom_look():
    """Each stream on the priced clock, what you see each frame (LOOK): every layer and your arrow exactly where
    the camera puts them; a tile's art within 1.5 px of its tile (its edges are whole pixels at the zoom it was
    laid out at, scaled with its canvas: half a pixel times the scale, ~3 at most while a zoom out lands);
    the tiles covering the view every frame, names and pins all but 0.1 s of the fastest scroll (laid out where
    the zoom is headed, ui/Engine.lua: at the camera, a fast zoom out ran past each layout before it landed);
    no layer gone and back; no frame over 8 ms, no call over its budget. Borders: as the spike's, the canvas
    from before the zoom scaled and dimmed until the one for where it's headed crossfades in (Layers.lua:
    1906-1940), so not counted."""
    for name in STREAMS:
        L, sim, ns, out, look = run_stream(name, look=True)
        fs, perf = ns.Runtime.FrameStats(), ns.Runtime.Perf()[0]
        layers = {k: r for k, r in look.layers.items()}
        print(f"{name}: {look.frames} frames, max {fs.max} ms, draw {perf['map: draw'].max:.2f} ms; "
              + "; ".join(f"{k} off {r.off:.0e}{f' tile {r.tile:.2f}' if k == 'tiles' else ''} px, uncovered "
                          f"{r.uncovered} ({r.worst:.2f})" for k, r in layers.items()))
        assert look.arrow < 1e-6 and all(r.off < 1e-6 for r in layers.values()), name
        assert layers["tiles"].tile <= 1.5 and layers["tiles"].uncovered == 0, name
        assert all(r.uncovered <= 6 for k, r in layers.items() if k != "borders"), name
        assert all(r.back == 0 for r in layers.values()), name
        assert fs.max <= 8 and sum(v.over for v in perf.values()) == 0 and perf["map: draw"].max <= 2, name
        assert not errors(sim, ns), "\n\n".join(errors(sim, ns))
