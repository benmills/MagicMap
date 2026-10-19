# MagicMap

A rebuild of the MagicMap WoW addon (Lua 5.1). See [architecture.md](architecture.md).
So far this is the foundation: **Atlas** (`atlas/`, load order in `atlas/files.txt`), the
library of facts that hold — tiles, tile colour, the sea, borders, map labels, walk grid,
uiMaps, areas, places, NPCs / objects / items / quests, coordinates and camera maths — plus
the offline tools that generate its data (`Data/`, see [docs/atlas-data.md](docs/atlas-data.md)).
The addon is **MagicMapAtlas** (the repo root is the addon root, `MagicMapAtlas.toc`); its
folders, load order and the Runtime contract are in [docs/structure.md](docs/structure.md).

## Setup

    python3 -m venv .venv && .venv/bin/pip install -r tools/requirements-dev.txt

## Regenerate data

Each generator reads a local install (see its docstring for options) and states the build
in its output's header. Run them in this order: gen_tilecolor reads Data/Tiles.lua, gen_sea
reads Tiles and TileColor (and writes Textures/Sea/<product>/ beside Data/), gen_questie
reads Data/UiMaps.lua from gen_world and gen_world's ItemIcons reads gen_questie's
Data/Items.lua (the data diet), so gen_world runs again after it; gen_labels reads Borders,
Places, Areas, UiMaps, Tiles and Walk, so it runs last. The rest are independent. gen_questie's
five files (Npcs, Objects, Items, Quests, BlipServices) are gitignored: QuestieDB declares no
license (see docs/atlas-data.md).

    W="/Applications/World of Warcraft"
    .venv/bin/python tools/gen_tiles.py     local "$W" wow_classic_beta -o Data/Tiles.lua
    .venv/bin/python tools/gen_tilecolor.py local "$W" wow_classic_beta -o Data/TileColor.lua
    .venv/bin/python tools/gen_sea.py       local "$W" wow_classic_beta -o Data/Sea.lua
    .venv/bin/python tools/gen_borders.py   local "$W" wow_classic_beta -o Data/Borders.lua
    .venv/bin/python tools/gen_walk.py      local "$W" wow_classic_beta -o Data/Walk.lua
    .venv/bin/python tools/gen_areagrid.py  local "$W" wow_classic_beta -o Data/AreaGrid.lua
    .venv/bin/python tools/gen_world.py     local "$W" wow_classic_beta -o Data   # UiMaps, Areas, Places, ItemIcons
    .venv/bin/python tools/gen_questie.py "$W/_classic_beta_/Interface/AddOns/QuestieDB"
    .venv/bin/python tools/gen_world.py     local "$W" wow_classic_beta -o Data   # again: ItemIcons for the items kept
    .venv/bin/python tools/gen_labels.py    -o Data/Labels.lua

The demo's assets, after the above:

    .venv/bin/python demo/export_tiles.py   # demo/tiles/<inst>: tile WebPs + sea textures (--inst N, --all, --sea-only); after gen_tiles, gen_sea
    .venv/bin/python tools/export_icons.py local "$W" wow_classic_beta   # demo/icons: the icons named in demo/index.html's GAME_ICON

## Install and try it in game

    .venv/bin/python tools/install.py      # into _classic_beta_ (WoW Forever); another flavor folder as argument

It writes the TOC from the folders' `files.txt` (`--toc`: only that), then copies the TOC, its
files and Textures/ into `Interface/AddOns/MagicMapAtlas` (the gitignored QuestieDB-derived
data too, when generated). It shares no globals with the
**MagicMap** spike (its data is `ns.Data`: docs/atlas-data.md), so both can be enabled. Log in
(a restart for a new TOC, files or textures, else `/reload`), then:

- `/mma` lists the commands; the map sits on the Minimap's spot from login (`/mma toggle` or
  the minimap button hides and shows it, M grows it into the big map, `/mma reset` puts it back)
- with the map shown, Blizzard's Minimap becomes an unseen sensor and its blips (mailboxes,
  herbs, services) are drawn on the map; `/mma minimap blizzard` gives it back, `/mma layer <name>`
  toggles a layer, `/mma record on|off` keeps the observations for Model replay tests
  (flow: docs/structure.md "One flow end to end")
- `/mma perf load`: Atlas's load cost (ms, KB) and time per step / event / timer / job
- `/mma errors`: errors caught so far (each is also printed once when it happens)

`tools/package.sh [ref]` zips a committed ref as `dist/MagicMapAtlas-<ref>.zip`.

## Telemetry

Play, `/reload`, then read what the addon saved (sessions, errors with stacks, marks with
state and trace, screenshots matched to `/mma shot`, the validation log, client `Logs/` lines
that mention the addon, and other addons' errors while ours was loaded). The contract is [docs/telemetry.md](docs/telemetry.md).

    .venv/bin/python tools/telemetry.py                  # everything, newest first
    .venv/bin/python tools/telemetry.py --errors --full  # one section: --errors --marks --shots --validation --logs
    .venv/bin/python tools/telemetry.py --since 30 --json   # last 30 minutes (or an ISO time), as JSON

Options: `--wow` (or `MAGICMAP_WOW`), `--flavor` (default `_classic_beta_`), `--sv <file>`, `--trace N`.

## Test and lint

The tests include a headless smoke test: the TOC's files loaded in order on a simulated WoW
Forever client (`tools/tests/wowsim.lua`), logged in, ~60 frames and every `/mma` command,
with no Lua error expected; `tools/luacheck.py` over the TOC (globals, every file listed,
the TOC = what the folders' `files.txt` make: `tools/install.py --toc` writes it); and
`tools/lint_div.py`, no `/` that may divide by 0 (docs/structure.md "Rules").

    tools/check.sh                                     # all three, as CI runs them (makes .venv if missing): before committing
    tools/check.sh --quick -k zoom                     # lints + the plain pass alone, pytest arguments passed on: while iterating
    MM_CLOCK_SCALE=4 tools/check.sh                    # the sim's real clock 4x slow: the tests (counted clock) don't notice
    .venv/bin/python -m pytest tools/tests -q -p no:cacheprovider
    .venv/bin/python tools/luacheck.py                 # the TOC's files: globals, TOC, boundaries
    .venv/bin/python tools/lint_div.py                 # each / by a literal, a constant or a reason

`check.sh` runs the tests twice side by side (plain, and `MM_STRICT=1`), each spread over half the
CPUs by pytest-xdist, so every test boots its own Lua and writes only under its `tmp_path`.
`--quick -n0 -s` runs in one process with the tests' prints shown.

`tools/sim.py` drives the same simulated client (the tests boot through it) from Python or the
shell: `s = sim.boot(priced=True)`, then `s.slash("/mma toggle")`, `s.run(3)`, `s.wheel(3)`,
`s.drag(200, 0, 20)`, `s.walk(10, "east")`, `s.press("M")`, `s.lua(code)`, and read back
`s.perf()` (FrameStats: byState, alloc, ledger; per-name calls), `s.errors()`, `s.layers()`;
`s.T` is the replays' harness (tools/tests/harness.lua). From the shell, a script:

    .venv/bin/python tools/sim.py --priced --run 'slash /mma toggle; run 3; wheel 3; run 2; perf; layers'
    .venv/bin/python tools/sim.py --help              # the commands

CI (`.github/workflows/check.yml`) runs `tools/check.sh` on every push and PR; without the
gitignored QuestieDB-derived data those tests skip.

## Boundaries

`tools/luacheck.py` enforces [architecture.md](architecture.md)'s Rules per folder: the
globals each may read (`BOUNDARIES`: sections of `tools/lua51_globals.txt` and
`tools/wow_globals.txt`) and the `ns.<System>`s it may use (`NS_RULES`, a static scan).
Also: `Runtime.On` only in game/ (Game registers game events) and `UI.View` only in
game/Apply.lua (`ONLY`); only a system's own folder sets its fields, but for the hooks it
declares (`HOOKS`: Runtime's `onError`, `onTrace`); named frames only from `FRAME_NAMES`.

| folder   | globals                                       | ns                                         |
|----------|-----------------------------------------------|--------------------------------------------|
| atlas/   | Lua 5.1 only                                  | Atlas, Data (its generated `ns.Data`)      |
| runtime/ | Lua 5.1 + `[lua]` `[runtime]`: frame, clocks | Runtime                                    |
| model/   | Lua 5.1 only                                  | Model, Atlas, Runtime                      |
| ui/      | Lua 5.1 + `[lua]` `[ui]`: widgets, input     | UI, Atlas, Runtime; Model's read API (`Known`, `Target`, `Route`, `you`, `hooked`, `Focus`); `Game.Command` (slash and saved data too) |
| game/    | all of it, and only it the SavedVariables     | Game, Atlas, Runtime; `UI.View` (game/Apply.lua), `Model.Observe` / `Load` / `SAVED` |
| game/parts/, game/commands/ | as game/                     | Game, Atlas, Runtime (no View, no Model: Observe and Apply have those) |

Known violations waiting on a contract are `BASELINE` in `tools/luacheck.py` (each with
its TODO); the check fails once one is gone, so the list only shrinks.

## Demo

Atlas on its own in a browser: the server runs Atlas in Lua (lupa) over its bundled data and
serves its answers as JSON; `demo/index.html` only draws them (Eastern Kingdoms: drag to pan, wheel to zoom, hover readout, zone fly-to,
walk-grid overlay).

    .venv/bin/python demo/server.py        # http://localhost:8000 (optional port argument)
