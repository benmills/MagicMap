-- obs.minimap (types/observation.lua MM.ObsMinimap), per frame: the takeover's state
-- (game/Minimap.lua Game.minimap), sensing if the sensor read this frame (obs.blips), indoors
-- (Game.Indoors) and whether /mm indoor reports (SavedGame.indoorDebug: game/parts/Interior.lua), and
-- the Minimap's home spot with the cluster's strata (game/Home.lua: a new rect only when re-read).
--   Game.Indoors() (MinimapTakeover.lua:52-54, 95-107): the Minimap drawing its indoor map here. Its
--     view radius tells: at its zoom the indoor view's width is nearer it than the outdoor one's. Not
--     IsIndoors() ("can't mount": false in Ironforge), but while a new zoom applies (radius 0).

local _, ns = ...
local Game = ns.Game

local OUTDOOR = { [0] = 466 + 2 / 3, 400, 333 + 1 / 3, 266 + 2 / 3, 200, 133 + 1 / 3 } -- yd across, by zoom (:52)
local INDOOR = { [0] = 300, 240, 180, 120, 80, 50 } -- (:54)

function Game.Indoors()
	local r = C_Minimap.GetViewRadius()
	if issecretvalue(r) or r <= 0 then return IsIndoors() end
	local z = Minimap:GetZoom()
	return math.abs(2 * r - INDOOR[z]) < math.abs(2 * r - OUTDOOR[z])
end

local minimap = {}

Game.Part("minimap", function(obs)
	local m = Game.minimap
	minimap.engaged, minimap.blocker, minimap.sensing = m.engaged, m.blocker, obs.blips ~= nil and m.still
	minimap.indoors, minimap.indoorDebug = Game.Indoors(), Game.saved.indoorDebug or false
	minimap.home, minimap.homeStrata = Game.Home()
	return minimap
end)
