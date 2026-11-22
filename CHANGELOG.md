# Changelog

Each release's notes, newest first. The zips are on [GitHub](https://github.com/benmills/MagicMap/releases).

## Unreleased

- **Blizzard's minimap, MagicMap's map.** Settings › General › Minimap look: Blizzard's keeps Blizzard's own
  minimap where it is, with its ring, zone name, buttons and clock, and draws MagicMap's map inside it in place of
  Blizzard's ground. It still pans and zooms as MagicMap's does; the big map (M) is unchanged. Blizzard's own + and - zoom it.
  A small MagicMap badge under the tracking button (in Blizzard's addon compartment box) marks it as MagicMap's;
  a click opens MagicMap's menu, with Minimap look to go back to MagicMap's frame. MagicMap's rim button stays
  hidden while the badge shows.

## 3.2.1 (build 1.60.1.71037)

- **Smoother when you stray from the line.** Finding the way again after you wander off it now makes about a
  quarter of the memory churn it did in 3.2.0, so it's gentler on your frame rate while you ride around.

## 3.2.0 (build 1.60.1.71037)

- **The line walks the ground.** "Path to" now finds the way you'd actually walk: round cliffs, mountains and
  lakes, over bridges and down ramps, and not off drops that would hurt you. Rough patches a few yards across are
  crossed rather than bent round, so the line stays calm.
- **A calm line by your arrow.** The line no longer swings each time you turn. It rejoins the way a little ahead
  of you and slides along as you walk.
- **A line you can see on snow and at night.** With no outline, the line now tints the ground under it instead
  of being painted on top: it reads on Winterspring snow and in Duskwood alike, without getting any louder.
  (White and the outline look as before.)
- **Settings › Route**, a new page: the gap round your arrow, how far ahead the line rejoins the way, when a new
  way is found, how round its corners are and how much rough ground it cuts across. "Leave the way you face" and
  "Skip ahead" bring back the old behaviour if you liked it.

## 3.1.1 (build 1.60.1.70938)

- **You can see your mail again.** While MagicMap replaces your minimap, Blizzard's new-mail icon (and the crafting
  order one) now sits at the map's top right, as it does on Blizzard's minimap. It shows while you have mail, and
  hovering it says who it's from.
- **Button-collector addons pick up MagicMap's button.** HidingBar, MBB and the like now gather the MagicMap
  minimap button with the rest. With HidingBar (or any addon that brings LibDataBroker and LibDBIcon) it's a
  standard addon launcher, so it shows in the bar by itself; otherwise it can be added by name,
  `MagicMapMinimapButton`.

## 3.1.0 (build 1.60.1.70938)

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
- **Fuller quest data.** Quest givers and turn-ins come from QuestieDB 1.1.0, which fills in much more of who gives
  and takes each quest on Forever.

### Known
- **Herb and ore tooltips are Blizzard's.** Since build 1.60.1.70938 the game keeps the names of Blizzard's minimap
  blips from addons, so MagicMap can't show its own tooltip for them (the node's icon, your skill against it);
  Blizzard's shows instead. `/mm overlay` says which this client does.

## 3.0.2 (build 1.60.1.70888)

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

## 3.0.1 (build 1.60.1.70888)

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

## 3.0.0 (build 1.60.1.70862)

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

## 2.2.1 (build 1.60.1.70790)

- **The time leads with day or night.** In the frame title, each time (local or server) starts with the minimap's own sun or moon in its gold ring, instead of AM or PM. The separate *Day or night* piece is gone.
- **New defaults,** tuned in play-testing:
  - **Title:** the zone and local time at rest; on hover, the zone, subzone, tracked target and distance.
  - **Quest pill:** backing at 60%.
  - **Track arrow:** 105% size, fully opaque, 96 px out.
  - **Tracked glow:** 200% size, fully opaque.
  - **Path line:** 1.4 px at 65%.
  
  Settings you've already changed are kept.

## 2.2.0 (build 1.60.1.70790)

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

## 2.1.2 (build 1.60.1.70790)

- **Every quest giver with a quest for you shows "!"**, including those the world map doesn't list (Ukor in Sen'jin Village). It checks your level, race, class, faction and earlier quests, and hides quests already in your log or handed in.
- **Quest icons never group** into pills, so a "!" or "?" is always on its own.
- **Minimap size is cleaner:** no zone names and no grouped pills. Both show on the big map (M).
- **The big map opens where you left it.** Move or resize it once, and M opens it there again, after a reload too. `/mm reset` puts it back.
- **Fewer gold dots:**
  - Vendors get the icon of what they sell (food, reagents, poisons, ammunition, fishing; a gold coin for general goods and trade supplies).
  - Forever's own herbs and ores (Wilted Peacebloom, Stunted Silverleaf, the amber and obsidian chunks) get their icons, and an herb or ore MagicMap doesn't know gets the icon of what you're tracking.
  - Flight masters get Blizzard's boot.
- **Settings > Info pills:** the quest pill (bottom left) and the distance pill (top). Choose their backing and size, what the quest pill shows, yards and/or time, and which corner.
- The zoom reset button uses Blizzard's gold dot.

## 2.1.1 (build 1.60.1.70790)

- **The map art repairs show again.** The game's patch to 70790 turned them off (they only draw on a build they've been checked against). Their tiles are unchanged in 70790, so they're back on.
- **Data from 70790:** one flight path link the patch removed is gone from routes. Everything else is the same as 2.1.0.

## 2.1.0

**MagicMap 2.1.** Choose what MagicMap replaces, set it up your way, and get where you're going: a welcome on first run (your minimap, the world map, both or neither), a Settings window for the map's look, click any icon to track it, and a calmer, clearer map throughout. 2.1 builds on 2.0, so everything you had is kept. Please keep opening issues for anything odd; a screenshot helps a lot.

## 2.0.0

**MagicMap 2.0.** Your minimap, zooming out to the whole world on the game's own terrain, with Blizzard's live blips still on it and Blizzard's indoor maps inside buildings. Press M and it grows into a big map. 2.0 is MagicMap rebuilt from the ground up: smoother, steadier, and it now knows where you are inside cities, caves and buildings. Please keep opening issues for anything odd; a screenshot helps a lot.
