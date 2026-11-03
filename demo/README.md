# Outdoor explorer

Run the real Atlas demo from the repository root:

```sh
python3 -m venv .venv
.venv/bin/pip install -r tools/requirements-dev.txt
.venv/bin/python demo/server.py 8124
```

Open http://localhost:8124. Port 8123 is reserved for the separate lab. The Python/Lua
server still serves current Atlas data. No frontend framework, package installation,
or build step is needed to run the demo.

The first visit opens a 3D flyover over Mulgore in Kalimdor, with only major zone names
enabled. The 2D/3D buttons remember the preference; a shared URL takes precedence.
2D remains the fallback when terrain or WebGL is unavailable. Search includes maps,
zones, places, flight points, NPCs, quests, objects
and items. Entity cards link quests to objective items and sources. Off-map entities
and source groups navigate to an available map; cards also offer explicit map links.

Drag to pan; a flick coasts in either view and touching again stops it immediately.
Pinch to zoom; in 3D, twist two fingers to rotate and slide two parallel fingers
vertically to tilt. The gesture midpoint stays anchored through zoom and rotation.
Trackpad scrolling pans; a platform pinch (ctrl+wheel) or mouse-wheel notch zooms.
Shift-drag or right-drag also orbits; visible rotation and tilt controls remain available. The compass restores north. Fit
frames highlighted locations or the entire map. Layers contains ordinary map content;
Tools contains ground analysis, profiles, coverage and diagnostics. Selection cards
become bottom sheets on phones.

Panning follows the screen at the current tilt and bearing. The height reference
stays fixed during a gesture so hills do not slip under the pointer; release rebases
the camera onto the ground without moving the view. Pinch/wheel zoom anchors the
touched ground elevation once per gesture. Navigation updates the camera height at
its new location; later mesh refinements never reposition a stationary camera.
Zoom limits use CSS map scale, independent of device pixel density.

Flyover slowly follows a local sightseeing loop, with gentle bearing changes and a
smooth pitch cycle up to eight degrees around the starting tilt. Dragging, zooming, searching or
using a control pauses it immediately; the Flyover button starts or pauses it.
Hidden tabs do not advance the tour. Reduced-motion preferences disable autoplay;
the button can still start it explicitly. Changing maps or losing WebGL stops it.
Layers → Place names has independent sub-layers for continents, major zones, towns,
subzones and landmarks. The parent toggle hides all names while keeping those choices.
Major zone names remain visible at close zoom when detailed name sub-layers are off.

Share copies a URL containing the map, camera, bearing, tilt, actual view mode, layer
and tool settings, name sub-layers, flyover state, selection, highlighted source
references and marker. Hash changes
restore the view without a reload. Profile endpoints and card-back history are local
session UI state, not included in links. Source lists in URLs are limited to 100 refs.
Previously shared camera/selection links stay still unless `fly=1` is explicit.
`fly=0` pauses a shared view, and `names=zone` shows only major zone names.

## Assets and build compatibility

The bundled data targets **wow_classic_beta 1.60.1.70450** (WoW Forever 1.60.x).
Exporters reject another product/build. Terrain and scenery manifests are checked
against Atlas's exact product and version; a different 1.60.x patch is not silently
accepted. The browser also checks binary sizes, finite vertices and triangle indices.

Generated terrain, objects, tiles and source caches are Git-excluded. A clone does
not include them. Missing terrain or unavailable/lost WebGL leaves the searchable 2D
map usable. Maps without tile imagery retain borders, names and interactive pins.
Asset coverage and diagnostics distinguish available files from missing data.

```sh
# Existing local install, exact Atlas build:
.venv/bin/python demo/export_tiles.py --all --wow "/Applications/World of Warcraft"
.venv/bin/python demo/export_terrain.py local "/Applications/World of Warcraft" wow_classic_beta --all

# Optional pinned public source (requires that this build is still served):
.venv/bin/python demo/export_tiles.py --source wago --version 1.60.1.70450 --all
.venv/bin/python demo/export_terrain.py wago wow_classic_beta --version 1.60.1.70450 --all

# Add/rebuild whole-map previews from existing local terrain and image exports:
.venv/bin/python demo/export_preview.py
```

Use `--inst 0 --inst 1` for individual maps. Completed matching exports can be resumed;
`--force` rebuilds them. Terrain export reads every root ADT of outdoor maps, retaining
native MCVT centre fans and hole masks. It also creates chunk and quarter-chunk meshes
for distant views. Texture resolution and mesh detail are chosen independently.

Input and camera animation own the frame loop. A module worker parses terrain,
builds the inspection index and calculates normals off the input thread. The renderer
commits at most one mesh and one image per moving frame (two each when stationary),
with a three-millisecond budget per queue. Hosts that cannot run workers retain a
main-thread fallback. GPU work still depends on the device; this is not a 60 fps guarantee.

Each queue reconciles work with the current viewport, discards obsolete results and
cancels obsolete requests. Visible work preempts background prefetch. Nearby centre
refinements can proceed without waiting for a slow edge tile. During direct manipulation,
existing mesh detail remains stable and expensive new refinements wait until motion ends.
Detail thresholds have hysteresis to avoid switching repeatedly at a zoom boundary.

Images share a texture across mesh levels and fade from their prior image or the
whole-map overview over 180 ms. When the overview is available, loading skips the
redundant per-tile thumbnail stage. Up to 48 nearby tiles are prefetched, ordered
with a short look ahead in the movement direction. Mesh and texture caches have
separate 96 MiB and 64 MiB budgets (plus up to 23 MiB for the preview; JS spatial-index
overhead is additional; visible resources are retained). Scenery is limited to 36
nearby tiles and stays visible while moving.

An optional whole-map preview fills unloaded ground with simplified terrain and
a 32-pixel-per-tile image atlas. It arrives in two small requests (about 355 KB total
for Kalimdor with HTTP compression), then individual meshes and sharper textures
replace it as they arrive. The atlas also textures detailed meshes while their
individual images are still loading. Preview geometry conservatively preserves
missing ground and supplies no picking, slope, elevation or profile data. Missing
or failed previews leave normal terrain streaming usable. The exporter creates
previews automatically; `export_preview.py` updates existing exports locally.

3D uses up to 3× screen density with an eight-million-pixel framebuffer budget.
Texture sizes follow projected screen pixels independently of mesh detail, with
mipmaps and up to 8× anisotropic filtering where supported. The source minimap
images still top out at 512 pixels per tile; the renderer does not invent detail.
Terrain and text responses use HTTP gzip with a bounded, modification-aware server
cache. Existing binary formats, URLs, and uncompressed clients remain supported.
Terrain loading starts without waiting for icon decoding, labels, borders or web fonts.

The original lab path `/Users/benmills/code/magic-map-lab` was unavailable in the
implementation environment. Its source and unpublished binary formats could not be
ported or checked. These demo-only adapters/export formats are documented below;
existing lab exports must be inspected/converted before using them here. None of the
old lab addon data is used, and the indoor-owned shared readers/runtime are unchanged.

## Ground and scenery limits

Terrain is the ADT ground surface, including the seabed. There is no water surface,
collision mesh, path guarantee, bridge deck, WMO floor or indoor floor inference.
Minimap textures already contain pictures of buildings; those pictures are not geometry.
A ground hole or unloaded sample stays unknown. Coarse meshes conservatively omit
chunks with holes, so they can show larger gaps than native meshes. Analysis reports
the current mesh resolution; contours are 25-yard shader contours in 3D and sampled
screen-grid contours in 2D. Profiles leave gaps where samples are unavailable.

The view is orthographic with bearing and tilt (0–65 degrees). Pins, labels, borders,
source rings and walk cells use the same ground projection. They remain map overlays
and can be seen through foreground terrain/scenery; they are not depth-occluded game
objects. Native mesh loading can refine their elevation slightly while zooming.

Scenery supports optional, untextured instanced meshes and explicit building picking.
Real scenery exports are not installed by the terrain exporter. Roof removal, room
isolation, indoor names, masks, pictures and portal connections remain future work.
The integration event `atlas:building-select` provides `{inst, buildingId, roomId: null,
name, placement}` without calling or modifying indoor Atlas APIs.

## Module boundaries

- `core.js`: shared map/view/selection state, projection interface, canvas composition.
- `view-state.mjs`: validated URL codec, fitting and request-generation tickets.
- `app.js`: navigation lifecycle, asset checks, preferences, controls and restoration.
- `cards.js`, `pins.js`, `navigation.js`, `tools.js`: entity UI, symbols, input and analysis.
- `flyover.js`: optional camera tour and interaction/visibility pause behavior.
- `map-motion.mjs`: gesture classification, release velocity and frame-independent momentum.
- `tile-stream.mjs`: prioritized, cancellable work and frame-budgeted commits.
- `terrain-decoder.mjs`, `terrain-worker.mjs`: background mesh preparation.
- `tiles.js`, `borders.js`, `labels.js`: the original Atlas painters, with map-aware caches.
- `terrain-scene.mjs`: pure projection, binary parsing, spatial sampling and ground picking.
- `terrain-3d.mjs`, `terrain-render.mjs`: streaming, culling, GPU resources and shaders.
- `terrain-textures.mjs`, `terrain-quality.mjs`: shared tile textures, retina resolution and pitch motion.
- `terrain-preview.mjs`, `export_preview.py`: whole-map display previews and local generation.
- `world-objects.mjs`: optional scenery resources and picking, separate from ground.
- `asset_manifest.py`, `export_terrain.py`, `export_tiles.py`: compatibility and asset tooling.
- `static_assets.py`: bounded HTTP compression cache for terrain and text.

The original painters are focused classic-script modules sharing `core.js` bindings;
the geometry/state code is native ES modules, and WebGL modules load only when needed.
The adapter surface is `project`, `pick`, `plane`, `bounds`, `fit`. Atlas tile coordinates
are column/east, row/south; a tile is 1600/3 yards. No Atlas Lua formats were changed.
`tools/export_icons.py` now reads `GAME_ICON` from `demo/pins.js`.

## Asset contracts

`terrain/<inst>/manifest.json`:

```json
{"format":"magicmap-terrain-v1","product":"wow_classic_beta","version":"1.60.1.70450","inst":0,
 "groundOnly":true,"expectedTiles":736,"tiles":[
   {"key":1968,"min":0,"max":200,"lods":{"coarse":"1968-coarse.mmt","detail":"1968-detail.mmt","native":"1968.mmt"}}
 ]}
```

`key = floor(col) * 64 + floor(row)`. Coarse is required; detail/native are optional.
Each MMT1 file is little endian: four bytes `MMT1`, uint32 vertex count, uint32 index
count, then xyz float32 triples (absolute tile column, absolute row, height in yards),
then uint32 triangle indices. Holes have no triangles. Three indices form one triangle.

The optional manifest `preview` contains `mesh`, optional `image`, tile-coordinate
`bounds: [c0,r0,c1,r1]`, and `tiles: [{key,offset,count}]`. Its MMT1 mesh combines
reduced geometry for the entire map; offsets/counts refer to triangle indices.
The image spans those bounds and is mapped using absolute tile coordinates. Preview
filenames include a content hash, so regenerated geometry cannot reuse stale cached
files with different index ranges.

`objects/<inst>/manifest.json` uses `magicmap-objects-v1`, the same product/version/inst,
and `tiles: [{"key":1968,"file":"1968.json"}]`. Each scene file contains:

```json
{"meshes":[{"id":"building-a","positions":[0,0,0,10,0,0,0,10,0],"indices":[0,1,2]}],
 "instances":[{"id":"placement-123","name":"Example building","mesh":"building-a",
               "col":30.5,"row":48.5,"height":100,"heading":0,"scale":1}]}
```

Scene vertices are local east/south/up **yards**; heading is radians around up, scale
is positive and uniform. Positions are transformed to Atlas coordinates by the renderer.
The small JSON example describes a format, not shipped game scenery. Manifest paths
must stay within their own map directory. Meshes and placements are tile-local resources;
shared instances are drawn with WebGL2 instancing.

## Checks

```sh
node --test demo/tests/*.test.mjs
.venv/bin/python -m pytest demo/tests/test_assets.py demo/tests/test_http.py tools/tests/test_demo.py -q
.venv/bin/pip install playwright
.venv/bin/playwright install chromium
.venv/bin/python -m pytest demo/tests/test_browser.py -q
PYTEST_XDIST_AUTO_NUM_WORKERS=4 tools/check.sh
```

`PLAYWRIGHT_CHROMIUM_EXECUTABLE` can select an existing Chromium binary. Browser tests
start the real server on an ephemeral port and use explicitly synthetic in-memory
terrain/scenery fixtures for deterministic WebGL checks. They never install fake game
assets. The existing Questie-data tests skip when those optional data files are absent.

`python demo/tests/benchmark_loading.py --url http://localhost:8124` measures a cold
Kalimdor view at 390×844, 3× density, 60 ms latency and 1 MB/s download throughput.
In the implementation environment, the whole-map preview appeared in 2.6 seconds,
visible ground improved from 13.4 to 5.8 seconds and target imagery from 14.5 to
8.3 seconds, while increasing the framebuffer from
2× to 3× and the target texture from 256 to 512 pixels. Timings vary with hardware,
network and cache state; these are Chromium emulation measurements, not iPhone timings.

`python demo/tests/benchmark_interaction.py --url http://localhost:8124` measures
main-thread stalls during a real-asset drag followed by native refinement. In a
matched headless Chromium run, the former loader produced seven tasks over 50 ms
(worst 112 ms; 172 ms total blocking time). Background preparation and frame-budgeted
uploads produced none in that run, with all visible native meshes ready. These are
repeatable browser measurements, not a physical-device smoothness guarantee.
