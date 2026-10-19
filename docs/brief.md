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

Ship this repo (addon `MagicMapAtlas`, slash `/mma`) as **MagicMap 2.0.0** (D7). It must look and behave
like the spike's shipped code, `~/code/MagicMap` (read-only), minus the non-goals (docs/v1-non-goals.md).
**The spec is the spike's code, not its release notes** (D4). Done (v1-plan §1): every feature in
docs/parity.md built and signed by the user (or "out, by decision"); the look matches §4 verbatim; 8/8
budgets PASS in game, two 10+ minute sessions per script (a)-(e), with `perf.slow`, `perf.gaps`, `sensor`
and `art` traces empty; `/mma check log` on throughout with 0 K4 drift lines; 0 errors, 0 taint; CI green
(the no-QuestieDB-data scenario too); renamed to MagicMap/`/mm`, merged and packaged (M6).

Where it stands: M0 done; M1's sim half done at e50e7d5 (`tools/check.sh` green plain and strict); M1b
(the user's play-test of the M1 build: M1.12 allocation while moving and the validator, M1.13 the
MVP's gear menu, M1.14 zoom and pan as the MVP: every wheel event a x1.3 tick, chased) merged by 743a615;
every
in-game check waits for one consolidated play-test at the end (D10, docs/playtest-final.md). Next: M2
quests on one pin store, M3 target/route/interactions, M4 feature-complete, M5 hardening and parity
sign-off, M6 rename, merge, release.

## 2. Rules for every package (v1-plan §3)

- **Contracts**: OPEN additions only, and not by you: don't edit `types/`. Name the addition in your
  hand-off (file, field, why); the lead commits it with its ADR consequence line (as b5b1880, e52fbd5).
  The only LOCKED changes are the SavedVariables rename (ADR 0007, M6.1's to write) and ADR 0004's two
  amendments (D6's 5000 seen blips an instance; optional keys), both recorded 2026-10-18.
- **Tests**: simple sim scenarios or `R-*` replays only. No unit-test sprawl.
- **No defensive code.** `x/0` (raises in the client: spike-bugs E3) is handled by the `/` lint rule and
  fixes at the source. Absent QuestieDB data is handled once in Atlas (empty indexes), not per call site.
- **Comments**: terse, spike-style.
- **§4 values** are constants copied verbatim, with the spike's `file:line` in a comment. Not starting points.
- Commands stay `/mma` until M6. The spike addon is disabled in every play-test (but the reference-shot
  session: the spike only, MagicMapAtlas off).
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
View, draw), **apply** (Game acts on View: Minimap mode, tracking, addon pins). Timers run before the
phases, jobs after; events fired during a frame are dispatched after its phases. The blip sensor reads
where the last Apply placed the Minimap, once that placement holds still.

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
  three `FRAME_NAMES` (`MagicMapAtlasMap` in ui/Window.lua, `MagicMapAtlasEscape`,
  `MagicMapAtlasMinimapStandIn`). `luacheck.py` fails any other global write, frame name, `_G`, `setfenv`...
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
| `Game.Part(name, read, keep)` | game/Observe.lua; files in game/parts/ | observe step: `obs[name] = read(obs) or keep`, in game/parts/files.txt order, each its own wrapped call |
| `Game.Handle(kind, fn)` | game/Command.lua; game/commands/ | input step: `fn(cmd)` per queued `Game.Command(cmd)` of that kind |
| `Game.Apply(name, fn)` | game/Apply.lua | apply phase: `fn(view)` as step `game.<name>`; view is `UI.View()` or SAFE |
| `Game.Slash(name, help, fn)` | game/Slash.lua | `/mma <name>`; UI registers through `Game.Command({ kind = "slash", ... })` |
| `Game.Load(owner, fn, spec)` | game/Game.lua | `fn(saved part)` once SavedVariables load; UI's via `Game.Command({ kind = "load", ... })` |
| `Model.Part(observe, load)`, `Model.Kind(kind, fn)` | model/Model.lua | `observe(obs, oracles)` each frame; `load(saved)`; `Known(kind)` answers `fn()` → list, rev |
| `Engine.Layer(name, level, build, rev, zoom)` | ui/Engine.lua | `build(canvas, inst, zoom, c0, r0, c1, r1)` in a layout job when view, zoom, map or `rev()` changes |
| `Menus.Layer(row)` | ui/Menus.lua; the layer's own file in ui/ | each time the gear opens: `row = { key, label, group, tip, parent?, onToggle? }` a checkbox in its group's submenu (`map`, `quests`, `places`, `people`, `you`, `addons`), in the order added; `key` is the Engine.Layer's name (and View.layers'); on until turned off (`Engine.LayerOn`): only the layers turned off are saved; `parent`: indented, greyed while it's off |

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
o, point, col, row)`: labels, pins), `"hold"` (borders). `build` yields with `Runtime.Yield()` and
returns true when it has nothing to draw at that zoom. Levels (an offset to the view's frame level) now:
tiles 1, borders 2, labels 3, rares 5, blips 6, the world socket +8 (ui/Sockets.lua), the arrow's overlay
+10 (ui/You.lua). The spike's order (parity S8) is tiles → shade → areas → lines → path → labels → pins:
no whole level is left for shade or quest areas (between tiles and borders) or the path (between borders
and labels), so M2.4, M3.3 and M4.4 renumber the levels with the lead, not stack new layers above labels.

## 5. Contracts (types/, docs/decisions/)

Each types file marks its LOCKED and OPEN parts. LOCKED: no change without a new ADR. OPEN: optional
additions, committed by the lead (§2). UI, Model and Atlas internals aren't contracts.

| Contract | Types | ADR | LOCKED | OPEN |
|---|---|---|---|---|
| Shared shapes | core.lua | 0001 | tile space (`MM.Pos`, `MM.Rect`), nil/false/{}, time kinds (frame, `GetTime`, epoch) | — |
| Observation + Oracles (Game → Model) | observation.lua | 0001 | one `Model.Observe(obs, oracles)` a frame; per-frame parts (`you`, `group`, `minimap`, `blips`, `hooked`) may be mutated, Model copies; every other part a new table on change (compare by identity); part names and meanings; oracles pure, same-frame, never error | how Game reads, new optional fields, new parts, new oracles (`Inside(quest, col, row)` today) |
| Focus (UI → Model) | focus.lua | 0002 | `Model.Focus { inst, rect?, zoom?, shown, follow }`, one frame behind | new optional fields |
| View + Commands (UI → Game) | view.lua | 0003 | `UI.View()` (v = 1, Game reads it only in apply, SAFE_VIEW fallback), its fields; `Game.Command` with kinds follow, waypoint, way, tracking, tooltip (idempotent, no reply); hooked kinds | new optional fields (`chrome`, `camera`, `diag`), command kinds (`slash`, `load`), hooked kinds (`toggle`) |
| SavedVariables | saved.lua | 0004 | one root `MagicMapAtlasDB` of owners (Game, UI, Model, telemetry...), `_v` per part, the migration rule, tile space, epoch times, v1 field names | what an owner adds in a new version (with `migrate`) |
| Runtime | runtime.lua | 0005 | the phases; Step/On/After/Every/Cancel/Job/Yield/Wrap/Trace/onError and their promises | budget numbers, Perf/FrameStats shapes, Grace, SetState, Worker/Wake/Idle, onTrace |
| Model's read API (UI → Model) | model.lua | 0006 | `Known(kind)` → list, rev (same table until it changes; unknown kind `{}, 0`), `Model.you`, `hooked`, `Target()`, `Route()`, `Load`/`SAVED` | kinds and their optional fields (`MM.KnownQuest`...), Target/Route beyond typed fields, more handed on (`minimap`, `addons`) |

`MM.Known { key, kind, pos, name, icon?, live, t?, text? }`: one shape for every pin kind, so a new kind is
a Model file that fills it and a UI layer that draws it (`icon`: `MM.Icon { atlas?, texture?, color? }`,
types/core.lua). ADR 0007 (the SV rename) is M6.1's to write.

## 6. Runtime (docs/runtime.md; types/runtime.lua)

- `Runtime.Step(phase, name, fn, opts)`: `fn(elapsed)` each frame in `input|observe|model|ui|apply`;
  `opts.shownOnly = frame` (only while visible), `opts.budgetMs`.
- `Runtime.On(event, name, fn)`: WoW event, `fn(event, ...)`; game/ only.
- `Runtime.After(s, name, fn)`, `Runtime.Every(s, name, fn)` → handle; `Runtime.Cancel(handle)`.
- `Runtime.Job(name, fn, budgetMs, maxFrames)`: a coroutine resumed each frame (default 2 ms, cancelled
  after 600 resumes); `.done`, `.err`. `Runtime.Yield()` gives the frame back once the budget is spent.
- `Runtime.Worker(name, fn, budgetMs, maxFrames)`, `Runtime.Wake(job)`, `Runtime.Idle()`: a job whose
  coroutine is made once (the engine's layouts).
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
(`map`), the memory read's collect (`gc`), `/mma bench`. Change a limit in docs/runtime.md, `BUDGETS` in
tools/telemetry.py and `FRAME_MS`/`CALL_MS` in runtime/Runtime.lua together. Tests run on the sim's
counted clock (`Sim.Counted`: 3 µs a widget call, Lua free, the same on every machine); `Sim.Price(true)`
adds what the client charges (~20 µs a region shown after moving, ~2 µs a sensor probe:
docs/evidence/perf-m0.md), so the `*_priced` tests hold these budgets in CI.

## 7. Decisions (v1-plan §9, all decided)

- **D1** QuestieDB licence: decided at the very end, before any public upload; 2.0.0 proceeds internally
  (QuestieDB-derived Data/ files are gitignored; a no-data build must still work).
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

**Open, for the lead before M2.4 starts: quest areas.** The M2.4 row and parity S53 say the spike's
blob art (DrawBlob: drawn twice, hidden while zooming, redrawn at settle). Spike-bugs P5's verdict
(PREVENTED) and its R-P5 sketch say UI draws quest areas itself and no POI/blob frame is visible. The
lead records which one M2.4 builds in its row.

## 8. Commands

Worktree setup (once, from its root): `ln -s /Users/benmills/code/magic-map/.venv .venv`, and for each of
`Npcs Objects Items Quests BlipServices`: `ln -sf /Users/benmills/code/magic-map/Data/$f.lua Data/$f.lua`
(gitignored, read-only QuestieDB-derived data: with none, those tests skip; with the four but not
BlipServices, test_atlas fails). Python is `.venv/bin/python`.

    tools/check.sh                                        # CI: luacheck, lint_div, then pytest plain and MM_STRICT=1 side by side (xdist)
    tools/check.sh --quick                                # luacheck, lint_div and the plain pass alone: while iterating
    tools/check.sh --quick -k blips                       # pytest arguments pass through (both passes without --quick)
    .venv/bin/python -m pytest tools/tests/test_map.py -q -p no:cacheprovider        # one file, while working
    MM_STRICT=1 .venv/bin/python -m pytest tools/tests/test_map.py -q -p no:cacheprovider
    .venv/bin/python -m pytest 'tools/tests/test_spike_bugs.py::test_replay[L1]' -q -s   # one replay, its print
    .venv/bin/python tools/luacheck.py                    # globals, TOC, boundaries
    .venv/bin/python tools/lint_div.py                    # every / safe
    .venv/bin/python tools/install.py --toc               # regenerate MagicMapAtlas.toc after a files.txt edit
    .venv/bin/python tools/sim.py --priced --run 'slash /mma toggle; run 3; wheel 3; run 2; perf; layers'
    .venv/bin/python tools/sim.py --help                  # its script commands and Python API
    .venv/bin/python tools/telemetry.py --budgets         # a play-test's SavedVariables against the budgets

To poke the sim, use tools/sim.py (a `--run` script, or `import sim; s = sim.boot()` from Python): don't
write your own boot. Run `tools/check.sh` (~10 s) once before you hand off, `--quick` or a single test
file while working.
Commits end with a blank line and `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## 9. Tests

- **Boot**: `from test_addon import boot, errors` (tools/sim.py's `load` and `errors`); `L, sim, ns =
  boot(saved=None)` loads the TOC's files on tools/tests/wowsim.lua, logged in, on the counted clock; then
  `sim.Slash("/mma toggle")`, `sim.Step()`, `sim.Run(seconds)`, `sim.Wheel(frame, delta)`, `sim.Drag(frame,
  dx, dy)`, `sim.Click(frame, button)`, `sim.Hover`, `sim.Press(key)`, `sim.Escape()`, `sim.FireEvent(...)`,
  `sim.MenuItems(kind)`; `errors(sim, ns)` must be empty. `ns.UI.Engine`, `ns.Model.Known("blips")`... are
  all reachable. From a script, `s = sim.boot(priced=False)` (tools/sim.py) is a Client: `run`, `step`,
  `slash`, `press`, `wheel`, `drag`, `walk`, `lua`, `perf`, `errors`, `layers`; `.L`, `.sim`, `.ns`, `.T`.
- **Replays**: tools/tests/replays/R-<id>.lua, one per spike-bugs row, collected by test_spike_bugs.py;
  their harness is tools/tests/harness.lua: `local T = ...; local sim, ns = T.Shown()`; every `sim.Step`
  checks the invariants (anchors ≤ 4096 px but the world socket's, no map region snapped, one canvas a
  layer outside a crossfade, every layer on one origin at rest, no protected call in combat, no Blizzard
  Minimap art while the takeover has it).
- **Model alone**: tools/tests/replay.lua (`Replay.Model`, `Replay.Stream(root, "quests")`,
  `Replay.Oracles`) feeds fixtures/streams/<part>.lua, what Game's part would hand over.
- Files: test_addon (smoke, luacheck, boundaries, Runtime's guarantees), test_no_globals
  (test_only_game_defines_globals), test_atlas, test_generators, test_sim (sim fidelity, streams),
  test_sim_cli (tools/sim.py's `--run`), test_blips (end to end), test_map, test_ground, test_zoom,
  test_motion, test_chrome, test_bigmap, test_takeover, test_you, test_gear, test_bench, test_telemetry,
  test_demo (the web demo's server), test_spike_bugs.

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
