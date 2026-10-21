**MagicMap 2.0.** Your minimap, zooming out to the whole world on the game's own terrain, with Blizzard's live blips still on it and Blizzard's indoor maps inside buildings. Press M and it grows into a big map. 2.0 is MagicMap rebuilt from the ground up: smoother, steadier, and it now knows where you are inside cities, caves and buildings. Please keep opening issues for anything odd; a screenshot helps a lot.

### Install
1. Download `MagicMap-v2.0.0.zip` below.
2. Unzip it into `World of Warcraft/_classic_beta_/Interface/AddOns/` (WoW Forever's folder), so you end up with `Interface/AddOns/MagicMap/MagicMap.toc` (not `MagicMap/MagicMap/...`). If you're updating, delete the old `MagicMap` folder first.
3. Restart the game (a `/reload` isn't enough the first time) and make sure MagicMap is ticked in the AddOns list.
4. In game the map sits on your minimap's spot. `/mm help` lists the commands; `/mm` swaps it with Blizzard's minimap.

You don't need QuestieDB or any other addon: the quest facts MagicMap shows are built in.

### What's new since 1.0
- **Indoor maps.** Inside a building, cave or city you see Blizzard's own indoor minimap pictures, placed on the map: the floor you're on whole, the floors below faded and the ones above ghosted where they overlap yours.
- **City maps.** On the big map in a capital (Ironforge, Orgrimmar, Undercity, Stormwind...), the whole city's buildings at once, with the city's own area names (The Great Forge, the Cleft of Shadow, the Trade Quarter...). Gear → Map → City maps turns it off.
- **Rebuilt.** The map does its work in small, timed slices, so zooming, dragging and growing it stay smooth, and an error in one part is caught and reported once (`/mm errors`) while the rest keeps running.
- **Blizzard's look.** The terrain as Blizzard drew it, on each map's dark water, with Blizzard's HD icons for quests, places and gathering nodes. Zone borders show on the big map.
- **Crowded icons grouped.** Overlapping icons become a small pill; click it to see them all.
- **New controls.** A quest line at the bottom left (the quest you follow and its progress, else your quests in this zone), and a zoom reset button above + while you're zoomed away from the default.
- **A tidier gear menu.** Map, Quests, Places, Nearby (rares, treasures, your party and Blizzard's tracking types), Other addons; Use Blizzard's minimap and Reset to defaults; then Settings.
- **More remembered blips.** Mailboxes and services seen before are kept up to 5000 a continent (1.0 kept 300); rares you see are remembered for every character on your account.
- **A fresh start for your settings.** 2.0 saves under a new name, so 1.0's window place, layers and remembered rares aren't carried over.
- **Gone since 1.0:** colour-matched tiles and the sea texture, the unexplored shade, and the estimated circles for quests the game gives no area.

### What it does
- **The minimap:** square on your minimap's spot, wheel and +/− zoom, drag to pan, glides back to you a few seconds after a pan, move and resize it, `/mm reset`.
- **The big map:** M or the red button grows it; M, the button or Escape shrinks it; L still opens Blizzard's map. Click the zone name to pick any continent, map or instance; click a zone to fly there.
- **Blizzard's blips:** herbs, ore, the mailbox and tracked NPCs around you with their icons and tooltips; town services and blips seen before when zoomed in; Blizzard's duplicate tracking switched off while MagicMap draws it, and always put back.
- **Quests:** your quests in Blizzard's art and difficulty colours, quests to pick up, rich tooltips, objective areas as the game draws them. Click one to follow it.
- **Where to go:** a hand-inked walking line to your corpse, the quest you follow or your waypoint, around cliffs, lava and water. Ctrl-click for a waypoint, Shift-click for a `/way` line, right-click for the menu.
- **Places and people:** flight points, dungeon entrances, graveyards, points of interest, party and raid members, rares and treasures, your corpse.
- **Other addons:** HereBeDragons world-map pins (Questie, HandyNotes...) on the map and minimap pins (GatherMate...) around you, nothing drawn twice.

### Known limits
- For **WoW Forever** only, on the client build it was made for (1.60.1), and English (enUS) clients only.
- Instances (dungeons, raids) hide your position: they're shown whole, without your arrow, the line or blips.
- Blizzard's blips are sensed only within about 230 yards of you.
- The map stays north up; with Rotate Minimap on, other addons' minimap pins hide.
- Routes are walking only: no flights, boats or portals. No per-character settings.
- Other minimap addons (SexyMap, square-minimap addons) may conflict; while FarmHud has the minimap, MagicMap steps aside.

### License and credits
MagicMap is free software under the GNU GPL, version 3. Its quest, NPC, object and item data is derived from [QuestieDB](https://github.com/Questie/QuestieDB) and [Questie](https://github.com/Questie/Questie), used under the GPLv3 terms they extend to copies of their work, with thanks to their authors and contributors: see `LICENSE` and `NOTICE.md` in the zip. MagicMap isn't affiliated with Questie or Blizzard.
