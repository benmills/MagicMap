---@meta
-- Contract 5: Runtime (library; anyone may use it). docs/decisions/0005-runtime.md
-- The per-failure guarantees, budgets and how each is observed: docs/runtime.md
-- (the authority for numbers; this file types the calls).
--
-- LOCKED (one-way door: every system is written against it):
--   * the phases and their order: input, observe, model, ui, apply
--   * Step / On / After / Every / Cancel / Job / Yield / Wrap / Trace / onError:
--     names, arguments, and what each promises:
--       - every callback is wrapped: an error in one is caught (with its stack),
--         reported, and never stops another callback, phase or frame
--       - steps run every frame in phase order, then registration order within
--         a phase; one added during a frame runs from the next
--       - events fired while a frame runs wait until its phases are done
--       - a periodic timer late by more than a period runs once, not in a burst
--       - a job runs only while its budget lasts each frame (Yield gives the
--         frame back); a job that doesn't finish in time is cancelled, reported
--       - nothing Runtime runs is ever retried in a tight loop: a callback that
--         keeps failing is throttled
--   * Trace's event shape (docs/telemetry.md)
-- OPEN: the budget numbers, throttling policy, Perf / FrameStats shapes,
-- new optional opts; Grace, SetState, FrameStats; Worker / Wake / Idle (a job
-- that lasts: its coroutine made once); Requeue / Left (jobs sharing a frame's
-- budget in an order of their own: ui/Engine.lua's layouts); the onTrace hook; Record / RecordEnd /
-- recording, Spent, Gauge / gauges (diagnostics: /mma perf, perf mem, debug).

---@alias MM.Phase "input"|"observe"|"model"|"ui"|"apply"

---@class MM.StepOpts
---@field shownOnly? table       a Frame: run only while it IsVisible() (drawing)
---@field budgetMs? number|false one call's budget (default Runtime.CALL_MS); false: not checked

---A handle from After / Every / Job, for Cancel.
---@class MM.Handle
---@field cancelled? boolean

---@class MM.Job: MM.Handle
---@field name string
---@field done? boolean          set once it finished, failed or was cancelled
---@field err? string            why it failed or was cancelled

---Detail of a trace event: a short string or a flat table of numbers and strings.
---@alias MM.TraceDetail string|table<string, string|number|boolean>|nil

---@class MM.TraceEvent
---@field f MM.Frame
---@field ms number              since login (load start before it), 0.1 ms
---@field k string               kind (docs/telemetry.md "Trace kinds")
---@field d MM.TraceDetail

---@class MM.PerfEntry
---@field name string
---@field n integer              calls
---@field ms number              total
---@field max number             slowest call
---@field over integer           calls over budget, outside graces
---@field fails integer          failures in a row
---@field kb? number             Lua KB its calls made, outside graces (docs/runtime.md "Attribution")
---@field kbN? integer           calls measured
---@field kbMax? number          most in one call
---@field gaps? integer          a job's stretches between Yields over its budget
---@field gapMax? number         the longest (ms)
---@field gapStack? string       the first one's stack

---Our cost a frame and who to blame (docs/runtime.md "Budgets", "Attribution"). Its keys are OPEN.
---@class MM.FrameStats
---@field frames integer         outside graces
---@field p50 number
---@field p95 number
---@field p99 number
---@field max number
---@field overruns integer
---@field kbPerSec? number       Lua KB a second our frames made (kb / kbSecs)
---@field kb number              KB measured, outside graces; with kbSecs (their seconds), two reads' difference
---@field kbSecs number          is a stretch's KB/s (a storm's: test_quests_storm, a mark's window)
---@field grace table<string, number>  each grace's slowest frame (ms)
---@field graceTop table<string, { top: string?, topMs: number }>  that frame's slowest call
---@field slow { name: string, n: integer, max: number }[]
---@field slowGc { name: string, n: integer }[]  over budget while the collector freed more than they made: its step, not theirs
---@field alloc { name: string, kbPerSec: number, kbMax: number, calls: integer }[]
---@field gaps { job: string, ms: number, n: integer, stack: string? }[]
---@field ledger { frame: MM.Frame, ms: number, top: string?, topMs: number, events: MM.TraceEvent[] }[]
---@field byState table<string, { frames: integer, p50: number, p95: number, p99: number, max: number, client: { p50: number, p95: number, p99: number, max: number } }>  client: the client's whole frame (ms between OnUpdates), booked to the state that frame ran in

---@class MM.RuntimeError
---@field name string            the Wrap name
---@field err string             the first message
---@field n integer              how many times

---@class MM.Boot
---@field t0 number              debugprofilestop() at load start
---@field mem0 number            KB then
---@field loaded? { t: number, mem: number }  once Atlas has loaded
---@field login? { t: number, mem: number }   at PLAYER_LOGIN

---@class MM.Runtime
---@field frames MM.Frame
---@field boot MM.Boot
---@field errors MM.RuntimeError[]   in the order they first failed
---@field FRAME_MS number            our budget for one frame (docs/runtime.md)
---@field CALL_MS number             default budget for one call
---@field onError? fun(name: string, err: any, stack: string?)  every caught error; set by Game (telemetry). If it fails it is turned off.
---@field onTrace? fun(kind: string, detail: MM.TraceDetail)  every trace, after the ring has it; set by Game (telemetry: kept kinds, stats). OPEN
local Runtime = {}

---fn(elapsed) every frame in `phase`.
---@param phase MM.Phase
---@param name string
---@param fn fun(elapsed: number)
---@param opts? MM.StepOpts
function Runtime.Step(phase, name, fn, opts) end

---fn(event, ...) on each WoW event (Game registers game events; Runtime dispatches).
---@param event string
---@param name string
---@param fn fun(event: string, ...: any)
function Runtime.On(event, name, fn) end

---@param seconds number
---@param name string
---@param fn fun()
---@return MM.Handle
function Runtime.After(seconds, name, fn) end

---@param seconds number
---@param name string
---@param fn fun()
---@return MM.Handle
function Runtime.Every(seconds, name, fn) end

---@param handle MM.Handle
function Runtime.Cancel(handle) end

---fn as a coroutine, resumed each frame (after the phases) until it returns.
---@param name string
---@param fn fun()
---@param budgetMs? number       per frame (default 2)
---@param maxFrames? integer     resumes before it's cancelled (docs/runtime.md)
---@return MM.Job
function Runtime.Job(name, fn, budgetMs, maxFrames) end

---Inside a job: give the frame back once its budget is spent. Elsewhere: nothing.
function Runtime.Yield() end

---A job that lasts: fn runs in one coroutine for good, each run ending in Runtime.Idle().
---Not running until Wake. OPEN
---@param name string
---@param fn fun()
---@param budgetMs? number       per frame (default 2)
---@param maxFrames? integer     resumes a run may take before it's cancelled
---@return MM.Job
function Runtime.Worker(name, fn, budgetMs, maxFrames) end

---Run a worker again as a job, from its Idle (cancelled or failed mid-run: fn anew). OPEN
---@param job MM.Job
---@param budgetMs? number
function Runtime.Wake(job, budgetMs) end

---Inside a worker: this run is done (the job's .done is set); the next Wake goes on from here. OPEN
function Runtime.Idle() end

---A queued job to the queue's end: its turn this frame comes after those queued now. Not from inside
---a job. A job whose budget is 0 waits its turn, queued, not resumed (nor counted). OPEN
---@param job MM.Job
function Runtime.Requeue(job) end

---Inside a job: ms of its budget left in this resume (elsewhere 0). OPEN
---@return number
function Runtime.Left() end

---fn timed and isolated under `name`; Step / On / After / Every / Job wrap for you.
---@generic F: function
---@param name string
---@param fn F
---@param budgetMs? number|false
---@return F
function Runtime.Wrap(name, fn, budgetMs) end

---Whether fn is a function Wrap returned (tests check every script the addon sets is one).
---@param fn function
---@return boolean
function Runtime.Wrapped(fn) end

---@param kind string
---@param detail? MM.TraceDetail
function Runtime.Trace(kind, detail) end

---@return MM.TraceEvent[]       oldest first
function Runtime.TraceCopy() end

---@return table<string, MM.PerfEntry> perf
---@return MM.Frame frames
function Runtime.Perf() end

---The next `seconds` of frames are expected to be slow (login, first map open): counted apart.
---@param name string
---@param seconds number
function Runtime.Grace(name, seconds) end

---The map's state now (UI's): the frames from here on count under it too (FrameStats byState).
---@param name "closed"|"small"|"big"|"zoom"|"drag"|string
function Runtime.SetState(name) end

---@return MM.FrameStats
function Runtime.FrameStats() end

---A recording (/mma perf: Perf.lua): the next `seconds` of frames, graces included, then done(rec),
---wrapped as name. Runtime.recording is the one going on (nil: none). OPEN
---@param seconds number
---@param name string
---@param done fun(rec: MM.Recording)
function Runtime.Record(seconds, name, done) end

---End the recording now (done(rec) then). OPEN
function Runtime.RecordEnd() end

---@class MM.Recording
---@field seconds number         how long it records
---@field t number               s recorded
---@field frames integer
---@field worst number           s: the slowest frame
---@field hitches integer        frames slower than Runtime.HITCH (1/30 s)
---@field ms number              our cost over it
---@field peak number            ms: our cost in one frame, the most
---@field calls table<string, { ms: number, n: integer, max: number }>  budgeted wrapped calls, by name

---ms the running job has taken since it was made or woken (outside a job: 0). OPEN
---@return number
function Runtime.Spent() end

---Numbers a system keeps for diagnostics: Runtime.gauges[name]() returns fn's table, wrapped; its shape the
---registrant's (ui/Engine.lua's "map": builds, buildMs, pans, past, objects, tiles, spare). OPEN
---@param name string
---@param fn fun(): table
function Runtime.Gauge(name, fn) end
