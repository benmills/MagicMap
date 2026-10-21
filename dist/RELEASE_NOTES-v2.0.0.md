**MagicMap 2.0.** Your minimap, zooming out to the whole world on the game's own terrain, with Blizzard's live blips still on it. Press M and it grows into a big map. 2.0 is MagicMap rebuilt from the ground up: it looks and behaves as 1.0 did, and underneath it's faster, steadier and easier to keep working. Please keep opening issues for anything odd, and a screenshot helps a lot.

### Install
Download `MagicMap-v2.0.0.zip` below and unzip it into `World of Warcraft/_classic_beta_/Interface/AddOns/`, so you end up with `Interface/AddOns/MagicMap/MagicMap.toc`. If you're updating, delete the old `MagicMap` folder first, then restart the game (not just `/reload`).

### What's new since 1.0
- **Rebuilt, same map.** Everything 1.0 shows and does is here, and it looks and feels the same. The difference is underneath: the map does its work in small, timed slices, so zooming, dragging and growing the map stay smooth, and an error in one part is caught and reported once (`/mm errors`) while the rest keeps running.
- **A fresh start for your settings.** 2.0 saves under a new name. Your window's place and size, the layers you turned off, and the rares 1.0 remembered (`MagicMapDB`, `MagicMapLandmarks`) aren't carried over. Rares you see from now on are remembered for every character again.
- <!-- D1, with the data: --> **No QuestieDB needed.** The quest facts MagicMap shows (mobs, items, turn-in, town services) are built in, so the QuestieDB addon isn't needed any more.
- <!-- D1, without the data: --> **Quests without their mobs and items.** MagicMap no longer reads QuestieDB. Your quests, their areas, following and the route all work, and one chat line at login says the quest details are missing: tooltips show without mobs, items and turn-in, and town services are plain gold dots, only where Blizzard's minimap shows them.
- **More remembered blips.** Mailboxes and services seen before are kept up to 5000 a continent (1.0 kept 300).
- **Diagnostics for bug reports.** `/mm help` lists them all: `/mm perf` records 10 seconds of play, `/mm errors` lists what went wrong, `/mm check` compares the map's data with your client. Everything stays in your saved variables: nothing leaves your computer.
- **Not in 2.0:** 1.0's notes mentioned a "Blizzard's blips past the edge" setting and path mode zooming out to fit your target. Neither was in 1.0's code, and neither is in 2.0.

### What it does
- **The minimap:** square on your minimap's spot, wheel and +/− zoom, drag to pan, glides back to you 6 seconds after a pan, move and resize it, `/mm reset`. `/mm`, the rim button or the addon compartment swaps it with Blizzard's.
- **The big map:** M or the red button grows it, M, the button or Escape shrinks it; L still opens Blizzard's map. Click the zone name to pick any continent, map or instance; click a zone to fly there.
- **The ground:** the game's minimap terrain at any zoom, as Blizzard drew it, zone and subzone names, and zone borders on the big map.
- **Indoors:** Blizzard's indoor minimap pictures inside buildings, by floor; on the big map in a capital, the whole city's buildings with its area names (City maps).
- **Blizzard's blips:** herbs, ore, the mailbox and tracked NPCs around you with their icons and tooltips; town services and blips seen before when zoomed in; Blizzard's duplicate tracking switched off while MagicMap draws it, and always put back.
- **Quests:** your quests in Blizzard's art and difficulty colours, quests to pick up, rich tooltips, objective areas as the game draws them. Click one to follow it; the quest line at the bottom left shows its progress.
- **Where to go:** a hand-inked walking line to your corpse, the quest you follow or your waypoint, around cliffs, lava and water, and an arrow on the edge when it's off the map. Ctrl-click for a waypoint, Shift-click for a `/way` line, right-click for the menu and, on the big map, what's there.
- **Places and people:** flight points, dungeon entrances, graveyards, points of interest, party and raid members, rares you've seen (account-wide), live rares and treasures, your corpse.
- **Other addons:** HereBeDragons world-map pins (Questie, HandyNotes...) on the map and minimap pins (GatherMate...) around you, nothing drawn twice.
- **Crowded icons:** overlapping icons grouped into a small pill; click it for them all.
- **The gear menu:** the layers by group (Map, Quests, Places, Nearby with Blizzard's tracking, Other addons), Use Blizzard's minimap, Reset to defaults, and Settings.

### Known limits
- For **WoW Forever** only, on the client build it was made for (1.60.1).
- English (enUS) clients only.
- Blizzard's blips are sensed only within about 230 yards of you.
- Instances that hide your position are shown whole, without the arrow, line or blips.
- The map stays north up; with Rotate Minimap on, other addons' minimap pins hide.
- Routes are walking only: no flights, boats or portals.
- Other minimap addons (SexyMap, square-minimap addons) may conflict. While FarmHud has the minimap, MagicMap steps aside.

<!--
Release checklist (the user's, before any upload; delete this block from the published notes)

- D1 (QuestieDB declares no licence): pick the zip. tools/package.sh v2.0.0 built both:
  dist/MagicMap-v2.0.0-no-questie-data.zip and dist/MagicMap-v2.0.0-with-questie-data.zip; rename the
  one D1 allows to MagicMap-v2.0.0.zip, and keep only the matching "D1" bullet above.
- D7: the channel (GitHub release, CurseForge, Wago); dist/listing-v2.0.0.md is the listing draft.
- D8 / M6.2: bring this repo into ~/code/MagicMap: docs/release/merge-plan.md (two options, nothing run).
- The final play-test, docs/playtest-final.md (D10): scripts (a)-(e) twice, every 10+ minutes, with
  `/mm check log` on: 0 errors, 0 taint, 8/8 budgets, perf.slow / perf.gaps / sensor / art empty, 0 K4
  drift lines (Data/ was regenerated at release on the installed 1.60.1.70450: byte for byte the same).
  The packaged zip installed alone (1.0 moved away): 0 errors, `/mm`, the rim button and the compartment.
- Its in-game items left open: a8, b21, c8, d9, e8 (the two sessions a script), e2 (Rotate Minimap),
  e5 (FarmHud), e7 (no data), the reference shots and the parity sign-off (docs/parity.md: every row
  signed or out by decision), and its "Decisions for you".
- New GIFs: docs/zoomable-minimap.gif and docs/minimap-to-big-map.gif are 1.0's (the look is the same).
- LICENSE: neither repo has one.
-->
