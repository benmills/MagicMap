# Telemetry

The addon can't reach the network, but WoW writes SavedVariables to disk on
`/reload` and logout, and this machine can read them (and the client's `Logs/`
and `Screenshots/`). So the loop is: play, `/reload`, run `tools/telemetry.py`.
The scripted sessions that feed it are docs/playtest.md.

## In game

- **Version stamp**: `tools/install.py` writes the checkout's version
  (`git describe --always --dirty`, e.g. `7aa8b30-dirty`) into the installed TOC's
  `## Version:`. Every record carries it (`GetAddOnMetadata(ADDON, "Version")`).
- **Errors**: everything `Runtime.Wrap` catches, and anything else the global
  error handler sees from our files, is kept with its stack.
- **Flight recorder**: `Runtime.Trace(kind, detail)` appends to an in-memory ring
  of the last 300 events. It's only persisted inside a mark, except the kinds that
  must stay empty (`taint`, `art`, `sensor`), which the session keeps, and the
  layout, swap and sweep events, which the session counts.
- **Motion ring**: the camera (`View.camera`) and your position, every frame, in
  120 preallocated slots (no garbage). Persisted inside a mark.
- **Marks**: a snapshot of state plus the recorder's ring and the motion ring, taken
  on an error's first occurrence, a taint's first occurrence per function,
  `/mma mark <note>`, and `/mma shot <id> [note]` (which also takes a screenshot).
- **Memory**: ours alone after a full `collectgarbage("collect")`, read twice: 10 s
  after login (past its 5 s grace) and at logout. The collect's frame is graced
  (`gc`), so it's never an overrun.
- **Taint**: ADDON_ACTION_BLOCKED / ADDON_ACTION_FORBIDDEN naming our addon.

## SavedVariables: `MagicMapAtlasDB.telemetry`

```lua
telemetry = {
  sessions = {          -- newest last, last 10 kept
    { id = 1, version = "7aa8b30-dirty", build = "1.60.1.70374", started = <time()>,
      boot = { loadMs, loadKB, loginMs }, frames = <n>, zones = { "Elwynn Forest", ... }, -- zones: first 30
      perf = { frames, p50, p95, p99, max, overruns,  -- our cost a frame (ms), outside graces
               grace = { login, loading, map, gc },   -- slowest frame (ms) in each grace
               slow = { { name, n, max }, ... },      -- the 5 calls with most overruns
               kbMin, kbMax,                          -- Lua KB: all addons' heap (sampled)
               kbPerSec, kbFrameP95, kbFrameMax, kbFrames, -- allocation outside graces (docs/runtime.md)
               ourKBLoad, ourKB,                      -- ours, after a full collect: 10 s after login, at logout
               alloc = { { name, kbPerSec, kbMax, calls }, ... },  -- top 5 allocators (KB/s; kbMax: one call's most)
               gaps = { { job, ms, stack }, ... },    -- a job ran longer than its budget between Yields
               ledger = { { frame, ms, top, events = { <events> } }, ... }, -- worst 5 frames outside graces, ±10 events
               byState = { [state] = { frames, p50, p95, p99, max } }, -- by map state: closed small big zoom drag
               errors, errorsPerHour, loadMs },       -- written at logout (and /reload) and with each mark
      kept = { <events> },  -- taint, art and sensor events, the first 50 (each one a bug)
      stats = { ["<kind> <layer>"] = { n, <field> = max |value|, lag } }, -- layout ends, swaps, blips sweeps
      bench = { [build] = { build, t, ops = { [op] = { n, ms, us } } } },  -- /mma bench regions (game/Bench.lua)
    },
  },
  _v = 1,               -- Game.Load's version stamp (docs/runtime.md "Saved data")
  errors = {            -- by key (name .. ": " .. first line), 50 kept (least recent dropped)
    [key] = { name, msg, stack, count, first = <time()>, last = <time()>, version, session },
  },
  marks = {             -- newest last, 20 kept
    { kind = "error" | "taint" | "mark" | "shot", note, t = <time()>, stamp = "MMDDYY_HHMMSS",
      session, version, frame, state = { ... }, trace = { <events> },
      motion = { { f, ms, cx, cy, zoom, px, py, w, h }, ... }, -- the last 120 frames, oldest first
      shot = { inst, cx, cy, zoom, w, h, left, top, big, uiScale, screenW, screenH } }, -- shot marks only
  },
}
```

- **Event**: `{ f = frame, ms = <ms since login>, k = kind, d = detail }`. `d` is a
  short string or a flat table of numbers and strings.
- **State** (Game assembles it; `map` and `layers` from UI's `View.diag()`): `you = { inst, col, row, facing }`, `zone`,
  `subzone`, `map = { shown, inst, cx, cy, zoom, follow, w, h }`, and
  `layers = { { name, busy, zoom, region = { c0, r0, c1, r1 } }, ... }` (the shown
  layout's; `zoom`/`region` nil before the first).
- **Motion**: one row a frame, sampled in the apply phase: `f`, `ms` (as an event's), the
  camera's centre `cx, cy` (tiles), `zoom` (px a tile) and view size `w, h` (UI's `View.camera`),
  and your position `px, py` (tiles; nil where the game hides it). Following, `cx, cy` = `px, py`.
  It's what to read for a tear: frame pacing (`ms` steps), camera steps in screen pixels, you
  against the camera, and the tile edges crossed.
- **Shot stamp**: what the screenshot shows, read when `/mma shot` runs: the map shown (`inst`), the
  camera (`cx, cy, zoom`), the view's size (`w, h`) and top-left on screen (`left, top`, UI units;
  nil while hidden), small or `big`, `uiScale` (UIParent's effective scale) and the screen in UI
  units (`screenW, screenH`). `note`'s first word is the shot's id (docs/playtest.md "Shots").
- **Errors' names**: the `Runtime.Wrap` name (e.g. `map: draw`), or `lua` for one
  the global error handler caught. "First occurrence" is per key per session: it
  sets the entry's `stack`, `version`, `session`, traces `error` (`d` = the key) and
  takes an `error` mark (`note` = the key).
- **Shot**: `stamp` is the local time formatted like the screenshot's file name
  (`WoWScrnShot_<stamp>.jpg`), taken when SCREENSHOT_SUCCEEDED fires.
- **Kept**: every event of a kind in Telemetry's `KEEP` (`taint`, `art`, `sensor`) as it's traced,
  the first 50 a session: the ring forgets them, and each one fails the gate.
- **Stats**: every `layout` end, `swap` and `blips` sweep as it's traced, by kind and layer:
  `n`, and the largest absolute value of each number in its `d` (a swap's `x`, `y` are canvas
  offsets: the tear's ~33,000 px suspect); a swap's `lag` is frames since its layer's last layout
  end (the end→swap delay).
- **Bench**: `Game.Bench.result` (M0.5, `/mma bench regions`) copied at logout and with each mark,
  keyed by its build: `ops[op] = { n, ms, us }`, `us` a call's µs (op names like `CreateLine`,
  `SetPoint`, `canvas.SetScale@1000live`, `canvas.Show@1000hidden`, `SetParent.park`).

## Trace kinds (so far)

`login`, `zone` (zone changed), `map` (shown or hidden), `cam` (a drag starts or
ends, wheel zoom, follow on/off: at most one per frame), `layout` (a rebuild:
start with its region, end with ms and regions used), `swap` (a layout shown,
with where it was placed), `error`, `taint`, `mark`, `shot`; and Runtime's (docs/runtime.md):
`slow` (a call over its budget), `spike` (a frame over its budget), `gap` (a job between
Yields over its budget), `throttled`, `job` (cancelled), `enter` (PLAYER_ENTERING_WORLD),
`position` (lost or back), `saved`; Game's `minimap` (the takeover engaged or released),
`art` (`/mma check art`: a name ui/Art.lua lists that the client lacks).

Their `d`:

| k | d |
|---|---|
| `login` | the version |
| `zone` | the zone's name |
| `map` | `"shown"` or `"hidden"` |
| `cam` | `{ e, cx, cy, zoom }`, `e` = `drag start` (follow turns off), `drag end`, `wheel`, `follow on` |
| `layout` | `{ e = "start", layer, inst, zoom, c0, r0, c1, r1 }`, then `{ e = "end", layer, ms, regions }` (`ms` wall time, over several frames), or `{ e = "failed", layer, retry }` |
| `swap` | `{ layer, x, y, scale }` |
| `error` | the error's key |
| `taint` | `{ e, fn }`: `e` = `blocked` (ADDON_ACTION_BLOCKED) or `forbidden` (ADDON_ACTION_FORBIDDEN), `fn` the protected function the client named |
| `art` | the missing atlas name or file |
| `mark`, `shot` | the note (nil without one) |
| `slow` | `{ name, ms, n }`: the call's 1st, 10th, then every 100th overrun (`n` = overruns so far) |
| `spike` | `{ ms, top, topMs, ... }`: the frame's cost and its slowest call; also its top allocator (M0.3) |
| `gap` | the job and how long it ran between Yields (M0.3; `perf.gaps` has its stack) |
| `throttled` | the name failing 10 calls in a row (now run once a second) |
| `job` | `{ name, e = "cancelled" }` |
| `enter` | `"login"`, `"reload"` or `"loading"` |
| `position` | `"lost"` or `"back"` |
| `saved` | `{ owner, e = "reset", was }` or `{ owner, e = "newer", v }` |
| `minimap` | `"engaged"` or `"released"` |

## Reading it

`.venv/bin/python tools/telemetry.py` finds the SavedVariables for the addon and
prints the sessions (with their perf), the newest session's attribution (`perf`:
allocators, gaps, the worst-frames ledger, per-state histograms, memory after GC,
layout/swap/sweep stats, the bench), its kept events, errors (with stacks), marks
(state, the motion ring's summary, each layout's start → end → swap with the end→swap
delay, and the trace around them), the newest screenshots matched to their shot marks
and paired with the reference shots, the validation report (`/mma check log`), and
client `Logs/` lines that mention the addon. It also lists
other addons' Lua errors in `Logs/` while ours was loaded (from each session's start to the
next's; any time when there are no sessions), `SHARED` first: an addon sharing our
`MagicMap` prefix, or an error naming a `MagicMap_` global. The spike's E1 (our old data
globals breaking it) named only its own files, so a filter on "MagicMapAtlas" missed it.

- `--trace`: every event of each mark's ring (not the last 40), each ledger frame's events, and
  each motion ring frame by frame: `dt`, the camera's step in screen pixels, you against the
  camera in pixels, `|col`/`|row` where a tile edge was crossed. `--trace N`: the last N events.
- `--budgets`: the newest session with perf against the budgets in docs/runtime.md, a
  PASS / FAIL line each and, under each FAIL, its **owner**: the frame budgets from the ledger
  (the call slowest in the worst frames, what that frame did), the per-state histograms and
  the gaps; allocation from `perf.alloc`; memory from `ourKBLoad` against `ourKB`; first open
  from `perf.slow`; errors from the session's errors. Then the gate's empties (docs/v1-plan.md §1):
  `perf.slow`, `perf.gaps`, `taint`, `art`, `sensor`, each named. Exit 1 on any FAIL.
  `--budgets --trace` also prints the perf, kept and marks sections it judged from.
- `--compare A B`: two sessions side by side with B − A: the budgets, memory after GC,
  per-state p95/p99/max, allocators, bench ops. A session is its id in the SavedVariables
  read, or `FILE:id` for another SavedVariables file (sessions roll off after 10: keep a copy).
- Shot pairing: a shot mark's id (its note's first word) is matched to the reference shot
  `docs/evidence/shots/<id>.jpg|png` (`--refs` for another folder); the reader prints both
  paths, the shot's stamp, and the reference ids with no shot this time.

Older SavedVariables (before these fields) still read: a missing field prints "not recorded"
and an owner says what's missing.
