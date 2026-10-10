# MagicMap

A minimap you can zoom out. MagicMap takes your minimap's spot and draws the game's own minimap
terrain at any zoom, from Blizzard's closest zoom out to several zones at once. Blizzard's live
blips (herbs, ore, tracked NPCs) stay on it. Press M and it grows into a big map in the same frame,
which zooms out to a whole continent.

For **WoW Forever** only.

![The minimap: zooming from a herb tooltip out past the whole coast](docs/zoomable-minimap.gif)
<!-- GIF (re-shoot, same story, current UI): the square minimap in Elwynn Forest, a Copper Vein
     blip and its tooltip, wheel out in one move to Elwynn, Westfall and Redridge, then back in. -->

## Why you'd want it

- **See what's past the minimap's edge.** The next quest hub, the road, the coast, without
  opening the world map.
- **Your gathering blips stay.** Herbs, ore and Blizzard's tracking (vendors, trainers) still
  show around you, with their tooltips, on top of the zoomed-out terrain.
- **One map.** The minimap and the big map are the same frame, at the same place in the world.
- **Questing in view.** Quest objective areas are on the map. Click a quest and the map keeps it
  in view, with a faint line toward it.
- **Your addons come along.** Questie, HandyNotes, GatherMate and other addons' pins show on it,
  and nothing is drawn twice.

## Install

1. Download `MagicMap-v<version>.zip` from [Releases](../../releases).
2. Unzip it into `World of Warcraft/_classic_beta_/Interface/AddOns/`, so you have
   `Interface/AddOns/MagicMap/MagicMap.toc`. When updating, delete the old `MagicMap` folder first.
3. Restart the game. A `/reload` isn't enough the first time, because new texture files only load
   at startup.

MagicMap takes your minimap's spot at once. `/mm` swaps back to Blizzard's minimap. To return,
type `/mm` again, click MagicMap's button on the minimap's rim, or use the addon compartment.

## Using it

### The minimap

It sits where your minimap was, square, about 200 yards across. The wheel zooms it. Drag to
pan. Take the mouse off it for a few seconds after panning and it glides back to you. Move it by dragging
the zone name or the border, or Alt-drag the map. Resize it from the bottom-right corner; it keeps
the same yards across as it grows. It remembers where you put it, and `/mm reset` puts it back.

The buttons show while you hover: follow and path at the bottom left, zoom at the bottom right,
and the gear and the big map button by the zone name.

Blizzard draws its blips (herbs, ore, tracked NPCs) and other addons' minimap pins around you.
MagicMap draws everything else: quests and their areas, flight points, dungeon entrances, points
of interest, party members, rares, your corpse and your waypoint. Where both could draw something,
only one does.

<!-- SCREENSHOT: the minimap at about 600 yards in Hillsbrad Foothills with Find Herbs and Find
     Minerals on: Kingsblood and Tin Vein blips near the arrow, one blip tooltip open, a quest
     area and a flight point drawn by MagicMap. -->

Indoors, it shows Blizzard's own floor plan, and the wheel zooms that.

### The big map (M)

M grows the minimap into a big map, centred on you; the red button by the zone name does the
same. M, the button or Escape shrinks it back. The quest log (L) still opens Blizzard's world map.

On the big map, right-click a spot for what's there: zone and sub-zone, coordinates, its level
range against yours, how far it is, the quests whose areas cover it, and the flight point, dungeon
or graveyard nearby.

![Pressing M grows the minimap into a big map and back](docs/minimap-to-big-map.gif)
<!-- GIF (re-shoot, current UI): standing in the Crossroads, press M; the minimap grows to the
     big map over the Barrens, then M shrinks it back to the minimap's spot. -->

### Every continent and instance

Click the zone name to pick a continent, another map or a dungeon or raid. With more than one zone
in view, click a zone to fly there. Zone borders and names are traced from the terrain itself.
`/mm zone <name>` flies to a zone by name.

![Picking Eastern Kingdoms from the title, then clicking Dun Morogh to fly there](docs/pick-and-fly.gif)

### Follow a quest, and path mode

Click a quest's icon on the map to follow it, and click again to stop. Zoomed in to a single
zone, clicking its area works too. The quest you follow is also the game's tracked quest.

Path mode keeps your target in view with a faint line toward it. On the minimap you stay in the
middle; on the big map you sit halfway toward the target. When the target is too far for your
zoom, the map eases out just enough to show both, and your zoom comes back once the target is near
or gone. For a quest with an area, the line goes to the area's nearest edge and stops once you're
inside. When the target is off the map, a gold arrow on its edge points the way.

Path mode turns on by itself when you get a new target: a quest you follow, a waypoint, or your
corpse while you're a ghost. The path button at the bottom left turns it off.

<!-- GIF: riding south out of the Crossroads after following a Barrens kill quest. The quest
     area sits at the minimap's edge, the dashed line runs to it, the map eases out to fit, and the
     line goes away as you ride into the area. -->

### Waypoints

Ctrl-click the map to set a waypoint, Ctrl-right-click to clear it. Right-click also offers
"Waypoint here" and "Clear waypoint". Shift-click opens chat with a `/way` line for that spot,
ready to share or send to a waypoint addon.

### Quest areas

Each quest's objective areas are drawn as the game draws them on its world map. Kill and collect
objectives the game gives no area for get a rough dashed circle. Hover an area to light it up and
see its quest.

<!-- SCREENSHOT: the big map over Westfall with three or four quest areas, one lit by hover with
     its tooltip, and one dashed estimated circle. -->

### Rares you've seen

Target a rare, or pass one the game shows, and MagicMap remembers where it was. Every character
on your account sees the ones you've found. Rares and treasures the game is showing right now get
their own pin. `/mm landmarks` says how many are remembered.

### Other addons

Addons that put pins on the world map through HereBeDragons (Questie, HandyNotes and others) show
them on MagicMap too, with their own icons, tooltips and clicks. Each addon gets an entry in the
gear's layers, so you can turn it off. Their minimap pins (GatherMate, HandyNotes) show around you
on the minimap. An addon whose world-map pins MagicMap already shows doesn't get its minimap pins
drawn again.

<!-- SCREENSHOT: the big map over Duskwood with Questie's quest givers and objectives on it, and
     the gear menu open at Other addons > Questie. -->

### The gear menu

By the zone name, on hover.

- **Map, Quests, Places, People, You, Other addons:** what's drawn. Hover an entry for what it
  does.
- **Tracking:** Blizzard's minimap tracking (herbs, minerals, vendors, trainers...). Its own
  button is hidden with the minimap's corner, so it lives here.
- **Settings:** the minimap button, tile colours, hiding Blizzard's copies of what MagicMap draws,
  putting the map back on the minimap's spot, switching to Blizzard's minimap, and some debug
  helpers.

<!-- SCREENSHOT: the gear menu open with the Quests submenu showing. -->

## Controls

| Do | How |
| --- | --- |
| Pan / zoom | Drag / wheel, or + / − at the bottom right |
| Move | Drag the zone name or the border, or Alt-drag the map |
| Resize | Drag the bottom-right corner |
| Big map | M, or the red button by the zone name; M, the button or Escape to go back |
| Pick a map | Click the zone name |
| Fly to a zone | Click it, while more than one zone is in view |
| Follow a quest | Click its icon (or its area, zoomed in); again to stop |
| Follow you / path mode | The two buttons at the bottom left |
| Waypoint | Ctrl-click; Ctrl-right-click clears |
| `/way` for a spot | Shift-click |
| Menu (waypoint, follow me; zone info on the big map) | Right-click |
| Blizzard's minimap | `/mm`, or gear → Settings → Use Blizzard's minimap |

Slash commands, `/mm` or `/magicmap`:

| Command | Does |
| --- | --- |
| `/mm` | MagicMap or Blizzard's minimap |
| `/mm follow`, `/mm path` | Toggle following you, and path mode |
| `/mm map <name or id>` | Show a map; on its own, lists them |
| `/mm zone <name>` | Fly to a zone |
| `/mm reset` | Back onto the minimap's spot, at its size |
| `/mm layers` | What's drawn, in chat |
| `/mm landmarks` | How many rares are remembered |
| `/mm icon` | Show or hide the minimap button |
| `/mm tint` | Tile colour correction on or off |
| `/mm dupes` | Keep Blizzard's own markers alongside MagicMap's |

For reporting problems: `/mm perf` records 10 seconds of play (`perf top` compares MagicMap's CPU
and memory with your other addons, `perf mem` breaks down its memory), `/mm sync` lays Blizzard's
terrain over MagicMap's to check its blips line up (`sync full` for full strength), `/mm tiles`
lists the tile set, and `/mm debug` shows tile details in the title.

Settings and remembered rares are shared by every character on your account.

## Limits

- **WoW Forever only.** The data and code target its client.
- **Blizzard's blips only show around you,** about 230 yards at most, and only inside the window.
  Zoomed far out, or while the map is zooming, they step aside and MagicMap's own markers remain.
- **Panning away shrinks the area where blips show,** since it has to stay centred on you, until
  the map glides back.
- **The big map has no Blizzard blips.** It shows MagicMap's markers and other addons' world-map
  pins.
- **Indoors, it's Blizzard's floor plan,** not MagicMap's terrain.
- **Instances that hide your position** are shown whole, without path mode or blips.
  Instances have no zone borders.
- **Rotate Minimap:** MagicMap stays north up, and other addons' minimap pins stay hidden while
  Rotate Minimap is on (they'd land in the wrong places).
- **Other minimap addons** (SexyMap, square-minimap addons) may conflict. While FarmHud has the
  minimap, MagicMap leaves Blizzard's blips to it.
- **"Action blocked" errors** are possible, especially in combat, since MagicMap hides Blizzard
  frames (the minimap's corner, and the world map when M opens MagicMap instead).

Please report anything odd as an [issue](../../issues), with a screenshot.

## Development

Python 3.9+. Generators use only the standard library (`gen_tilecolor.py --preview` needs Pillow).

- `tools/check.sh` runs everything CI runs: the Lua globals check, then the tests (the addon in a
  simulated client, and the generators against golden output). It sets up `.venv` on first use.
  pytest arguments pass through: `tools/check.sh -k minimap`.
- `.venv/bin/python tools/install.py _classic_beta_` copies the working tree into WoW Forever's
  AddOns folder, after the Lua check. `/reload` in game; new texture files need a restart. Set
  `MAGICMAP_WOW` or pass `--wow` if the game isn't in the standard place.
- Regenerate `Data/` when a Forever patch changes the terrain, in this order (`gen_tilecolor.py`
  reads `Data/Tiles.lua` and rewrites `Textures/Water/`):

  ```sh
  python3 tools/gen_tiles.py local "/Applications/World of Warcraft" wow_classic_beta -o Data/Tiles.lua
  python3 tools/gen_borders.py local "/Applications/World of Warcraft" wow_classic_beta -o Data/Borders.lua
  python3 tools/gen_tilecolor.py local "/Applications/World of Warcraft" wow_classic_beta -o Data/TileColor.lua
  ```

  `wago wow_classic_beta` works in place of `local <install> wow_classic_beta`; `gen_tiles.py`
  then needs `--all-maps` for instances.
- Release: set `## Version:` in `MagicMap.toc`, commit, tag `v<version>`, then
  `tools/package.sh v<version>` writes `dist/MagicMap-v<version>.zip`.

### How it works

Minimap tiles are textures an addon can draw by FileDataID; MagicMap lays them out on the 64×64
grid of 533⅓-yard tiles and places everything else by world position. The tile lists, zone
borders and coast colours in `Data/` are generated offline from the game files. Blizzard's real
Minimap sits inside the window with its terrain switched off, centred on you and scaled to match,
so its blips land on MagicMap's terrain. Every change to Blizzard's minimap is in
`MinimapTakeover.lua`, paired with its undo; `MinimapBlips.lua` decides where it goes each frame.

### Risks

The takeover relies on behaviour the client doesn't document: blips hiding where the Minimap's
mask is transparent, `C_Minimap.SetMinimapInsetInfo` pushing the rim's icons off screen, and
HereBeDragons' internal pin table. The tests catch crashes and wrong API assumptions, not how it
looks in the real client. Tile IDs change between Forever builds, so `Data/` must be regenerated
when they do.

## Credits

[wowdev](https://wowdev.wiki) for file-format docs and the community listfile;
[wago.tools](https://wago.tools) for build and file access.
