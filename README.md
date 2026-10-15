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
reads Data/UiMaps.lua from gen_world. The rest are independent. gen_questie's four files
(Npcs, Objects, Items, Quests) are gitignored: QuestieDB declares no license (see
docs/atlas-data.md).

    W="/Applications/World of Warcraft"
    .venv/bin/python tools/gen_tiles.py     local "$W" wow_classic_beta -o Data/Tiles.lua
    .venv/bin/python tools/gen_tilecolor.py local "$W" wow_classic_beta -o Data/TileColor.lua
    .venv/bin/python tools/gen_sea.py       local "$W" wow_classic_beta -o Data/Sea.lua
    .venv/bin/python tools/gen_borders.py   local "$W" wow_classic_beta -o Data/Borders.lua
    .venv/bin/python tools/gen_walk.py      local "$W" wow_classic_beta -o Data/Walk.lua
    .venv/bin/python tools/gen_areagrid.py  local "$W" wow_classic_beta -o Data/AreaGrid.lua
    .venv/bin/python tools/gen_world.py     local "$W" wow_classic_beta -o Data   # UiMaps, Areas, Places, ItemIcons
    .venv/bin/python tools/gen_questie.py "$W/_classic_beta_/Interface/AddOns/QuestieDB"

The demo's assets, after the above:

    .venv/bin/python demo/export_tiles.py   # demo/tiles/<inst>: tile WebPs + sea textures (--inst N, --all, --sea-only); after gen_tiles, gen_sea
    .venv/bin/python tools/export_icons.py local "$W" wow_classic_beta   # demo/icons: the icons named in demo/index.html's GAME_ICON

## Install and try it in game

    .venv/bin/python tools/install.py      # into _classic_beta_ (WoW Forever); another flavor folder as argument

It copies the TOC, its files and Textures/ into `Interface/AddOns/MagicMapAtlas` (the
gitignored QuestieDB-derived data too, when generated). In game: disable the **MagicMap**
spike addon (same `MagicMap_*` data globals), log in (a restart for a new TOC, files or
textures, else `/reload`), then:

- `/mma` lists the commands; `/mma map` shows the map window
- `/mma perf`: Atlas's load cost (ms, KB) and time per step / event / timer / job
- `/mma errors`: errors caught so far (each is also printed once when it happens)

`tools/package.sh [ref]` zips a committed ref as `dist/MagicMapAtlas-<ref>.zip`.

## Telemetry

Play, `/reload`, then read what the addon saved (sessions, errors with stacks, marks with
state and trace, screenshots matched to `/mma shot`, the validation log, client `Logs/` lines
that mention the addon). The contract is [docs/telemetry.md](docs/telemetry.md).

    .venv/bin/python tools/telemetry.py                  # everything, newest first
    .venv/bin/python tools/telemetry.py --errors --full  # one section: --errors --marks --shots --validation --logs
    .venv/bin/python tools/telemetry.py --since 30 --json   # last 30 minutes (or an ISO time), as JSON

Options: `--wow` (or `MAGICMAP_WOW`), `--flavor` (default `_classic_beta_`), `--sv <file>`, `--trace N`.

## Test and lint

The tests include a headless smoke test: the TOC's files loaded in order on a simulated WoW
Forever client (`tools/tests/wowsim.lua`), logged in, ~60 frames and every `/mma` command,
with no Lua error expected; and `tools/luacheck.py` over the TOC (globals, every file listed,
the Atlas section = `atlas/files.txt`).

    .venv/bin/python -m pytest tools/tests -q -p no:cacheprovider
    .venv/bin/python tools/luacheck.py                       # the TOC's files, against tools/wow_globals.txt
    .venv/bin/python tools/luacheck.py --allow tools/lua51_globals.txt atlas/*.lua model/*.lua   # plain Lua only

## Demo

Atlas on its own in a browser: the server runs Atlas in Lua (lupa) over its bundled data and
serves its answers as JSON; `demo/index.html` only draws them (Eastern Kingdoms: drag to pan, wheel to zoom, hover readout, zone fly-to,
walk-grid overlay).

    .venv/bin/python demo/server.py        # http://localhost:8000 (optional port argument)
