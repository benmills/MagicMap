-- Indoors (MinimapTakeover.lua:48-54, 95-107, 405-477, 524-557; IndoorArt.lua:151-188): what Game
-- tells UI for its pick of View.renderer, and the whole Minimap when UI picks "blizzard".
--   Game.Indoors(): obs.minimap.indoors (game/parts/MinimapState.lua), the Minimap drawing its indoor
--     map here. Its view radius tells: at its zoom the indoor view's width is nearer it than the
--     outdoor one's. Not IsIndoors() ("can't mount": Undercity is underground where you may), but while
--     a new zoom applies (radius 0). Open-air cities it draws badly, much of their ground grey
--     (OPEN_CITIES): outdoors there, our terrain. The art of the map you're on: game/parts/IndoorArt.lua.
--   Game.Whole(w): View.renderer "blizzard" (indoors with no art: game/Minimap.lua's apply, while
--     engaged): Blizzard's Minimap as it is (terrain, rim, its own hover tooltips, its arrow) the size of
--     the window's view, centred, over a black backdrop of Game's that takes the mouse (our map isn't
--     there to drag) and wheels the Minimap's zoom, both above the map's layers, our arrow under them.
--     Game.Whole(nil): out of it (game/Minimap.lua puts the sensor's settings back).
--   Each change of what's decided (the map you're on, indoors, its art, the renderer) is traced
--   ("indoor") while engaged, and printed with /mm indoor (saved: SavedGame.indoorDebug), which also
--   has UI outline the art (obs.indoorArt.outline).

local _, ns = ...
local Game, Runtime = ns.Game, ns.Runtime

local OPEN_CITIES = { [1454] = "Orgrimmar" } -- by uiMap (MinimapTakeover.lua:50)
local OUTDOOR = { [0] = 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 } -- yd across, by zoom (:52)
local INDOOR = { [0] = 300, 240, 180, 120, 80, 50 } -- (:54)
local LEVEL = 20 -- over the window's: above the map's layers (the view +1, ui/You.lua's overlay its +18), under its border
local SHOWS = { ours = "terrain", ["ours+art"] = "art", blizzard = "floor plan" } -- the note's (IndoorArt.lua:162)

function Game.Indoors()
	local r, indoor = C_Minimap.GetViewRadius(), nil
	if issecretvalue(r) or r <= 0 then
		indoor = IsIndoors()
	else
		local z = Minimap:GetZoom()
		indoor = math.abs(2 * r - INDOOR[z]) < math.abs(2 * r - OUTDOOR[z])
	end
	return indoor and not OPEN_CITIES[Game.obs.you.uiMap or 0]
end

-- The whole Minimap ------------------------------------------------------------------------

local backdrop = CreateFrame("Frame", nil, UIParent)
backdrop:Hide()
backdrop:EnableMouse(true)
backdrop:EnableMouseWheel(true)
local black = backdrop:CreateTexture(nil, "BACKGROUND")
black:SetAllPoints()
black:SetColorTexture(0, 0, 0, 1)
backdrop:SetScript("OnMouseWheel", Runtime.Wrap("game.renderer: wheel", function(_, delta)
	local z = Minimap:GetZoom() + delta
	if z >= 0 and z < Minimap:GetZoomLevels() then Minimap:SetZoom(z) end
end))
Game.backdrop = backdrop

local place, strata, level -- the window as last placed

function Game.Whole(w)
	local m, mm = Game.minimap, Minimap
	if not w then
		m.whole, place = false, nil
		backdrop:Hide()
		return
	end
	if not m.whole then
		m.whole = true
		mm:SetIconScale(1)
		mm:SetAlpha(1)
		C_Minimap.SetDrawGroundTextures(true)
		mm:EnableMouse(true)
		mm:SetMouseClickEnabled(false)
		mm:SetMouseMotionEnabled(true)
		mm:EnableMouseWheel(false)
		backdrop:Show()
	end
	local p = w.place -- (a new table when the window moves)
	if not (place == p and strata == w.strata and level == w.level) then
		place, strata, level = p, w.strata, w.level
		local d = math.floor(math.min(p.w, p.h) + 0.5)
		backdrop:SetFrameStrata(w.strata)
		backdrop:SetFrameLevel(w.level + LEVEL)
		backdrop:ClearAllPoints()
		backdrop:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", p.left, p.top)
		backdrop:SetSize(p.w, p.h)
		mm:SetFrameStrata(w.strata)
		mm:SetFrameLevel(w.level + LEVEL + 1)
		mm:SetSize(d, d)
		mm:ClearAllPoints()
		mm:SetPoint("CENTER", UIParent, "BOTTOMLEFT", p.left + p.w / 2, p.top - p.h / 2)
	end
	if not mm:IsShown() then mm:Show() end
end

-- What's decided, traced and noted ---------------------------------------------------------

local map, indoors, art, shows -- as last traced
local due -- /mm indoor turned on: noted at the next apply

-- MinimapTakeover's decision, as the spike printed it (IndoorArt.lua:163-176).
local function Note(view)
	local info = map and C_Map.GetMapInfo(map)
	local facts = art and Game.ArtFacts(map)
	Game.Say(("indoor: map %s (%s, type %s); Minimap %s; art %s; showing %s"):format(tostring(map),
		info and info.name or "?", info and tostring(info.mapType) or "?", indoors and "indoors" or "outdoors",
		art and ("%d layer(s), %s, %d pieces%s"):format(facts.layers, facts.size, #art.pieces,
			art.pieces[1].rect.inst == view.inst and "" or ", on another map") or "none",
		SHOWS[shows]))
end

Game.Apply("renderer", function(view)
	if not Game.minimap.engaged then return end
	local o = Game.obs
	local changed = not (o.you.uiMap == map and o.minimap.indoors == indoors and o.indoorArt == art and view.renderer == shows)
	if changed then
		map, indoors, art, shows = o.you.uiMap, o.minimap.indoors, o.indoorArt, view.renderer
		Runtime.Trace("indoor", { map = map, indoors = indoors, art = art and art.uiMap or false, shows = shows })
	end
	if (changed or due) and Game.saved.indoorDebug then Note(view) end
	due = nil
end)

-- IndoorArt.lua:178-185.
Game.Slash("indoor", "report what's decided indoors as it changes (the art outlined); again to stop", function()
	local s = Game.saved
	s.indoorDebug = not s.indoorDebug or nil
	due = s.indoorDebug
	Game.Say(s.indoorDebug and "indoor maps: reporting each change (the art outlined in pink); /mm indoor to stop"
		or "indoor maps: quiet")
end)
