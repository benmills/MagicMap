-- obs.minimap (types/observation.lua MM.ObsMinimap), per frame: the takeover's state
-- (game/Minimap.lua Game.minimap), indoors (Game.Indoors) and whether /mm indoor reports
-- (SavedGame.indoorDebug: game/parts/Interior.lua), and the Minimap's home spot with the cluster's strata (game/Home.lua: a new
-- rect only when re-read).
--   Game.Indoors() (MinimapTakeover.lua:52-54, 95-107): the Minimap drawing its indoor map here. Its
--     view radius tells: at its zoom the indoor view's width is nearer it than the outdoor one's. Not
--     IsIndoors() ("can't mount": false in Ironforge), but while a new zoom applies (radius 0).

local _, ns = ...
local Game = ns.Game

local OUTDOOR = { [0] = 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 } -- yd across, by zoom (:52)
local INDOOR = { [0] = 300, 240, 180, 120, 80, 50 } -- (:54)

-- The yards across the Minimap shows at each zoom (0..5), indoors or out.
function Game.MinimapYards(indoors) return indoors and INDOOR or OUTDOOR end

function Game.Indoors()
	local r = C_Minimap.GetViewRadius()
	if issecretvalue(r) or r <= 0 then return IsIndoors() end
	local z = Minimap:GetZoom()
	return math.abs(2 * r - INDOOR[z]) < math.abs(2 * r - OUTDOOR[z])
end

local minimap = {}

Game.Part("minimap", function()
	local m = Game.minimap
	minimap.engaged, minimap.blocker = m.engaged, m.blocker
	minimap.indoors, minimap.indoorDebug = Game.Indoors(), Game.saved.indoorDebug or false
	minimap.home, minimap.homeStrata = Game.Home()
	minimap.mouse, minimap.blip = m.mouse == true, m.blip == true
	minimap.names = m.blip and m.names or nil
	minimap.marks = minimap.names and m.marks or nil
	minimap.overlaid = m.engaged and m.overlaid == true or nil
	minimap.instance = m.engaged and m.instance == true or nil
	minimap.steps = m.engaged and m.stepsOn and m.steps or nil
	minimap.minZoom = minimap.steps and m.minZoom or nil
	minimap.maxZoom = m.engaged and m.maxZoom or nil
	return minimap
end)
