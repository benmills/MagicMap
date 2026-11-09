**MagicMap 3.0.0.** For WoW Forever, build 1.60.1.70862.

Game build 1.60.1.70862 stopped addons from reading the minimap's blips, so herbs, ore, quest givers and town services went missing from MagicMap. 3.0.0 fixes that by putting **Blizzard's own minimap blips over the map**, and tidies the menus and settings around it.

- **Blizzard's blips, on our map.** Herbs, ore, mailboxes, trainers and quest givers' `!` and `?` are drawn by Blizzard's own minimap, centred on you and sized to the map's zoom.
  - While the map follows you, the mouse wheel and zoom buttons step through Blizzard's minimap zooms. Past its widest or closest zoom, the blips hide and the zoom glides as before.
  - The blips hide on the big map and while a path's line is drawn.
  - In an instance that hides where you are, Blizzard's own minimap shows.
- **Richer blip tooltips:**
  - **Herbs and ores** show the skill they need in a pill, coloured by your skill against it (red to grey), with the profession under the name.
  - **NPCs** show their title ("General Goods"), then the quests they have for you, each in its difficulty colour.
- **Quests:**
  - The map shows the quests you're on. Quests to pick up and hand in are Blizzard's `!` and `?`.
  - On the big map, each quest's name sits under its pin, in its difficulty colour.
- **A new quest pill.** WoW Forever's progress bar in a thin bronze frame.
  - By default it says the quest's progress, then the distance, smaller.
  - An **×** at its end stops following, tracking or pathing.
  - It shows only what you track; the "N quests in this zone" count is gone.
- **Gear menu, simplified:**
  - **Map** holds every layer in one list.
  - **Tracking** matches Blizzard's tracking menu.
  - **Keep tracking** and **Other addons** each have their own row.
- **AddOns button.** Your minimap's addon buttons, calendar and clock move to their own button beside the gear, shown while you point at the map.
- **Other addons' pins** (Questie, HandyNotes) sit above Blizzard's blips, so their tooltips work. On the big map they show only when you're zoomed in to about two zones across.
- **New defaults:**
  - Subzone names: 55% opacity.
  - Quest pill: backing 35%, size 90%, bar 60%.

  Settings you've already changed are kept.
- **Removed:**
  - The Settings pages Resources and Grouping (their defaults stay; Keep tracking is in the gear).
  - The City maps option (city interiors always show on the big map).
  - Fade quest pill.
  - The Indoor maps report row (use `/mm indoor`).
  - MagicMap's own herb, ore and town-service pins, now Blizzard's blips.

### Install
1. Download `MagicMap-v3.0.0.zip` below, or update from [CurseForge](https://www.curseforge.com/wow/addons/magic-map).
2. Unzip it into `World of Warcraft/_forever_/Interface/AddOns/`, replacing the old `MagicMap` folder.
3. Restart the game (this version adds files, so `/reload` isn't enough). Your settings are kept.
