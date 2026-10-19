-- obs.waypoint (types/observation.lua MM.Pos|false), on change: the user waypoint (C_Map), where it
-- stands; false: none, or on a map Atlas hasn't (Layers.lua:624-633). Read again on
-- USER_WAYPOINT_UPDATED, and at once after a waypoint Command (Game.WaypointChanged: the target doesn't
-- wait for the event, Layers.lua:2093-2095). A new table only when it moved. obs.waypointSet: one is
-- set, wherever (the spike's HasWaypoint, Layers.lua:2080-2081: the menu's Clear waypoint).

local _, ns = ...
local Atlas, Game, Runtime = ns.Atlas, ns.Game, ns.Runtime

local pos, set = false, false -- the last handed over
local dirty = true

-- Read the waypoint again this observe.
function Game.WaypointChanged() dirty = true end
Runtime.On("USER_WAYPOINT_UPDATED", "game.waypoint", Game.WaypointChanged)

Game.Part("waypoint", function()
	if not dirty then return pos end
	dirty = false
	local point, inst, col, row = C_Map.GetUserWaypoint(), nil, nil, nil
	set = point ~= nil
	if point then inst, col, row = Atlas.MapToTile(point.uiMapID, point.position.x, point.position.y) end
	if not inst then
		pos = false
	elseif not (pos and pos.inst == inst and pos.col == col and pos.row == row) then
		pos = { inst = inst, col = col, row = row }
	end
	return pos
end)
Game.Part("waypointSet", function() return set end)
