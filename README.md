# MagicMap

A big, smooth, zoomable World of Warcraft map drawn from the game's own
**minimap terrain**. It shows the detailed ground you see on your minimap, rather than
the parchment world-map art, across a whole continent. Zone borders, quest areas,
points of interest and the places you've visited are drawn on top.

Built for **WoW Forever**. It also runs on Classic Era, Anniversary, MoP Classic
and Retail.

## Features

- **Every continent and instance at minimap detail.** Click the title to pick a
  continent, another map, or a dungeon or raid (grouped by the continent its entrance
  is on). Zoom smoothly with the mouse wheel. Instances are listed when the game has
  minimap terrain for them, so all-interior dungeons don't appear yet.
- **Click a zone to fly there.** A quick, eased pan and zoom lands on the zone.
  Hovering highlights the zone you'd fly to. Once you're zoomed into one zone, clicks
  stop zooming, so panning never zooms by accident.
- **Follow mode.** The map tracks you, and right-click glides back to you.
- **Zone and sub-zone borders**, taken from the terrain's own area data. Zone borders
  are thin, warm lines. Sub-zone outlines and names appear as you zoom in. Where a
  border runs out, for example into the sea, it breaks into fading dashes. Labels are
  placed so they don't collide.
- **Quest areas.** The game's own objective areas, with the same quest icons as the
  world map. Hover an area to see its objectives. Objectives the game doesn't define
  an area for get a dashed estimate.
- **Landmarks you've visited.** Vendors, repair NPCs, innkeepers, trainers, banks,
  auction houses, stable masters and mailboxes are learned as you use them and
  remembered for all your characters. Rares are remembered too.
- **Live points of interest**: flight points, dungeon entrances, graveyards, your
  corpse, nearby rares and treasures, and your waypoint.
- **Minimap mode.** The spyglass button (or `/mm minimap`) turns the window into your
  minimap: it moves onto the minimap's spot, square and at the minimap's own scale, with
  just the map and the zone name floating above it. The buttons appear when you hover.
  Blizzard's minimap moves inside with its terrain hidden, so its live blips (tracked herbs
  and ore, party, quest marks, with their tooltips) and other addons' pins (GatherMate,
  HandyNotes) land on MagicMap's terrain. You can zoom out much further than the minimap
  allows, but blips only reach as far as the minimap can see (about 230 yards). Pan away
  and it glides back to you after a few seconds. Opening the world map grows it to most of
  the screen instead, and M, Escape or the close button shrink it back. Click the button
  again to put the window back where it was.
- **Follow a quest.** Click a quest's icon, or its area, to follow it: it's tracked, becomes
  your target (super-tracked where the client supports it), and gets a soft halo. Click
  again to stop.
- **Path mode.** The path button (next to Follow) keeps you and your target (the quest you follow,
  else your waypoint) both in view, with a faint dashed line between you and the distance in
  the title. Panning or zooming leaves it, and right-click (or, in minimap mode, a few
  seconds untouched) brings it back. While no target is set, it just follows you.
- **Waypoints.** Ctrl-click sets the game's waypoint. Shift-click puts a `/way`
  command into chat.
- A window built on Blizzard's own frame template, so it matches the rest of your UI.

## Install

MagicMap is in **alpha**: expect rough edges, and please report what you find.

1. Download `MagicMap-<version>.zip` from the
   [Releases](../../releases) page.
2. Unzip it into `World of Warcraft/<flavor>/Interface/AddOns/`, so you end up with
   `Interface/AddOns/MagicMap/MagicMap.toc`. For WoW Forever, the flavor folder is
   `_classic_beta_`.
3. Restart the game, or `/reload`.

## Use

| | |
| --- | --- |
| Open or close | Minimap button, addon compartment (Retail), `/mm`, or Esc to close |
| Pick a map or instance | Click the title |
| Pan / zoom | Drag / mouse wheel |
| Go to a zone | Click it (while several zones are in view) |
| Back to you | Right-click, or the follow button |
| Follow a quest | Click its icon or area |
| Path mode | The path button, next to Follow |
| Layers | The scroll button in the title bar |
| Minimap mode | The spyglass button in the title bar |
| Waypoint | Ctrl-click to set, Ctrl-right-click to clear |
| `/way` | Shift-click |
| Move / resize | Drag the title bar / the corner grip |

Slash commands (`/mm` or `/magicmap`): `follow`, `map <name|id>`, `zone <name>`,
`icon` (show or hide the minimap button), `minimap` (minimap mode), `layers`, `landmarks`, `tiles`, `debug`,
`reset`.

On WoW Forever, the title also shows the ground height under the cursor.

## How it works

**Terrain.** Minimap tiles are ordinary game textures, and an addon can draw one by
its FileDataID: `Texture:SetTexture(fileDataID)`. MagicMap lays out the tiles you can
see on a 64×64 grid, where each tile is 533⅓ yards across, and positions everything
else in that grid.

**Which tiles.** Tile IDs can't be derived from coordinates, and the same ID can hold
different images in different game versions. Each map's WDT file lists the exact
minimap texture for every tile. `tools/gen_tiles.pl` reads those files, and the
client's own `Map.db2`, which lists every open-world map, straight from a local
install, or from wago.tools. It writes `Data/Tiles_<product>.lua`. At load time,
`Data/Select.lua` keeps only the set that matches your client, with Retail as the
fallback.

**Backdrop.** Past the last tile there's only open sea. The generator samples the water
along each map's outer edge, reading the DXT1 colour blocks of the edge tiles, and
stores the median as that map's backdrop colour. At runtime, each edge tile fades
into that colour, so the map's rim reads as deepening water rather than a hard edge.

**Borders.** Each ADT terrain tile is split into 16×16 chunks of about 33 yards, and every
chunk records its AreaTable ID. `tools/gen_borders.pl` reads every chunk's area and
height, and uses the area parents to work out zones and sub-zones. It traces the chunk
edges where the area changes and skips edges out over open water. It then simplifies
the edges into polylines, marks dead ends so they can fade, and places each label at
the area's deepest inland chunk. Maps without this data fall back to sampling
`GetMapInfoAtPosition` at runtime.

**Heights.** With `--heights`, `tools/gen_tiles.pl` also reads every
root ADT and averages each chunk's height (the MCNK position plus its 145 MCVT
values). It stores one byte per chunk, quantized per map, in
`Data/Heights_<product>.lua`, which the title's elevation readout uses.

**Everything else** is placed by world position using C_Map. A uiMap is a world
rectangle, so `GetWorldPosFromMapPos` at (0,0) and (1,1) gives a linear transform
between any map's coordinates and the tile grid.
- **Zone borders:** the continent is sampled with `GetMapInfoAtPosition`, then the
  borders are traced with marching squares, refined by bisection, simplified and
  smoothed.
- **Quest areas:** drawn by the same `QuestPOIFrame` the world map uses.

## Development

The tools are Perl, because the author's machine has no Lua or Python.

- `perl tools/luacheck.pl *.lua Data/*.lua` is a Lua 5.1 syntax checker. Add
  `--globals` to list every global each file uses, which helps catch typos.
- `perl tools/gen_tiles.pl local "/Applications/World of Warcraft" wow_classic_beta --heights Data/Heights_wow_classic_beta.lua > Data/Tiles_wow_classic_beta.lua`
  regenerates tiles, and terrain heights, from a local install. `perl tools/gen_tiles.pl wago wow_classic_era`
  pulls from wago.tools instead.
- `perl tools/gen_borders.pl "/Applications/World of Warcraft" wow_classic_beta > Data/Borders_wow_classic_beta.lua`
  regenerates zone and sub-zone borders from terrain. It takes about 30 seconds for WoW Forever.
- `tools/casc_extract.pl` is a minimal read-only CASC reader. It extracts any file
  by FileDataID from a local install.
- `tools/db2dump.pl` is a minimal WDC5 `.db2` reader. It skips encrypted sections.

`.pkgmeta` and `.gitattributes` leave `tools/` out of packaged releases.

To cut a release, set `## Version:` in `MagicMap.toc`, commit, tag it `v<version>`, and run
`tools/package.sh v<version>`. It checks the tag matches the TOC, runs the syntax checker,
and writes `dist/MagicMap-v<version>.zip`.

## Credits

- The [wowdev](https://wowdev.wiki) community, for the file-format documentation
  and the community listfile.
- [wago.tools](https://wago.tools), for build and file access.
