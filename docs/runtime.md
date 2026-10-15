# Runtime: what holds when things go wrong

Runtime (runtime/Runtime.lua) runs every frame's steps in phase order
(architecture.md "Each frame": Input → Observe → Model → UI → Apply), then timers'
due callbacks before them and jobs after them, and dispatches WoW events. This page
says, for each way the frame loop can fail, what is guaranteed, what enforces it,
and where it shows up in telemetry (docs/telemetry.md). The sim test
`tools/tests/test_addon.py::test_failures` drives each of them.

"Wrapped" below means `Runtime.Wrap`: every step, event handler, timer, job,
loader and slash command goes through it.

## Budgets

Our cost a frame is everything we run in it: timers, the five phases, jobs, and
the event handlers since the previous frame. It's measured with `debugprofilestop`
into a histogram (0.05 ms buckets up to 20 ms), so p50/p95/p99 are a bucket's top.
Frames inside a *grace* are kept apart (their slowest is reported, not counted):
5 s after each PLAYER_ENTERING_WORLD (`login` for login and /reload, `loading` for
a loading screen) and 2 s after the first map open (`map`).

| Budget | Limit | Why |
|---|---|---|
| frame cost p95 | ≤ 1.0 ms | 6% of a 60 fps frame; the spike's map ran ~0.3–1 ms/frame on average and felt free. |
| frame cost p99 | ≤ 5 ms | a frame with a layout slice (Map's jobs take 4 ms) plus the steps. |
| frame cost max, outside graces | ≤ 8 ms | half a 60 fps frame: at worst one dropped frame, never a hitch you notice. Each frame over it is an *overrun*. |
| one call (step, handler, timer) | ≤ 2 ms | `CALL_MS`: a step taking more starves the rest; work that size belongs in a Job. A job's resume: ≤ 2× its own budget. |
| first map open, slowest frame | ≤ 50 ms | first-use Atlas indexes (Labels: 17 ms in one call in the sim, 22 ms frame); ~3 frames, once a session. |
| load (Data + Atlas at login) | ≤ 250 ms | the sim measures 84–110 ms (`/mma atlas`); the client also reads the files from disk, so ~2.5× room. |
| our Lua memory, after a full collect (at logout) | ≤ 64 MB | ours alone (`GetAddOnMemoryUsage`) after `collectgarbage("collect")`, so garbage isn't counted (the play-test's 70.8 MB held ~24 MB of it: docs/v1-plan.md §2). Read at logout (`ourKB`) and 10 s after login (`ourKBLoad`: Data + Atlas, ~40 MB expected). Over it: a leak (`ourKB` − `ourKBLoad`, and `perf.alloc`) or data growth (`ourKBLoad`). |
| Lua allocation, outside graces | ≤ 50 KB/s | garbage is paid for later, by the collector, in someone's frame. A standing frame should make next to none: the sim, map open, measures 0.7 KB/s standing, 1.7 walking, ~80 during a sustained 1.5 views/s fling (layouts, and the first layout on a canvas creating its regions: one frame of several MB). `kbFrameP95` (KB a frame) is reported beside it, to find the frames. |
| errors per hour | 0 | every error is a bug; the counts make a regression obvious. |

Login frames aren't budgeted (load time is); their slowest is reported as `grace.login`.

Allocation is the Lua heap's growth (`collectgarbage("count")`) over each frame's run, the
same frames as the cost: `kbFrameP95`, `kbFrameMax` (KB a frame), `kbPerSec`, `kbFrames`. A
frame in which the collector freed more than we allocated (the heap shrank) can't be measured
and is left out, so it's a lower bound; event handlers between frames aren't in it. In the sim,
widget calls cost no Lua memory (as in the client), so the replays (tools/tests/test_spike_bugs.py
P3) measure ours alone.

`tools/telemetry.py --budgets` checks the newest session's `perf` against these
(PASS / FAIL each, exit 1 on a FAIL). The limits live there in `BUDGETS`, and
`FRAME_MS`, `CALL_MS` in runtime/Runtime.lua: change all three with this table.

## Guarantees

| Failure | Guarantee | Enforced by | Observed |
|---|---|---|---|
| a step errors | the frame's other steps, timers and jobs still run; recorded once per key with its stack; after 10 failing calls in a row it runs once a second until one succeeds; a stack is walked for a name's first failure, then at most once per 10 s | `Wrap`: `xpcall` + its catch (stack, `StackDue`), `Fail`, strikes in `Finish` | `errors[key]` (count, stack on first), an `error` mark with the trace, `throttled` trace, `perf.errors`, `errorsPerHour`; `/mma errors` |
| a step overruns its budget | it finishes (Lua can't be preempted); counted per name; the frame is counted as an overrun if over 8 ms | `Done` (per call), `Count` (per frame) | `slow` trace (1st, 10th, every 100th), `spike` trace naming the frame's slowest call, `perf.overruns`, `perf.slow`, `perf.max`; `/mma perf` |
| an event arrives mid-frame | handlers never run inside a phase: an event fired during a frame is dispatched after its phases; Game's handlers only note what changed and the observe step reads, so Model sees one snapshot a frame | `inFrame` + `queued` + `Flush` in Runtime; the rule for Game | handlers' time counts in the next frame's cost |
| a stuck job | a job still running after 600 resumes (its `maxFrames`) is cancelled and reported; one that doesn't `Yield` can't be stopped, but shows as an overrun; Map's layout jobs that fail or are cancelled leave their layer on its last good canvas and lay out again after a backoff (0.5 s, doubling to 30 s) | `RunJobs` watchdog; `Done(job, 2× budget)`; ui/Map.lua `Failed` | `job` trace, `errors[key]` ("still running after N frames: cancelled"), `slow`/`spike` traces; handle `.done`, `.err` |
| nil position (instances, loading) | Observation carries nil fields; Model keeps the last known with `stale = true`; the map follows it with the arrow greyed; no step assumes a position | game/Observe.lua, model/Model.lua, ui/Map.lua (`you.stale`) | `position` trace (`lost`/`back`); marks' `state.you` |
| missing or stale saved data | the loader always gets a table of its version: absent or not a table → defaults; older → `migrate` (failing: reset) and defaults by type; newer (a downgrade) → left untouched on disk, the session runs on defaults | `Game.Load(owner, fn, spec)` (game/Game.lua `Open`) | `saved` trace (`reset`, `newer`), a failing migrate or loader as an error |
| loading screen / PLAYER_ENTERING_WORLD again | handlers are idempotent; the frames after it are a grace, not overruns | game/Game.lua `game.enter` → `Runtime.Grace` | `enter` trace, `perf.grace.login`, `.loading` |
| /reload mid-job | nothing half-done is saved: jobs build into locals or widgets and commit in their last, non-yielding stretch; SavedVariables are written from tables at PLAYER_LOGOUT, which /reload fires | the rule (Map's layouts: back canvas, then swap) | `perf` written at logout |
| a callback added during iteration | runs from the next pass: a step from the next frame, a handler from the next event, a timer when due; a job started in a frame runs that frame | `for i = 1, #list` read once; `RunTimers` keeps added timers; `RunJobs` walks to the end | — |
| timers late after a hitch | an `After` fires once; an `Every` fires once, then re-phases: never a burst | `RunTimers` | — |
| error handler recursion | an error while reporting an error isn't reported again: a failing `onError` is switched off (printed once); our global error handler never re-enters and always calls the previous one | `reporting` in `Fail`; `inHandler` + `pcall` in game/Telemetry.lua | the print; `lua` errors |

### A step errors

`Wrap` calls the function under `xpcall`; its catch takes `debugstack` while the
failing frames still exist, but only for the name's first failure and then at most once
every 10 s (`STACK_EVERY`): Telemetry keeps only a key's first stack, and a step failing
every frame would otherwise walk the stack 60 times a second (the spike's E1 rate). `Fail` prints the first error per name, keeps
`Runtime.errors` (`{ name, err, n }`), and hands every one to `Runtime.onError`,
which Telemetry keys by `name: first line of the message`: the first occurrence
in a session stores the stack, traces `error` and takes an `error` mark; later
ones only count. One failing step costs nothing else: the loop goes on to the next.

Throttling: a callback failing 10 calls in a row (`STRIKES`) is skipped except once
a second (`RETRY`) until a call succeeds, which resets it. We keep retrying rather
than disabling it because most every-frame errors are about state (an instance, a
missing frame) that passes; once a second keeps the stack walk and the spam down to
nothing while it doesn't.

### A step overruns

Lua in WoW can't be preempted (there are no debug hooks), so Runtime never stops
a call; it measures it. A call over its budget (`CALL_MS` 2 ms, a step's
`opts.budgetMs`, a job resume's 2× its budget) adds to the name's `over` and traces
`slow` on the 1st, 10th and every 100th, so repeated overruns show as a rising `n`
without flooding the ring. A frame whose cost is over `FRAME_MS` (8 ms) outside a
grace is an overrun: counted in `perf.overruns`, and traced as `spike` with the
frame's slowest call. `perf.slow` lists the five names with most overruns.

### Events

WoW fires events between frames, and also synchronously inside some API calls a
step makes (CVars, tracking, quest log selection). Between frames a handler runs at
once. During a frame (`inFrame`), the event is queued and dispatched after the
Apply phase and jobs, so no handler ever runs inside a phase. Game's handlers only
note what changed (a dirty flag, a buffered value); the observe step reads the game
and hands Model one observation, so Model sees one consistent snapshot a frame and
UI draws from it.

### A stuck job

A job is a coroutine resumed once a frame for up to its budget. If it's still
running after `maxFrames` resumes (default 600: 10 s at 60 fps; frames, not
seconds, so a loading screen doesn't count against it) it's cancelled: `.done`,
`.err` set, a `job` trace and an error (once per key). A job that never calls
`Runtime.Yield` runs to its end in one resume; that can't be stopped, but its resume
shows as an overrun (`slow`, and `spike` if the frame went over). A job whose body
errors ends with `.err` and its coroutine's stack recorded.

### Nil position

`UnitPosition` returns nothing in instances and on some loading frames, and
`GetPlayerFacing` likewise. Observe hands Model nil fields, never a guess, and
traces `position lost`/`back` on the change. Model keeps the last known position
and facing with `you.stale = true` (cleared on the next real one; if a new instance
is known but no position, the old position is dropped). The map keeps following the
last known spot and greys the arrow (desaturated, half alpha); with nothing ever
known it hides it. Every step treats every observed field as possibly nil.

### Saved data

`Game.Load(owner, fn, spec)` with `spec = { version, defaults, migrate(saved, from) }`
(all optional; version 1, no defaults). `MagicMapAtlasDB` that isn't a table is
replaced. Then per owner, before `fn` sees it:

- not a table, or a non-number `_v`: reset to `{}` (traced `saved reset`);
- `_v` newer than ours (an older build after a newer one): the saved table is left
  exactly as it is, and `fn` gets fresh defaults, not saved this session (traced
  `saved newer`): a downgrade never destroys data;
- `_v` older (absent counts as 0) with data and a `migrate`: it runs wrapped; if it
  errors the table is wiped (traced `saved reset`, the error recorded);
- every key in `defaults` whose saved value has another type gets a copy of the default;
- `_v` is stamped with our version.

`fn` itself is wrapped: if it errors, the error is recorded and the rest of the
addon loads. Each owner's `fn` runs once a session, at ADDON_LOADED (or at once, if `Load` is called later).

### Loading screens, /reload, iteration, timers, recursion

- PLAYER_ENTERING_WORLD fires at login, /reload and every loading screen. Handlers
  must be idempotent (Game's only starts a grace and traces `enter`). Frames after
  it, often slow while the world streams in, are graced, not overruns.
- /reload throws away all Lua state, jobs included, after PLAYER_LOGOUT. So a job
  must never leave saved data half-written across a yield: build in locals (or a
  hidden canvas, as Map's layouts do) and commit in one stretch at the end.
  Telemetry writes the session's `perf` at PLAYER_LOGOUT.
- Lists are walked with their length read once: a step or handler added during a
  pass runs from the next. Timers added by a timer callback are kept. Jobs are
  walked to the end, so one started this frame runs this frame.
- After a hitch, `After` timers fire once, late; an `Every` fires once and its next
  is one period from now.
- `Runtime.onError` runs under `pcall` with a re-entry guard; if it fails it's
  switched off for the session, printed once. Telemetry's global error handler
  records under `pcall`, ignores errors raised while it records, and always passes
  the error on to the previous handler.

## Not guaranteed

- An infinite loop that never yields freezes the client: nothing in WoW's Lua can
  interrupt it.
- Event handlers called by the client between frames can't be delayed: only ones
  fired during our frame are queued.
- Memory is sampled as the whole Lua heap (`collectgarbage("count")`: every addon)
  every 10 s outside graces; ours alone (`GetAddOnMemoryUsage`), after a full collect, only
  twice: 10 s after login and at logout, since a full collect and `UpdateAddOnMemoryUsage`
  are too slow to call while playing (the one at load is graced as `gc`).
