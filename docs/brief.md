# Agent brief: read this first

The one page an agent reads before working here. The other docs are references: **open a full doc
only for the section you need, and grep it** (`grep -n 'R-P5' docs/*.md`,
`sed -n '/^### Saved data/,/^##/p' docs/runtime.md`); don't read them whole. Then get your package:

    .venv/bin/python tools/brief.py M2.1   # its plan row, milestone Goal/Exit, owner-file outlines, the replays and
                                           # tests it names, its types/ blocks and decision records, its parity.md and
                                           # spike-bugs.md rows, the spike files they cite, the APIs around it
    .venv/bin/python tools/brief.py M2     # a milestone: Goal, Exit, every row, their parity and spike-bugs rows
    .venv/bin/python tools/brief.py --list

## 1. The goal

Ship this repo (addon `MagicMap`, slash `/mm`: renamed at M6.1) as **MagicMap 2.0.0** (D7). It must look and behave
like the spike's shipped code, `~/code/MagicMap` (read-only), minus the non-goals (docs/v1-non-goals.md).
**The spec is the spike's code, not its release notes** (D4). Done (v1-plan §1): every feature in
docs/parity.md built and signed by the user (or "out, by decision"); the look matches §4 verbatim; 8/8
budgets PASS in game, two 10+ minute sessions per script (a)-(e), with `perf.slow`, `perf.gaps`, `sensor`
and `art` traces empty; `/mm check log` on throughout with 0 K4 drift lines; 0 errors, 0 taint; CI green
(the no-QuestieDB-data scenario too); renamed to MagicMap/`/mm`, merged and packaged (M6).

Where it stands: M0 done; M1's sim half done at e50e7d5 (`tools/check.sh` green plain and strict); M1b
(the user's play-test of the M1 build: M1.12 allocation while moving and the validator, M1.13 the
MVP's gear menu, M1.14 zoom and pan as the MVP: every wheel event a x1.3 tick, chased) merged by 743a615,
its sim half done at 2f79ffb (the M1b gate, 2026-10-19: 86 passed plain and strict), M1.15 (the layouts fit the frame)
done at cfdc6d2 (held borders still short of the edge ~9 frames of a glide: play-test a1g); every
in-game check waits for one consolidated play-test at the end (D10, docs/playtest-final.md). M2 (quests
on one pin store): wave 1 merged 2026-10-19 (M2.1 the pin store with blips and rares on it, M2.2 Game's
quests, offers, follow and tooltip, M2.3 Model's quests and offers); M2.4 (UI quests, areas, tooltip)
merged 2026-10-19 (d634976) on the quest-areas decision (§7), its review's fixes (two rounds) on main; M2's
sim half done at 2112c2d (the M2 gate, 2026-10-19: 112 passed plain and strict), its in-game half in
docs/playtest-final.md (b6-b20, c7, e4). M3 (target, route, interactions): wave 1 merged 2026-10-19
(M3.1 Model's Target and Route, M3.2 Game's waypoint, way and corpse, M3.3 the path, edge arrow,
corpse and waypoint pins and the title's target, M3.4 the picker, right-click menu and inspector, zone
hover and fly; 138 passed plain and strict), its review's fixes (two rounds) on main; M3's sim half
done at 2d0069e (the M3 gate, 2026-10-19: 148 passed plain and strict; the sim walks the way GetPlayerFacing
points since), its in-game half in docs/playtest-final.md (c1-c3, a5b's big-zones). M4 (feature-complete):
wave 1 merged 2026-10-19 (M4.1 Game's places, group, vignettes, explored and tracking parts; M4.2 duplicate
tracking, indoors and the whole Minimap, full HBD; M4.3 Model's places, group, seen rares, vignettes,
services; M4.4 UI's places, group, shade, indoor art, renderer, sockets (the art and renderer since replaced by ADR 0008's interiors), the inspector's lines; M4.5 the
gear's Tracking and Advanced; M4.6 the diagnostics slash), its types/ additions committed, its review's round 1
on main; M4's sim half done at 9d2dc45 (the M4 gate, 2026-10-19: 178 passed plain and strict; every parity row
built but F56, M5.2's, and S31, the user's call), its in-game half in docs/playtest-final.md (a6, d0-d8, e1c, e2,
e6; a3c, a7s, b7, e5 from the review). M5 (hardening and parity): wave 1 merged 2026-10-19 (M5.1 the 10-minute priced soak,
test_soak; M5.2 every replay without QuestieDB's data too, F56's notice; M5.3 the S rows audited against the spike's code);
M5's sim half done at 532cd9e (the M5 gate, 2026-10-19: 211 passed plain and strict), its in-game half in
docs/playtest-final.md (a8, b21, c8, d9, e8: two 10+ minute sessions a script; e2, e5, e7; the sign-off). M1.15 done at cfdc6d2.
M6 (rename, package) done: 2.0.0 at 17c6870, tagged locally (never published).
Since 2.0.0 (the log from v2.0.0 to main), toward **2.0.0-rc.1**, a release candidate for external play-testing
(docs/playtest-external.md): interiors (ADR 0008: Blizzard's indoor minimap pictures placed by us, City maps and the
cities' area names on the big map) replaced the world map's indoor art and Blizzard's whole Minimap; the sea and the
colour-matched tiles, the unexplored shade and the estimated quest areas are gone; zone borders are the big map's only;
icon grouping (ui/Cluster.lua), the zoom reset button and the quest line; the gear reorganised (Map, Quests, Places,
Nearby, Other addons; Follow you in Settings); Blizzard's HD icons; the QuestieDB data packed.

## 2. Rules for every package (v1-plan §3)

- **Contracts**: OPEN additions only, and not by you: don't edit `types/`. Name the addition in your
  hand-off (file, field, why); the lead commits it with its ADR consequence line (as b5b1880, e52fbd5).
  The only LOCKED changes are the SavedVariables rename (ADR 0007, M6.1: `MagicMap2DB`) and ADR 0004's two
  amendments (D6's 5000 seen blips an instance; optional keys), both recorded 2026-10-18.
- **Tests**: simple sim scenarios or `R-*` replays only. No unit-test sprawl.
- **No defensive code.** `x/0` (raises in the client: spike-bugs E3) is handled by the `/` lint rule and
  fixes at the source. Absent QuestieDB data is handled once in Atlas (empty indexes), not per call site.
- **Comments**: terse, spike-style.
- **§4 values** are constants copied verbatim, with the spike's `file:line` in a comment. Not starting points.
- Commands are `/mm` and `/magicmap` (M6.1). The spike isn't installed in a play-test: it and this addon share the
  folder `MagicMap` (tools/install.py `--replace-spike` moves it to `MagicMap.spike-backup`); the reference-shot
  session runs the spike alone.
- Risky client behaviour (QuestPOI Inside, HBD borrow, M/Escape hooks, taint) is proven thin in game a
  milestone before features lean on it.
- Model builds against fixture streams through stubs with the real interface, so the fixture → Game swap
  needs no code change.
- **Every package runs in its own git worktree branch; the lead merges.** An exclusive package (`X` in
  the Wave / Iso column) holds its files alone until merged. Never edit main's working tree, never push.
- **Hand-off**: say which spike-bugs rows you closed and which parity rows you ticked (with your sha).
  **Only the lead edits docs/evidence/spike-bugs.md and docs/parity.md**, once per gate (and adds the
  in-game items to docs/playtest-final.md).
- Hot files are split so packages add files: per-folder `files.txt`, the registries (§4 below), one replay
  per file under `tools/tests/replays/R-XX.lua`, per-Data-file FORMATS versions.

## 3. Architecture (architecture.md)

Three systems over two libraries: **Game** (everything outside: the WoW API, other addons,
SavedVariables), **Model** (what we know), **UI** (what you see and do); **Atlas** (facts that hold:
generated Data/), **Runtime** (when things run).

- Only Game reads or changes game state or other addons. Anyone may make widgets.
- Anyone may read Atlas and use Runtime; neither reads a system.
- Model is plain Lua and sees only what it's handed: observations and oracles from Game, focus from UI.
- UI reads Model, owns View, sends commands to Game. Its drawing reads only Model and View, never input.
- Game reads only View from UI. Saved data belongs to the system that owns it; Game only loads and saves it.

Each frame, in phase order: **input** (UI turns input into commands; Game carries them out), **observe**
(Game reads and calls `Model.Observe(obs, oracles)`), **model** (merge, target, route slice), **ui** (camera,
View, draw), **apply** (Game acts on View: Minimap mode, tracking, addon pins; and carries out the commands
a ui step sent: their effect shows in the next frame's Observation, a click's in the same one). Timers run
before the phases, jobs after; events fired during a frame are dispatched after its phases. The blip sensor
reads where the last Apply placed the Minimap, once that placement holds still.

## 4. Where things live (docs/structure.md)

    atlas/            Atlas: plain Lua 5.1, no WoW API; reads ns.Data (Data/*.lua, generated by tools/gen_*.py)
    runtime/          Runtime.lua (frame loop, wraps, jobs, perf), Boot.lua
    game/             the only code touching the WoW API; game/parts/ (Game.Part), game/commands/ (Game.Handle)
    model/            Model.lua (Observe, Focus, Load, Known) + one file per kind
    ui/               Window, Camera, Motion, Engine (layers), Chrome, Controls, Title, BigMap, Menus, layers, View
    types/            LuaLS contracts (not shipped)    docs/decisions/  one ADR per contract
    tools/            generators, install.py, luacheck.py, lint_div.py, telemetry.py, check.sh, brief.py
    tools/tests/      pytest + lupa: wowsim.lua (the simulated client), replays/R-<id>.lua, fixtures/streams/

- **Namespace**: every file starts `local ADDON, ns = ...` (or `local _, ns = ...`); each piece hangs one
  table off `ns` (`ns.Atlas`, `ns.Runtime`, `ns.Game`, `ns.Model`, `ns.UI`, data `ns.Data`). **Nothing is
  global** but, in game/ only, the SavedVariables, `SLASH_*` and the compartment func; and, anywhere, the
  three `FRAME_NAMES` (`MagicMapFrame` in ui/Window.lua, `MagicMapWorldMapEscape`,
  `MagicMapMinimapStandIn`). `luacheck.py` fails any other global write, frame name, `_G`, `setfenv`...
- **TOC is generated**: a new file goes in its folder's `files.txt`, then `.venv/bin/python tools/install.py
  --toc`; luacheck fails while the TOC differs or a `.lua` isn't listed. Load order: runtime/Boot, Data,
  atlas, runtime, model, game, game/commands, game/parts, ui.
- **Boundaries** (`tools/luacheck.py` BOUNDARIES/NS_RULES): atlas/ and model/ see Lua 5.1 only; ui/ sees
  widgets and input, `ns.UI/Atlas/Runtime`, Model's read API and `Game.Command`; game/ sees everything,
  `UI.View` only in game/Apply.lua, `Model.Observe/Load/SAVED`; game/parts and game/commands: Game,
  Atlas, Runtime only. `Runtime.On` (events) only in game/. runtime/ sees Lua 5.1, wow_globals.txt's `lua`
  and `runtime` sections and `ns.Runtime` only. Only a system's own folder sets its fields (HOME), but
  `Runtime.onError` and `Runtime.onTrace`, which Game sets (HOOKS).
- **Dividing**: in atlas/ model/ game/ ui/ runtime/, each `/` divides by a non-zero literal, an UPPER_CASE
  constant, or its line says `-- /: never 0 (why)`. `tools/lint_div.py` enforces it; `MM_STRICT=1` makes
  the sim raise on `x/0` like the client.
- **Atlas first use**: a whole-table index over thousands of rows is built offline (a generator into
  Data/) or takes `step` and calls it every 128 rows so a `Runtime.Job` caller passes `Runtime.Yield`.
- **Positions are tile space**: `MM.Pos { inst, col, row }`, col/row 0..64, `TILE_YARDS = 1600/3`
  (docs/atlas-data.md "Conventions"). No yards, uiMap 0..1 or pixels cross a boundary.
- **nil / false / {}**: nil unknown (keep the last belief), false known none, `{}` known empty.

**Registries** (a new piece is a new file plus a `files.txt` line):

| Call | In | Called |
|---|---|---|
| `Game.Part(name, read, keep)` | game/Observe.lua; files in game/parts/ | observe step: `obs[name] = read(obs)` (nil: `keep`; false comes through), in game/parts/files.txt order, each its own wrapped call |
| `Game.Handle(kind, fn)` | game/Command.lua; game/commands/ | input step, and again in apply (one a ui step sent: that frame): `fn(cmd)` per queued `Game.Command(cmd)` of that kind |
| `Game.Apply(name, fn)` | game/Apply.lua | apply phase: `fn(view)` as step `game.<name>`; view is `UI.View()` or SAFE. Not in game/parts or game/commands (luacheck `NOT_IN`): they read `Game.shownInst`, the instance shown (false: hidden; nil: no apply yet) |
| `Game.Slash(name, help, fn)` | game/Slash.lua | `/mm <name>`; UI registers through `Game.Command({ kind = "slash", ... })` |
| `Game.Load(owner, fn, spec)` | game/Game.lua | `fn(saved part)` once SavedVariables load; UI's via `Game.Command({ kind = "load", ... })` |
| `Model.Part(observe, load)`, `Model.Kind(kind, fn)` | model/Model.lua | `observe(obs, oracles)` each frame; `load(saved)`; `Known(kind)` answers `fn()` → list, rev |
| `Engine.Layer(name, level, build, rev, zoom)` | ui/Engine.lua | `build(canvas, inst, zoom, c0, r0, c1, r1)` in a layout job when view, zoom, map or `rev()` changes |
| `Pins.Layer(name, level, fill, rev, opts)` | ui/Pins.lua; the kind's own file in ui/ (Blips, Rares; Quests: quests and offers) | an Engine `"pin"` layer: its layout calls `fill(put, inst, zoom, want)`; `put(e, look, minZoom?)` for each Known entry to draw (kept by `e.key`: only what changed is set; `look` is StylePin's, one table a look); `want(minZoom)`: whether that zoom's pins draw in this layout. `opts`: `lines(e)` → title, lines... (default `e.name`, `e.text`), `tooltip(GameTooltip, e)`, `hover(e or nil)`, `click(e, button)` (ui/Window.lua's left click, before areas: `Pins.Tap`). Pins never take the mouse: `Pins.Hovered()` finds the one under the cursor while the view has it. `Pins.Small(first, last)`: tooltip lines in small type, restored on hide |
| `Menus.Layer(row)` | ui/Menus.lua; the layer's own file in ui/ | each time the gear opens: `row = { key, label, group, tip, parent?, onToggle? }` a checkbox in its group's submenu (`map`, `quests`, `places`, `nearby`, `addons`), in the order added; `key` is the Engine.Layer's name (and View.layers'); on until turned off (`Engine.LayerOn`): only the layers turned off are saved; `parent`: indented, greyed while it's off |

**The map's engine** (ui/Engine.lua; why: docs/runtime.md "The map's engine"): each layer has two
always-shown canvases swapped by alpha; one layout job at a time (a layer the view lacks first, 5 ms a
frame, else by level at 4 ms, and 2.5 ms ahead of a pan while the view is still covered: `PAN_MS`);
regions come from `Engine.Get(canvas, kind, "tex"|"line"|"font", make, key)` (pooled per canvas, the
unused parked). A layout keeps what it can first: `Engine.Keep(canvas, kind, key)` hands back the region
that showed `key` (a tile, a border piece) on that canvas (nil: none, then Get it); stamped with
`canvas.epoch` (its map, zoom, origin, the layer's rev), one set in the same epoch is left as it stands,
so a pan's layout sets only the ground it adds (ui/Tiles.lua). Tile (col, row) sits at `((col -
canvas.ox) * zoom, -(row - canvas.oy) * zoom)` on a shared origin; `zoom` says how a layer shows until
the zoom settles (0.15 s, `Camera.ZoomSettled`): `"scale"` (tiles), `"move"` (placed with `Engine.At(c,
o, point, col, row)`, laid out at the camera's zoom each log(1.25) drift and where it lands: names),
`"pin"` (placed so too, laid out a drift on toward where the zoom is headed: pins, `minZoom` shown by
the canvas's frame for it, `Engine.From` saying whether a layout at a zoom draws them), `"hold"`
(borders). `build` yields with `Runtime.Yield()` and returns true when it has nothing to draw at that
zoom, or the zoom what it left out shows from. Levels (an offset to the view's frame level), renumbered
at M2.4 (ef8b2ee) for the spike's order (parity S8: tiles → shade → areas → lines → path → labels → pins):
tiles 1, the interiors 2 (ui/Interiors.lua: the building's indoor minimap pictures and their veil, ADR 0008), quest areas 3 (their frames +5..+7, ui/Areas.lua), borders 7 (the hovered
zone's border over theirs, on their canvas: ui/ZoneInfo.lua), the path 8 (its own canvas: ui/Path.lua),
labels 9, the world socket +10 (other addons' pins, under ours: ui/Sockets.lua), rares 11 and places with
the live vignettes 11 (ui/Places.lua), blips 12, your corpse and waypoint 13 (ui/You.lua), offers 14, quests
15, the group's dots +15 (ui/Group.lua), the minimap socket +16 and its pins +17 (ui/Sockets.lua), the arrow's
and the edge arrow's overlay +18 (ui/You.lua). A pin layer's pins stand 3 above it (its canvas, the canvas's frame for a minimum zoom, the
pin a level each). M4.4 takes the level named for it; a new layer between two asks the lead.

## 5. Contracts (types/, docs/decisions/)

Each types file marks its LOCKED and OPEN parts. LOCKED: no change without a new ADR. OPEN: optional
additions, committed by the lead (§2). UI, Model and Atlas internals aren't contracts.

| Contract | Types | ADR | LOCKED | OPEN |
|---|---|---|---|---|
| Shared shapes | core.lua | 0001 | tile space (`MM.Pos`, `MM.Rect`), nil/false/{}, time kinds (frame, `GetTime`, epoch) | — |
| Observation + Oracles (Game → Model) | observation.lua | 0001 | one `Model.Observe(obs, oracles)` a frame; per-frame parts (`you`, `group`, `minimap`, `blips`, `hooked`) may be mutated, Model copies; every other part a new table on change (compare by identity); part names and meanings; oracles pure, same-frame, never error | how Game reads, new optional fields, new parts, new oracles (`Inside(quest, col, row)` today) |
| Focus (UI → Model) | focus.lua | 0002 | `Model.Focus { inst, rect?, zoom?, shown, follow }`, one frame behind | new optional fields |
| View + Commands (UI → Game) | view.lua | 0003 | `UI.View()` (v = 1, Game reads it only in apply, SAFE_VIEW fallback), its fields; `Game.Command` with kinds follow, waypoint, way, tracking, tooltip (idempotent, no reply); hooked kinds | new optional fields (`chrome`, `camera`, `diag`), command kinds (`slash`, `load`, `run`: not idempotent), hooked kinds (`toggle`) |
| SavedVariables | saved.lua | 0004, 0007 | one root `MagicMap2DB` of owners (Game, UI, Model, telemetry...), `_v` per part, the migration rule, tile space, epoch times, v1 field names | what an owner adds in a new version (with `migrate`) |
| Runtime | runtime.lua | 0005 | the phases; Step/On/After/Every/Cancel/Job/Yield/Wrap/Trace/onError and their promises | budget numbers, Perf/FrameStats shapes, Grace, SetState, Worker/Wake/Idle, onTrace |
| Model's read API (UI → Model) | model.lua | 0006 | `Known(kind)` → list, rev (same table until it changes; unknown kind `{}, 0`), `Model.you`, `hooked`, `Target()`, `Route()`, `Load`/`SAVED` | kinds and their optional fields (`MM.KnownQuest`...), Target/Route beyond typed fields, more handed on (`minimap`, `addons`, `levels`, `explored`, `exploredCells`, `interior`, `tracking`) |

`MM.Known { key, kind, pos, name, icon?, live, t?, text? }`: one shape for every pin kind, so a new kind is
a Model file that fills it and a UI layer that draws it (`icon`: `MM.Icon { atlas?, texture?, color? }`,
types/core.lua). ADR 0007: the SV rename to `MagicMap2DB` (M6.1).

## 6. Runtime (docs/runtime.md; types/runtime.lua)

- `Runtime.Step(phase, name, fn, opts)`: `fn(elapsed)` each frame in `input|observe|model|ui|apply`;
  `opts.shownOnly = frame` (only while visible), `opts.budgetMs`.
- `Runtime.On(event, name, fn)`: WoW event, `fn(event, ...)`; game/ only.
- `Runtime.After(s, name, fn)`, `Runtime.Every(s, name, fn)` → handle; `Runtime.Cancel(handle)`.
- `Runtime.Job(name, fn, budgetMs, maxFrames)`: a coroutine resumed each frame (default 2 ms, cancelled
  after 600 resumes: a long job passes its own, as the route's 2400); `.done`, `.err`. `Runtime.Yield()`
  gives the frame back once the budget is spent.
- `Runtime.Worker(name, fn, budgetMs, maxFrames)`, `Runtime.Wake(job)`, `Runtime.Idle()`: a job whose
  coroutine is made once (the engine's layouts; ZoneInfo's hover border): a new one only when a run was
  cancelled or failed after it began.
- `Runtime.Wrap(name, fn, budgetMs)`: timed, budgeted, isolated (every callback above is wrapped: an error
  is caught, reported once, the rest runs on; 10 failures in a row → once a second).
- `Runtime.Trace(kind, detail)`, `TraceCopy()`: a ring of 300 events (docs/telemetry.md "Trace kinds").
- `Runtime.Perf()`, `Runtime.errors`, `Runtime.FrameStats()` (p50/p95/p99/max, overruns, `alloc`, `gaps`,
  `ledger`, `byState`), `Runtime.Grace(name, s)`, `Runtime.SetState(state)`.
- Never `pcall` your own callbacks, never `C_Timer` or a raw `OnUpdate`: go through Runtime. A rule, not
  a check: luacheck catches `C_Timer` in atlas/, model/ and ui/ only. The one raw `OnUpdate` is
  game/Button.lua's, set only while the minimap button is dragged.

| Budget (outside graces) | Limit |
|---|---|
| frame cost p95 at rest (`small`, `big`, `closed`) | ≤ 1.0 ms |
| frame cost p99 at rest, and p95 moving (`zoom`, `drag`) | ≤ 5 ms |
| frame cost max (an overrun past it) | ≤ 8 ms (`FRAME_MS`) |
| one call (step, handler, timer); a job resume | ≤ 2 ms (`CALL_MS`); ≤ 2× its budget |
| first map open, slowest frame | ≤ 50 ms |
| load (Data + Atlas) | ≤ 250 ms |
| our Lua memory after a full collect | ≤ 64 MB |
| Lua allocation | ≤ 50 KB/s |
| errors per hour | 0 |

Graces: 5 s after each PLAYER_ENTERING_WORLD (`login`, `loading`), 2 s after the first map open
(`map`), the memory read's collect (`gc`), `/mm bench`. Change a limit in docs/runtime.md, `BUDGETS` in
tools/telemetry.py and `FRAME_MS`/`CALL_MS` in runtime/Runtime.lua together. Tests run on the sim's
counted clock (`Sim.Counted`: 3 µs a widget call, Lua free, the same on every machine); `Sim.Price(true)`
adds what the client charges (~20 µs a region shown after moving, ~2 µs a sensor probe:
docs/evidence/perf-m0.md), so the `*_priced` tests hold these budgets in CI. `load(lua=True)` (tools/sim.py:
`boot(lua=True)`, `--lua`) charges our own Lua too, R-P2's 10 ns a VM instruction (M3's path tests: with it,
M1's engine's zoom frames go past their budgets, `map: draw` to 2.3 ms in the big window: M1.15's, M5's).

## 7. Decisions (v1-plan §9, all decided)

- **D1** QuestieDB licence: decided 2026-10-21. MagicMap is GPLv3, the terms Questie's and QuestieDB's
  LICENSE.md extend to copies; the QuestieDB-derived Data/ files are committed and shipped, credited in
  NOTICE.md (a no-data build must still work).
- **D2** docs/v1-non-goals.md confirmed as drafted.
- **D3** Offline data diet approved: Items/ItemIcons only what quests reach, NPCs only open-world or needed
  (no item tooltips, no dungeon NPCs).
- **D4** The spec is the spike's code (not "blips past the edge" or path auto-fit from its release notes).
- **D5** Borders: the spike's look, 1 shadow + line (2 Lines a segment).
- **D6** Seen blips: 5000 an instance (ADR 0004 amended).
- **D7** Version 2.x.x: this release is 2.0.0; channel decided at the end.
- **D8** Merge into ~/code/MagicMap at the end; blunt is fine (old history may go).
- **D9** A new SavedVariables name at the rename (spike rares lost, accepted): ADR 0007.
- **D10** One consolidated play-test at the end (scripts a-e + reference shots), not one per milestone:
  a package's in-game Verify items go to the lead for docs/playtest-final.md.

**Quest areas** (decided by the lead, 2026-10-19, at M2's review): the spike's blob art, as M2.4 built
it (the M2.4 row, parity S53; D4: what you see is the spike's). UI draws your quests' areas with the
client's art on QuestPOIFrames of its own (ui/Areas.lua): drawn as laid out and again the next frame,
out of sight while the zoom moves, laid out and drawn twice where it lands (Layers.lua:765-1069,
2032-2043), and hit-tests them for hover and click. It is the one game read UI makes, through a
widget (architecture.md "Rules"; luacheck's `POI_FILES`: ui/Areas.lua and game/Oracles.lua, which alone
make a QuestPOIFrame or call its DrawBlob, UpdateMouseOverTooltip). Spike-bugs
P5 is MOVED (was PREVENTED), bounded by hiding while zooming (R-P5).

**M3's review** (decided by the lead, 2026-10-19, round 1): the target follows the layers (D4: the
spike's comes from what its layers show; parity F32's question: Focus `off`), and the inspector's level
line is the client's map levels (D4; F38's: obs.levels). A route search that gave up at 60,000 nodes (a
goal no way reaches, as a rule: ~18 s of 1 ms slices, 4.4 MB) is searched again for its goal only once
you've come half the way it spanned, not each 3-chunk stray or 12 chunks moved as the spike's (riding
toward a plateau ran one search after another: 285 KB/s, p95 1.35 ms); and none runs while the view moves
(Focus `moving`). The exit's "Dun Morogh route at ≤1 ms/frame" reads a 1 ms slice a frame, at most the
slice and one node (≤1.1 ms), as R-P2 holds every Job. Round 2: the path lays half its dashes a frame (odd
and even by turns) when the zoom and origin are the last layout's or the line is new (a walk, a turn, a route
found: one frame behind, unseen; while the zoom moves, all at once), and past MAX_PIECES a dash's ends are at
whole pixels (every dash re-spaces as the line's length changes; under 0.5 px from the spike's): the big
window walking at zoom 400 holds p95 ≤ 1 ms with our Lua charged (D4: neither is seen).

## 8. Commands

Worktree setup (once, from its root): `ln -s /Users/benmills/code/magic-map/.venv .venv`. Python is
`.venv/bin/python`.

    tools/check.sh                                        # CI: luacheck, lint_div, then pytest plain and MM_STRICT=1 side by side (xdist)
    tools/check.sh --quick                                # luacheck, lint_div and the plain pass alone: while iterating
    tools/check.sh --quick -k blips                       # pytest arguments pass through (both passes without --quick)
    .venv/bin/python -m pytest tools/tests/test_map.py -q -p no:cacheprovider        # one file, while working
    MM_STRICT=1 .venv/bin/python -m pytest tools/tests/test_map.py -q -p no:cacheprovider
    .venv/bin/python -m pytest 'tools/tests/test_spike_bugs.py::test_replay[L1]' -q -s   # one replay, its print
    .venv/bin/python tools/luacheck.py                    # globals, TOC, boundaries
    .venv/bin/python tools/lint_div.py                    # every / safe
    .venv/bin/python tools/install.py --toc               # regenerate MagicMap.toc after a files.txt edit
    .venv/bin/python tools/sim.py --priced --run 'slash /mm toggle; run 3; wheel 3; run 2; perf; layers'
    .venv/bin/python tools/sim.py --help                  # its script commands and Python API
    .venv/bin/python tools/telemetry.py --budgets         # a play-test's SavedVariables against the budgets

To poke the sim, use tools/sim.py (a `--run` script, or `import sim; s = sim.boot()` from Python): don't
write your own boot. Run `tools/check.sh` (~10 s) once before you hand off, `--quick` or a single test
file while working.
Commits end with a blank line and `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## 9. Tests

- **Boot**: `from test_addon import boot, errors` (tools/sim.py's `load` and `errors`); `L, sim, ns =
  boot(saved=None)` loads the TOC's files on tools/tests/wowsim.lua, logged in, on the counted clock; then
  `sim.Slash("/mm toggle")`, `sim.Step()`, `sim.Run(seconds)`, `sim.Wheel(frame, delta)`, `sim.Drag(frame,
  dx, dy)`, `sim.Click(frame, button)`, `sim.Hover`, `sim.Press(key)`, `sim.Escape()`, `sim.FireEvent(...)`,
  `sim.MenuItems(kind)`; `errors(sim, ns)` must be empty. `ns.UI.Engine`, `ns.Model.Known("blips")`... are
  all reachable. From a script, `s = sim.boot(priced=False)` (tools/sim.py) is a Client: `run`, `step`,
  `slash`, `press`, `wheel`, `drag`, `walk`, `lua`, `perf`, `errors`, `layers`; `.L`, `.sim`, `.ns`, `.T`.
- **Replays**: tools/tests/replays/R-<id>.lua, one per spike-bugs row, collected by test_spike_bugs.py;
  their harness is tools/tests/harness.lua: `local T = ...; local sim, ns = T.Shown()`; every `sim.Step`
  checks the invariants (anchors ≤ 4096 px but the world socket's, no map region snapped, one canvas a
  layer outside a crossfade, every layer on one origin at rest, no protected call in combat, no Blizzard
  Minimap art while the takeover has it, one pin a thing: no key twice on a pin layer, no quest both a
  quest's pin and an offer's). test_replay_no_data runs each again without the QuestieDB-derived data
  where it's here (CI has none: test_replay is that run); every boot of either ends with only its
  replay's own errors (`ERRORS`) and the no-data notice (F56) once without the data, never with it.
- **Model alone**: tools/tests/replay.lua (`Replay.Model`, `Replay.Stream(root, "quests")`,
  `Replay.Oracles`) feeds fixtures/streams/<part>.lua, what Game's part would hand over.
- Files: test_addon (smoke, luacheck, boundaries, Runtime's guarantees), test_no_globals
  (test_only_game_defines_globals), test_atlas, test_generators, test_sim (sim fidelity, streams),
  test_sim_cli (tools/sim.py's `--run`), test_blips (end to end), test_map, test_ground, test_zoom,
  test_motion, test_chrome, test_bigmap, test_takeover, test_you, test_gear, test_bench, test_telemetry,
  test_demo (the web demo's server), test_spike_bugs, test_pins (the pin store: diff, StylePin, tooltips,
  click and drag), test_quest_parts (Game's quests and offers parts, the follow and tooltip Commands;
  run as a script, it records fixtures/streams/quests.lua and offers.lua again), test_model_quests
  (Model alone on those streams), test_quests (UI's quest pins, follow, tooltip), test_quest_areas (areas,
  hover, a 12-tile zone at zoom 800; 25 quests' budgets, the first open, allocation over a
  stretch alone: `stretch`), test_target (Model's target end to end: priority, a quest's area edge, inside
  held; the layers turned off), test_route (A* in its job: budget, cap, the old route kept, replans, Dun
  Morogh's pace and long open routes', riding off the line priced, a capped search priced and kept half
  its way, none while zooming),
  test_target_parts (Game's waypoint, way and corpse round trips), test_path (the line, its redraws and
  cap, the edge arrow, corpse forces follow, the title's target, the corpse and waypoint pins, walking and
  priced, small and big, and with our Lua charged too: `boot(lua=True)`), test_interact (the picker, /mm map and zone, zone hover and fly, Ctrl/Shift clicks through
  Game's handlers, the right-click menu and inspector), test_world_parts (Game's places, group, vignettes,
  explored and tracking parts, the tracking Command), test_tracking (duplicate tracking off and back, after a
  crash too), test_addonpins (HBD's world and minimap pins), test_model_kinds (Model's places and group),
  test_services (services and remembered gated by tracking), test_world_layers (UI's places, group,
  View, the inspector's lines), test_interiors (Atlas's buildings and rooms, the interiors layer, City maps),
  test_cluster (grouped icons: pills and their grid), test_diagnostics (every `/mm` diagnostic, the recording, `run`), test_soak (M5's 10-min priced
  soak: scripts (a)-(e), every layer on; heap flat after a collect, no job stuck, 8/8 budgets). The sim's C_ calls make their tables anew each call, as the client's (their
  garbage is measured); a scenario changing Sim.quests fires QUEST_LOG_UPDATE, the sim QUEST_ACCEPTED and
  QUEST_REMOVED with it. A QuestPOIFrame draws into its rect as the last frame's end laid it out (L1); its
  drawing moves with it on a pan, not on a resize or a scale.

## 10. The docs: what each holds (grep, don't read)

| Doc | Words | Holds |
|---|---|---|
| docs/v1-plan.md | 10.5k | §1 done, §3 rules, §4 style values, §6 packages (tools/brief.py prints yours), §9 decisions |
| docs/parity.md | 7.6k | one row per feature (F) and style value (S): package, proof, shot, status |
| docs/evidence/spike-bugs.md | 9.5k | the spike's 39 failures (E, P, D, L, S, G, K, M rows), verdicts, replay sketches |
| docs/runtime.md | 4.5k | budgets, attribution, the map engine's price table, Runtime's guarantees, saved data |
| docs/atlas-data.md | 3k | Data/ files, their row layouts, the wrapper, conventions |
| docs/evidence/perf-m0.md | 2.7k | what the client charges, measured |
| docs/telemetry.md | 2.4k | SavedVariables `telemetry`, trace kinds, `tools/telemetry.py` flags |
| docs/structure.md | 2.1k | folders, namespace, rules, load order, Runtime API, registries, one flow end to end |
| docs/playtest.md, playtest-final.md | 5.3k | play-test scripts (a)-(e), the final session's checklist |
| docs/decisions/0001-0006 | 0.4-0.9k each | why each contract is shaped as it is; Locked/Open lines |
| types/*.lua | 6k in all | the contracts themselves |
