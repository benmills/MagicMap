# Project structure

The repo root is the addon root. Folders follow architecture.md: two libraries
(Atlas, Runtime) under three systems (Game, Model, UI).

```
MagicMap.toc          load order (below), generated from each folder's files.txt
Data/                 generated Atlas data (the QuestieDB-derived five: NOTICE.md)
Textures/             generated textures the addon loads (the map art alone: BaseEasternKingdoms and BaseKalimdor: tools/gen_base.py; Repaint*: tools/ai_map.py, not under the GPLv3: NOTICE.md)
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
`MagicMap_OnAddonCompartmentClick`, the addon compartment's `AddonCompartmentFunc`) and the
`SLASH_*` names (`SlashCmdList` entries are fields of WoW's table), and six named frames:
`MagicMapFrame` (the client keeps a moved frame's place by its name),
`MagicMapMinimapStandIn` (the Minimap's children wait on it; for code that reads a parent's
name), `MagicMapWorldMapEscape` (game/Hooks.lua's Escape catcher:
`UISpecialFrames` holds names), `MagicMapFeel` (ui/Feel.lua's settings window), `MagicMapWelcome` (ui/Welcome.lua's
first-run dialog) and `MagicMapPopup` (ui/Popup.lua's pin popup), each named in `UISpecialFrames` so Escape closes it. tools/luacheck.py fails any other global write anywhere,
any other frame name (`FRAME_NAMES`), and any use of `_G`, `setglobal`, `getfenv` or
`setfenv` (they reach globals past the bytecode check).

The addon is `MagicMap` (folder and TOC), SavedVariables `MagicMap2DB`, slash `/mm` and `/magicmap`:
the spike's names but its SavedVariables (ADR 0007: the spike's aren't read), so the two can't
be installed together.

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
  labels (`Atlas.Labels`, Data/Labels.lua). Tables of a few hundred
  rows (maps, uiMaps, places) are indexed at first use, ≤0.2 ms each in lupa; per-key caches
  (`Atlas.Area`, the walk grid's tiles) aren't indexes.

- **Quest areas (the one game read in UI).** A QuestPOIFrame draws the client's quest areas
  (`DrawBlob`) and hit-tests them (`UpdateMouseOverTooltip`): game state read through a widget.
  Only game/Oracles.lua (the `Inside` sensor, unseen) and ui/Areas.lua (the areas you see, the
  spike's blobs, decided at M2: docs/brief.md §7) make one; `tools/luacheck.py` fails any other
  file that does (`POI_FILES`).

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
and `tools/install.py` writes `MagicMap.toc` from them (`MANIFESTS` there gives the
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
- `Runtime.Perf()` — per-name totals `{ n, ms, max, over }` and frames run, for `/mm perf load`;
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
- Diagnostics (M4.6): `Runtime.Record(seconds, name, done)` — the spike's `/mm perf` recording: the
  next frames, graces included, then `done(rec)` (`MM.Recording`: frames, the worst, hitches past
  `Runtime.HITCH`, our cost and each budgeted call's); `Runtime.recording` while it runs,
  `Runtime.RecordEnd()` ends it now. `Runtime.Gauge(name, fn)` — numbers a system keeps for `perf mem`
  (`Runtime.gauges[name]()`, wrapped: ui/Engine.lua's "map").
- `Runtime.boot` — `t0, mem0` at load start (runtime/Boot.lua); `loaded` = `{ t, mem }`
  once Atlas has loaded; `login` = `{ t, mem }` at PLAYER_LOGIN.

## Registries: a new piece is a new file

Shared files take additions by registration, so packages add files instead of editing
the same ones (each listed in its folder's `files.txt`):

| Registry | In | One file each | Called |
|---|---|---|---|
| `Game.Part(name, read, keep)` | game/Observe.lua | game/parts/ (`You`, `MinimapState`, `Addons`, `Quests`, `Offers`, `Waypoint`, `Corpse`, `Buttons`, `Clock`); `hooked` from game/Hooks.lua (registered at its load, so first) | observe step, each frame: `obs[name] = read(obs)` (nil: `keep`; false comes through, known none) in game/parts/files.txt's order, so a part may read those before it; each its own wrapped call (`game.part <name>`: timed, its KB counted, a failing one leaves its field nil, or `keep`: the table a per-frame part refills, `you`'s); per-frame parts refill one table, on-change parts hand a new one only when it changed (types/observation.lua) |
| `Game.Handle(kind, fn)` | game/Command.lua | game/commands/ (`slash`, `load`, `follow`, `tooltip`, `waypoint`, `way`, `button`) | input step, and again in the apply phase (one a ui step sent: carried out that frame): `fn(cmd)` for each queued command of that kind (types/view.lua Commands) |
| `Game.Apply(name, fn)` | game/Apply.lua | game/ (`Minimap`, `AddonPins`, `Tracking`, `Keep`, `Home`, `Chrome`, `Hooks`, `Button`, `Tooltip`, in game/files.txt's order), never game/parts or game/commands (luacheck `NOT_IN`) | apply phase, each frame: `fn(view)` as its own step `game.<name>`; view is `UI.View()`, or SAFE when Game doesn't know its `v`. Apply.lua's own first keeps `Game.shownInst` (the instance shown, false while hidden, nil before the first apply): what Game's parts read of View |
| `Model.Part(observe, load)`, `Model.Kind(kind, fn)` | model/Model.lua | model/ (`Rares`, `Quests`, `Offers`; `Target`: `corpse`, `waypoint` and `Model.Target()`; `Route`: `Model.Route()`) | `observe(obs, oracles)` each frame after Model's own `you`, `load(saved)` with Model's saved part; `Known(kind)` answers with `fn()` → list, rev (ADR 0006) |
| `Engine.Layer(name, level, build, rev, zoom)` | ui/Engine.lua | ui/ (`Tiles`, `Labels`, `Areas`: `questAreas`, `"hold"`; `Rares`, `Quests`, `You` through `Pins.Layer`; the path is a canvas of its own at level 8, not a layer: ui/Path.lua) | `build(canvas, inst, zoom, c0, r0, c1, r1)` in a layout job (the layouts share a frame's budget, one at a time, in turn: Engine.Draw's plan) when the view, zoom, map or `rev()` needs it; it returns true when it has nothing to draw at that zoom, or the zoom what it left out shows from (laid out again once a layout would draw it); regions from `Engine.Get`, tile (col, row) at `((col - canvas.ox) * zoom, -(row - canvas.oy) * zoom)` (the shared origin); `zoom` how it shows until the zoom settles: `"scale"` (tiles), `"move"` (placed with `Engine.At(canvas, region, point, col, row, dx?, dy?, minZoom?)`, moved to the camera's zoom: names, laid out at the camera's zoom each log(1.25) drift and where the zoom lands), `"pin"` (placed and moved so too: pins, laid out a drift on toward where the zoom is headed; a region with a `minZoom` stands on the canvas's frame for it, shown as the zoom crosses it, so a layer lays those out from `Engine.DRIFT` below it but zooming out: `Engine.From(zoom, minZoom)`), `"hold"` (borders). A region Got with a `key` (what it shows: a tile, a border piece) is taken back by the next layout on that canvas with `Engine.Keep(canvas, kind, key)` (nil: none, then `Engine.Get`), as it was set while `canvas.epoch` (the canvas's map, zoom, origin, the layer's rev) holds: a pan's layout sets only the ground it adds |
| `Pins.Layer(name, level, fill, rev, opts)` | ui/Pins.lua | ui/ (`Rares`; `Quests`: `quests` and `offers`; `You`: `corpse` and `waypoint`) | the one pin store (spike-bugs D1): an Engine `"pin"` layer whose layout calls `fill(put, inst, zoom, want)`; `put(e, look, minZoom?)` for each MM.Known entry it would draw, kept by `e.key` on its canvas (`Engine.Keep`) so a layout sets only what changed: its look (StylePin, Layers.lua:304-400, each setter only when its value differs) and its place; `want(minZoom)`: whether pins from that zoom draw in this layout (`Engine.From`). `opts`: `lines(e)` → title, lines... for its tooltip (default `e.name`, `e.text`), `tooltip(tip, e)` to fill it itself (GameTooltip, or the popup), `hover(e or nil)` (ui/Window.lua's left click calls `Pins.Tap` first: pins beat areas; a click grows the pin's tooltip into the popup, ui/Popup.lua, its buttons `Track.Actions(e)`, ui/Track.lua: Track or Path to sets the waypoint at the icon; a quest pin's follow it). Every pin layer's `rev` carries `Track.Rev()` and `PinTypes.Rev()`; a look's `type` (ui/PinTypes.lua) sets its style: a hidden type is never put, its size a factor on the look's, its opacity, its chosen icon. A pin is a frame that never takes the mouse: while the view has it, `Pins.Hovered()` is the pin under the cursor on the canvases shown (the topmost layer's, the nearest centre); the tips' one look (small facts in one grey, `Tip.Small`'s fonts put back when a tooltip hides or clears) is ui/Tip.lua's |
| `Menus.Layer(row)` | ui/Menus.lua | the layer's own file in ui/, after Menus.lua (`labels`, `rares` are in Menus.lua itself) | each time the gear opens: `row = { key, label, group, tip, default?, parent?, onToggle? }` is a checkbox in its group's submenu (`group`: `map`, `quests`, `places`, `nearby`, `addons`, after the spike's order: Layers.lua:30-70; a group with no row is left out; each submenu an "All" box on top and each row's icon; `nearby` then lists Blizzard's tracking types), its rows in the spike's order whenever added (Menus.lua's ORDER, the spike's keys: a new layer takes its spike key, or adds its own there; one not listed goes last), with its tip (white title, gold body); `key` is the Engine.Layer's name (and View.layers', for Game's); its setting is read with `Engine.LayerOn` and set with `Engine.SetLayer` (UI.saved.layers holds only the keys that aren't their default, types/saved.lua); `default`: false for a layer off until turned on (missing: on: Engine.defaults); `parent`: indented 5 spaces, clickable only while that layer is on; `onToggle(on)` after a flip. Other addons' rows come from Model.addons (each with world pins; ui/Sockets.lua keeps their View.layers keys) |

The map window: ui/Camera.lua (where it looks: `cam`, `inst`, `follow`; `Camera.ZoomSettled()`,
`Camera.Settled()`, `Camera.Velocity()`), ui/Window.lua (the frame; routes the view's input to Motion;
its `map: draw` step), ui/Engine.lua (layers, canvases, layout jobs, the shared origin, park, swap by
alpha: docs/runtime.md "The map's engine"), ui/Motion.lua (wheel
and button zoom, drag, follow, chase, flights, idle return), ui/Chrome.lua (the metal border,
band and grip), ui/Controls.lua (the buttons, hover reveal, tips), ui/Title.lua (the title
band), ui/BigMap.lua (the minimap form, grow and shrink: Model.hooked, the home spot from
Model.minimap), ui/Menus.lua (the client's menus: the gear's layers, `Menus.Layer`, its Minimap buttons (game/MinimapButtons.lua: Model.buttons, the button Command) and Settings; the map's right-click),
ui/Replace.lua (what MagicMap replaces, the minimap and the world map: `Replace.Get/Set/Chosen`, saved as UI.saved.replace;
it migrates 2.0's `saved.worldmap` ("Override world map", retired) and `saved.minimap` to it at load: an existing player keeps
both on), ui/Welcome.lua (the first-run welcome, `MagicMapWelcome`: four cards, one chosen, Continue saves it through Replace;
shown on the first open while nothing is chosen, and by `/mm welcome`), ui/Feel.lua (the settings window, `MagicMapFeel`: the gear's
Settings, `/mm feel`, `/mm settings`, and Options -> AddOns; a sidebar of pages, General, Map, Title, Pins, Quest pill, Pill layout, Tracking, Pathing, Quest
areas, Diagnostics, each built from the settings its owners declare next to their code, `UI.Feel.Add` (loaded right after
ui/Window.lua, so every UI file can: docs/development.md "How to add a setting"); `UI.Feel.Get/Set/rev`, saved as UI.saved.feel, the
last page as UI.saved.feelPage), game/Options.lua (the client's own Options -> AddOns -> MagicMap entry: a button that opens the settings
window; nothing is made without the client's Settings API), ui/Base.lua (the base picture: one stylised texture a continent from
Data/Base.lua and Textures/Base*.blp, drawn under the tiles at every zoom, an underlay only for where they aren't yet),
ui/Repaint.lua (the map art repairs: AI-repainted patches from Data/Repaint.lua and Textures/Repaint*.blp over the tiles' broken ground,
the setting `repaint.on`, on by default; nothing drawn when it's off or on another game build: docs/decisions/0011-ai-map-art.md),
ui/PinTypes.lua (the pin inventory: every type of pin, declared beside its look by the file that draws it, Settings > Pins
built from them, and `Types.Of(id)`: a type's show, size, opacity, icon and grouping, resolved for all types as `Feel.rev`
moves), ui/Pins.lua (the one pin store: `Pins.Layer`, StylePin, hover, pin tooltips, clicks), ui/Resources.lua (the tracker kept on, View.keep, and Settings > Resources), ui/Track.lua (a pin's
actions, its popup's buttons: Track or Path to any icon, the waypoint at it, `UI.saved.tracked` and `UI.saved.path`),
ui/Tip.lua (every tip's one look) and ui/Popup.lua (the popup a pin's click grows its tooltip into), ui/Guide.lua (Track's gold arrow,
placed along the route), ui/Path.lua (Path to's line and the small map's framing of it: `Motion.Frame`),
ui/Sockets.lua (View.sockets: the world socket Game hosts other addons' HereBeDragons pins on,
game/AddonPins.lua) and ui/You.lua (your arrow, over them all). The spike bugs' replays are one
file each, tools/tests/replays/R-<id>.lua, collected by tools/tests/test_spike_bugs.py.

## Slash commands

`ns.Game.Slash(name, help, fn)` registers `/mm <name>` (`fn(args)`, wrapped); `/mm`
alone is the name `""` (UI's: the map shown or hidden, as the spike's `/mm`), and an unknown
name lists them. A name may be two words (`check art`): it wins over its first word's.
UI registers its own through `Game.Command({ kind = "slash", ... })`.

## One flow end to end: Minimap blips

MagicMap draws no blips of its own: since 1.60.1.70862 addon code can't read them
(`Minimap:UpdateMouseoverAtPoint` is ignored for it), so Blizzard's Minimap draws them over our map.

    apply    game/Minimap.lua   Game.Apply("minimap"): View.minimap "ours" + window shown: Blizzard's
                                Minimap the overlay, over the tiles inside View.window.place, centred
                                on you, its view radius as many yards as ours, no ground (undo list;
                                "blizzard": released); its blips' tooltips Blizzard's
             game/Tracking.lua  Blizzard's tracking of what our layers draw (flight, quests, pois) off
    observe  game/parts/MinimapState.lua  obs.minimap: engaged, overlaid (its arrow is yours), the
                                Minimap's zoom steps, mouse / blip (UI's hovers give way to a blip)
    ui       ui/View.lua        UI.View(): minimap, window (place), here (you on the view)
             ui/Motion.lua      the wheel steps through Blizzard's zooms while you're followed
    tests    tools/tests/test_takeover.py, replays R-G1, R-G2, R-G3

## Saved data and what Game hands over

- `ns.Game.Load(owner, fn, spec)` — `fn(MagicMap2DB[owner])` once SavedVariables are loaded
  (at once if they are). Owner is the system: Model's is `Game.Load("Model", Model.Load,
  Model.SAVED)` (game/Observe.lua), UI's comes through a `load` Command. `spec = { version, defaults,
  optional, migrate(saved, from) }`: fn always gets a table of the current version (docs/runtime.md "Saved data").
- Each frame's observe step hands `ns.Model.Observe(obs, oracles)` an observation (types/observation.lua):
  `obs.you = { inst, col, row, facing, uiMap, zone, subzone, level, faction, dead, ghost, combat }` (nil fields:
  unknown), `obs.minimap`, `obs.hooked`, `obs.addons`, and Model keeps `ns.Model.you`:
  the last known position, `stale = true` while there's none (the rest: this frame's).
- Game's own part, `Game.Load("Game", ...)` (game/Game.lua): `Game.saved`, the minimap button's
  angle and the tracking it turned off (types/saved.lua MM.SavedGame).
