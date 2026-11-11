**MagicMap 3.0.1.** For WoW Forever, build 1.60.1.70888.

> **The quest pill is now off by default.** If you used it in 3.0.0 and never changed its setting, it's gone after
> this update. Turn it back on in Settings → Quest pill → Shows. Quest names on the big map are off by default too
> (Settings → Pins → Quest → Names on the big map).

- **The small map goes back to you on its own:** 3 seconds after you pan or zoom and move the cursor away, it glides
  back to you at your default zoom (it used to wait 6 seconds and keep your zoom). Settings → General → Return to
  default and Return after.
- **Pin a view.** A pin above the reset arrow holds the view you've made until you click it again, Track or Path to
  something, or reload.
- **Default zoom** in the gear (small map): Auto, or any of Blizzard's minimap zooms, shown as the yards across.
- **Quest names on the big map** (when on) show the quest's progress under the name, smaller and muted. The small
  map shows neither.
- **Blips above or below you** keep their full tooltip (icon, skill colour and pill), with Blizzard's arrow on the icon.
- **Fixes:**
  - An addon turned off in the gear's Other addons (Questie, say) hides all its pins: its minimap pins drifted over
    the map before.
  - The map's art repairs stay on through game patches that don't change the map (later builds of the same
    version), instead of turning off with a chat message each time.
  - Blizzard's minimap tooltips work again after switching back to it.
  - Zooming in a dungeon no longer flashes black.
  - Not replacing the minimap now leaves Blizzard's minimap as it is: no blips over our map, no AddOns button, its
    buttons where they were.
  - If MagicMap can't show Blizzard's blips (a game update, or another minimap addon), it says so once in chat
    instead of hiding them silently.

- **Data** for game build 1.60.1.70888, and quest data from QuestieDB 1.0.14.

### Install
1. Download `MagicMap-v3.0.1.zip` below, or update from [CurseForge](https://www.curseforge.com/wow/addons/magic-map).
2. Unzip it into `World of Warcraft/_forever_/Interface/AddOns/`, replacing the old `MagicMap` folder.
3. `/reload` (no new files since 3.0.0). Your settings are kept.
