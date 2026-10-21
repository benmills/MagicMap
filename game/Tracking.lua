-- Blizzard's own markers for what our layers draw (MinimapTakeover.lua:231-269, 624-634): its flight
-- master, quest objective and point-of-interest tracking (DUPLICATES), off while the takeover senses
-- (engaged) with our layer of the same on (View.layers flight, quests, pois), back on otherwise: at
-- release (the window hidden, /mm minimap blizzard, a View Game can't use), with our layer off. Acts on a change, and
-- again every AGAIN while engaged (a layer toggled). SavedGame.trackingOff remembers which Game turned
-- off, so ones a /reload or a crash left off come back: at logout, and at PLAYER_ENTERING_WORLD and
-- MINIMAP_UPDATE_TRACKING while not sensing (their state is known only once the client has sent it).

local _, ns = ...
local Game, Runtime = ns.Game, ns.Runtime

local F = Enum.MinimapTrackingFilter
local DUPLICATES = { [F.TaxiNode] = "flight", [F.QuestPOIs] = "quests", [F.POI] = "pois" } -- MinimapTakeover.lua:237
local AGAIN = 2 -- s (MinimapTakeover.lua:266)
local NONE = {}
Game.DUPLICATES = DUPLICATES -- filter id -> our layer (MM.ObsTracking kind "duplicate")

local sensing, at = nil, 0 -- what Sync last did, and when

-- on: our layers are on the map in Blizzard's place (MinimapTakeover.lua:241-261).
local function Sync(on, layers)
	local off = Game.saved.trackingOff
	for i = 1, C_Minimap.GetNumTrackingTypes() do
		local filter = C_Minimap.GetTrackingFilter(i)
		local id = filter and filter.filterID
		local layer = id and DUPLICATES[id]
		if layer then
			local info = C_Minimap.GetTrackingInfo(i)
			local want = on and layers[layer]
			if want and info and info.active then
				C_Minimap.SetTracking(i, false)
				off[id] = true
			elseif not want and off[id] and info then -- (no info yet at login: next time)
				if not info.active then C_Minimap.SetTracking(i, true) end
				off[id] = nil
			end
		end
	end
end

Game.Apply("tracking", function(view)
	local m, t = Game.minimap, GetTime()
	local on = m.engaged
	if on == sensing and not (m.engaged and t - at >= AGAIN) then return end
	sensing, at = on, t
	Sync(on, view.layers)
end)

local function Restore(event)
	if (event == "PLAYER_LOGOUT" or not sensing) and next(Game.saved.trackingOff) then Sync(false, NONE) end
end
for _, event in ipairs({ "PLAYER_LOGOUT", "PLAYER_ENTERING_WORLD", "MINIMAP_UPDATE_TRACKING" }) do
	Runtime.On(event, "game.tracking restore", Restore)
end
