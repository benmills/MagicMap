![MagicMap: small map? Big mistake. Zoom, there it is. Free, for WoW Forever.](docs/images/banner.webp)

# MagicMap

A minimap that zooms out to the whole continent. Free, for WoW Forever.

**[Download](https://github.com/benmills/MagicMap/releases/latest)** ·
**[CurseForge](https://www.curseforge.com/wow/addons/magic-map)** ·
**[Try it in your browser](https://magic-map-outdoor.exe.xyz)**

<!-- TODO(#9): refreshed hero, the minimap and the big map with no zone borders and the ocean -->
![The minimap at Red Cloud Mesa, and M grows it into the big map over Mulgore and the Barrens](docs/images/hero-minimap-and-big-map.jpg)

## What you get

- **Scroll out from your feet to all of Kalimdor**, in your minimap's spot. Press M to make it big.
- **Floor plans indoors.** Undercity, Ironforge and caves show the floor you're on.
- **Quests on the map.** Objective areas, quest givers nearby, and a tooltip with the mobs, items and
  turn-in. Click a quest for a walking line to it, around cliffs and water.
- **Click any icon, choose Track.** A flight master, mailbox or rare: a line to it, with yards and minutes.
- **Herbs, ore and trainers at any zoom**, with their tooltips. Rares you've seen stay on the map for all
  your characters.
- **Works with Questie, HandyNotes and GatherMate.** Their pins show on the map, never twice. No other
  addon is needed: the quest data is built in.

<!-- TODO(#9): refreshed zoomed-out minimap (no zone borders) -->
<img src="docs/images/minimap-zoomed-out.jpg" alt="The minimap zoomed out over Mulgore" width="400">

![Undercity's Trade Quarter and Ironforge's Great Forge](docs/images/indoors-undercity-ironforge.jpg)

<!-- TODO(#12): refreshed followed-quest shot (no zone borders) -->
![A followed quest at Camp Narache: the line to its turn-in](docs/images/followed-quest-route.jpg)

<!-- TODO(#11): screenshot, a tracked flight master: focus ring, line, the yards and time pill -->
<!-- TODO(#14): screenshot, crowded icons in pills, one opened into its grid -->
<!-- TODO(#13): screenshots, the welcome's four cards and the Settings window -->
<!-- TODO(#10): GIF, wheeling out from your feet to the whole continent, then M -->

[Every feature](docs/features.md).

## Install

1. Get `MagicMap-v2.1.0.zip` from the [latest release](https://github.com/benmills/MagicMap/releases/latest),
   or install from [CurseForge](https://www.curseforge.com/wow/addons/magic-map).
2. Unzip it into `World of Warcraft/_forever_/Interface/AddOns/`. Updating from 1.x? Delete the old
   `MagicMap` folder first.
3. Restart the game, then click the minimap button. It asks what to replace: the minimap, the world map,
   both or neither.

## Controls

| | |
| --- | --- |
| Zoom, pan | Mouse wheel or + / −; drag |
| Big map | M |
| Follow a quest | Click its pin |
| Track an icon | Click it, then Track |
| Waypoint | Ctrl-click; right-click for more |
| Settings | The gear, or `/mm settings` |
| Back to Blizzard's minimap | `/mm` (again to switch back); `/mm help` for the rest |

## Limits

- WoW Forever only, English client, build 1.60.1.70707.
- No arrow in dungeons and raids (the game hides your position there).
- Herbs and ore show within about 230 yards, the same range as Blizzard's minimap.
- May conflict with other minimap addons such as SexyMap. [More](docs/features.md#limits-in-detail).

**Found a bug?** Type `/mm mark <what you saw>` when it happens, then
[open an issue](https://github.com/benmills/MagicMap/issues) with a screenshot.

## AI-repainted map art

A few broken patches of Blizzard's map art (flat, unfinished blocks) are repainted using AI image
generation from the art around them. Everything else is the game's own art. Turn it off in Settings >
Map > "Repair broken map art".

## For developers

    python3 -m venv .venv && .venv/bin/pip install -r tools/requirements-dev.txt
    tools/check.sh                       # lint and every test, as CI runs them
    .venv/bin/python tools/install.py    # install into your WoW Forever client

How it's built: [architecture.md](architecture.md). Data, the simulator and releases:
[docs/development.md](docs/development.md).

## License

GPLv3 ([LICENSE](LICENSE)). Quest, NPC and item data comes from
[QuestieDB](https://github.com/Questie/QuestieDB) and [Questie](https://github.com/Questie/Questie),
with thanks ([NOTICE.md](NOTICE.md)). The repainted map art isn't under the GPLv3 (see NOTICE.md).
Not affiliated with Blizzard Entertainment or Questie.
