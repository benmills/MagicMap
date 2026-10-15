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
      boot = { loadMs, loadKB, loginMs }, frames = <n>, zones = { "Elwynn Forest", ... } }, -- zones: first 30
  },
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
- **State** (Game assembles it): `you = { inst, col, row, facing }`, `zone`,
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
with where it was placed), `error`, `mark`, `shot`.

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

## Reading it

`.venv/bin/python tools/telemetry.py` finds the SavedVariables for the addon and
prints the sessions, errors (with stacks), marks (state plus the trace around
them), the newest screenshots matched to their shot marks, the validation report
(`/mma check log`), and client `Logs/` lines that mention the addon.
