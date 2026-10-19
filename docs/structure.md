# Project structure

The repo root is the addon root. Folders follow architecture.md: two libraries
(Atlas, Runtime) under three systems (Game, Model, UI).

```
MagicMapAtlas.toc     load order (below), generated from each folder's files.txt; addon name until we merge into MagicMap
Data/                 generated Atlas data (some gitignored: QuestieDB-derived)
Textures/             generated textures the addon loads (Sea, ...)
atlas/                Atlas library: facts that hold (plain Lua 5.1, no WoW API)
runtime/              Runtime library: when things run (frame steps, slices, timers, events, perf)
game/                 Game system: the only code that touches the WoW API, other addons, SavedVariables
game/parts/           the observation's parts (Game.Part), one file each
game/commands/        the command kinds Game carries out (Game.Handle), one file each
model/                Model system: what we know (plain Lua; sees only what it's handed)
ui/                   UI system: what you see and do (frames, drawing, input → commands)
types/                LuaLS annotations of the contracts between pieces (not in the TOC, not shipped)
tools/                generators, exporters, install/package, luacheck, tests (not shipped)
tools/tests/replays/  the spike bugs' replays, R-<id>.lua, one each (test_spike_bugs.py runs them)
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

**Nothing is global** except, in game/ only, what the TOC names (the SavedVariables, and
`MagicMapAtlasOnAddonCompartmentClick`, the addon compartment's `AddonCompartmentFunc`) and the
`SLASH_*` names (`SlashCmdList` entries are fields of WoW's table), and three named frames:
`MagicMapAtlasMap` (the client keeps a moved frame's place by its name),
`MagicMapAtlasMinimapStandIn` (the Minimap's children wait on it; named as the spike's was,
for code that reads a parent's name) and `MagicMapAtlasEscape` (game/Hooks.lua's Escape catcher:
`UISpecialFrames` holds names). tools/luacheck.py fails any other global write anywhere,
any other frame name (`FRAME_NAMES`), and any use of `_G`, `setglobal`, `getfenv` or
`setfenv` (they reach globals past the bytecode check).

While this is "MagicMapAtlas": SavedVariables `MagicMapAtlasDB`, slash `/mma`. It shares
no names with the MagicMap spike, so both can be enabled.

## Rules

- **Dividing (spike-bugs E3).** WoW's Lua raises "Division by zero" where plain Lua (lupa,
  so every test) gives inf or nan. In atlas/, model/, game/, ui/ and runtime/, each `/`
  divides by a numeric literal other than 0, a named constant (UPPER_CASE, two characters
  or more: `TILE_YARDS`, `Atlas.Walk.CHUNKS`), or its line carries `-- /: never 0 (<why>)`,
  the why true by construction (a clamp, a minimum, a check beside it, what the client
  guarantees: an effective scale is > 0).
  Fix at the source first: `Atlas.Camera.Fit` takes a minimum span, so one point fits.
  `tools/lint_div.py` (in `tools/check.sh`) fails on any other `/`; `MM_STRICT=1` makes
  the sim raise as the client does (check.sh, so CI, runs the tests both ways).
- **Atlas first use.** A whole-table Atlas index (built by walking every row of a Data
  table of thousands: NPCs, objects, items, quests, areas) is built offline, by its
  generator into Data/, or takes `step` and calls it every 128 rows, so a caller in a
  `Runtime.Job` passes `Runtime.Yield` and the first use spreads over frames
  (`Atlas.Rares`, `SpawnsIn`, `ZoneLevels`, `Find`'s names and its scan: R-P2 runs each in a 1 ms
  job, every resume ≤2 ms on a clock counting Lua's instructions). Offline: the ranked
  labels (`Atlas.Labels`, Data/Labels.lua) and a blip name's service (`Atlas.BlipService`,
  Data/BlipServices.lua; there's no name → NPC index at runtime). Tables of a few hundred
  rows (maps, uiMaps, places) are indexed at first use, ≤0.2 ms each in lupa; per-key caches
  (`Atlas.Area`, the walk grid's tiles) aren't indexes.

## Load order (TOC)

1. `runtime/Boot.lua` — marks the load start (time, Lua memory)
2. `Data/*.lua` — in `atlas/files.txt` order
3. `atlas/*.lua` — in `atlas/files.txt` order
4. `runtime/files.txt`, `model/files.txt`, `game/files.txt`, `game/commands/files.txt`,
   `game/parts/files.txt`, `ui/files.txt` (`MANIFESTS` in tools/install.py). Model first: Game
   hands it observations and its saved part; UI sends Game commands at load. Game's subfolders
   after all of game/: they register into it, and game/parts/ registers in observe order.

The TOC lists files explicitly (no XML), and is generated: each folder lists its files, in
order, in its own `files.txt` (paths from the repo root; `atlas/files.txt` holds Data/ too),
and `tools/install.py` writes `MagicMapAtlas.toc` from them (`MANIFESTS` there gives the
folders' order). A new file goes in its folder's `files.txt`, then `tools/install.py --toc`;
`tools/luacheck.py` (so `tools/check.sh`) fails while the committed TOC differs, or a `.lua`
isn't listed.

## Runtime (the contract other pieces use)

- `Runtime.Step(phase, name, fn, opts)` — run `fn(elapsed)` every frame in phase order
  `input, observe, model, ui, apply` (architecture.md "Each frame"). Steps marked
  `opts = { shownOnly = frame }` run only while that frame is shown (IsVisible);
  `opts.budgetMs` overrides the per-call budget (2 ms). A step added during a frame runs from the next.
- `Runtime.On(event, name, fn)` — WoW event handler, `fn(event, ...)` (Game registers; Runtime dispatches;
  luacheck's `ONLY` keeps it in game/).
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
- `Runtime.Perf()` — per-name totals `{ n, ms, max, over }` and frames run, for `/mma perf load`;
  `Runtime.errors` — `{ name, err, n }` per failing name.
- `Runtime.FrameStats()` — our cost a frame, outside graces: `{ frames, p50, p95, p99, max, overruns,
  kbMin, kbMax, grace = { [name] = slowest ms }, graceTop = { [name] = { top, topMs } }, slow = { { name, n, max } } }`
  and who to blame:
  `alloc`, `gaps`, `ledger`, `byState` (docs/runtime.md "Attribution");
  `Runtime.Grace(name, seconds)` — the next frames are expected slow (login, loading, first map open);
  `Runtime.SetState(state)` — UI's map state (`closed`, `small`, `big`, `zoom`, `drag`), for `byState`.
  Each caught error (every time, with its stack) goes to `Runtime.onError(name, err, stack)`
  if set (game/Telemetry.lua persists it).
- `Runtime.Trace(kind, detail)` — a ring of the last 300 events, each handed on to
  `Runtime.onTrace(kind, detail)` if set (game/Telemetry.lua: the kinds it keeps or counts);
  `Runtime.TraceCopy()` copies it, oldest first (docs/telemetry.md). `onError` and `onTrace` are
  the only Runtime fields another system sets.
- `Runtime.boot` — `t0, mem0` at load start (runtime/Boot.lua); `loaded` = `{ t, mem }`
  once Atlas has loaded; `login` = `{ t, mem }` at PLAYER_LOGIN.

## Registries: a new piece is a new file

Shared files take additions by registration, so packages add files instead of editing
the same ones (each listed in its folder's `files.txt`):

| Registry | In | One file each | Called |
|---|---|---|---|
| `Game.Part(name, read, keep)` | game/Observe.lua | game/parts/ (`You`, `Blips`, `MinimapState`, `Addons`); `hooked` from game/Hooks.lua (registered at its load, so first) | observe step, each frame: `obs[name] = read(obs) or keep` in game/parts/files.txt's order, so a part may read those before it; each its own wrapped call (`game.part <name>`: timed, its KB counted, a failing one leaves its field nil, or `keep`: the table a per-frame part refills, `you`'s); per-frame parts refill one table, on-change parts hand a new one only when it changed (types/observation.lua) |
| `Game.Handle(kind, fn)` | game/Command.lua | game/commands/ (`slash`, `load`) | input step: `fn(cmd)` for each queued command of that kind (types/view.lua Commands) |
| `Game.Apply(name, fn)` | game/Apply.lua | game/ (`Minimap`, `AddonPins`, `Home`, `Chrome`, `Hooks`, `Button`, `Tooltip`, in game/files.txt's order) | apply phase, each frame: `fn(view)` as its own step `game.<name>`; view is `UI.View()`, or SAFE when Game doesn't know its `v` |
| `Model.Part(observe, load)`, `Model.Kind(kind, fn)` | model/Model.lua | model/ (`Blips`, `Rares`) | `observe(obs, oracles)` each frame after Model's own `you`, `load(saved)` with Model's saved part; `Known(kind)` answers with `fn()` → list, rev (ADR 0006) |
| `Engine.Layer(name, level, build, rev, zoom)` | ui/Engine.lua | ui/ (`Tiles`, `Borders`, `Labels`, `Blips`, `Rares`) | `build(canvas, inst, zoom, c0, r0, c1, r1)` in a layout job (one at a time, by level) when the view, zoom, map or `rev()` needs it; regions from `Engine.Get`, tile (col, row) at `((col - canvas.ox) * zoom, -(row - canvas.oy) * zoom)` (the shared origin); `zoom` how it shows until the zoom settles: `"scale"` (tiles), `"move"` (placed with `Engine.At`: labels, pins), `"hold"` (borders) |

The map window: ui/Camera.lua (where it looks: `cam`, `inst`, `follow`; `Camera.ZoomSettled()`,
`Camera.Settled()`, `Camera.Velocity()`), ui/Window.lua (the frame; routes the view's input to Motion;
its `map: draw` step), ui/Engine.lua (layers, canvases, layout jobs, the shared origin, park, swap by
alpha: docs/runtime.md "The map's engine"), ui/Motion.lua (wheel
and button zoom, drag, follow, chase, flights, idle return), ui/Chrome.lua (the metal border,
band and grip), ui/Controls.lua (the buttons, hover reveal, tips), ui/Title.lua (the title
band), ui/BigMap.lua (the minimap form, grow and shrink: Model.hooked, the home spot from
Model.minimap), ui/Menus.lua (the client's menus; the gear, the map's right-click),
ui/Sockets.lua (View.sockets: the world socket Game hosts other addons' HereBeDragons pins on,
game/AddonPins.lua) and ui/You.lua (your arrow, over them all). The spike bugs' replays are one
file each, tools/tests/replays/R-<id>.lua, collected by tools/tests/test_spike_bugs.py.

## Slash commands

`ns.Game.Slash(name, help, fn)` registers `/mma <name>` (`fn(args)`, wrapped); `/mma`
alone is the name `""` (UI's: the map shown or hidden, as the spike's `/mm`), and an unknown
name lists them. A name may be two words (`check art`): it wins over its first word's.
UI registers its own through `Game.Command({ kind = "slash", ... })`.

## One flow end to end: Minimap blips

    apply    game/Minimap.lua   Game.Apply("minimap"): View.minimap "ours" + window shown: Blizzard's
                                Minimap an unseen sensor under View.window.place (undo list;
                                "blizzard": released)
    observe  game/Blips.lua     Game.Blips(): a slice of the sweep where Apply placed it, once still;
                                a `blips` trace each sweep
             game/parts/Blips.lua  the blips part (after you)
             game/parts/MinimapState.lua  obs.minimap (sensing: the blips part read)
             game/Observe.lua   the parts → Model.Observe(obs, oracles); Game.oracles (Inside:
                                game/Oracles.lua, on hidden QuestPOI frames)
             game/Record.lua    /mma record on|off: the observations, for replay
    model    model/Blips.lua    Known("blips") (sensed now, deduped against the remembered) and
                                Known("remembered") (saved.blips, Focus's instance, bucketed by cell)
    ui       ui/Blips.lua       the "blips" layer (Engine.Layer) draws both (the remembered from zoom 60),
                                redrawn on their revs
             ui/View.lua        UI.View(): minimap, window (place, still), layers; Model.Focus
    tests    tools/tests/test_blips.py: end to end in the sim (and /reload); Model alone replaying
             tools/tests/fixtures/blips_stream.lua (tools/tests/replay.lua)

## Saved data and what Game hands over

- `ns.Game.Load(owner, fn, spec)` — `fn(MagicMapAtlasDB[owner])` once SavedVariables are loaded
  (at once if they are). Owner is the system: Model's is `Game.Load("Model", Model.Load,
  Model.SAVED)` (game/Observe.lua), UI's comes through a `load` Command. `spec = { version, defaults,
  optional, migrate(saved, from) }`: fn always gets a table of the current version (docs/runtime.md "Saved data").
- Each frame's observe step hands `ns.Model.Observe(obs, oracles)` an observation (types/observation.lua):
  `obs.you = { inst, col, row, facing, uiMap, zone, subzone, level, faction, dead, ghost, combat }` (nil fields:
  unknown), `obs.blips`, `obs.minimap`, `obs.hooked`, `obs.addons`, and Model keeps `ns.Model.you`:
  the last known position, `stale = true` while there's none (the rest: this frame's).
- Game's own part, `Game.Load("Game", ...)` (game/Game.lua): `Game.saved`, the minimap button's
  angle and the tracking it turned off (types/saved.lua MM.SavedGame).
