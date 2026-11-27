-- Blizzard's own markers for what our layers draw: its flight
-- master, quest objective and point-of-interest tracking (DUPLICATES), off while the takeover is engaged
-- (its overlay would draw them over ours) with our layer of the same on (View.layers flight, quests, pois), back on otherwise: at
-- release (the window hidden, /mm minimap blizzard, a View Game can't use), with our layer off. Acts on a change:
-- the takeover engaged or released, one of our three layers toggled, the client's tracking changed
-- (MINIMAP_UPDATE_TRACKING: its own menu, ours) or sent anew (PLAYER_ENTERING_WORLD); never on a timer (a look reads a
-- table or two a tracking type from the client: garbage every time), but again AGAIN s after one that found a
-- type's state not sent yet (login). SavedGame.trackingOff remembers which Game turned
-- off, so ones a /reload or a crash left off come back: at logout, and at PLAYER_ENTERING_WORLD and
-- MINIMAP_UPDATE_TRACKING while not engaged (their state is known only once the client has sent it).

local _, ns = ...
local Game, Runtime = ns.Game, ns.Runtime

local F = Enum.MinimapTrackingFilter
local DUPLICATES = { [F.TaxiNode] = "flight", [F.QuestPOIs] = "quests", [F.POI] = "pois" }
local AGAIN = 2 -- s: until the client has sent every duplicate's state
local NONE = {}
Game.DUPLICATES = DUPLICATES -- filter id -> our layer (MM.ObsTracking kind "duplicate")

local sensing -- what Sync last did (engaged or not)
local flight, quests, pois -- our layers as it last read them
local dirty, again = false, nil -- the client's tracking changed; GetTime() to look again at (a state not sent yet)

-- on: our layers are on the map in Blizzard's place. False: a duplicate's state isn't known yet.
local function Sync(on, layers)
	local off, known = Game.saved.trackingOff, true
	for i = 1, C_Minimap.GetNumTrackingTypes() do
		local filter = C_Minimap.GetTrackingFilter(i)
		local id = filter and filter.filterID
		local layer = id and DUPLICATES[id]
		if layer then
			local info = C_Minimap.GetTrackingInfo(i)
			local want = on and layers[layer]
			known = known and info ~= nil
			if want and info and info.active then
				C_Minimap.SetTracking(i, false)
				off[id] = true
			elseif not want and off[id] and info then -- (no info yet at login: next time)
				if not info.active then C_Minimap.SetTracking(i, true) end
				off[id] = nil
			end
		end
	end
	return known
end

Game.Apply("tracking", function(view)
	local on, l = Game.minimap.engaged, view.layers or NONE
	local toggled = on and (l.flight ~= flight or l.quests ~= quests or l.pois ~= pois)
	if on == sensing and not toggled and not (on and (dirty or again and GetTime() >= again)) then return end
	sensing, flight, quests, pois, dirty = on, l.flight, l.quests, l.pois, false
	again = not Sync(on, l) and on and GetTime() + AGAIN or nil
end)

local function Restore(event)
	if event ~= "PLAYER_LOGOUT" then dirty = true end
	if (event == "PLAYER_LOGOUT" or not sensing) and next(Game.saved.trackingOff) then Sync(false, NONE) end
end
for _, event in ipairs({ "PLAYER_LOGOUT", "PLAYER_ENTERING_WORLD", "MINIMAP_UPDATE_TRACKING" }) do
	Runtime.On(event, "game.tracking restore", Restore)
end
