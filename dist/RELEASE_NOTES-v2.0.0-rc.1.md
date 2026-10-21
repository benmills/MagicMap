**MagicMap 2.0.0-rc.1 (release candidate, for play-testing).** Your minimap, zooming out to the whole world on the game's own terrain, with Blizzard's live blips still on it and Blizzard's indoor maps inside buildings. Press M and it grows into a big map. This is a test build: it should work, but it hasn't been played much outside one machine yet. What you notice is what makes 2.0.0 good.

### Install
1. Download the MagicMap zip below.
2. Unzip it into `World of Warcraft/_classic_beta_/Interface/AddOns/` (WoW Forever's folder), so you end up with `Interface/AddOns/MagicMap/MagicMap.toc` (not `MagicMap/MagicMap/...`). If an older `MagicMap` folder is there, delete it first.
3. Restart the game (a `/reload` isn't enough the first time). At the character select, AddOns: MagicMap ticked.
4. In game, the map sits on your minimap's spot. `/mm help` lists the commands; `/mm` swaps it with Blizzard's minimap.

You don't need QuestieDB or any other addon.

### What's new since 1.0
- **Rebuilt.** The map does its work in small, timed slices, so zooming, dragging and growing it stay smooth, and an error in one part is caught and reported once while the rest keeps running.
- **Indoor maps.** Inside a building you see Blizzard's own indoor minimap pictures, placed on the map: your floor whole, the floors below faded and above ghosted where they overlap yours.
- **City maps.** On the big map in a capital (Ironforge, Orgrimmar, Undercity...), the whole city's buildings at once, underground faded, with the city's own area names (The Great Forge, the Cleft of Shadow...). Gear → Map → City maps turns it off.
- **Blizzard's look.** The terrain is drawn as Blizzard drew it, on each map's dark water, with Blizzard's HD icons for quests, places and gathering nodes. Zone borders show on the big map.
- **Crowded icons grouped.** Overlapping icons become a small pill; click it to see them all.
- **New controls.** A quest line at the bottom left (the quest you follow and its progress, else your quests in this zone), and a zoom reset button above + while you're zoomed away from the default.
- **A tidier gear menu.** Map, Quests, Places, Nearby (rares, treasures, your party and Blizzard's tracking types), Other addons; Use Blizzard's minimap and Reset to defaults; then Settings (Follow you, Group overlapping icons, Minimap button, Reset window position, Advanced).
- **A fresh start.** 2.0 saves under a new name: 1.0's window place, layers and remembered rares aren't carried over. Rares you see from now on are remembered for every character on your account. Blips seen before are kept up to 5000 a continent.
- **Gone since 1.0:** colour-matched tiles and the sea texture, the unexplored shade, and the estimated circles for quests the game gives no area.

### Known limits
- **WoW Forever** only, on the client build it was made for, and English (enUS) clients only.
- **Instances** (dungeons, raids) hide your position: they show whole, without your arrow, the line or blips.
- Blizzard's blips are sensed only within about 230 yards of you.
- The map stays north up; with Rotate Minimap on, other addons' minimap pins hide.
- Routes are walking only: no flights, boats or portals. No per-character settings.
- Other minimap addons (SexyMap, square-minimap addons) may conflict; while FarmHud has the minimap, MagicMap steps aside. Neither has been tried in game yet.
- Not yet checked in a long play session: the final round of testing (performance over 10+ minute sessions, combat, Questie alongside, the build without quest data) is what this candidate is for.

### How to report
- The moment something looks wrong, type `/mm mark <what you saw>` (it saves what the map was doing). A screenshot (Print Screen) helps a lot.
- When you're done, `/reload` or log out (the game writes its file then), and send `World of Warcraft/_classic_beta_/WTF/Account/<your account>/SavedVariables/MagicMap.lua` and your screenshots (`_classic_beta_/Screenshots/`). Nothing is sent anywhere by the addon itself.
- A 20-minute guide of places to try: [docs/playtest-external.md](../docs/playtest-external.md).

<!--
Release checklist (the user's, before the upload; delete this block from the published notes)

- D1 (QuestieDB declares no licence): pick the zip. tools/package.sh v2.0.0-rc.1 builds both
  (the tag must match the TOC's ## Version); which one goes up is D1's call. Without the data, the
  install note "You don't need QuestieDB" still holds, but quest tooltips lose their mobs and items
  (one chat line says so at login): say so in the notes.
- Mark the GitHub release a pre-release.
-->
