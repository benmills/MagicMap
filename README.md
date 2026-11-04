![MagicMap: small map? Big mistake. Zoom, there it is. Free, for WoW Forever.](docs/images/banner.webp)

# MagicMap

**A minimap that zooms out to the whole continent.** The Classic minimap shows a few hundred yards and
the world map covers your screen. MagicMap is one map in your minimap's spot: wheel out from your feet
to all of Kalimdor, see inside Undercity and Ironforge, and see your quests, herbs and flight masters on
it. Press M and the same map grows into a big map.

For **WoW Forever**. Free and open source (GPLv3). No other addon needed: the quest data is built in.
[Download the latest release](https://github.com/benmills/MagicMap/releases/latest) or get it on
[CurseForge](https://www.curseforge.com/wow/addons/magic-map), or [try the map in your browser](https://magic-map-outdoor.exe.xyz) first.

<!-- TODO(#9): refreshed hero, the minimap and the big map with no zone borders and the ocean -->
![The minimap at Red Cloud Mesa, and M grows it into the big map over Mulgore and the Barrens](docs/images/hero-minimap-and-big-map.jpg)

<!-- TODO(#10): GIF, wheeling out from your feet to the whole continent, then M -->
*Animation coming: one wheel from your feet to the whole of Kalimdor.*

## Why players use it

**See the whole zone without opening a map.** Wheel out from the street you're on to a whole zone or
the continent, right in your minimap's spot, with zone and subzone names to find your way. Drag to look
around; a moment later it glides back to you. It's the game's own map art at every zoom (a few broken
patches repaired: [see below](#ai-repainted-map-art)).

<!-- TODO(#9): refreshed zoomed-out minimap (no zone borders) -->
<img src="docs/images/minimap-zoomed-out.jpg" alt="The minimap zoomed out over Mulgore" width="400">

**Never lost in Undercity or Ironforge.** Inside a city, cave or building that has Blizzard's indoor
maps, the map shows those floor plans in place: your floor in full, the levels above and below faded. Small buildings zoom you in as you walk in.
On the big map, a capital shows every building at once, its districts named.

![Undercity's Trade Quarter and Ironforge's Great Forge](docs/images/indoors-undercity-ironforge.jpg)

**Your quests on the map, no alt-tab.** The quests in your log with their progress, their objective
areas as the game draws them, quests to pick up nearby, and a tooltip with the mobs, items and who to
turn in to. Click a quest to follow it and a line walks you there, around cliffs, water and lava.

<!-- TODO(#12): refreshed followed-quest shot (no zone borders) -->
![A followed quest at Camp Narache: the line to its turn-in](docs/images/followed-quest-route.jpg)

**Click anything to go there.** A flight master, a mailbox, a rare, a quest giver: click it, choose
Track, and the line takes you there, with the yards and the minutes left in a small pill.

<!-- TODO(#11): screenshot, a tracked flight master: focus ring, line, the yards and time pill -->
*Screenshot coming: tracking a flight master across town.*

**Herbs and ore stay on the map when you zoom out.** Everything Blizzard's minimap tracks (herbs, ore,
mailboxes, trainers and other services) keeps its icon and tooltip at any zoom. Mailboxes and services
you've passed are remembered for when you're back in town, and rares you've seen are remembered for
every character on your account.

![Peacebloom herbs in Tirisfal Glades with their tooltip](docs/images/herb-blips.jpg)

**A tidy minimap.** Blizzard's own art and icons. Crowded icons group into a small pill you open with a
click. Pins from Questie, HandyNotes and GatherMate show where you'd expect them, never twice. Every
layer switches on and off from the gear menu.

<!-- TODO(#14): screenshot, crowded icons in pills, one opened into its grid -->
*Screenshot coming: a crowded town, its icons grouped, one pill opened.*

**Your map, your way.** The first time you open it, a short welcome asks what MagicMap should replace:
your minimap, the world map (M), both, or neither (then the minimap button opens it as a window).
Change your mind any time in the Settings window, which also tunes the look: label and icon sizes, the
tracking line's style and colour, the quest areas, the grouping. It stays light: the map works in small
slices so the game stays smooth, and turning it off gives Blizzard's minimap back as it was.

<!-- TODO(#13): screenshots, the welcome's four cards and the Settings window -->
*Screenshots coming: the welcome and the Settings window.*

## Everything it does

- **The map:** the game's minimap art from your feet to the whole continent; zone and subzone names; an
  ocean round the land; a few broken patches of Blizzard's map art repaired ([below](#ai-repainted-map-art)).
- **Small and big:** in your minimap's spot, movable and resizable; M grows it into a big map; click the
  zone name to jump to another zone, continent or instance.
- **Indoors:** Blizzard's floor plans where the game has them (buildings, caves, cities), your floor on top; auto-zoom in
  small buildings; whole capitals on the big map, their districts named.
- **Quests:** your log's quests with progress, objective areas, quests to pick up, a compact tooltip,
  follow one with a click; the quest pill shows its progress.
- **Getting there:** a walking line round cliffs, water and lava to the quest you follow, your corpse,
  your waypoint or any icon you track; yards and minutes left; an arrow at the edge when it's off the map;
  Ctrl-click for a waypoint, Shift-click for a `/way` line in chat.
- **Around you:** herbs, ore, mailboxes, trainers and services from Blizzard's tracking; flight points,
  dungeon entrances, points of interest and graveyards (off by default); party and raid in class
  colours; rares and treasures, the ones you've seen remembered for every character; your corpse.
- **Other addons:** Questie, HandyNotes and other HereBeDragons pins on the map; GatherMate's around you.
- **Your choice:** a welcome that asks what it replaces; a Settings window (General, Map, Icons,
  Tracking line, Quest areas, Grouping, Diagnostics), also under Options > AddOns; `/mm` commands.

[Every feature in detail](docs/features.md).

## Install

1. Download `MagicMap-v2.1.0.zip` from the [latest release](https://github.com/benmills/MagicMap/releases/latest)
   (or install it with the CurseForge app: [MagicMap on CurseForge](https://www.curseforge.com/wow/addons/magic-map)).
2. Unzip it into `World of Warcraft/_forever_/Interface/AddOns/`, so you have
   `Interface/AddOns/MagicMap/MagicMap.toc`. Updating from 1.x: delete the old `MagicMap` folder first.
3. Restart the game (a `/reload` isn't enough the first time) and tick MagicMap in the AddOns list.
4. Click the minimap button: the welcome asks what MagicMap replaces. (Updating from 2.0 keeps your setup.)

You don't need any other addon: the quest data is built in.

## Using it

| | |
| --- | --- |
| **Zoom, pan** | Mouse wheel or + / −; drag the map. Reset (above +) goes back to the default zoom. |
| **Big map** | M or the red button; M or Escape to shrink (if you kept Blizzard's world map, the button or `/mm` opens ours). |
| **Follow a quest** | Click its pin; the quest pill at the bottom left shows its progress. |
| **Track any icon** | Click it and choose Track; the pill at the top left gives the yards and time. |
| **Waypoint** | Ctrl-click the map; right-click for more. |
| **Settings** | The gear by the zone name, then Settings; or Options > AddOns > MagicMap; or `/mm settings`. |
| **Commands** | `/mm` swaps MagicMap and Blizzard's minimap; `/mm help` lists the rest. |

**Limits:** WoW Forever only (English clients), on the game build it was made for (1.60.1.70707).
Instances hide your position, so they're shown without your arrow. Blizzard's blips (herbs, ore) are only
seen within about 230 yards, as on its minimap.
Other minimap addons (SexyMap and the like) may conflict. [More](docs/features.md#limits-in-detail).

**Found a problem?** Type `/mm mark <what you saw>` the moment it happens, then
[open an issue](https://github.com/benmills/MagicMap/issues) with a screenshot. For a deeper look,
attach `World of Warcraft/_forever_/WTF/Account/<your account>/SavedVariables/MagicMap.lua` after a `/reload`. Nothing leaves
your computer otherwise.

# How it works

MagicMap is a World of Warcraft addon (Lua) built on facts prepared offline, and on what the game
tells it while you play:

- **Atlas, the facts** (`atlas/`, `Data/`). Offline tools in `tools/` read the game client's own files
  and bake what never changes into Lua data: the minimap terrain tiles' IDs, zone and place names, a
  walkable grid for routes, flight points and places, and every building's indoor minimap pictures,
  placed from its 3D model ([ADR 0008](docs/decisions/0008-interiors.md)). Quest, NPC and item facts
  come from QuestieDB. At runtime the addon draws the game's own textures by file ID, and a few
  pictures that ship with it: the base map under the tiles, the ocean, and the map art repairs (below).
- **Game, the senses** (`game/`). Blizzard's minimap keeps running out of sight as a sensor: MagicMap
  reads its blips (herbs, services, quest givers) and turns them into its own pins. It reads your
  position, quests and party, works out which building room you're in from your position and subzone,
  and borrows other addons' pins.
- **Model and UI** (`model/`, `ui/`). Model decides what matters (your target, the walking route, what's
  remembered); UI draws it with a small engine that lays out each layer in timed slices off the frame,
  so zooming and panning stay smooth.

Each part may only reach the others through a narrow, checked boundary
([architecture.md](architecture.md), [docs/structure.md](docs/structure.md)). A headless simulator of
the WoW client runs the addon in CI: every command, replays of past bugs, and frame-time budgets
priced from real client measurements.

## Development

    python3 -m venv .venv && .venv/bin/pip install -r tools/requirements-dev.txt
    tools/check.sh                       # lint and every test, as CI runs them
    .venv/bin/python tools/install.py    # install into your WoW Forever client
    .venv/bin/python tools/sim.py --help # drive the simulated client

Regenerating the data, telemetry, the simulator, the release steps and the architecture rules:
[docs/development.md](docs/development.md).

## License and credits

MagicMap is free software under the GNU General Public License, version 3 ([LICENSE](LICENSE)). Its
quest, NPC, object and item data is derived from [QuestieDB](https://github.com/Questie/QuestieDB) and
[Questie](https://github.com/Questie/Questie), used under the GPLv3 terms they extend to copies of
their work, with thanks to their authors and contributors ([NOTICE.md](NOTICE.md)). The repainted map
art isn't under the GPLv3 (also in NOTICE.md). MagicMap isn't affiliated with Questie or Blizzard
Entertainment.

## AI-repainted map art

Some clearly broken parts of the game's map art, flat unfinished blocks, are patched with repaints made
using AI image generation from the surrounding game art. The rest of the terrain is the game's own
textures, drawn at runtime. It's a setting, on by default, under Map in the Settings window ("Repair
broken map art"). Turn it off, or play on a game build the repaints weren't made for, and you see
Blizzard's map as it is. MagicMap isn't affiliated with Blizzard.
