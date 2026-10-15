# Telemetry

The addon can't reach the network, but WoW writes SavedVariables to disk on
`/reload` and logout, and this machine can read them (and the client's `Logs/`
and `Screenshots/`). So the loop is: play, `/reload`, run `tools/telemetry.py`.

## In game

- **Version stamp**: `tools/install.py` writes the checkout's version
  (`git describe --always --dirty`, e.g. `7aa8b30-dirty`) into the installed TOC's
  `## Version:`. Every record carries it (`GetAddOnMetadata(ADDON, "Version")`).
- **Errors**: everything `Runtime.Wrap` catches, and anything else the global
  error handler sees from our files, is kept with its stack.
- **Flight recorder**: `Runtime.Trace(kind, detail)` appends to an in-memory ring
  of the last 300 events. It's only persisted inside a mark.
- **Marks**: a snapshot of state plus the recorder's ring, taken on an error's
  first occurrence, on `/mma mark <note>`, and on `/mma shot` (which also takes a
  screenshot).

## SavedVariables: `MagicMapAtlasDB.telemetry`

```lua
telemetry = {
  sessions = {          -- newest last, last 10 kept
    { id = 1, version = "7aa8b30-dirty", build = "1.60.1.70374", started = <time()>,
      boot = { loadMs, loadKB, loginMs }, frames = <n>, zones = { "Elwynn Forest", ... }, -- zones: first 30
      perf = { frames, p50, p95, p99, max, overruns,  -- our cost a frame (ms), outside graces
               grace = { login, loading, map },       -- slowest frame (ms) in each grace
               slow = { { name, n, max }, ... },      -- the 5 calls with most overruns
               kbMin, kbMax, ourKB,                   -- Lua KB: all addons' heap (sampled), ours at logout
               errors, errorsPerHour, loadMs } },     -- written at logout (and /reload) and with each mark
  },
  _v = 1,               -- Game.Load's version stamp (docs/runtime.md "Saved data")
  errors = {            -- by key (name .. ": " .. first line), 50 kept (least recent dropped)
    [key] = { name, msg, stack, count, first = <time()>, last = <time()>, version, session },
  },
  marks = {             -- newest last, 20 kept
    { kind = "error" | "mark" | "shot", note, t = <time()>, stamp = "MMDDYY_HHMMSS",
      session, version, frame, state = { ... }, trace = { <events> } },
  },
}
```

- **Event**: `{ f = frame, ms = <ms since login>, k = kind, d = detail }`. `d` is a
  short string or a flat table of numbers and strings.
- **State** (Game assembles it; `map` and `layers` from UI's `View.diag()`): `you = { inst, col, row, facing }`, `zone`,
  `subzone`, `map = { shown, inst, cx, cy, zoom, follow, w, h }`, and
  `layers = { { name, busy, zoom, region = { c0, r0, c1, r1 } }, ... }` (the shown
  layout's; `zoom`/`region` nil before the first).
- **Errors' names**: the `Runtime.Wrap` name (e.g. `map: draw`), or `lua` for one
  the global error handler caught. "First occurrence" is per key per session: it
  sets the entry's `stack`, `version`, `session`, traces `error` (`d` = the key) and
  takes an `error` mark (`note` = the key).
- **Shot**: `stamp` is the local time formatted like the screenshot's file name
  (`WoWScrnShot_<stamp>.jpg`), taken when SCREENSHOT_SUCCEEDED fires.

## Trace kinds (so far)

`login`, `zone` (zone changed), `map` (shown or hidden), `cam` (a drag starts or
ends, wheel zoom, follow on/off: at most one per frame), `layout` (a rebuild:
start with its region, end with ms and regions used), `swap` (a layout shown,
with where it was placed), `error`, `mark`, `shot`; and Runtime's (docs/runtime.md):
`slow` (a call over its budget), `spike` (a frame over its budget), `throttled`,
`job` (cancelled), `enter` (PLAYER_ENTERING_WORLD), `position` (lost or back), `saved`;
Game's `minimap` (the takeover engaged or released).

Their `d`:

| k | d |
|---|---|
| `login` | the version |
| `zone` | the zone's name |
| `map` | `"shown"` or `"hidden"` |
| `cam` | `{ e, cx, cy, zoom }`, `e` = `drag start` (follow turns off), `drag end`, `wheel`, `follow on` |
| `layout` | `{ e = "start", layer, inst, zoom, c0, r0, c1, r1 }`, then `{ e = "end", layer, ms, regions }` (`ms` wall time, over several frames) |
| `swap` | `{ layer, x, y, scale }` |
| `error` | the error's key |
| `mark`, `shot` | the note (nil without one) |
| `slow` | `{ name, ms, n }`: the call's 1st, 10th, then every 100th overrun (`n` = overruns so far) |
| `spike` | `{ ms, top, topMs }`: the frame's cost and its slowest call |
| `throttled` | the name failing 10 calls in a row (now run once a second) |
| `job` | `{ name, e = "cancelled" }` |
| `enter` | `"login"`, `"reload"` or `"loading"` |
| `position` | `"lost"` or `"back"` |
| `saved` | `{ owner, e = "reset", was }` or `{ owner, e = "newer", v }` |
| `minimap` | `"engaged"` or `"released"` |

## Reading it

`.venv/bin/python tools/telemetry.py` finds the SavedVariables for the addon and
prints the sessions (with their perf), errors (with stacks), marks (state plus the trace around
them), the newest screenshots matched to their shot marks, the validation report
(`/mma check log`), and client `Logs/` lines that mention the addon. It also lists
other addons' Lua errors in `Logs/` while ours was loaded (from each session's start to the
next's; any time when there are no sessions), `SHARED` first: an addon sharing our
`MagicMap` prefix, or an error naming a `MagicMap_` global. The spike's E1 (our old data
globals breaking it) named only its own files, so a filter on "MagicMapAtlas" missed it.

`.venv/bin/python tools/telemetry.py --budgets` checks the newest session with perf
against the budgets in docs/runtime.md: a PASS / FAIL line each, exit 1 on any FAIL.
