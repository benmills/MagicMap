# Project structure

The repo root is the addon root. Folders follow architecture.md: two libraries
(Atlas, Runtime) under three systems (Game, Model, UI).

```
MagicMapAtlas.toc     load order (below); addon name until we merge into MagicMap
Data/                 generated Atlas data (some gitignored: QuestieDB-derived)
Textures/             generated textures the addon loads (Sea, ...)
atlas/                Atlas library: facts that hold (plain Lua 5.1, no WoW API)
runtime/              Runtime library: when things run (frame steps, slices, timers, events, perf)
game/                 Game system: the only code that touches the WoW API, other addons, SavedVariables
model/                Model system: what we know (plain Lua; sees only what it's handed)
ui/                   UI system: what you see and do (frames, drawing, input → commands)
types/                LuaLS annotations of the contracts between pieces (not in the TOC, not shipped)
tools/                generators, exporters, install/package, luacheck, tests (not shipped)
demo/                 web demo of Atlas (not shipped)
docs/                 architecture notes and data contract (not shipped)
docs/decisions/       decision records, one per locked contract (ADR style, numbered)
.luarc.json           points LuaLS at types/ (Lua 5.1)
```

## Contracts (types/ and docs/decisions/)

The one-way doors between pieces are typed in `types/` (`---@meta` files LuaLS reads
through `.luarc.json`; the game never loads them) and each has a decision record:

| Contract | Types | Record |
|---|---|---|
| Observation and Oracles (Game → Model) | types/observation.lua, types/core.lua | docs/decisions/0001-observation-and-oracles.md |
| Focus (UI → Model) | types/focus.lua | docs/decisions/0002-focus.md |
| View (UI → Game, Apply) and Commands (UI → Game, Input) | types/view.lua | docs/decisions/0003-view-and-commands.md |
| SavedVariables, per owner | types/saved.lua | docs/decisions/0004-saved-variables.md |
| Runtime | types/runtime.lua | docs/decisions/0005-runtime.md (numbers: docs/runtime.md) |
| Model's read API (UI → Model) | types/model.lua | docs/decisions/0006-model-read-api.md |

Each types file says which parts are LOCKED and which stay OPEN. UI, Model and Atlas
internals aren't contracts. What v1 won't do: docs/v1-non-goals.md (draft).

For the WoW API's types too, install the "WoW API" extension (ketho.wow-api) for
VS Code: it adds its annotations to LuaLS's library for a folder with a .toc.

## Namespace

Every file starts `local ADDON, ns = ...`. Each piece hangs one table off `ns`:
`ns.Atlas`, `ns.Runtime`, `ns.Game`, `ns.Model`, `ns.UI`. Files within a piece
share that table. The generated data is `ns.Data` too (docs/atlas-data.md "The
wrapper"), never a global: a global is shared with every addon, and the rebuild's old
`MagicMap_*` data globals broke the MagicMap spike, which has the same names
(docs/evidence/spike-bugs.md E1).

**Nothing is global** except, in game/ only, the SavedVariables (the TOC's) and the
`SLASH_*` names (`SlashCmdList` entries are fields of WoW's table). tools/luacheck.py
fails any other global write anywhere, and any use of `_G`, `setglobal`, `getfenv` or
`setfenv` (they reach globals past the bytecode check).

While this is "MagicMapAtlas": SavedVariables `MagicMapAtlasDB`, slash `/mma`. It shares
no names with the MagicMap spike, so both can be enabled.

## Load order (TOC)

1. `runtime/Boot.lua` — marks the load start (time, Lua memory)
2. `Data/*.lua` — in `atlas/files.txt` order
3. `atlas/*.lua` — in `atlas/files.txt` order
4. `runtime/*.lua` (rest), `model/*.lua`, `game/*.lua`, `ui/*.lua` (Model first: Game hands it
   observations and its saved part; UI sends Game commands at load)

The TOC lists files explicitly (no XML).

## Runtime (the contract other pieces use)

- `Runtime.Step(phase, name, fn, opts)` — run `fn(elapsed)` every frame in phase order
  `input, observe, model, ui, apply` (architecture.md "Each frame"). Steps marked
  `opts = { shownOnly = frame }` run only while that frame is shown (IsVisible);
  `opts.budgetMs` overrides the per-call budget (2 ms). A step added during a frame runs from the next.
- `Runtime.On(event, name, fn)` — WoW event handler, `fn(event, ...)` (Game registers; Runtime dispatches).
  An event fired during a frame (by an API call a step made) is dispatched after the frame's phases.
- `Runtime.After(seconds, name, fn)`, `Runtime.Every(seconds, name, fn)` — timers, `fn()`;
  they return a handle for `Runtime.Cancel(handle)` (jobs too).
- `Runtime.Job(name, fn, budgetMs, maxFrames)` — run `fn` as a coroutine, resumed each frame
  until done, yielding via `Runtime.Yield()` once the frame's budget is spent
  (default 2 ms; `Yield` outside a job does nothing). The handle's `.done` is set when it ends;
  `.err` if it failed or was cancelled (still running after `maxFrames` resumes, default 600).
- `Runtime.Wrap(name, fn, budgetMs)` — every callback above is wrapped: timed (perf), budgeted
  (a call over `budgetMs`, default 2 ms, is an overrun), and isolated (an error is caught,
  reported once, and the rest keep running; one failing 10 calls in a row then runs once a second
  until it succeeds). docs/runtime.md has the guarantees.
- `Runtime.Perf()` — per-name totals `{ n, ms, max, over }` and frames run, for `/mma perf`;
  `Runtime.errors` — `{ name, err, n }` per failing name.
- `Runtime.FrameStats()` — our cost a frame, outside graces: `{ frames, p50, p95, p99, max, overruns,
  kbMin, kbMax, grace = { [name] = slowest ms }, slow = { { name, n, max } } }`;
  `Runtime.Grace(name, seconds)` — the next frames are expected slow (login, loading, first map open).
  Each caught error (every time, with its stack) goes to `Runtime.onError(name, err, stack)`
  if set (game/Telemetry.lua persists it).
- `Runtime.Trace(kind, detail)` — a ring of the last 300 events; `Runtime.TraceCopy()`
  copies it, oldest first (docs/telemetry.md).
- `Runtime.boot` — `t0, mem0` at load start (runtime/Boot.lua); `loaded` = `{ t, mem }`
  once Atlas has loaded; `login` = `{ t, mem }` at PLAYER_LOGIN.

## Slash commands

`ns.Game.Slash(name, help, fn)` registers `/mma <name>` (`fn(args)`, wrapped); `/mma`
alone lists them. UI registers its own through `Game.Command({ kind = "slash", ... })`.

## One flow end to end: Minimap blips

    apply    game/Minimap.lua   View.minimap "ours" + window shown: Blizzard's Minimap an unseen
                                sensor under View.window.place (undo list; "blizzard": released)
    observe  game/Blips.lua     Game.Blips(): a slice of the sweep where Apply placed it, once still
             game/Observe.lua   obs.blips, obs.minimap → Model.Observe(obs, oracles)
             game/Record.lua    /mma record on|off: the observations, for replay
    model    model/Blips.lua    merged with the remembered (saved.blips): Known("blips")
    ui       ui/Blips.lua       the "blips" layer draws Known("blips"), redrawn on its rev
             ui/View.lua        UI.View(): minimap, window (place, still), layers; Model.Focus
    tests    tools/tests/test_blips.py: end to end in the sim (and /reload); Model alone replaying
             tools/tests/fixtures/blips_stream.lua (tools/tests/replay.lua)

## Saved data and what Game hands over

- `ns.Game.Load(owner, fn, spec)` — `fn(MagicMapAtlasDB[owner])` once SavedVariables are loaded
  (at once if they are). Owner is the system: Model's is `Game.Load("Model", Model.Load,
  Model.SAVED)` (game/Observe.lua), UI's comes through a `load` Command. `spec = { version, defaults,
  migrate(saved, from) }`: fn always gets a table of the current version (docs/runtime.md "Saved data").
- Each frame's observe step hands `ns.Model.Observe(obs, oracles)` an observation (types/observation.lua):
  `obs.you = { inst, col, row, facing }` (nil fields: unknown), `obs.blips`, `obs.minimap`, and Model keeps `ns.Model.you`:
  the last known position, `stale = true` while there's none.
