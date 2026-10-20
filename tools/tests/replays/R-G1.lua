-- G1: indoors was decided wrongly, six fixes in a row: surface terrain in the Cleft of Shadow,
-- Blizzard's grey patchy Minimap in Orgrimmar, Undercity NPCs strewn over the ruins, a whole zone's
-- painting in a Sun Rock hut (each signal the wrong question). MOVED: still a heuristic over the
-- client, each decision now explicit and traced. Game says what it can: obs.minimap.indoors from the
-- Minimap's view radius (not IsIndoors(): Undercity is mountable), but in the open-air Orgrimmar
-- (game/Renderer.lua's OPEN_CITIES); obs.indoorArt, the art of the map you're on when it's the place's
-- own (no wider than 1600 yd, or a dungeon floor: a zone's painting never; game/parts/IndoorArt.lua).
-- UI picks View.renderer from them as the spike did (MinimapTakeover.lua:550-554; ui/IndoorArt.lua), and
-- Game acts on it:
-- "blizzard" the whole Minimap in the window over Game's black backdrop, the wheel zooming it, our
-- arrow under them, no sensor; out of it the sensor again. Each change leaves one "indoor" trace.
local T = ...
local sim, ns = T.Shown()
local Game, Model, UI = ns.Game, ns.Model, ns.UI
local M = Enum.UIMapType

-- The places (rects as Data/UiMaps.lua's), each map with art (Sim.mapArt: w, h, tile px).
sim.maps[1454] = { "Orgrimmar", M.Zone, 1414, 1, 38.901, 27.736, 41.531, 29.49 }
sim.maps[1458] = { "Undercity", M.Zone, 1415, 0, 30.363, 28.479, 32.162, 29.679 }
sim.maps[1412] = { "Mulgore", M.Zone, 1414, 1, 27.352, 31.5, 38.891, 39.191 }
sim.maps[291] = { "The Deadmines", M.Dungeon, nil, 36, 30, 30, 36, 36 }
for _, id in ipairs({ 1429, 1454, 1458, 1412, 291 }) do sim.mapArt[id] = { 1002, 668, 256 } end

local view = UI.View()
local traces, onTrace = {}, ns.Runtime.onTrace
ns.Runtime.onTrace = function(k, d)
	if k == "indoor" then traces[#traces + 1] = d end
	return onTrace(k, d)
end

local PLACES = { -- what, inst, col, row, can't mount, floor plan; the map, indoors, art, renderer
	{ "outdoors in Elwynn", 0, 31.95, 49.75, false, false, 1429, false, false, "ours" },
	{ "Orgrimmar: mountable, a floor plan", 1, 40.2, 28.6, false, true, 1454, false, true, "ours" },
	{ "Undercity: mountable, a floor plan", 0, 31.2, 29.1, false, true, 1458, true, true, "ours+art" },
	{ "a hut in Mulgore", 1, 32, 35, true, false, 1412, true, false, "blizzard" },
	{ "a dungeon floor", 36, 32.5, 32.5, true, false, 291, true, true, "ours+art" },
	{ "a hut in Mulgore again", 1, 32, 35, true, false, 1412, true, false, "blizzard" },
	{ "back out in Elwynn", 0, 31.95, 49.75, false, false, 1429, false, false, "ours" },
}
local W = view.window
local function Placed(f, p, w, h)
	local l, b, fw, fh = f:GetRect()
	return math.abs(l + fw / 2 - (p.left + p.w / 2)) < 0.01 and math.abs(b + fh / 2 - (p.top - p.h / 2)) < 0.01
		and math.abs(fw - w) < 0.01 and math.abs(fh - h) < 0.01
end
for i, p in ipairs(PLACES) do
	local what = p[1]
	sim.player.inst, sim.player.col, sim.player.row, sim.indoors, sim.floorPlan = p[2], p[3], p[4], p[5], p[6]
	sim.FireEvent("ZONE_CHANGED_NEW_AREA")
	local n = #traces
	sim.Run(1)
	local art, m = Game.obs.indoorArt, Game.minimap
	T.Print("G1: %s: map %s, indoors %s, art %s, renderer %s; %d trace(s)", what, tostring(Model.you.uiMap),
		tostring(Model.minimap.indoors), art and #art.pieces .. " pieces" or "none", view.renderer, #traces - n)
	assert(Model.you.uiMap == p[7] and Model.minimap.indoors == p[8] and (art ~= false) == p[9], what)
	assert(view.renderer == p[10], what .. ": " .. view.renderer)
	local one = i > 1 -- (where we are already: traced as it engaged)
	assert(#traces == n + (one and 1 or 0) and (not one or traces[#traces].shows == p[10] and traces[#traces].map == p[7]),
		what .. ": one trace")
	assert(m.engaged and m.whole == (p[10] == "blizzard") and m.sensor == not m.whole, what)
	if m.whole then
		-- The whole Minimap the view's size, centred, shown with its ground and own icons; the backdrop
		-- over the view; both over our arrow, the Minimap over the backdrop.
		local place, d = W.place, math.floor(math.min(W.place.w, W.place.h) + 0.5)
		local mm, bg, overlay = Minimap, Game.backdrop, UI.You.overlay
		assert(Placed(mm, place, d, d) and Placed(bg, place, place.w, place.h), "the view's size, centred")
		assert(mm:IsVisible() and mm:GetEffectiveAlpha() == 1 and C_Minimap.GetDrawGroundTextures() and bg:IsVisible())
		assert(mm:GetFrameStrata() == W.strata and bg:GetFrameStrata() == W.strata)
		assert(overlay:GetFrameLevel() < bg:GetFrameLevel() and bg:GetFrameLevel() < mm:GetFrameLevel())
		assert(sim.state[mm].mouseMotion and not sim.state[mm].mouseClick and not sim.state[mm].wheel)
		sim.Wheel(bg, 1) -- the wheel zooms it (its radius 0 a frame or two: IsIndoors() meanwhile, still indoors)
		sim.Run(0.5)
		assert(mm:GetZoom() == 1 and view.renderer == "blizzard" and #traces == n + 1, "zoomed, nothing else traced")
		if i == 4 then -- what's decided, printed (IndoorArt.lua:170-175), and the art outlined
			sim.Slash("/mm indoor")
			sim.Step()
			assert(sim.prints[#sim.prints]:find("indoor: map 1412 (Mulgore, type 3); Minimap indoors; art none; showing floor plan", 1, true))
		end
	else
		assert(not Game.backdrop:IsShown() and Minimap:GetZoom() == 0, what .. ": the sensor's")
	end
	if i == 5 then
		assert(#art.pieces == 12 and art.outline, "4 x 3 tiles of 256 px, outlined")
		local last = art.pieces[12]
		assert(math.abs(last.rect.c1 - 36) < 1e-9 and math.abs(last.rect.r1 - 36) < 1e-9 and last.rect.inst == 36)
		assert(math.abs(last.u - (1002 - 768) / 256) < 1e-9 and math.abs(last.v - (668 - 512) / 256) < 1e-9)
		assert(sim.prints[#sim.prints]:find("art 1 layer(s), 1002x668, 12 pieces; showing art", 1, true))
	end
end
sim.Slash("/mm indoor")
assert(sim.prints[#sim.prints]:find("indoor maps: quiet", 1, true))
assert(#T.Errors(sim, ns) == 0, table.concat(T.Errors(sim, ns), "\n\n"))
