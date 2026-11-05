# Play-testing 2.1: a beta-session checklist

For the next session on WoW Forever with the 2.1.0 tree installed (`.venv/bin/python tools/install.py`, then
restart the game: new files need it).

## 0. Before anyone plays

- Play in the **release client**, `World of Warcraft/_forever_/` (wowf 1.60.1.70707), not the old beta
  (`_classic_beta_`, 70532): the data and the map-art repairs are built for 70707, and on another build the
  repairs switch off. Run the Forever client once so it makes `_forever_/Interface/AddOns`, then
  `tools/install.py` (its default is now `_forever_`) and restart the game.
- AddOns list at the character screen: MagicMap is listed and **not** marked out of date (the TOC says
  `## Interface: 16001`). If it is, note the client's interface number: the TOC needs it before release.
- No chat line saying the game build differs (game/parts/Build.lua); Settings > Map shows "Repair broken map
  art" on, and the repaints show (e.g. Stonetalon's dark square, Blasted Lands' south edge are filled in). Each line is an action and what should happen. Note anything else with
`/mm mark <what you saw>` and a screenshot. Items tagged **[unverified]** have never been seen in the real
client: they are the likeliest to be wrong.

## 1. Welcome and modes

- Fresh start (delete `MagicMap2DB` from `WTF/.../SavedVariables/MagicMap.lua` with the game closed), log in:
  Blizzard's minimap and world map are untouched, nothing of ours shows. Click the minimap button: the welcome
  opens with four cards, the first (minimap and world map) chosen and marked recommended.
- Escape on the welcome: it closes and nothing changes; click the button again and it asks again.
- Pick each mode with Continue, and `/mm welcome` to return between them:
  - **Minimap and world map:** our small map is on the minimap's spot at once; M opens our big map.
  - **Minimap only:** our small map on the minimap's spot; M opens Blizzard's world map.
  - **World map only:** Blizzard's minimap stays and works; the map opens big; M opens ours; closing it
    hides it (it never shrinks to a minimap).
  - **Neither:** nothing of Blizzard's changes; the minimap button, the addon compartment and `/mm` open and
    close our big map as a window.
- Settings > General: flip Replace minimap and Replace world map live; the map appears, hides or changes
  M's behaviour straight away, without `/reload`.
- Update path: with a 2.0 save (SavedVariables from before), log in: no welcome, both replaced as before.
- Gear menu: "Use Blizzard's minimap" shows only while ours replaces the minimap, with Blizzard's logo.

## 2. The Settings window

- Gear, then Settings; `/mm settings`; and Game menu > Options > AddOns > MagicMap > Open MagicMap Settings
  (the Options window closes behind it): each opens the same window. Escape closes it; reopening shows the
  last page you used.
- **[unverified]** The window looks right as the client's ButtonFrameTemplate: header bar, close button, sidebar
  icons not clipped, nothing overlapping the footer, draggable by its header, clamped to the screen.
- Visit every page (General, Map, Icons, Tracking line, Quest areas, Grouping, Diagnostics). **[unverified]**
  Slider art: the track and thumb look like the client's, the value reads beside the label, the thumb follows
  the mouse and the value is right at both ends.
- Drag a slider on each page with the map visible: it changes live (label size, arrow size,
  icon size, pill backing, indoor dimming; line weight and opacity; area fills; grouping distance).
- Each page's Reset puts its own settings back; Reset all (bottom) puts everything back and the widgets follow.
  `/reload`: changed values persist.
- Diagnostics: each row prints in chat or toggles (record 10 seconds, compare, memory).

## 3. Tracking and the line

- Click an icon (a flight point, a mailbox, a rare, a quest pin), left or right: the same menu, the icon's name,
  Track, then the map's rows (Clear waypoint, Follow me). Track: the line goes to it, the icon gets the focus ring, the title names it, and the tracking pill (top left of
  the map) shows yards and a time estimate. The menu then says Stop tracking.
- Click a quest pin: "Track quest" follows it (the quest pill at the bottom left shows progress); "Open in quest
  log" opens the game's quest log on it.
- Following a quest: hover the quest pill (the quest's tooltip, its area lit); click it: its menu, Stop tracking.
- A tracked icon in a crowd (a town) stands alone, out of its pill; a tracked rare shows zoomed out too.
- Click an icon inside a grouped pill's grid: the same menu.
- Ctrl-right-click (clear waypoint): the tracking ends and the ring goes.
- The line is a thin gold **dashed** line at 55%, no glow, breath or outline; it leaves your arrow with a gentle
  fade; a turning route bends in rounded corners, and turns lazily as you move. Settings > Tracking line: Dotted
  and Solid change it live; colour, glow, breathing and the outline (and its colour) toggle.
- Settings > Icons: the focus ring's size, opacity and colour change the ring on what you track, live.
- /reload with a changed line look: it comes back as set (not the defaults).

## 4. Icons and pills

- A crowd of icons (a town) becomes pills of two icons and "+N"; click one for the grid. Group icons off in
  Settings > General ungroups them.
- The quest pill (bottom left) and tracking pill (top left) are small and quiet; Info pill backing changes
  how dark they are. Zoom reset above +/- appears only when off the default zoom.
- Settings > Info pills: each row changes the pills live (size, backing, the quest pill off or followed-only, no
  progress, no fade; the distance pill off, yards or time only, top right, fading until you point at the map).
- Minimap button: round, with the ring and shape of other addons' buttons (LibDBIcon), dragging round the rim.

## 5. Quests

- Quest tooltip: a compact one-row of facts, level in its difficulty colour, "Group N" where it applies;
  turn-in shown with a `?` icon before who takes it in; no "Dropped by" heading.
- Quest areas look like Blizzard's own, the followed quest filled lightly, others a quiet edge; hover an area
  or its pin: it lifts gently, not harshly. Settings > Quest areas sliders restyle live.
- Accept a quest from an NPC you can sense on the map: the "!" over that NPC disappears as soon as the quest
  is in your log (no stale "!"). Hand it in: the "?" goes the same way.
- A quest giver with a quest for you shows "!" even when the world map lists none (Ukor in Sen'jin Village);
  one with nothing left for you (done, too high, wrong class) is a plain dot. Quest icons never group.

- Herbs and ore with Find Herbs (or Find Minerals) on: every node has its herb or ore icon, Forever's own too
  (Wilted Peacebloom and Stunted Silverleaf in the starter zones, amber and obsidian chunks); a name MagicMap
  doesn't know still gets the icon of what you track.
- Sen'jin Village's vendors: Hai'zan food, Zansoa a fish, K'waii and Tai'tasi a gold coin, Trayexir repair. Any gold dot left: hover it, `/mm mark dot <its name>`.

## 6. Ground, base picture and indoors

- **[unverified]** The base pictures load (Textures/BaseEasternKingdoms.blp, BaseKalimdor.blp): zoom all the
  way out in Kalimdor and Eastern Kingdoms, and flick the wheel fast out and in: where tiles haven't drawn yet
  you see flat zone-coloured ground with a clean coast, not the dark backdrop or a broken/white texture.
  If it's missing, nothing breaks but gaps show backdrop: note it.
- **[unverified]** The ocean: our own water round each continent and Zephras Isle (Textures/Sea*.tga), its dark
  green edge by the land, fading into the deep backdrop farther out: no seam at the coast or where it meets the
  backdrop, at any zoom and when panning; no hairline between tiles on the big map. No zone borders (gone in
  2.1); names as before. Settings > Map > Ocean off: the near-black game water again.
- Walk into a small building (an inn, a house): the small map zooms in by itself; walking out zooms back.
  Settings > Map > Indoor auto-zoom off stops it. Indoors the small map dims the terrain (Indoor dimming);
  on the big map there is no veil.
- A capital (Ironforge, Orgrimmar) on the big map: whole city, its area names (as 2.0).

## 7. Memory and performance (a glance)

- `/mm perf mem` after a session: note MagicMap's total; the quest data was packed in 2.1, so it should be lower
  than 2.0's.
- `/mm errors` after the session: none expected.
