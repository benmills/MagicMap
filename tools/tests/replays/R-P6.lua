-- P6: where time went was invisible. CONTAINED: every script on a frame the addon made is a
-- Runtime.Wrap closure (timed per name, isolated), after the map and every /mm command.
local T = ...
local sim, ns = T.Shown()
local names = {}
for _, name in ipairs(ns.Game.commands) do names[#names + 1] = name end
for _, name in ipairs(names) do
	if name ~= "map" then
		sim.Slash("/mm " .. name)
		sim.Step()
	end
end
local all, frames, unwrapped = sim.Frames(), 0, {}
for i = T.simFrames + 1, #all do
	local f = all[i]
	frames = frames + 1
	for script, s in pairs(sim.state[f].scripts) do
		local fns = { s.main }
		for _, h in pairs(s.hooks) do fns[#fns + 1] = h end
		for _, fn in pairs(fns) do
			if not ns.Runtime.Wrapped(fn) then
				unwrapped[#unwrapped + 1] = (sim.state[f].name or sim.state[f].type) .. ":" .. script
			end
		end
	end
end
T.Print("P6: %d addon frames checked", frames)
assert(frames > 5 and #unwrapped == 0, table.concat(unwrapped, ", "))
assert(#T.Errors(sim, ns) == 0)
