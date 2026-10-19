-- waypoint (types/view.lua MM.CmdWaypoint): the game's user waypoint at pos, on the map of the zone
-- there, super-tracked so it's your target; where it can't go, why not in chat. false clears it
-- (Layers.lua:2079-2097). The same frame's obs.waypoint has a click's (game/parts/Waypoint.lua).

local _, ns = ...
local Atlas, Game = ns.Atlas, ns.Game

-- The zone whose map has pos: { mapID, name, x, y } (Atlas.ZoneAt's, x and y on its map); nil: none
-- (Layers.lua:2059-2070: the client's zone at a point on the continent's map).
function Game.WaypointZone(pos)
	local z = Atlas.ZoneAt(pos.inst, pos.col, pos.row)
	if z and z.x >= 0 and z.x <= 1 and z.y >= 0 and z.y <= 1 then return z end
end

Game.Handle("waypoint", function(c)
	local z = c.pos and Game.WaypointZone(c.pos)
	if not c.pos then
		C_Map.ClearUserWaypoint()
	elseif not z then
		Game.Print("no zone here to put a waypoint in")
	elseif not C_Map.CanSetUserWaypointOnMap(z.mapID) then
		Game.Print("can't place a waypoint in " .. z.name)
	else
		C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(z.mapID, z.x, z.y))
		C_SuperTrack.SetSuperTrackedUserWaypoint(true)
	end
	Game.WaypointChanged()
end)
