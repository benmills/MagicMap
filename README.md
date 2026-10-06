# MagicMap

A big, smooth, zoomable World of Warcraft map drawn from the game's own minimap terrain,
not the parchment world-map art. Built for WoW Forever; also runs on Classic Era,
Anniversary, MoP Classic and Retail.

**Status: beta.** Expect a few rough edges. Please report anything odd, with a screenshot.

## Install

1. Download `MagicMap-<version>.zip` from [Releases](../../releases).
2. Unzip it into `World of Warcraft/<flavor>/Interface/AddOns/` (WoW Forever: `_classic_beta_`).
3. `/reload`, then open it with `/mm` or the minimap button.

## Features

**The map.** Every continent and instance at minimap detail, with smooth zoom from street level
out to the whole map.

![Zooming smoothly from a city out to the whole island](docs/big-map-zoom.gif)

**Any continent, any zone.** Pick a continent or instance from the title, then click a zone to fly
there. Zone and sub-zone borders and names are traced from the terrain itself.

![Picking Eastern Kingdoms from the title, then clicking Dun Morogh to fly there](docs/pick-and-fly.gif)

Also drawn: the game's own **quest areas**, and **landmarks** you've used (vendors, trainers,
flight points and more).

**Minimap mode.** MagicMap takes your minimap's spot, square and framed, and zooms out far past
it. MagicMap draws its own markers (quests, flight points, points of interest, party members)
and hides Blizzard's copies; Blizzard's blips (herbs, ore, NPCs) and other addons' pins
(GatherMate, HandyNotes) still show, clipped to the window, tooltips and all. Indoors, the window
simply shows Blizzard's own minimap.

![Minimap mode: zooming from a herb tooltip out to the whole coast](docs/zoomable-minimap.gif)

**World map takeover.** In minimap mode, M grows it into a big map, and M again shrinks it back.
The quest log (L) still opens Blizzard's world map as usual.

![Pressing M grows the minimap into a big map and back](docs/minimap-to-big-map.gif)

**Follow a quest and path mode.** Click a quest to track it and make it your target (it gets a
gold halo). Path mode then leans the view toward it, at your zoom, with a faint line between you;
when the target is off the map, a gold arrow on the map's edge points to it. The zoom is always
yours (wheel or + / −); nothing else changes it.

## Controls

| Do | How |
| --- | --- |
| Pan / zoom | Drag / mouse wheel |
| Pick a map | Click the title |
| Fly to a zone | Click it |
| Back to you, or a waypoint there (and path mode) | Right-click for the menu |
| Follow a quest | Click its icon or area |
| Waypoint | Ctrl-click (Ctrl-right-click clears) |
| Follow / Path | Toggles at the map's bottom-left (on hover) |
| Resting zoom | + / − at the map's bottom-right (on hover) |
| Layers / Minimap mode | Gear and red button by the zone name (on hover) |

Slash commands (`/mm`): `follow`, `path`, `map <name>`, `zone <name>`, `minimap`, `layers`, `icon`,
`debug`, `reset`. For checking things in game: `perf` (how the map keeps up) and `sync` (Blizzard's
minimap terrain over ours, to see whether its blips line up; `sync full` to compare the two) and
`tint` (tile colour correction and coast fades on/off), `clip` (`mask`, `scroll` or `off`: how the
Minimap is kept inside the window) and `dupes` (keep Blizzard's own markers alongside ours).

## How it works

- **Terrain.** Minimap tiles are ordinary textures an addon can draw by FileDataID. MagicMap
  lays them out on the 64×64 grid of 533⅓-yard tiles and places everything else in that grid.
- **Data, generated offline.** Python tools in `tools/` read the game files from a local install
  or wago.tools: each map's WDT (which tile goes where), `Map.db2` (which maps exist), and the
  ADT terrain (area IDs and heights per 33-yard chunk). They write `Data/*.lua`: tile lists,
  zone borders and labels, and heights. At load, only the set for your client version is kept.
- **Coasts, evened out.** The minimap art mixes bright shallow water with dark open sea, which
  showed as blue rectangles zoomed out. `tools/gen_tilecolor.py` reads the tiles' pixels and writes
  which tiles are open sea (not drawn), each coast tile's edge colour (faded outward), a few tile
  tints, and small water masks (`Textures/Water/`) that shade shallow water into the sea.
  `/mm tint` turns it off, to compare.
- **Everything else** is placed by world position through `C_Map`. Quest areas use the world
  map's own `QuestPOIFrame`.
- **Rendering.** Only visible tiles are drawn, from a pool. Wheel zoom eases toward a target.
  Pins and labels move as you zoom and are re-laid out once it settles. Borders (thousands of
  lines) are built a slice per frame into a hidden buffer, then cross-faded in.
- **Minimap mode** copies FarmHud's trick: `Minimap:SetAlpha(0)` hides Blizzard's terrain but
  not its blips. The real Minimap then moves into MagicMap's window, centred on you and sized
  so its yards-per-pixel matches our zoom, so its blips (and HereBeDragons pins) line up with our
  terrain. The client doesn't clip it to the window, so a mask texture (`Textures/MinimapMask/`)
  confines its blips to the biggest square around you inside the window, and HereBeDragons pins
  move to a plain frame the window does clip. Blizzard's tracking for flight masters, quest
  objectives and points of interest is switched off meanwhile (we draw those) and restored after.
  The rest of Blizzard's minimap cluster is hidden meanwhile.

## Unknowns and risks

- **Barely tested in-game.** Most features were written without the game at hand. They're now
  run headlessly in a simulated client on every push (see Development), which catches crashes,
  but not how things look or behave against the real client. Some code paths may simply be wrong.
- **Detail outside Forever.** Generated borders and heights exist only for WoW Forever. Other
  clients fall back to slower, rougher borders sampled at runtime, and have no height readout.
- **Minimap mode relies on undocumented behaviour:**
  - that `SetAlpha` on the Minimap hides only the terrain (FarmHud depends on this too);
  - HereBeDragons' internal pin table;
  - `C_Minimap.SetMinimapInsetInfo` pushing the rim arrows off screen (its arguments aren't documented);
  - Blizzard's default round mask texture, restored when minimap mode ends.
  Another minimap addon (SexyMap, FarmHud, square-minimap addons) may conflict.
- **Blip range is the minimap's.** Blizzard's blips only cover about 230 yards around you, so
  zoomed far out, only MagicMap's own pins remain. They also step aside while zooming, and when
  zoomed in closer than Blizzard's closest minimap zoom.
- **Rotate Minimap isn't supported**; minimap mode hands the minimap back while it's on.
- **Taint.** Minimap mode hides Blizzard frames from addon code (the minimap cluster, and the
  world map when M grows MagicMap instead). That could cause "action blocked" errors, especially
  in combat.
- **Instances and restricted positions.** Where the game withholds your position (many
  instances, some Retail contexts), following, path mode and minimap mode step aside.
- **Data drifts with patches.** Tile IDs and terrain change between game versions. The data
  files must be regenerated per client build, or tiles can be missing or wrong.

## Development

The tools need Python 3.9+. Generators use only the standard library; the checks
and tests need `pip install -r tools/requirements-dev.txt` (Lua 5.1 via `lupa`, and `pytest`).

- `python3 tools/install.py [flavor]`: replaces the installed MagicMap in a WoW flavor folder
  (`_classic_ptr_`, `_classic_beta_`, ...) with this working tree, after a Lua check; `/reload`
  to test. Without a flavor it uses the one MagicMap is already installed in. The WoW folder
  defaults to the standard location; set `MAGICMAP_WOW` or pass `--wow` if yours is elsewhere.
- `python3 tools/luacheck.py`: compiles every file in the TOC with a real Lua 5.1 and checks
  globals from the bytecode: a global write is a missing `local`, a read of anything not set by
  the addon or listed in `tools/wow_globals.txt` is likely a typo. `--globals` lists them per file.
- `python3 tools/smoketest.py`: loads the addon in a simulated client (`tools/tests/wowsim.lua`:
  frames, layout, events, a mock world) as Forever, Era and Retail, and drives it through the
  scenarios in `tools/tests/scenarios.lua`, reporting every Lua error and failed expectation.
  It catches crashes and wrong API assumptions, not rendering or taint.
- `python3 tools/bench.py`: drives the simulated client through a ride, fast pans, a continent
  pan and a wheel zoom on real Forever data, and reports per-frame Lua time, widget calls and
  frames where the view ran past the drawn zone borders. `--call-us 3` charges each widget call
  a client-like cost, so the time-sliced border builder takes as many frames as it would in game.
  In game, `/mm perf` records 10 seconds of real use and reports the same things.
- `python3 -m pytest tools/tests`: all of the above, plus the generators end to end on a synthetic
  game install (`tools/tests/fixtures.py`) against golden output. CI runs this on every push.
- Regenerate data from a local install (or `wago <product>` instead of `local INSTALL <product>`;
  wago.tools downloads are cached in `~/.cache/magicmap`):

  ```sh
  python3 tools/gen_tiles.py local "/Applications/World of Warcraft" wow_classic_beta \
      -o Data/Tiles_wow_classic_beta.lua --heights Data/Heights_wow_classic_beta.lua
  python3 tools/gen_borders.py local "/Applications/World of Warcraft" wow_classic_beta \
      -o Data/Borders_wow_classic_beta.lua
  ```

  Borders are deterministic: the same game data always gives the same file.
- `tools/casc_extract.py` and `tools/db2dump.py` pull single files out of an install and dump
  `.db2` tables, for poking at game data.
- Release: set `## Version:` in `MagicMap.toc`, commit, tag `v<version>`, run `tools/package.sh v<version>`.
  This writes `dist/MagicMap-v<version>.zip`, without `tools/` or `docs/`.

## Credits

[wowdev](https://wowdev.wiki) for file-format docs and the community listfile;
[wago.tools](https://wago.tools) for build and file access.
