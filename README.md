# MagicMap

A rebuild of the MagicMap WoW addon (Lua 5.1). See [architecture.md](architecture.md).
So far this is the foundation: **Atlas** (`atlas/`, load order in `atlas/files.txt`), the
library of facts that hold — tiles, tile colour + water, borders, walk grid, map catalogue,
coordinates and camera maths — plus the offline tools that generate its data (`Data/`).

## Regenerate data

Each generator reads a local install (see its docstring for options):

    python3 tools/gen_tiles.py     local "/Applications/World of Warcraft" wow_classic_beta -o Data/Tiles.lua
    python3 tools/gen_tilecolor.py local "/Applications/World of Warcraft" wow_classic_beta -o Data/TileColor.lua
    python3 tools/gen_borders.py   local "/Applications/World of Warcraft" wow_classic_beta -o Data/Borders.lua
    python3 tools/gen_walk.py      local "/Applications/World of Warcraft" wow_classic_beta -o Data/Walk.lua
    python3 tools/gen_catalogue.py local "/Applications/World of Warcraft" wow_classic_beta -o demo/catalogue.lua
    .venv/bin/python demo/export_tiles.py          # demo/tiles/0 PNGs (--inst N, --all)

## Test and lint

    .venv/bin/python -m pytest tools/tests -q -p no:cacheprovider
    .venv/bin/python tools/luacheck.py --allow tools/lua51_globals.txt atlas/*.lua

## Demo

Atlas on its own in a browser: the server runs Atlas in Lua (lupa) over fixture readers
(`demo/catalogue.lua`, `demo/readers.lua`) and serves its answers as JSON; `demo/index.html`
only draws them (Eastern Kingdoms: drag to pan, wheel to zoom, hover readout, zone fly-to,
walk-grid overlay).

    .venv/bin/python demo/server.py        # http://localhost:8000 (optional port argument)
