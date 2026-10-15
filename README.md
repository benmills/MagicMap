# MagicMap

A rebuild of the MagicMap WoW addon (Lua 5.1). See [architecture.md](architecture.md).
So far this is the foundation: **Atlas** (`atlas/`, load order in `atlas/files.txt`), the
library of facts that hold — tiles, tile colour, the sea, borders, walk grid, uiMaps, areas,
places, NPCs / objects / items / quests, coordinates and camera maths — plus the offline
tools that generate its data (`Data/`, see [docs/atlas-data.md](docs/atlas-data.md)).

## Regenerate data

Each generator reads a local install (see its docstring for options). `gen_world.py` writes
UiMaps, Areas, Places and ItemIcons; `gen_questie.py` writes Npcs, Objects, Items and Quests
from an installed QuestieDB, through Data/UiMaps.lua (so run it after gen_world). Those four
are gitignored: QuestieDB declares no license (see docs/atlas-data.md).

    python3 tools/gen_tiles.py     local "/Applications/World of Warcraft" wow_classic_beta -o Data/Tiles.lua
    python3 tools/gen_tilecolor.py local "/Applications/World of Warcraft" wow_classic_beta -o Data/TileColor.lua
    .venv/bin/python tools/gen_sea.py local "/Applications/World of Warcraft" wow_classic_beta -o Data/Sea.lua  # after the two above
    python3 tools/gen_borders.py   local "/Applications/World of Warcraft" wow_classic_beta -o Data/Borders.lua
    python3 tools/gen_walk.py      local "/Applications/World of Warcraft" wow_classic_beta -o Data/Walk.lua
    python3 tools/gen_areagrid.py  local "/Applications/World of Warcraft" wow_classic_beta -o Data/AreaGrid.lua
    python3 tools/gen_world.py     local "/Applications/World of Warcraft" wow_classic_beta -o Data
    .venv/bin/python tools/gen_questie.py "/Applications/World of Warcraft/_classic_beta_/Interface/AddOns/QuestieDB"
    .venv/bin/python demo/export_tiles.py          # demo/tiles/0 WebPs + sea textures (--inst N, --all, --sea-only)
    .venv/bin/python tools/export_icons.py local "/Applications/World of Warcraft" wow_classic_beta  # demo/icons: the pins' game icons

## Test and lint

    .venv/bin/python -m pytest tools/tests -q -p no:cacheprovider
    .venv/bin/python tools/luacheck.py --allow tools/lua51_globals.txt atlas/*.lua

## Demo

Atlas on its own in a browser: the server runs Atlas in Lua (lupa) over its bundled data and
serves its answers as JSON; `demo/index.html` only draws them (Eastern Kingdoms: drag to pan, wheel to zoom, hover readout, zone fly-to,
walk-grid overlay).

    .venv/bin/python demo/server.py        # http://localhost:8000 (optional port argument)
