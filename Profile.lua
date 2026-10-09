-- Where MagicMap's time goes, for /mm perf (Perf.lua). Every entry point the
-- client calls (frame scripts, hooks, event handlers, timers) is wrapped by
-- ns.Timed; while a recording runs, each call's time goes into a bucket by
-- name. Otherwise a wrapper costs one table lookup.

local _, ns = ...
local clock = debugprofilestop

-- fn wrapped to time each call into bucket `name`.
function ns.Timed(name, fn)
	return function(...)
		local perf = ns.perf
		if not perf then return fn(...) end
		local t0 = clock()
		fn(...)
		perf.Spent(name, clock() - t0)
	end
end

-- An OnEvent handler (self, event, ...) wrapped to time each event into
-- bucket "<name>: <event>".
function ns.TimedEvents(name, fn)
	local names = {}
	return function(self, event, ...)
		local perf = ns.perf
		if not perf then return fn(self, event, ...) end
		local t0 = clock()
		fn(self, event, ...)
		local key = names[event]
		if not key then
			key = name .. ": " .. tostring(event)
			names[event] = key
		end
		perf.Spent(key, clock() - t0)
	end
end
