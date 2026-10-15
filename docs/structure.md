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
tools/                generators, exporters, install/package, luacheck, tests (not shipped)
demo/                 web demo of Atlas (not shipped)
docs/                 architecture notes and data contract (not shipped)
```

## Namespace

Every file starts `local ADDON, ns = ...`. Each piece hangs one table off `ns`:
`ns.Atlas`, `ns.Runtime`, `ns.Game`, `ns.Model`, `ns.UI`. Files within a piece
share that table; nothing else is global except the generated `MagicMap_*` data
tables, the SavedVariables, and the `SLASH_`/`SlashCmdList` entries.

While this is "MagicMapAtlas": SavedVariables `MagicMapAtlasDB`, slash `/mma`.
Its data globals have the same names as the MagicMap spike's (`MagicMap_Tiles`,
...), so disable the spike while testing this one.

## Load order (TOC)

1. `runtime/Boot.lua` — marks the load start (time, Lua memory)
2. `Data/*.lua` — in `atlas/files.txt` order
3. `atlas/*.lua` — in `atlas/files.txt` order
4. `runtime/*.lua` (rest), `game/*.lua`, `model/*.lua`, `ui/*.lua`

The TOC lists files explicitly (no XML).

## Runtime (the contract other pieces use)

- `Runtime.Step(phase, name, fn, opts)` — run `fn(elapsed)` every frame in phase order
  `input, observe, model, ui, apply` (architecture.md "Each frame"). Steps marked
  `opts = { shownOnly = frame }` run only while that frame is shown (IsVisible).
- `Runtime.On(event, name, fn)` — WoW event handler, `fn(event, ...)` (Game registers; Runtime dispatches).
- `Runtime.After(seconds, name, fn)`, `Runtime.Every(seconds, name, fn)` — timers, `fn()`;
  they return a handle for `Runtime.Cancel(handle)` (jobs too).
- `Runtime.Job(name, fn, budgetMs)` — run `fn` as a coroutine, resumed each frame
  until done, yielding via `Runtime.Yield()` once the frame's budget is spent
  (default 2 ms; `Yield` outside a job does nothing). The handle's `.done` is set when it ends.
- `Runtime.Wrap(name, fn)` — every callback above is wrapped: timed (perf) and
  isolated (an error is caught, reported once, and the rest keep running).
- `Runtime.Perf()` — per-name totals `{ n, ms, max }` and frames run, for `/mma perf`;
  `Runtime.errors` — `{ name, err, n }` per failing name.
- `Runtime.boot` — `t0, mem0` at load start (runtime/Boot.lua); `loaded` = `{ t, mem }`
  once Atlas has loaded; `login` = `{ t, mem }` at PLAYER_LOGIN.

## Slash commands

`ns.Game.Slash(name, help, fn)` registers `/mma <name>` (`fn(args)`, wrapped); `/mma`
alone lists them.

## Saved data and what Game hands over

- `ns.Game.Load(owner, fn)` — `fn(MagicMapAtlasDB[owner])` once SavedVariables are loaded
  (at once if they are). Owner is the system, e.g. `"UI"`, `"Model"`.
- Each frame's observe step hands `ns.Model.Observe(obs)` an observation:
  `obs.you = { inst, col, row, facing }`, and Model keeps `ns.Model.you` (nil fields: unknown).
