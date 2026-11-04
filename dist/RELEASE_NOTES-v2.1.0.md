**MagicMap 2.1.** Choose what MagicMap replaces, set it up your way, and get where you're going: a welcome on first run (your minimap, the world map, both or neither), a Settings window for the map's look, click any icon to track it, and a calmer, clearer map throughout. 2.1 builds on 2.0, so everything you had is kept. Please keep opening issues for anything odd; a screenshot helps a lot.

### Install
1. Download `MagicMap-v2.1.0.zip` below.
2. Unzip it into `World of Warcraft/_forever_/Interface/AddOns/` (WoW Forever's folder), so you end up with `Interface/AddOns/MagicMap/MagicMap.toc` (not `MagicMap/MagicMap/...`). If you're updating, delete the old `MagicMap` folder first.
3. Restart the game (a `/reload` isn't enough the first time) and make sure MagicMap is ticked in the AddOns list.
4. **New players:** click the minimap button (or type `/mm`): a welcome asks what MagicMap should replace. **Updating from 2.0:** your setup is kept (both the minimap and the world map, as before) and there's no welcome; change it any time in Settings. `/mm help` lists the commands.

You don't need QuestieDB or any other addon: the quest facts MagicMap shows are built in.

### What's new since 2.0
- **You choose what it replaces.** A short welcome on first open: your minimap, the world map (M), both (recommended), or neither, opened from the minimap button as a window of its own. Settings > General changes it live, and `/mm welcome` shows the welcome again. 2.0's "Override world map" is now Replace world map.
- **A Settings window.** The gear's Settings (also `/mm settings`, and Game menu > Options > AddOns > MagicMap) opens a window with a page for General, Map, Icons, Tracking line, Quest areas, Grouping and Diagnostics. Sliders change the map as you drag them; each page has its Reset.
- **Click any icon to track it.** A click (left or right) on a place, a quest, a rare or a grouped icon offers Track: the line goes to it, it wears the focus ring a followed quest does, and it's never lost in a group of icons. A quest's menu can open it in the quest log, and while you follow one, the quest pill shows its tooltip and its menu.
- **A clearer way to go.** The line is a thin, quiet gold dash (its style, colour, glow and outline in Settings), leaves your arrow smoothly and turns in rounder bends. A small pill at the top left of the map gives the yards to go and an estimated time.
- **Tidier icons.** Crowded icons group into a pill of two icons and a "+N", the quest pill sits bottom left, the pills are smaller and quieter, and the zoom reset button sits above + and −. The minimap button takes the usual shape of other addons' buttons.
- **Quests.** A compact tooltip (the level in its colour, a `?` for who takes it in), quest areas drawn as the game does with a gentler hover, and a quest-giver's `!` disappears as soon as you accept the quest.
- **A steadier ground.** A flat picture of each continent lies under the map tiles, so a fast zoom out or a flick never shows bare backdrop. The ocean is our own: calm water round each continent that fades to the deep sea, in place of the game's near-black tiles. Zone borders are gone, so the land reads cleaner.
- **Indoors.** Walking into a small building (a house, an inn) zooms the small map in, and out again when you leave. The big map has no veil over the terrain.
- **Lighter.** Quest data takes less memory.
- **Broken map art repaired.** Some clearly broken parts of the game's map art, flat unfinished blocks, are patched with repaints made using AI image generation from the surrounding game art. The rest of the terrain is the game's own textures. It's a setting, on by default ("Repair broken map art", under Map in the Settings window); off, or on a game build they weren't made for, you see Blizzard's map as it is.

### What it does
- **The minimap:** square on your minimap's spot, wheel and +/− zoom, drag to pan, glides back to you a few seconds after a pan, move and resize it, `/mm reset`.
- **The big map:** M or the red button grows it; M, the button or Escape shrinks it; L still opens Blizzard's map. Click the zone name to pick any continent, map or instance; click a zone to fly there.
- **Blizzard's blips:** herbs, ore, the mailbox and tracked NPCs around you with their icons and tooltips; town services and blips seen before when zoomed in; Blizzard's duplicate tracking switched off while MagicMap draws it, and always put back.
- **Quests:** your quests in Blizzard's art and difficulty colours, quests to pick up, rich tooltips, objective areas as the game draws them. Click one to follow it.
- **Where to go:** a walking line to your corpse, the quest you follow, the icon you track or your waypoint, around cliffs, lava and water. Ctrl-click for a waypoint, Shift-click for a `/way` line, right-click for the menu.
- **Indoors and cities:** Blizzard's indoor maps placed on the map, and whole capitals on the big map with their area names.
- **Places and people:** flight points, dungeon entrances, graveyards, points of interest, party and raid members, rares and treasures, your corpse.
- **Other addons:** HereBeDragons world-map pins (Questie, HandyNotes...) on the map and minimap pins (GatherMate...) around you, nothing drawn twice.

### Known limits
- For **WoW Forever** only, on the client build it was made for (1.60.1), and English (enUS) clients only.
- Instances (dungeons, raids) hide your position: they're shown whole, without your arrow, the line or blips.
- Blizzard's blips are sensed only within about 230 yards of you.
- The map stays north up; with Rotate Minimap on, other addons' minimap pins hide.
- Routes are walking only: no flights, boats or portals. No per-character settings.
- Quest areas use the game's own art, so their look is adjustable only in fill, edge and hover strength.
- Other minimap addons (SexyMap, square-minimap addons) may conflict; while FarmHud has the minimap, MagicMap steps aside.

### License and credits
MagicMap is free software under the GNU GPL, version 3. Its quest, NPC, object and item data is derived from [QuestieDB](https://github.com/Questie/QuestieDB) and [Questie](https://github.com/Questie/Questie), used under the GPLv3 terms they extend to copies of their work, with thanks to their authors and contributors: see `LICENSE` and `NOTICE.md` in the zip. MagicMap isn't affiliated with Questie or Blizzard.
