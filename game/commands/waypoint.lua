-- waypoint (types/view.lua MM.CmdWaypoint): the game's user waypoint at pos, on the map of the zone
-- there, super-tracked so it's your target; where it can't go, why not in chat. false clears it
-- (Layers.lua:2079-2097). The same frame's obs.waypoint has a click's (game/parts/Waypoint.lua).

local _, ns = ...
local Atlas, Game = ns.Atlas, ns.Game

Game.Handle("waypoint", function(c)
	local z = c.pos and Atlas.ZoneMapAt(c.pos.inst, c.pos.col, c.pos.row) -- (the zone whose map has it)
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
