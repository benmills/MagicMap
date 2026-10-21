# Reference shots: the spike

What v1 has to look like (docs/v1-plan.md §1 gate 2, §4), shot once from the MagicMap spike
1.0.0 in one session (M0.8). Every gate pairs its `/mma shot`s with these by id, and each row of
docs/parity.md names the shot it's judged against.

- Files: `ref-<id>.jpg`. Each is a client screenshot, `WoWScrnShot_<MMDDYY_HHMMSS>.jpg`, renamed by
  `tools/refshots.py`. The script also notes which stamp became which id in `stamps.txt`.
- Never edited. A retake replaces one file.
- Zoom is the spike's: screen units (UI units) per tile, 16..800, a tile being 533.33 yd. "home"
  means after `/mm reset`: the window's side × 2.67, so 200 yd across. "big home" means home ÷ 1.5,
  which is where M lands.
- Motion (grow, shrink, flights, the zoom chase, fades) is judged against the spike's GIFs, not
  stills: `~/code/MagicMap/docs/{zoomable-minimap,minimap-to-big-map,big-map-zoom,pick-and-fly}.gif`
  and `~/code/MagicMap/MagicMap-path-mode.gif`.

## Before the session

1. AddOns list: **MagicMap on, MagicMapAtlas off**, everything else off. The spike and the
   rebuild both hook ToggleWorldMap and take over the Minimap (v1-plan §3). Questie comes back on
   only for the optional block O.
2. Screenshots: JPEG, the client's default (`/console screenshotFormat jpeg` if it was changed).
   Raise the quality for these: `/console screenshotQuality 10`.
3. Spike state: every layer at its default (gear: everything on except Graveyards and Shade
   unexplored), Rotate Minimap off, colour-matched tiles on (gear → Settings → Map).
4. A macro called `ref` on a key, run before every shot. It prints the zoom (the spike saves it
   once a zoom settles), the window's size and the UI scale into chat, so the numbers are in the
   picture:

       /run local f=MagicMapFrame print(format("ref zoom %.0f  window %dx%d  ui %.2f",MagicMapDB.zoom,f:GetWidth(),f:GetHeight(),UIParent:GetEffectiveScale()))

5. Fill in the Session table below.
6. Stand in Kharanos (Dun Morogh) at the door of the Thunderbrew Distillery and run `/mm reset`.

For each shot: set it up, press `ref`, then Print Screen. Take one screenshot per shot, in list
order. If a shot goes wrong, delete the bad file from `Screenshots/` and take it again before
moving on. The script pairs the newest screenshots with the list in order.

## The list

"Cursor off" means the cursor is off the window, its buttons and any pin, and no tooltip is up.

### Block A: Kharanos, the minimap

| # | id | spot | uiMap | zoom | form | what to frame / do |
|---|---|---|---|---|---|---|
| 1 | `small-home` | Kharanos, Thunderbrew door | 1426 | home | small | Whole screen, cursor off, follow on. The window on Blizzard's minimap spot, the metal border, the title band (above it, or below when the window is within 24 px of the screen's top), the arrow, blips. |
| 2 | `small-hover` | same | 1426 | home | small | Cursor resting on the map left of the arrow, not on a pin. The controls are revealed (mode, gear, zoom −/+, follow with its ring, grip) and the title shows coordinates. |
| 3 | `small-drag` | same | 1426 | home | small | Drag the map ~40 px east (follow turns off), then let the cursor rest on the map. Follow button off: no ring, grey, faded. Afterwards take the cursor off and wait 6 s for the glide back. |
| 4 | `small-near` | same | 1426 | 800 | small | Wheel in to the closest (800), cursor off. Tiles close up, the arrow's size, blips and service icons at 14 px. |
| 5 | `small-seam` | Kharanos, east edge, on the tile line | 1426 | 800 | small | `/mm debug` on. Walk east until the title's tile reads `33_42` instead of `32_42`, then step back ~5 yd so the tile line is in view. Cursor off. Shows whether the spike's ground has a seam, and the debug title. Then `/mm debug` off. |
| 6 | `small-town` | Kharanos, Thunderbrew door | 1426 | 250–300 | small | Cursor off. Subzone borders and names (weight ≥15), town services and the mailbox around the village. |
| 7 | `small-zone` | same | 1426 | 62–80 | small | Cursor off. Ironforge's zone border with its shadow, UPPERCASE zone names, places; remote blips and rares (both from zoom 60). |

### Block B: the big map

Start from home: `/mm reset` while small, then M.

| # | id | spot | uiMap | zoom | form | what to frame / do |
|---|---|---|---|---|---|---|
| 8 | `big-home` | Kharanos | 1426 | big home | big | Press M and let it settle. Whole screen, cursor off. The window centred at 0.7 of the screen, the title band above it, coordinates in the title. |
| 9 | `big-hover` | same | 1426 | big home | big | Cursor on the gear button until its tip (`Layers & settings`) shows. Every control is revealed. |
| 10 | `big-zones` | Dun Morogh centred | 1426 | 80–100 | big | Wheel out until Dun Morogh, Ironforge, Loch Modan and part of Wetlands are in view. Cursor resting inside Loch Modan: the hover zone border and its lit label, Loch Modan named in the title. |
| 11 | `big-shade` | same view | 1426 | 80–100 | big | Gear → Map → Shade unexplored on, cursor off. Undiscovered parts shaded. Then turn it off again. |
| 12 | `big-places` | Dun Morogh, Ironforge | 1426 | 40–60 | big | Gear → Places → Graveyards on. Cursor on Ironforge's flight point for its tooltip. Flight points, Gnomeregan's entrance, graveyards and points of interest are in view. Then turn Graveyards off again. |
| 13 | `big-continent` | Eastern Kingdoms | 1415 | 16 | big | Wheel all the way out, cursor off. The whole continent: coast fades, sea colour, zone names. |
| 14 | `big-picker` | same | 1415 | 16 | big | Click the zone name: the map picker is open, cursor on its first entry. |
| 15 | `big-instance` | an instance (picker → Gnomeregan, or the first dungeon listed) | — | as it opens | big | Pick it. The instance map is shown whole, with no arrow, borders or blips. Cursor off. |
| 16 | `big-browse` | Kalimdor (picker) | 1414 | as it opens | big | Pick Kalimdor, cursor off. The title names the continent and the hint reads `right-click: Follow me`. Then right-click → Follow me. |
| 17 | `big-gear` | Kharanos | 1426 | big home | big | Gear → Map open, cursor on Zone borders for its tip. |
| 18 | `big-settings` | same | 1426 | big home | big | Gear → Settings → Advanced open, cursor on its first entry for the tip. |
| 19 | `big-tracking` | same | 1426 | big home | big | Gear → Tracking open: Blizzard's tracking types, less those the map replaces. |
| 20 | `big-inspector` | Kharanos | 1426 | 300–400 | big | Back on you (wheel to 300–400 if needed). Right-click the ground ~300 yd from you: the zone info lines and the menu (Waypoint here, Clear waypoint, Follow me). |
| 21 | `big-waypoint` | same | 1426 | 300–400 | big | Choose Waypoint here. Cursor off. The waypoint pin, the dashed route from you to it, and the target in the title (`<title> N yd`). |
| 22 | `small-edge-arrow` | Kharanos | 1426 | home | small | M to shrink. With the waypoint off the window: the gold edge arrow and the route to the edge. Cursor off. Then Ctrl-right-click to clear the waypoint. |

### Block C: quests (Kharanos, or the hub you're questing at: note it in the Session table)

Needs 3+ quests in the log near you: a kill, a collect, ideally one ready to turn in, and a quest
giver with a `!` nearby.

| # | id | spot | uiMap | zoom | form | what to frame / do |
|---|---|---|---|---|---|---|
| 23 | `big-quests` | your quest areas | 1426 | 100–130 | big | M, wheel and pan until the quest areas fill the window, cursor off. Quest pins with difficulty discs, objective icons and counts, blobs, dashed estimates, turn-in `?`, offers `!`. |
| 24 | `big-quest-tip` | same | 1426 | 100–130 | big | Cursor on a quest pin: the full quest tooltip. |
| 25 | `big-quest-follow` | same | 1426 | 100–130 | big | Click that pin to follow it, then cursor off. The followed pin (26 px, glow), its blue area, the route to it, the target in the title. |
| 26 | `small-quests` | same | 1426 | home | small | M to shrink, cursor off. Pins at minimap size, followed quest still on. Afterwards click the quest again (big map) to stop following it. |

### Block D: Ironforge

| # | id | spot | uiMap | zoom | form | what to frame / do |
|---|---|---|---|---|---|---|
| 27 | `small-indoor` | Ironforge, The Commons | 1455 | home | small | Walk in, cursor off. Ironforge's indoor minimap pictures over the dimmed tiles (ADR 0008). |
| 28 | `big-indoor` | same | 1455 | big home | big | M, cursor off. Then M back. |

### Block E: chat and release

| # | id | spot | uiMap | zoom | form | what to frame / do |
|---|---|---|---|---|---|---|
| 29 | `chat-layers` | anywhere | — | — | — | `/mm layers`: frame the chat, which shows the prefix and the on/off colours. |
| 30 | `blizzard-rim` | anywhere outdoors | 1426 | — | Blizzard's | `/mm toggle`: the window hides and Blizzard's minimap is back as it was. Cursor on MagicMap's rim button (215°, lower left) for its tip. Then `/mm toggle` again. |

### Block O: optional (only if the moment comes; `refshots.py --skip` the rest)

| # | id | spot | uiMap | zoom | form | what to frame / do |
|---|---|---|---|---|---|---|
| 31 | `small-group` | anywhere, in a party or raid | — | home | small | Party dots in class colours (a dead one is grey). |
| 32 | `small-corpse` | wherever you died, as a ghost | — | home | small | Released: the tombstone pin, the route to it, follow forced on. |
| 33 | `small-rare` | near a rare you've seen | — | 62–80 | small | Cursor on the rare's pin: `Seen here <Mon DD>`. |
| 34 | `small-vignette` | near a live rare or treasure | — | home | small | The live vignette pin, cursor off. |
| 35 | `small-addon-pins` | Kharanos, Questie on (`/reload`) | 1426 | home | small | Questie's minimap pins on the window, cursor off. |
| 36 | `big-addon-pins` | same | 1426 | 100–130 | big | Questie's world pins on the big map, and gear → Other addons open. |

## After the session

    .venv/bin/python tools/refshots.py --dry-run          # the pairing, oldest first: check it
    .venv/bin/python tools/refshots.py --skip small-group,small-corpse   # the optional ones not taken
    .venv/bin/python tools/refshots.py small-seam         # a retake: the newest screenshot only

`--wow`/`MAGICMAP_WOW` and `--flavor` work as in tools/telemetry.py. Restore any CVars you changed,
turn MagicMapAtlas back on, and commit `ref-*.jpg`, `stamps.txt` and the Session table.

## Session

| | |
|---|---|
| Date | |
| Client build (`/run print(GetBuildInfo())`) | |
| Resolution, UI scale | |
| Character (level, race, class) | |
| Spike | MagicMap 1.0.0 (installed TOC `## Version: 1.0.0`) |
| Quest hub for block C | |
| Optional shots taken | |
