-- Runtime: when things run. One OnUpdate frame drives every frame's steps
-- (in phase order), timers and jobs; one frame dispatches events. Every
-- callback is wrapped: timed for Perf, and isolated (an error is caught,
-- printed once per name, kept in Runtime.errors, and the rest run on).
-- The first file after Atlas, so it marks Atlas's load end (boot.loaded).

local _, ns = ...
local Runtime = ns.Runtime
Runtime.boot.loaded = { t = debugprofilestop(), mem = collectgarbage("count") }

local now = debugprofilestop
local PHASES = { "input", "observe", "model", "ui", "apply" } -- architecture.md "Each frame"

-- Wrap: timing and isolation -------------------------------------------------

local perf, failed = {}, {}
Runtime.errors = {} -- { name, err, n }, in the order they first failed
Runtime.frames = 0

local function Stat(name)
	local p = perf[name]
	if not p then p = { n = 0, ms = 0, max = 0 }; perf[name] = p end
	return p
end

local function Done(p, t0)
	local dt = now() - t0
	p.n, p.ms = p.n + 1, p.ms + dt
	if dt > p.max then p.max = dt end
end

local function Fail(name, err)
	local e = failed[name]
	if e then e.n = e.n + 1; return end
	e = { name = name, err = tostring(err), n = 1 }
	failed[name] = e
	Runtime.errors[#Runtime.errors + 1] = e
	print("|cffff6060MagicMap Atlas|r error in " .. name .. ": " .. e.err)
end

local function Finish(name, p, t0, ok, ...)
	Done(p, t0)
	if not ok then return Fail(name, (...)) end
	return ...
end

function Runtime.Wrap(name, fn)
	local p = Stat(name)
	return function(...) return Finish(name, p, now(), pcall(fn, ...)) end
end

-- Per-name { n = calls, ms = total, max = slowest call }, and frames run.
function Runtime.Perf() return perf, Runtime.frames end

-- Steps ------------------------------------------------------------------------

local steps = {}
for _, phase in ipairs(PHASES) do steps[phase] = {} end

-- fn(elapsed) every frame; opts.shownOnly = frame: only while it's visible.
function Runtime.Step(phase, name, fn, opts)
	local list = assert(steps[phase], "Runtime.Step: no phase " .. tostring(phase))
	list[#list + 1] = { fn = Runtime.Wrap(name, fn), shown = opts and opts.shownOnly }
end

-- Events -----------------------------------------------------------------------

local events = CreateFrame("Frame")
local handlers = {}

-- fn(event, ...) on each WoW event.
function Runtime.On(event, name, fn)
	local list = handlers[event]
	if not list then
		list = {}
		handlers[event] = list
		events:RegisterEvent(event)
	end
	list[#list + 1] = Runtime.Wrap(name, fn)
end

events:SetScript("OnEvent", function(_, event, ...)
	local list = handlers[event]
	for i = 1, #list do list[i](event, ...) end
end)

-- Timers -----------------------------------------------------------------------

local timers = {}

local function Timer(seconds, name, fn, every)
	local t = { at = GetTime() + seconds, every = every and seconds, fn = Runtime.Wrap(name, fn) }
	timers[#timers + 1] = t
	return t
end

-- fn() once after `seconds`; fn() every `seconds`. Both return a handle for Cancel.
function Runtime.After(seconds, name, fn) return Timer(seconds, name, fn, false) end
function Runtime.Every(seconds, name, fn) return Timer(seconds, name, fn, true) end
function Runtime.Cancel(handle) handle.cancelled = true end -- a timer or a job

local function RunTimers()
	local time, n, keep = GetTime(), #timers, 0
	for i = 1, n do
		local t = timers[i]
		if not t.cancelled and t.at <= time then
			t.fn()
			if t.every then
				t.at = t.at + t.every
				if t.at <= time then t.at = time + t.every end -- after a hitch: no burst
			else
				t.cancelled = true
			end
		end
		if not t.cancelled then keep = keep + 1; timers[keep] = t end
	end
	for i = n + 1, #timers do keep = keep + 1; timers[keep] = timers[i] end -- added by a callback
	for i = #timers, keep + 1, -1 do timers[i] = nil end
end

-- Jobs: coroutines resumed each frame, each with its own per-frame budget -------

local jobs, current = {}, nil

-- Runs fn() as a coroutine until it returns; it calls Runtime.Yield() often.
-- The handle's .done is set when it has finished (or failed).
function Runtime.Job(name, fn, budgetMs)
	local job = { name = name, co = coroutine.create(fn), budget = budgetMs or 2, p = Stat(name) }
	jobs[#jobs + 1] = job
	return job
end

-- Gives the frame back once the running job's budget is spent; elsewhere a no-op.
function Runtime.Yield()
	if current and now() - current.t0 >= current.budget and coroutine.running() == current.co then
		coroutine.yield()
	end
end

local function RunJobs()
	local i = 1
	while jobs[i] do
		local job = jobs[i]
		if not job.cancelled then
			current, job.t0 = job, now()
			local ok, err = coroutine.resume(job.co)
			current = nil
			Done(job.p, job.t0)
			if not ok then Fail(job.name, err) end
		end
		if job.cancelled or coroutine.status(job.co) == "dead" then
			job.done = true
			table.remove(jobs, i)
		else
			i = i + 1
		end
	end
end

-- The frame ----------------------------------------------------------------------

local function Frame(_, elapsed)
	Runtime.frames = Runtime.frames + 1
	RunTimers()
	for p = 1, #PHASES do
		local list = steps[PHASES[p]]
		for i = 1, #list do
			local s = list[i]
			if not s.shown or s.shown:IsVisible() then s.fn(elapsed) end
		end
	end
	RunJobs()
end

events:SetScript("OnUpdate", Runtime.Wrap("runtime (whole frame)", Frame))
