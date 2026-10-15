-- Runtime: when things run. One OnUpdate frame drives every frame's steps
-- (in phase order), timers and jobs; one frame dispatches events. Every
-- callback is wrapped: timed for Perf, and isolated (an error is caught
-- with its stack, printed once per name, kept in Runtime.errors, handed to
-- Runtime.onError(name, err, stack) if set, and the rest run on).
-- The guarantees, budgets and how each is observed: docs/runtime.md.
-- Runtime.Trace keeps a ring of recent events (docs/telemetry.md).
-- The first file after Atlas, so it marks Atlas's load end (boot.loaded).

local _, ns = ...
local Runtime = ns.Runtime
Runtime.boot.loaded = { t = debugprofilestop(), mem = collectgarbage("count") }

local now = debugprofilestop
local PHASES = { "input", "observe", "model", "ui", "apply" } -- architecture.md "Each frame"

-- Budgets (docs/runtime.md): our cost in one frame, and in one call (a step, handler or timer).
local FRAME_MS, CALL_MS = 8, 2
Runtime.FRAME_MS, Runtime.CALL_MS = FRAME_MS, CALL_MS
local STRIKES, RETRY = 10, 1 -- a callback failing STRIKES calls in a row then runs once a RETRY seconds
local STACK_EVERY = 10 -- s: a name's failures take a stack (debugstack: costly) at most this often
local JOB_RESUMES = 600 -- a job still running after this many frames is cancelled (default)

local function R1(v) return math.floor(v * 10 + 0.5) / 10 end

-- Wrap: timing, budgets and isolation ----------------------------------------------

local perf, failed = {}, {}
Runtime.errors = {} -- { name, err, n }, in the order they first failed
Runtime.frames = 0

local function Stat(name)
	local p = perf[name]
	if not p then p = { name = name, n = 0, ms = 0, max = 0, over = 0, fails = 0 }; perf[name] = p end
	return p
end

local top, topMs = nil, 0 -- this frame's slowest call, for a spike's trace

-- budget: ms one call may take (false: not checked); over it is an overrun, traced at its 1st, 10th, 100th...
local function Done(p, t0, budget)
	local dt = now() - t0
	p.n, p.ms = p.n + 1, p.ms + dt
	if dt > p.max then p.max = dt end
	if not budget then return end
	if dt > topMs then top, topMs = p.name, dt end
	if dt > budget then
		p.over = p.over + 1
		local o = p.over
		if o == 1 or o == 10 or o % 100 == 0 then Runtime.Trace("slow", { name = p.name, ms = R1(dt), n = o }) end
	end
end

local reporting -- in Runtime.onError: an error there isn't reported again (no recursion)
local function Fail(name, err, stack)
	local e = failed[name]
	if e then
		e.n = e.n + 1
	else
		e = { name = name, err = tostring(err), n = 1 }
		failed[name] = e
		Runtime.errors[#Runtime.errors + 1] = e
		print("|cffff6060MagicMap Atlas|r error in " .. name .. ": " .. e.err)
	end
	if Runtime.onError and not reporting then -- Game persists it
		reporting = true
		local ok, why = pcall(Runtime.onError, name, err, stack)
		reporting = false
		if not ok then
			Runtime.onError = nil
			print("|cffff6060MagicMap Atlas|r error reporting failed, now off: " .. tostring(why))
		end
	end
end

-- Whether a failure of p takes a stack: its first, then at most once a STACK_EVERY (a step failing
-- every frame would otherwise walk the stack 60 times a second; Telemetry keeps only a key's first).
local function StackDue(p)
	local t = GetTime()
	if p.stackAt and t - p.stackAt < STACK_EVERY then return false end
	p.stackAt = t
	return true
end

local stack -- the failing call's, set by its Wrap's catch while its frames still exist (or nil)
local function Finish(p, budget, t0, ok, ...)
	Done(p, t0, budget)
	if ok then
		p.fails = 0
		return ...
	end
	p.fails = p.fails + 1
	if p.fails >= STRIKES then
		p.retry = GetTime() + RETRY
		if p.fails == STRIKES then Runtime.Trace("throttled", p.name) end
	end
	return Fail(p.name, (...), stack)
end

local wrapped = setmetatable({}, { __mode = "k" }) -- every function Wrap returned

-- budgetMs: one call's budget (default CALL_MS; false: none, for callers of other wrapped calls).
function Runtime.Wrap(name, fn, budgetMs)
	local p = Stat(name)
	local budget = budgetMs == nil and CALL_MS or budgetMs
	local function catch(err)
		stack = StackDue(p) and debugstack(2) or nil
		return err
	end
	local w = function(...)
		if p.fails >= STRIKES and GetTime() < p.retry then return end -- failing every call: throttled
		return Finish(p, budget, now(), xpcall(fn, catch, ...))
	end
	wrapped[w] = true
	return w
end

-- Whether fn came from Wrap (timed and isolated): for tests that every script is.
function Runtime.Wrapped(fn) return wrapped[fn] == true end

-- Trace: a ring of recent events { f = frame, ms = since login, k = kind, d = detail } ------

local RING = 300
local ring, head, boot = {}, 0, Runtime.boot
for i = 1, RING do ring[i] = {} end

-- detail: a short string or a flat table of numbers and strings.
function Runtime.Trace(kind, detail)
	head = head % RING + 1
	local e = ring[head]
	e.f, e.ms, e.k, e.d = Runtime.frames, now() - (boot.login and boot.login.t or boot.t0), kind, detail
end

-- A copy of the ring, oldest first (ms to 0.1).
function Runtime.TraceCopy()
	local out = {}
	for i = 1, RING do
		local e = ring[(head + i - 1) % RING + 1]
		if e.k then out[#out + 1] = { f = e.f, ms = R1(e.ms), k = e.k, d = e.d } end
	end
	return out
end

-- Per-name { n = calls, ms = total, max = slowest call, over = overruns, fails = in a row }, and frames run.
function Runtime.Perf() return perf, Runtime.frames end

-- Steps ------------------------------------------------------------------------

local steps = {}
for _, phase in ipairs(PHASES) do steps[phase] = {} end

-- fn(elapsed) every frame; opts.shownOnly = frame: only while it's visible; opts.budgetMs.
function Runtime.Step(phase, name, fn, opts)
	local list = assert(steps[phase], "Runtime.Step: no phase " .. tostring(phase))
	list[#list + 1] = { fn = Runtime.Wrap(name, fn, opts and opts.budgetMs), shown = opts and opts.shownOnly }
end

-- Events: dispatched at once between frames; one fired during a frame (by an API call
-- a step made) waits until the frame's phases are done. ----------------------------------

local events = CreateFrame("Frame")
local handlers = {}
local inFrame, queued, eventMs = false, {}, 0 -- eventMs: handlers' time since the last frame

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

local function Dispatch(event, ...)
	local t0, list = now(), handlers[event]
	for i = 1, #list do list[i](event, ...) end -- one added meanwhile runs from the next event
	eventMs = eventMs + now() - t0
end

local function Flush()
	local i = 1
	while queued[i] do
		local q = queued[i]
		queued[i] = nil
		Dispatch(unpack(q, 1, q.n))
		i = i + 1
	end
end

events:SetScript("OnEvent", Runtime.Wrap("runtime: events", function(_, ...)
	if inFrame then queued[#queued + 1] = { n = select("#", ...), ... } else Dispatch(...) end
end, false))

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
-- The handle's .done is set when it has finished, failed (.err) or been cancelled;
-- one still running after maxFrames resumes (default JOB_RESUMES) is cancelled and reported.
function Runtime.Job(name, fn, budgetMs, maxFrames)
	local job = { name = name, co = coroutine.create(fn), budget = budgetMs or 2, p = Stat(name),
		resumes = 0, maxFrames = maxFrames or JOB_RESUMES }
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
	while jobs[i] do -- one started meanwhile runs this frame
		local job = jobs[i]
		if not job.cancelled and job.resumes >= job.maxFrames then
			job.cancelled, job.err = true, "still running after " .. job.maxFrames .. " frames: cancelled"
			Runtime.Trace("job", { name = job.name, e = "cancelled" })
			Fail(job.name, job.err)
		end
		if not job.cancelled then
			current, job.t0, job.resumes = job, now(), job.resumes + 1
			local ok, err = coroutine.resume(job.co)
			current = nil
			Done(job.p, job.t0, job.budget * 2) -- not yielding (often enough) shows as an overrun
			if not ok then job.err = tostring(err); Fail(job.name, err, StackDue(job.p) and debugstack(job.co) or nil) end
		end
		if job.cancelled or coroutine.status(job.co) == "dead" then
			job.done = true
			table.remove(jobs, i)
		else
			i = i + 1
		end
	end
end

-- Frame cost: our time each frame (its steps, timers and jobs, and the events since the last),
-- in a histogram for percentiles; frames inside a grace (login, loading, first map open) apart.
-- Allocation: the Lua heap's growth over the frame's run (collectgarbage("count") before and
-- after), KB/frame in a histogram and KB/s; a frame in which the collector freed more than we
-- allocated (the heap shrank) can't be measured and is left out. ---

local BUCKET, NB = 0.05, 400 -- ms per bucket; the last (20 ms+) holds the rest
local KB_BUCKET = 0.1 -- KB per allocation bucket (NB of them: the last, 40 KB+, holds the rest)
local hist, kbHist, graces, graceMax = {}, {}, {}, {}
for i = 1, NB do hist[i], kbHist[i] = 0, 0 end
local stats = { frames = 0, max = 0, overruns = 0, kbFrames = 0, kb = 0, kbSecs = 0, kbMaxFrame = 0 }
local MEM_EVERY, memAt = 10, 0

-- The next `seconds` of frames are expected to be slow: kept apart, as graceMax[name].
function Runtime.Grace(name, seconds) graces[name] = GetTime() + seconds end

local function Count(cost, kb, elapsed)
	local time, graced = GetTime(), false
	for name, t in pairs(graces) do
		if time < t then
			graced = true
			if cost > (graceMax[name] or 0) then graceMax[name] = cost end
		else
			graces[name] = nil
		end
	end
	if graced then return end
	local s = stats
	s.frames = s.frames + 1
	local b = math.floor(cost / BUCKET) + 1
	hist[b < NB and b or NB] = hist[b < NB and b or NB] + 1
	if cost > s.max then s.max = cost end
	if kb >= 0 then
		s.kbFrames, s.kb, s.kbSecs = s.kbFrames + 1, s.kb + kb, s.kbSecs + elapsed
		local k = math.floor(kb / KB_BUCKET) + 1
		kbHist[k < NB and k or NB] = kbHist[k < NB and k or NB] + 1
		if kb > s.kbMaxFrame then s.kbMaxFrame = kb end
	end
	if cost > FRAME_MS then
		s.overruns = s.overruns + 1
		Runtime.Trace("spike", { ms = R1(cost), top = top, topMs = R1(topMs) })
	end
	if time >= memAt then -- all addons' Lua heap (ours is most of it), outside graces
		memAt = time + MEM_EVERY
		local kb = collectgarbage("count")
		if not s.kbMin or kb < s.kbMin then s.kbMin = kb end
		if not s.kbMax or kb > s.kbMax then s.kbMax = kb end
	end
end

local function Pct(q, h, n, bucket, max)
	local want, seen = q * n, 0
	for i = 1, NB do
		seen = seen + h[i]
		if seen >= want then return math.min(math.floor(i * bucket * 100 + 0.5) / 100, max) end -- its top
	end
	return 0
end

local function R2(v) return math.floor(v * 100 + 0.5) / 100 end

-- { frames, p50, p95, p99, max, overruns, kbMin, kbMax (ms, KB) } outside graces;
-- allocation: kbFrameP95, kbFrameMax (KB a frame), kbPerSec, kbFrames (frames measured);
-- grace = { [name] = slowest frame }; slow = the 5 calls with most overruns { name, n, max }.
function Runtime.FrameStats()
	local s = stats
	local mx = R1(s.max)
	local out = { frames = s.frames, p50 = Pct(0.5, hist, s.frames, BUCKET, mx), p95 = Pct(0.95, hist, s.frames, BUCKET, mx),
		p99 = Pct(0.99, hist, s.frames, BUCKET, mx), max = mx, overruns = s.overruns,
		kbMin = s.kbMin and math.floor(s.kbMin), kbMax = s.kbMax and math.floor(s.kbMax),
		kbFrames = s.kbFrames, kbFrameMax = R2(s.kbMaxFrame),
		kbFrameP95 = s.kbFrames > 0 and Pct(0.95, kbHist, s.kbFrames, KB_BUCKET, R2(s.kbMaxFrame)) or nil,
		kbPerSec = s.kbSecs > 0 and R1(s.kb / s.kbSecs) or nil,
		grace = {}, slow = {} }
	for name, ms in pairs(graceMax) do out.grace[name] = R1(ms) end
	for _, p in pairs(perf) do
		if p.over > 0 then out.slow[#out.slow + 1] = { name = p.name, n = p.over, max = R1(p.max) } end
	end
	table.sort(out.slow, function(a, b) return a.n > b.n end)
	for i = #out.slow, 6, -1 do out.slow[i] = nil end
	return out
end

-- The frame ----------------------------------------------------------------------

local function Frame(_, elapsed)
	Flush() -- left by a frame that died
	local t0, kb0 = now(), collectgarbage("count")
	inFrame = true
	Runtime.frames = Runtime.frames + 1
	RunTimers()
	for p = 1, #PHASES do
		local list = steps[PHASES[p]]
		for i = 1, #list do -- one added meanwhile runs from the next frame
			local s = list[i]
			if not s.shown or s.shown:IsVisible() then s.fn(elapsed) end
		end
	end
	RunJobs()
	inFrame = false
	Flush()
	Count(now() - t0 + eventMs, collectgarbage("count") - kb0, elapsed or 0)
	eventMs, top, topMs = 0, nil, 0
end

events:SetScript("OnUpdate", Runtime.Wrap("runtime: frame", Frame, false))
