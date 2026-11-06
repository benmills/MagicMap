-- Tracking kept on (#18): View.keep names one of Blizzard's tracking types, a spell's (MM.ObsTracking.id with
-- `spell`: Find Herbs, Find Minerals), that Game turns back on each time the game may have dropped it: at login,
-- /reload and every loading screen (PLAYER_ENTERING_WORLD), death and resurrection (PLAYER_DEAD, PLAYER_ALIVE,
-- PLAYER_UNGHOST), once the client lists it (learnt, or listed late after login), and when View.keep names
-- another. Only then: a tracker you turn off yourself stays off till the next of those (UI makes one you pick its
-- new choice, ui/Resources.lua). A try waits while it can't cast: in combat, dead or a ghost, casting or
-- channelling, on a flight; one that didn't take is tried again 3, 6, 12, then 24 s on, five in all, then left
-- till the next of those. If the client blocks the call (ADDON_ACTION_BLOCKED or _FORBIDDEN naming
-- C_Minimap.SetTracking), no more tries this session.

local ADDON, ns = ...
local Game, Runtime = ns.Game, ns.Runtime

local WAIT, TRIES = 3, 5 -- s before the second try, doubling; tries a window

local want -- View.keep as last read
local due, tries, at = false, 0, 0 -- turning it on is wanted; tries so far; the next not before (GetTime)
local listed, stale = false, true -- the client lists want (a spell you know); its list changed since we looked
local blocked = false

local function Due()
	due, tries, at = true, 0, 0
end
for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST" }) do
	Runtime.On(event, "game.keep " .. event, Due)
end
for _, event in ipairs({ "MINIMAP_UPDATE_TRACKING", "SPELLS_CHANGED" }) do
	Runtime.On(event, "game.keep " .. event, function() stale = true end)
end
for _, event in ipairs({ "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }) do
	Runtime.On(event, "game.keep " .. event, function(_, addon, call)
		if addon == ADDON and type(call) == "string" and call:find("SetTracking", 1, true) then
			blocked = true
			Runtime.Trace("keep", { blocked = call })
		end
	end)
end

-- The tracking type of id: its index and its info; nil while the client doesn't list it.
local function Find(id)
	for i = 1, C_Minimap.GetNumTrackingTypes() do
		if Game.TrackingID(i) == id then return i, C_Minimap.GetTrackingInfo(i) end
	end
end

-- Nothing in the way of a cast.
local function Free()
	return not (InCombatLockdown() or UnitIsDeadOrGhost("player") or UnitCastingInfo("player")
		or UnitChannelInfo("player") or UnitOnTaxi("player"))
end

Game.Apply("keep", function(view)
	local id = view.keep or nil
	if id ~= want then want, listed, stale = id, false, true; Due() end
	if not id or blocked then return end
	if stale and (due or not listed) then -- (the list changed: learnt, or listed at last, a drop of its own; or on)
		stale = false
		local _, info = Find(id)
		if info and not listed then listed = true; Due() end
		if info and info.active then due = false end
	end
	local t = GetTime()
	if not (due and listed) or t < at or not Free() then return end
	local i, info = Find(id)
	if not info then listed = false; return end
	if info.active then due = false; return end
	if tries >= TRIES then due = false; return end -- (given up till the next drop)
	tries = tries + 1
	at = t + WAIT * 2 ^ (tries - 1)
	Runtime.Trace("keep", { id = id, try = tries })
	C_Minimap.SetTracking(i, true)
	Game.TrackingChanged()
end)
