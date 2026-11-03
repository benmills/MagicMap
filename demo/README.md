# The web demo

Atlas on its own in a browser, at https://magic-map-outdoor.exe.xyz. `server.py` runs the addon's Atlas (atlas/, Data/:
tools/atlas_lua.py) in Lua (lupa) and serves its answers as JSON; the page (index.html, its classic scripts and the
3D modules) only draws them. Not shipped with the addon.

One map: Kalimdor, the Eastern Kingdoms and Zephras Isle on one world. `server.py`'s `OFFSET` places each (world tile =
the map's tile + its offset); the page reads the offsets and bounds from `/api/maps`. The Eastern Kingdoms sit where
Blizzard's Azeroth world map (UiMap 947) has them; the isle, which isn't on it, is ours. Requests speak world
coordinates; `real_*` and `to_real` turn them back into one map's. 3D isn't available on it (the page says so and stays in 2D),
nor are the terrain tools; the code is kept.

What it draws, as the addon does: the tiles on the map's backdrop (open-sea tiles not drawn), the patched sea tile, the ocean, the
AI repaints (Menu: Ocean, AI repaint), place names, pins and flight points from the Atlas, search (`/api/find`) and cards. The
Review button is the map review (docs/hardening-plan.md M6): tools/maplint.py's issues, marked on the server.

## Run it here

    .venv/bin/python demo/server.py 8000      # http://localhost:8000; tools/check.sh sets up .venv

Without the baked assets below it still runs: names, search and pins, on the backdrop.

## Assets (all gitignored: Blizzard's art)

| folder | what | made by |
|---|---|---|
| tiles/&lt;inst&gt;/ | tile WebPs, 512 px and 256/128/64 copies, a manifest naming the build | `demo/export_tiles.py --all` (the local install, `--wow`) |
| sea/0.webp, 1.webp, sea.json | the oceans | `tools/gen_sea.py local "$W" wowf --bake demo/sea`, then `bake_world.py feather demo/sea` |
| sea/isle.webp | Zephras Isle over the ocean, its near-black gone | `demo/bake_world.py isle demo/sea/isle.webp` |
| sea/world.webp | the whole map at 24 px a tile, while the tiles load | `demo/bake_world.py world demo/sea/world.webp`: again after `OFFSET` moves |
| patches/ | the patched sea tile (Data/Patches.lua) | `demo/export_patches.py` |
| ai/ | the AI repaints | `tools/ai_map.py bake` |
| icons/ (committed) | pin icons | `tools/export_icons.py` |
| lint/issues.json (committed) | the review's issues | `tools/maplint.py --wow "$W" -q --issues demo/lint/issues.json` |
| terrain/, objects/ | 3D meshes and scenery, per map | `demo/export_terrain.py`, `demo/export_preview.py` |

`bake_world.py` reads a running demo's tiles (`MAGICMAP_DEMO`, default the hosted one). The server only draws tiles whose
manifest names Data/Tiles.lua's product and version: after a new build's data, re-export them, or, where gen_tiles.py gave every
tile the same FileDataID as before (the art is the same), change the manifests' `product` and `version`.

## Deploy (the hosted demo)

The VM `magic-map-outdoor` runs it from `/opt/magic-map-outdoor` (a copy of this repo's atlas/, Data/, tools/ and demo/; not a
git checkout): service `magic-map-outdoor`, `.venv/bin/python demo/server.py 8000`. The review's marks are kept on the VM outside it (`MAGICMAP_REVIEW`), so a
deploy doesn't touch them; saving one needs the token (`MAGICMAP_REVIEW_TOKEN`, from the infra repo's secrets).

1. Copy in the committed files: `git ls-files atlas Data tools demo` into `/opt/magic-map-outdoor` (tar, then `tar xzf - -C`).
   The assets above stay where they are; bake and copy one when it changes.
2. `sudo systemctl restart magic-map-outdoor` (the page's scripts are served no-cache; the server loads the Atlas once).
3. Check: `curl -s https://magic-map-outdoor.exe.xyz/api/maps` names the parts; the page shows both continents and the isle.

## Reading the review's marks back

    .venv/bin/python tools/review.py --from https://magic-map-outdoor.exe.xyz/
    .venv/bin/python tools/review.py --from https://magic-map-outdoor.exe.xyz/ --save docs/map-review.json

After a linter change, regenerate lint/issues.json and copy it in. Issue ids are stable, so the marks carry over.
