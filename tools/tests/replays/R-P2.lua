-- P2: cooperative budget overrun. MOVED: Yield checks the budget only where the job calls it, so
-- a job yielding every 200 iterations overruns (and Perf's max shows it); one that yields every
-- iteration keeps to budget + one iteration.
local T = ...
local sim, ns = T.Boot()
sim.Run(1)
local R = ns.Runtime
local function Run(name, every)
	local tick = 0
	local clock = sim.Clock
	sim.Clock = function() return tick * 0.02 end -- 0.02 ms an iteration, nothing else costs
	local job = R.Job(name, function()
		for i = 1, 1e4 do
			tick = tick + 1
			if i % every == 0 then R.Yield() end
		end
	end, 1)
	for _ = 1, 400 do if job.done then break end sim.Step() end
	sim.Clock = clock
	return job.done, R.Perf()[name].max
end
local done, coarse = Run("test.coarse", 200)
assert(done and coarse > 1 + 0.1) -- the risk: ~4 ms against a 1 ms budget
local fine
done, fine = Run("test.fine", 1)
T.Print("P2: job max %.2f ms yielding every 200, %.2f ms yielding every 1 (budget 1)", coarse, fine)
assert(done and fine <= 1 + 0.1)
