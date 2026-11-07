**MagicMap 2.2.0.** For WoW Forever, build 1.60.1.70790.

- **Track or path to any icon.** Click any pin and its tooltip grows into a small popup with Blizzard's red buttons: **Track** shows the way with the gold arrow alone, and **Path** draws the walk as a line.
  - Quests also get *Open in quest log*; your waypoint gets *Clear*.
  - Path to keeps you and the target in view on the minimap, **zooming in as you get closer**.
  - **Arriving finishes it.** Within 5 yards (or inside a quest's area), the arrow and line go away and the waypoint clears.
  - What you track wears the world map's soft gold glow (Settings > Tracking > Tracked icon).
- **One look for tooltips, popups and menus:** compact and minimal.
  - A quest's level sits in a subtle pill beside its title.
  - Herbs and ores lead with their item's icon.
  - Hover and the popup have small, quick animations.
- **Quest pins as the world map draws them:** the dark disc with its gold ring and yellow dots.
- **Herb and ore pins coloured by difficulty**, by your skill against the node's, in the game's skill-up colours.
- **A tidier big map:**
  - Most pins show only once you're zoomed in. Quests, party, flight points, dungeons and raids always show; set it per type in Settings > Pins.
  - Settings > Pins lists every pin type, with its size, opacity, icon and grouping.
- **The quest pill is the one pill for your target:**
  - It shows its name, progress and yards over a progress fill.
  - Pick its pieces and their order, and the bar's colour, in Settings > Quest pill.
  - Hover it for the quest's tooltip; click it for the popup.
- **Map controls:**
  - A round recenter button by the zoom buttons replaces Follow me.
  - The big map's mode button turns to Blizzard's condense arrow.
- **Frame title** (Settings): choose what the title and subtitle say: zone, coordinates, target, distance, times, or day or night in the minimap's gold ring.
- **Resources:** keep your gathering tracker on through deaths, reloads and loading screens.
- **Fixes:**
  - Gathered nodes vanish within about a second.
  - No ghost dots from you, your party or your pets.
  - Quest tooltips no longer list "dropped by".
- The settings window is rebuilt: pages in a sidebar, undo per setting, Reset per page.

### Install
1. Download `MagicMap-v2.2.0.zip` below, or update from [CurseForge](https://www.curseforge.com/wow/addons/magic-map).
2. Unzip it into `World of Warcraft/_forever_/Interface/AddOns/`, replacing the old `MagicMap` folder.
3. Restart the game (this version adds files, so `/reload` isn't enough). Your settings are kept.

Known: a followed quest's dots can look stretched over its disc ([#22](https://github.com/benmills/MagicMap/issues/22)), to be fixed in a 2.2.1.
