**MagicMap 3.0.2.** For WoW Forever, build 1.60.1.70888.

- **Quest names on the small map.** Settings → Pins → Quest → Names on small map puts each quest's name and progress
  under its pin on the small map, for playing without Questie. Off by default; the big map's switch is now
  "Names on big map".
- **Zone and subzone opacity work.** The names drew fully solid whatever Zone name opacity and Subzone opacity said.
- **New defaults** (settings you've changed are kept):
  - A new install's small map sits at the screen's top right, 234 by 219, with its title above it. If you already
    have MagicMap, your map stays where it is; `/mm reset` or Settings → General's reset moves it to the new spot.
  - Subzone names: 45% opacity, 80% size.
  - The title says the time, then the zone; on hover, the coordinates, then the zone.
  - Points of interest off (gear → Map).

### Install
1. Download `MagicMap-v3.0.2.zip` below, or update from [CurseForge](https://www.curseforge.com/wow/addons/magic-map).
2. Unzip it into `World of Warcraft/_forever_/Interface/AddOns/`, replacing the old `MagicMap` folder.
3. `/reload` (no new files since 3.0.0). Your settings are kept.
