-- tracking (types/view.lua MM.CmdTracking): one of Blizzard's tracking types (MM.ObsTracking.id) on or
-- off (GearMenu.lua:16-22). The same frame's obs.tracking has it when sent from a click (carried out in
-- Input: game/parts/Tracking.lua); from a ui step, the next frame's.

local _, ns = ...
local Game = ns.Game

Game.Handle("tracking", function(c)
	for i = 1, C_Minimap.GetNumTrackingTypes() do
		local info = Game.TrackingID(i) == c.id and C_Minimap.GetTrackingInfo(i)
		if info and info.active ~= c.on then C_Minimap.SetTracking(i, c.on) end
	end
	Game.TrackingChanged()
end)
