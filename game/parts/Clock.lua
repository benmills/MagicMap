-- obs.clock (types/observation.lua MM.ObsClock), on change: the time, local (date) and the server's (GetGameTime),
-- whether it's day (C_DateAndTime.IsDayTime: the minimap's day and night picture, Blizzard_Minimap's Diel.lua;
-- without it, 6:00 to 18:00 server time) and whether Blizzard's clock shows 24 hours (its timeMgrUseMilitaryTime);
-- read once a second, a new table only when one changed (the minute, mostly). The title shows them (ui/Title.lua).

local _, ns = ...
local Game, Runtime = ns.Game, ns.Runtime

local clock
local due, minute = true, nil
Runtime.Every(1, "game.clock", function() due = true end)

Game.Part("clock", function()
	if not due then return clock end
	due = false
	local t = time()
	local sh, sm = GetGameTime()
	local h, m = clock and clock.h, clock and clock.m
	if t - t % 60 ~= minute then -- (the local minute turns with the clock's: date's table once a minute)
		local d = date("*t", t)
		minute, h, m = t - t % 60, d.hour, d.min
	end
	local day
	if C_DateAndTime and C_DateAndTime.IsDayTime then day = C_DateAndTime.IsDayTime() == true else day = sh >= 6 and sh < 18 end
	local military = GetCVar("timeMgrUseMilitaryTime") == "1"
	local c = clock
	if c and c.h == h and c.m == m and c.sh == sh and c.sm == sm and c.day == day and c.military == military then
		return clock
	end
	clock = { h = h, m = m, sh = sh, sm = sm, day = day, military = military }
	return clock
end)
