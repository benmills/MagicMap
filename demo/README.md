# The web demo

Atlas on its own in a browser, at https://magic-map-outdoor.exe.xyz. `server.py` runs the addon's Atlas (atlas/, Data/:
tools/atlas_lua.py) in Lua (lupa) and serves its answers as JSON; the page (index.html, its classic scripts and the
3D modules) only draws them. Not shipped with the addon.

One map: Kalimdor, the Eastern Kingdoms and Zephras Isle on one world. `server.py`'s `OFFSET` places each (world tile =
the map's tile + its offset); the page reads the offsets and bounds from `/api/maps`. The Eastern Kingdoms sit where
Blizzard's Azeroth world map (UiMap 947) has them; the isle, which isn't on it, is ours. Requests speak world
coordinates; `real_*` and `to_real` turn them back into one map's.

3D works on the world: `/api/assets` gives each map's terrain (and scenery) at world keys, with the map's `inst` and own
key (`src`) for its files in `terrain/<inst>/`, and the page moves each mesh by its map's offset as it decodes it. Heights
are each map's own (the maps don't touch). 3D draws the game's tiles on the ground, not the ocean or the AI repaints (it
never did). It needs 64 px a tile (`MIN_3D_ZOOM`, core.js): about 150 tiles on a phone, all streamed while panning;
further out, 3D zooms in to it first, and zooming out past it levels the view and goes back to 2D.

What it draws, as the addon does: the tiles on the map's backdrop (open-sea tiles not drawn), the patched sea tile, the ocean, the
AI repaints, place names, and pins and flight points from the Atlas. A fresh view shows only flight points, dungeon entrances and
zone names. The controls are one column in the bottom right: north (only while 3D is turned or tilted), 3D, zoom, and the menu,
which opens beside them: Map Pins and Zone Names (each all of its kind off or on, keeping what Advanced picked), Share, and
Advanced (every pin layer, name tier, scenery and map-art switch, and the terrain's tools: 3D camera, elevation, slope, contours,
ground profile, pathing debug). **Pathing Debug** (`tools=path` in a link) is the walk grid and the addon's own route search
(atlas/Route.lua, `/api/route`) to find where they're wrong: a tap sets a route's start, then its goal; the map zooms in to
6144 px a tile; a panel in the top left has the layers (cell classes, missing crossings, cut-off pockets, connectors, the
4-yd squares under each cell with a slope rule and limit to try, the cells searched in order, A*'s chunk path, the addon's
line, its search box), the route's numbers, and what's under the mouse (map, chunk, its class and region, the square's slope).
It compares three walks: the released 3.1.1's, frozen in `walk311/` (13f5be7's atlas/Walk.lua and Data/Walk.lua, and its
search as f95cb2f moved it into atlas/Route.lua), main's before v2, frozen in `walk31/` (5eedf63's Walk, Route, Walk and
WalkRegions data), each loaded into its own ns, and the tree's (v2). The panel's toggle picks the one drawn (`pv=311|31|2` in
a link, with the route's ends `pa`, `pb`); a route runs on all three and their numbers sit side by side (`/api/route?v=`,
`/api/walk?v=`). Its Cases (`walk_cases.json`) and a sweep's table (`walk_sweep.json`, from tools/walk_sweep.py `--json`, if
copied here) run one on a click. pathdebug.js. **Routes** (Advanced > Routes: Previous vs New; routes.html, routes.js) is a page
of `walk_cases.json`'s `"grid"` cases, each run live (`/api/cases`) on 3.1.1 and v2 (`?sides=31,2` compares others): a pair of
map views per case, its numbers and what it should do; a view opens the map there in Pathing Debug on that walk. A tap on the map (or a pin) opens a small popup naming the zone and the place there (`/api/at`), with
Zoom In and Zoom In with 3D. Going into 3D and back out is a flight (flyover.js `flight`): the camera eases its zoom, heading,
tilt and ground height, from the 2D view down into a tilted one and back up, level and north, to 2D; any input stops it.

## Run it here

    .venv/bin/python demo/server.py 8000      # http://localhost:8000; tools/check.sh sets up .venv

Without the baked assets below it still runs: names and pins, on the backdrop.

## Assets (all gitignored: Blizzard's art)

| folder | what | made by |
|---|---|---|
| tiles/&lt;inst&gt;/ | tile WebPs, 512 px and 256/128/64 copies, a manifest naming the build | `demo/export_tiles.py --all` (the local install, `--wow`) |
| tiles/&lt;inst&gt;/b8/ | every 8 x 8 tiles' 64 px copies in one 512 px block: the page's quick fill (a screen in a few requests) and all a zoomed-out view draws | `demo/export_blocks.py demo/tiles` (after the tiles; Pillow, so made where the tiles are and copied up) |
| sea/world-sea.webp, swell.webp, swell2.webp, sea.json | the ocean: one picture over the whole world (every map's coasts; the floating isle's clouds), and the far water's two seamless swells (8 and 13 tiles) the page tiles behind it | `tools/gen_sea.py local "$W" wowf --bake demo/sea`: again after `OFFSET` moves |
| sea/world.webp | the whole map at 24 px a tile, while the tiles load | `demo/bake_world.py world demo/sea/world.webp`: again after `OFFSET` moves |
| patches/ | the patched sea tile (Data/Patches.lua) | `demo/export_patches.py` |
| ai/ | the AI repaints | `tools/ai_map.py bake` |
| icons/ (committed) | pin icons | `tools/export_icons.py` |
| walkquads/&lt;inst&gt;/ | pathing debug's 4-yd squares (slope, liquid, holes), a gzip a tile | `demo/export_walkquads.py local "$W" wowf` |
| terrain/, objects/ | 3D meshes and scenery, per map | `demo/export_terrain.py local "$W" wowf --all`, `demo/export_preview.py` |

`bake_world.py` reads a running demo's tiles (`MAGICMAP_DEMO`, default the hosted one). The server only draws tiles whose
manifest names Data/Tiles.lua's product and version: after a new build's data, re-export them, or, where gen_tiles.py gave every
tile the same FileDataID as before (the art is the same), change the manifests' `product` and `version`. The same goes for terrain/: 70707's export is byte for byte the beta 70450's.

## Deploy (the hosted demo)

The VM `magic-map-outdoor` runs it from `/opt/magic-map-outdoor` (a copy of this repo's atlas/, Data/, tools/ and demo/; not a
git checkout): service `magic-map-outdoor`, `.venv/bin/python demo/server.py 8000`.

1. Copy in the committed files: `git ls-files atlas Data tools demo` into `/opt/magic-map-outdoor` (tar, then `tar xzf - -C`).
   The assets above stay where they are; bake and copy one when it changes.
2. `sudo systemctl restart magic-map-outdoor` (the page's scripts are served no-cache; the server loads the Atlas once).
3. Check: `curl -s https://magic-map-outdoor.exe.xyz/api/maps` names the parts; the page shows both continents and the isle.
