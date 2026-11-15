**MagicMap 3.1.0.** For WoW Forever, build 1.60.1.70938.

- **Time of day.** The map takes on the game's own outdoor light where you stand, as Forever's minimap does: warm at
  dawn and dusk, cool and dimmer at night, on both the small and the big map. It's on by default. Settings → Map →
  Time of day turns it off; open it (+) for Strength and Night darkening. `/mm tint` says what it's doing here and now.
- **Default zoom is a slider.** Settings → General → Default zoom picks one of Blizzard's minimap zooms, shown as
  yards across, so herbs, ores and the other minimap blips always show at it; the gear's Default zoom lists the same.
  A zoom you'd picked before is kept.
- **The AddOns menu lists each addon once.** An addon in both the compartment and as a minimap button (Altoholic,
  Leatrix Plus) shows one row, and Questie's quest pins on the minimap no longer show up as buttons.
- **Track can show the line.** Settings → Tracking → Shows: the gold arrow (as before, the default), the
  line Path to draws (without moving the map), or both.
- **Settings, reorganized.** Seven pages, one job each: General (the window, now with **Lock window**, and how the
  map moves), Map (how it looks), Header (the line above the map, was Frame title), Pins, Quests (the quest pill,
  quest names on the map, and two simple strengths for quest areas), Tracking (the arrow, the line and the target,
  was split over Tracking and Pathing) and Advanced (the pill layout, the quest areas' raw numbers, diagnostics).
  Grouping and Keep tracking are back on the Pins page. The gear's map rows (Quests, Flight points, Graveyards...)
  are now the same switches as Settings → Pins, so the two can't disagree, and each addon with map pins has its own
  switch under Pins → Addons. Your settings are kept.
- **Questie's pins are back.** Questie 12.8 moved its map pins somewhere MagicMap didn't look, so none of them
  showed on our map. They show again, and on the big map zoomed in to about three zones across, not two.
- **Quests to turn in and to pick up are back.** A gold "?" where a finished quest is turned in and a "!" where a
  quest can be picked up, on both the small and the big map (Settings → Pins → Quests: To turn in, To pick up).
  Where ours shows, Questie's matching "!" or "?" steps aside, so each shows once and ours can be hovered.
- **Pins respond more reliably.** Hovering a pin near Blizzard's blips, just after the blips appear under a still
  cursor, or after another addon hid its tooltip, now shows its tooltip; Questie icons it has faded out no longer
  sit invisibly over our pins.

### Known
- **Herb and ore tooltips are Blizzard's.** Since build 1.60.1.70938 the game keeps the names of Blizzard's minimap
  blips from addons, so MagicMap can't show its own tooltip for them (the node's icon, your skill against it);
  Blizzard's shows instead. `/mm overlay` says which this client does.

### Install
1. Download `MagicMap-v3.1.0.zip` below, or update from [CurseForge](https://www.curseforge.com/wow/addons/magic-map).
2. Unzip it into `World of Warcraft/_forever_/Interface/AddOns/`, replacing the old `MagicMap` folder.
3. Restart the game (not just `/reload`): this version adds new files. Your settings are kept.
