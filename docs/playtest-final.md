# The final play-test

One sitting at the end of the run (D10), in place of a session per gate: the reference shots with the spike (~25 min), then the route with MagicMap 2.0.0 (about an hour: five sessions of 10+ minutes, one a script, and a short one on the release zip), then say **check telemetry**. Everything the lead reads is in what the client saves (SavedVariables, Screenshots/, Logs/): nothing to copy out by hand but the two checkpoint copies the route asks for. The second session a script (gate 3) is another sitting, §6.

How the route works (why: docs/playtest.md "Every session"):

- **Tick each box** as chat answers it: `marked`, or `shot <id>: WoWScrnShot_<stamp>, marked`.
- **Marks** start with the item's id: `/mm mark a1 ok`, or `/mm mark a1 <what you saw>`. A box with several checks takes one mark for all of them: `ok`, or name the ones that weren't. The moment anything looks or feels wrong (a hitch, a tear, a pin in the wrong place, missing art), mark it then: `/mm mark <id> <what>` (a mark keeps the last 2 s of trace and motion).
- **Shots**: `/mm shot <id>` standing still, cursor off the window, its buttons and pins unless the box says otherwise. No answer, or `the client took no screenshot`: take it again.
- **The client stays in front** during a session; alt-tab only at the character select.
- **Sessions**: every login and `/reload` starts one, and the lead reads each. `/reload` or log out only where a segment ends. Each segment runs **10 minutes or more** from its login (gate 3): if its boxes are done sooner, play on as its last box says. Wait **10 s** after each login before anything (the login grace and the memory read: one hitch, don't mark it).
- Zoom is px a tile, 16..800: from the closest (800) each wheel notch out is a x1.3 tick, so 4 notches out is ~280 and 9 is ~75. `/mm debug` shows it in the title (off for shots but small-seam).

## 0. Before

- [ ] A Dun Morogh character, low level, at the Kharanos inn: its quest log full (the log's cap) of Coldridge and Kharanos quests, a kill, a collect, one ready to turn in, offers (`!`) near, one with a usable item if you have it; Find Herbs or Find Minerals if it has the profession; a friend or an alt to group with for D, if you can. The same character for the reference shots and the route.
- [ ] Watch the spike's GIFs (judge against them from memory: the client stays in front): `~/code/MagicMap/docs/zoomable-minimap.gif`, `minimap-to-big-map.gif`, `big-map-zoom.gif`, `pick-and-fly.gif`, and `~/code/MagicMap/MagicMap-path-mode.gif`.

## 1. The reference shots (the spike alone, ~25 min)

First, and before the route: every shot below is paired with the spike's at the same spot, and both addons save to `SavedVariables/MagicMap.lua`, so a spike session after the route would drop 2.0.0's telemetry before the lead reads it.

- [ ] Quit the client. In a terminal:

      cd "/Applications/World of Warcraft/_classic_beta_/Interface/AddOns"
      mv MagicMap ~/.Trash/MagicMap-2.0.0 && mv MagicMap.spike-backup MagicMap

- [ ] Start the client. AddOns: **MagicMap** (the spike, 1.0.0) and **QuestieDB** (the spike requires it) on, everything else off.
- [ ] docs/evidence/shots/README.md, "Before the session" 2-6 (its step 1 is pre-rename: the spike is `MagicMap` now): JPEG at quality 10, the spike's layers at their defaults, Rotate Minimap off, the `ref` macro, the Session table, `/mm reset` at the Thunderbrew Distillery's door.
- [ ] Its blocks A-E in order, 30 shots: set each up, `ref`, Print Screen.
- [ ] Its block O: 35 `small-addon-pins` and 36 `big-addon-pins` (tick Questie, `/reload`): the route shoots both. 31-34 only if the moment comes.
- [ ] Quit the client. In `~/code/magic-map`: `.venv/bin/python tools/refshots.py --dry-run` (the pairing, oldest first: check it), then `.venv/bin/python tools/refshots.py --skip small-group,small-corpse,small-rare,small-vignette` (the O shots you didn't take). Now, before the route's screenshots: it pairs the newest. Leave `ref-*.jpg` and `stamps.txt` uncommitted (the lead commits them).

## 2. Install MagicMap 2.0.0

- [ ] The client closed: `cd ~/code/magic-map && .venv/bin/python tools/install.py --replace-spike`. It moves the spike to `MagicMap.spike-backup` and installs main as `MagicMap`, its TOC stamped `v2.0.0-…`; it says `restart the client (not /reload)`: files new to the client need a restart (L5).
- [ ] Start the client. AddOns at the character select:
  - **MagicMap** on: 2.0.0 (its version `v2.0.0-…`), the only MagicMap (`MagicMap.spike-backup` and `MagicMapAtlas.backup` don't load).
  - **Questie** (with **QuestieDB**, which it requires) **off until segment E**, and an HBD-pins addon (GatherMate2, HandyNotes) with it if you have one: none is installed today, so Questie's own HereBeDragons pins stand in. Off before E because the shots compare with the spike alone and b8 and c7 read Blizzard's tracker.
  - Every other addon off (Auctionator, Plater, Leatrix_Plus, BlizzMove, MagicTracker...).
- [ ] Log in at the Kharanos inn.

## 3. The route

### Segment A: Kharanos, motion and the big map (script a, ~17 min)

The map small on the Minimap's spot, following, at its home zoom. Note the time.

- [ ] Wait 10 s. `/console taintLog 1`; `/mm check clear`; `/mm check log` (chat: `validation log on`; again if it says off: it stays on through every login after). `/mm check art`: chat `art: all 41 there` (the sim's count), else **a0** `/mm mark a0 art <names>`.

At the Thunderbrew Distillery's door, small:

- [ ] **a1** The session's first open (`/mm toggle` if it's hidden), cursor off → `/mm shot small-home`
- [ ] **a1h** Cursor resting on the map left of the arrow, not on a pin: the controls show, the title gains coordinates → `/mm shot small-hover`
- [ ] **a1d** Drag the map ~40 px east (follow turns off), cursor resting on the map → `/mm shot small-drag`
- [ ] **a1g, a1r** Drag the map about its width east, let go, cursor off: 6 s later it glides back to you; tiles, names, pins and borders stay on the map the whole way (the borders missed its edges at the M1b gate: M1.15's fix). Alt-Z twice (the UI hidden, back), then `/mm toggle` twice (Blizzard's minimap, ours): each time the map fills in as at the first open, tiles first, no hitch → `/mm mark a1 <ok, or what>`

The ground and the wheel (as the MVP's: every wheel event a x1.3 tick, the glide stacking):

- [ ] **a1b** Wheel in a notch at a time to the closest (800), cursor off → `/mm shot small-near`
- [ ] **a4** The tear walk (docs/playtest.md "The tear walk"), at 800: `/mm debug` on, walk east until the title's tile reads `33_42`, step back ~5 yd (the col 32|33 line, x = 47.4, in view) → `/mm shot small-seam`; `/mm debug` off. Then 2 minutes back and forth across x = 47.4 between y 49 and 53, walking and running, cursor off between checks: at ~1 min → `/mm mark a4 walk`; a tear, a jump or a seam at once → `/mm mark a4 tear <what>`
- [ ] **a1b** 4 notches out (~280: subzone borders and names, town services, the mailbox) → `/mm shot small-town`; 5 more (~75: Ironforge's border on its shadow, zone names in capitals, remote blips and rares) → `/mm shot small-zone`
- [ ] **a2** On out a notch at a time to 16 and back in to 800: rares appear as the zoom passes 60, names change every quarter zoom. Then as fast as the wheel turns, 16→800→16 (every notch a tick): against zoomable-minimap.gif, the glide, the ground covered at the edges zooming out fast (names and pins may miss the edges for a few frames of a trackpad's fastest flick; none on the mouse wheel) → `/mm mark a2 wheel mouse <ok, or what>`
- [ ] **a2** With a trackpad or Magic Mouse, if you have one: a flick, then a slow drag → `/mm mark a2 wheel trackpad <ok, or what>` (each mark's `wheel` traces show what the device sends)
- [ ] **a3, a1b** Fling: drag-pan fast in several directions, release, let it settle: no blank edges, no hitch. Your arrow: the Minimap's own, its shadow softened, turning smoothly as you turn. Then `/mm reset` (home zoom, following) → `/mm mark a3 <fling ok, arrow ok, or what>`
- [ ] **a3b, a1c, a3c** Find Herbs or Find Minerals off, then on (spellbook; skip without the profession): a herb or vein in view shows within ~1 s. Mount and ride a loop out of Kharanos past herbs and veins, then stop: blips met riding settle on their spots, none doubled. Then, at 60 or more, walk away from a herb or a vein: it stays drawn while the Minimap tracks it (~220-233 yd), then goes → `/mm mark a3b <blips ok; herb in N s; gone at N yd, or what>`. Two of one name a few yards apart: `/mm toggle`, hover Blizzard's minimap where they overlap, `/mm toggle` back → `/mm mark a3b twin <twice, once>`. A blip appearing while you stand still (a respawn) can take ~40 s: say if that bothers you (decision 9).

The big map (the reference session's block B, in its order), back at the door:

- [ ] **a5** Grow and shrink x5 (M, or the red button), each animation ended, against minimap-to-big-map.gif → `/mm mark a5 grow <ok, or what differs>`. M once more, cursor off as it lands → `/mm shot big-home`; cursor on the gear until its tip (`Layers & settings`) shows → `/mm shot big-hover`
- [ ] **a5g, d2, d2t** The gear, big: a submenu a group of layers (Map, Places, People...), a line, Settings; hover each row: its tip, a white title over gold text; turn every layer off and on from its row: it goes at once and comes back, the menu staying open. Gear → Map open, cursor on Zone borders → `/mm shot big-gear`. Gear → Settings → Advanced open, cursor on its first entry → `/mm shot big-settings`. Gear → Tracking open (Flight Master, Track Quest POIs and Points of Interest aren't offered) → `/mm shot big-tracking`; each box turns its type on and off in Blizzard's tracking menu too. Settings > Advanced: Debug info in the title (tile, FileDataID, zoom, layout ms), Indoor maps, Record 10 seconds, Compare with other addons, Memory breakdown: each runs its command and its box follows. Settings > Map: Colour-matched tiles off and on (plain, then tinted). Settings > Minimap: Minimap button off and on (the rim button goes, comes back); Use Blizzard's minimap (ours hides), then `/mm toggle` (back). Shrink (M): the gear's rows the same small. The duplicates: Blizzard's tracking menu (or `/run for i=1,C_Minimap.GetNumTrackingTypes() do local n=C_Minimap.GetTrackingInfo(i) print(n.name,n.active) end`): Flight Master, Track Quest POIs and Points of Interest off while ours shows; `/mm toggle`: on; `/mm toggle`: off. Does each setting work, and is it clear how? → `/mm mark a5g <ok, or what doesn't work or isn't clear>`. Grow (M) again.
- [ ] **a5b** Big, Dun Morogh, Ironforge, Loch Modan and part of Wetlands in view (80-100), cursor resting inside Loch Modan: its border lit over the borders, its name bright, Loch Modan in the title → `/mm shot big-zones`
- [ ] **a7s** Same view, Gear → Map → Shade unexplored on, cursor off → `/mm shot big-shade`. What you haven't discovered darkens spot by spot (an unexplored subzone beside an explored one stays dark up to where the client's explored art ends; the wilderness between subzones too); right-click a dark spot: `Unexplored, near <subzone>`; a lit one names its subzone. **d0 (1)**: hover a dark spot of Dun Morogh, note its coordinates x, y and type `/run local m=C_Map.GetBestMapForUnit("player") local t=C_MapExplorationInfo.GetExploredAreaIDsAtPosition(m,CreateVector2D(x/100,y/100)) print(t,t and #t)` with them in. Shade off → `/mm mark a7s <ok, or what differs>; d0 explored <nil, or table N>`
- [ ] **c2d** Hover zones: the name brightens and its border is drawn over the borders (under the route line) once the map rests; a quest's area under the cursor isn't clickable, a pin is. Click Loch Modan: it flies there (fit 0.92), following off; against pick-and-fly.gif. Right-click → Follow me → `/mm mark c2d zone hover <ok, or what>`
- [ ] **d1p** Wheel out to 40-60, Dun Morogh and Ironforge in view: Gear → Places → Graveyards on, cursor on Ironforge's flight point → `/mm shot big-places`. Flight points (their art; a dot of their faction's colour where the client lacks it), dungeon entrances, points of interest, graveyards: hover each: its name, then what it is; a flight point on a zone's map and the continent's is one pin. Graveyards off → `/mm mark d1p places <ok, or what>`
- [ ] **a5b, b18** Wheel in to 140-200 and pan about (up to ~2750 border Lines): borders keep up. Then, standing still, `/mm bench regions` once (it hitches; a box flickers with lines), wait for its result (its `poi.*` lines price your quests' areas) → `/mm mark a5b <borders ok, or what>`
- [ ] **a7** Out to 16, the whole Eastern Kingdoms, cursor off → `/mm shot big-continent`. Pan about, against big-map-zoom.gif; `/mm tint` twice (plain, then tinted) → `/mm mark a7 continent <ok, or what differs>`
- [ ] **a7b** Still big: `/mm reset` answers `reset: shrink the map back first (M)`. Shrink. Move the window by its title, by its border, and Alt-drag on the map; resize it by the grip (the yards across kept); push it against the screen's edge (it stays on). `/mm reset`: back on the Minimap's spot, following → `/mm mark a7b window <ok, or what>`
- [ ] Under 10 minutes since the login? Ride Kharanos and the roads out, wheel, drag, M and back till it's 10. Then, at the Kharanos inn: `/mm reset` (home zoom), `/mm toggle` (hidden), `/reload`.

### Segment B: the Kharanos quests (script b, ~13 min)

Before b13: mouse over, target or see the nameplate of a mob a kill quest needs, if none yet.

- [ ] **b12** Wait 10 s. `/mm toggle`: the quest-heavy first open (small, home zoom: the read takes its slowest frame). No mark.
- [ ] **b15** Big (M), wheel and pan until the quest areas fill the window (100-130), cursor off → `/mm shot big-quests`. Each area in the client's art, a quiet edge (kill rust, collect green, other blue); a kill or collect quest the game gives no area gets a faint dashed disc (one for two close), none where an area covers its pin.
- [ ] **b13, b10** Hover quest pins: a kill, a collect, one ready to turn in, an offer (`!`). Each tooltip as the spike's: the title in its difficulty colour, the facts line (level, tag, ready), objectives, up to 3 droppers (lowest first, `(+N more)`), apart and dim `Turn in to` and the click hint; the mob you met shows its portrait over a dark disc, a mob never met the plain icon. Hover an area where no pin is: it lights (drawn again on top), its quest's tooltip; onto a pin inside another quest's area: the pin's. Cursor on a collect quest's pin → `/mm shot big-quest-tip`; `/mm mark b13 <tooltips ok, portraits ok, or what>`
- [ ] **b15** Click that pin: followed (26 px, its glow, its area filled blue, the line to it, the target in the title), cursor off → `/mm shot big-quest-follow`. M, cursor off → `/mm shot small-quests`. Grow (M), click the pin again (none followed) → `/mm mark b15 areas <ok, or what>`
- [ ] **b8, b14** Super-track a quest from Blizzard's objective tracker: our map shows it followed within a frame. Click one of our quest pins: Blizzard's tracker super-tracks and watches it; again: none. Click a quest's area where no pin is: super-tracks that quest; again: none; a pin inside another's area follows the pin's → `/mm mark b8 <follow ok, area click ok, or what>`
- [ ] **b16** An area in view, big: wheel 60 → 140 → 384 and back: out of sight while the zoom moves, back on their pins where it lands (not offset, not squashed); the cursor resting on an area through a tick keeps its tooltip. Drag ~200 px slowly, then fling: the areas move with the map, on their pins every frame → `/mm mark b16 <zoom ok, drag ok, or what>`
- [ ] **b9** Big, out to the continent (its first time this session): quests to pick up in other zones appear ~0.4 s later. Track Hidden Quests on (the Minimap's tracking menu): the hidden ones appear; off: gone → `/mm mark b9 offers <ok, or what>`
- [ ] **b7** Big, back at the hub, blips about: hover a blip, then a seen rare (if one's near): the tooltip to the right of the pin, its name then small grey lines (a rare's `Rare`, `Seen here <Mon DD>`), gone as the cursor leaves. Press on a pin and drag: the map pans, no tooltip left. Hover a pin under the window's buttons (zoom +/-, the gear): the button's tip only. Zoom over where pins were: no tooltip from a pin that's gone → `/mm mark b7 tips <ok, or what>`
- [ ] **b6** Small. Walk into a quest's area: `/mm check inside` (inside); out: again (not) → `/mm mark b6 inside <agrees, or what>`
- [ ] **b17** Accept a quest from an offer on the map: its `!` goes and its pin comes, never both in a frame; abandon one: its pin goes, its `!` comes back; hand one in whose next quest is offered near: its pin goes, the next one's `!` comes; each within ~0.3 s. Finish an objective: its pin and area move to the next objective or the turn-in. An offer that waits for a later event (a reputation, a profession): say so → `/mm mark b17 offer taken <ok, or what>`
- [ ] **b11** The map open: `/mm mark b11 before`, loot quest items quickly for ~10 s, `/mm mark b11 storm`: no hitch. `/mm toggle` (hidden): `/mm mark b11 before hidden`, ~10 s of the same, `/mm mark b11 storm hidden`; `/mm toggle`.
- [ ] Play on questing at the hub, the map shown, till 10 minutes since the login. Then **b19**: `/mm perf load poi`, `/mm perf load quest` → `/mm mark b19 poi <its calls>, <game.quests' calls> in <minutes>`
- [ ] At the inn: **log out** (not `/reload`). At the character select, alt-tab, the checkpoint (the game keeps 64 marks):

      cp "/Applications/World of Warcraft/_classic_beta_/WTF/Account/"*/SavedVariables/MagicMap.lua ~/mm-sv-after-b.lua

  Back to the client, log in.

### Segment C: route, waypoint, picker, combat, corpse (script c, ~13 min)

- [ ] **c2b** Wait 10 s. Big (M), on you at 300-400: right-click the ground ~300 yd from you: the menu leads with the inspector: the zone in gold; its subzones and coordinates; `Level 1-10` in green, red or grey against yours (the client's map levels); how far (5 yd steps close, 10 further, `You're here` close by) and which way; up to 2 quests whose areas hold the spot (the followed one gold, `(following)`). The subzones are Atlas's, not the client's explored ones (F38's known difference) → `/mm shot big-inspector`; `/mm mark c2b inspector <ok, or what differs>`
- [ ] **c2, c1b** Choose Waypoint here, cursor off: the cyan waypoint pin, Blizzard's tracker super-tracks it, the line to it, the title ending `<title> N yd` → `/mm shot big-waypoint`. Stand still 10 s: the line doesn't flicker; wheel in and out over it: laid out again at each zoom. Hover the pin: `Waypoint`, `Ctrl-right-click the map to clear`.
- [ ] **c1** M, the waypoint off the window: the gold edge arrow 16 px inside the edge, the line to it, cursor off → `/mm shot small-edge-arrow`. Cursor on the map: the title `<title> N yd` small too. Ctrl-right-click: cleared.
- [ ] **c2** Big: Ctrl-click the map: a waypoint, super-tracked, the line to it; Ctrl-right-click: cleared. Wheel out, Ctrl-click far out at sea: no waypoint, the press pans. Shift-click: the chat box opens on `/way <zone> x y`, not sent; Escape. Right-click: Waypoint here, Clear waypoint (one set), Follow me (not following) → `/mm mark c2 waypoint <ok, or what>`
- [ ] **c2c** Big, out to 16: click the zone name: the picker (Continents, Other maps, Instances by their entrance's continent), cursor on its first entry → `/mm shot big-picker`. Pick Gnomeregan (as the reference): shown whole, no arrow, line, blips or borders, cursor off → `/mm shot big-instance`. Picker → Kalimdor: whole, following off, the title naming it and the hint `right-click: Follow me`, Blizzard's minimap cluster still hidden, cursor off → `/mm shot big-browse`. Right-click → Follow me. `/mm map` lists the maps; `/mm map Deadmines`: whole, no arrow, line, blips or borders; `/mm zone Westfall`: it flies there (0.55 s); drag the zone name: the window moves, no picker. Right-click → Follow me → `/mm mark c2c picker <ok, or what>`
- [ ] **c1** Small, following: follow a quest whose area is off the view (wheel out, click its pin, back in): a hand-inked dashed line from you to the area's nearest edge (not its pin), a light stroke over a dark edge, uneven, faded at both ends, along the way you'd walk (round cliffs and deep water); the edge arrow where it leaves the view. Walk toward it: the line keeps to the route (no hop sideways, no straight flash). In the area 0.5 s: line and arrow step aside, the title (hovered) `<title> here`. Outside again, turn on the spot: the first dashes curve out of the way you face, the arrow pointing as you face. Against MagicMap-path-mode.gif → `/mm mark c1 route <ok, or what>`
- [ ] **c5, d1r** Out of combat, small, a quest's area in reach: Blizzard's quest-area rim ring and the Minimap's rim arrows don't float on our map. M (grow), Escape (shrink), L (Blizzard's quest log; close it). `/mm toggle`: Blizzard's minimap back exactly as it was, its ring and arrows as before; cursor on our rim button (lower left) for its tip → `/mm shot blizzard-rim`; `/mm toggle`. `/mm errors`: none naming `game.chrome` → `/mm mark c5 <keys ok, rim ok, or what>`
- [ ] **c7** Out of combat: follow a quest that has a usable item by its pin, then by its area; use the item from Blizzard's tracker → `/mm mark c7 follow <ok, or what blocked>` (no such quest: say so)
- [ ] **The combat block.** Pull a mob of your level near Kharanos and let it fight you (another if combat drops; dying here is c3's). In combat:
  - **c4** M: Blizzard's map opens, ours doesn't grow; with it open `/mm check combat` (it prints whether the client blocked hiding it; decision 3); close it. `/mm toggle` twice: the cluster fades, its hide or show waits for combat's end → `/mm mark c4 combat keys` after the check's line
  - **c6, c2, c7, d5** Spellbook (P) and talents (N) by keybind, closed. `/target <the mob>` in chat and an action-bar ability (the /way box's state was written from our code). Click our quest pin to follow and again to stop, then a quest's area to follow; use the tracker's quest item if one's there. Big: Ctrl-click the map (a waypoint), Ctrl-right-click; the item again. The gear: a tracking type, a layer and the minimap button off and on. `/mm toggle` twice. `/mm indoor` on, walk into the Thunderbrew Distillery and out, `/mm indoor` off → `/mm mark c6 combat <ok, or what blocked>`
- [ ] **c3** Die (pull mobs well above your level, or a long fall), small; drag the map away and release: a few seconds later the tombstone pin, the view glides back to you, the line runs to the corpse; as a ghost, small, cursor off → `/mm shot small-corpse`. Corpse run; resurrect: pin and line gone → `/mm mark c3 corpse <ok, or what>`
- [ ] Play on with a quest followed, big and small, riding along the line and fighting on it, till 10 minutes since the login. `/reload`.

### Segment D: Ironforge (script d, ~10 min)

- [ ] Wait 10 s. Ride into Ironforge (the ride is this session's play).
- [ ] **a6** The Commons, small, cursor off: the city as our tiles, dimmed, and over them Ironforge's own indoor minimap pictures (the floors, as Blizzard's minimap draws them), lined up with the streets and walls under them, our pins over them → `/mm shot small-indoor`. M, cursor off: the same, big → `/mm shot big-indoor`. M.
- [ ] **d3** `/mm indoor` on: chat `indoor: building …, room …` at each change of room. In the Commons (the ring street, subzone Ironforge): the whole ring and the halls off it drawn whole, nothing cut up; only what lies under or over the street faded. Walk into The Great Forge: `room 65 (The Great Forge)`; the Forge's hall drawn over every other room, the bridge high over it ghosted. Up to The High Seat (the throne room): `room 88 (The High Seat)`; its floor drawn on top, the Forge whole beside it, the upper bridge ghosted. Back through the Forge and out the Gates of Ironforge: `indoor: no building` a couple of seconds after the gate; the tiles undimmed, the city still drawn over them, faded (it's all under the mountain: City maps). Gear → Map → City maps off: the pictures gone outside; on again. Wheel and drag inside: the pictures stay on their spots. Leave it on (off at e2). (On a Horde character, any time: in Orgrimmar outdoors, the city's buildings over undimmed tiles, the Cleft of Shadow among them; walk the Valley of Strength and into a building: which pictures show, does the Cleft read as below the streets, and do they fit the streets? In Undercity's Ruins of Lordaeron: the Undercity under them, faded. Say so in the mark.)
- [ ] **d1** Big: zoom out to about 36 and back in, dragging and wheeling at each zoom, then over the same views again. Shrink, follow on, walk in and out of a few doors: no blank edges, no hitch on the drags. `/mm check report`: it names this build, and no city's or building's own subzone (The Commons, a hall) is in it → `/mm mark d1 city <ok, or what>`
- [ ] **d1t, a3c** The Commons, small, at 60 or more: the town services and the mailbox at their tracking icons (14 px), from zoom 60 (none at 59); hover one: `<name>`, its title, `Not in sight`. Hover a sensed NPC: its name and title (`Innkeeper`); a `!` blip by a quest giver no pin of ours covers, a `?` at one who only takes quests in. Gear → Tracking → Mailbox off: the remembered mailboxes go; on: back → `/mm mark d1t services <ok, or what>`
- [ ] **d8** `/mm perf` (10 s, then its report), `/mm perf top`, `/mm perf mem`, `/mm debug` (the title's debug line; again: off), `/mm blips`, `/mm tiles`, `/mm landmarks`, `/mm layers` (the spike's keys zoneLabels and zoneBorders, on green, off grey) → `/mm shot chat-layers`. `/mm check art` (PartyRaidBlipsV2 among `all N there`), `/mm nosuch` (the spike's usage line). Each prints, no error → `/mm mark d8 diagnostics <ok, or what errored; what perf top printed>`
- [ ] **d0** Type each, say what it printed: (2) `/run for i=1,C_Minimap.GetNumTrackingTypes() do local f,n=C_Minimap.GetTrackingFilter(i),C_Minimap.GetTrackingInfo(i) print(i,n and n.name,f.filterID,f.spellID) end`: Find Herbs' (a spell's) filterID, nil or 0? (3) `/run local n=C_TaxiMap.GetTaxiNodesForMap(1415)[1] print(n.name,n.isUndiscovered)`: true, false or nil? (4) Near a rare's or a treasure's vignette, if one comes: `/run for _,g in ipairs(C_VignetteInfo.GetVignettes()) do local v=C_VignetteInfo.GetVignetteInfo(g) print(v.name,v.atlasName,v.objectGUID) end` → `/mm mark d0 <tracking filterID>, <taxi isUndiscovered>, <vignette objectGUID, nil, or none met>`
- [ ] **d4** (grouped) Walk apart: their dot in their class colour (12 px), moving smoothly, small and big; hover: name, level, class; they die and release: grey → `/mm shot small-group`; `/mm mark d4 party <ok, or what>`
- [ ] **d7** (when the moment comes, any segment) Target a rare, or pass a rare's vignette: its pin (15 px, from zoom 60) where you saw it; while its vignette shows, one pin; Gear → People → Live rares & treasures off: the seen rare's instead; hover: `Rare`, `Seen here <Mon DD>`; after the next login still there, and on another character → `/mm shot small-rare`, `/mm shot small-vignette`, `/mm mark d7 rares <ok, or what>`
- [ ] Play on in the city, big and small, in and out of its buildings, till 10 minutes since the login. Walk out through the Gates of Ironforge (outdoors, the map shown). **Log out**; at the character select tick Questie and QuestieDB (and GatherMate2 or HandyNotes if you have one); log in.

### Segment E: Questie (script e, ~10 min)

- [ ] **d6** Wait 10 s. Blizzard's tracking menu (or a5g's `/run` line): Flight Master, Track Quest POIs and Points of Interest off again while ours shows (the logout put them back, the login took them again); `/mm toggle`: on; `/mm toggle`: off → `/mm mark d6 after login <ok, or what>`
- [ ] Walk into the gate (the zone turns Ironforge) and out again, then ride to Kharanos, the map shown: Questie's minimap pins around you. **b20** There, big, wheel in to 800 over a quest's area and drag a little: each area on its pin, its shape as at zoom 100, not a sliver nor off to one side → `/mm mark b20 big zone <ok, or what>`
- [ ] **e1** Big at 140, out to the continent and back: Questie's pins on our map, see-through while the zoom moves, back where it rests (decision 7). M with Questie loaded can hitch on the key press (the spike's too: say if it's worse) → `/mm mark e1 pins <ok, or what>`
- [ ] **e1c** Big, 100-130, Gear → Other addons open → `/mm shot big-addon-pins`. Out to 16-24: past 48 px a tile only Questie's continent pins; none over 128 px. Back at 140: Questie's `?` at a turn-in our quests layer shows isn't drawn beside ours; Gear → Quests → Quests off: Questie's comes back within a second; on again → `/mm mark e1c filter <ok, or what>`
- [ ] **e4** Where a Questie pin overlaps one of ours (a blip, a rare): hover the overlap: Questie's tooltip, not ours, never both → `/mm mark e4 overlap <ok, or what>`
- [ ] **e2** Shrink, `/mm reset`, cursor off: Questie's minimap pins (and GatherMate's nodes) around you, each on its spot → `/mm shot small-addon-pins`. Wheel: they follow the zoom. Gear → Other addons → Questie off and on: its minimap pins show while its world layer is off, hide while it's on. Rotate Minimap on (Interface options): theirs hidden; off: back.
- [ ] **d3, e2** Into the Thunderbrew Distillery: chat `indoor: building …`; its rooms' pictures over the dimmed tiles in the small window, our arrow, their pins over it; the wheel zooms it as outdoors. M: the same, big; M. `/mm indoor` off → `/mm mark e2 minimap pins <ok, or what>`; `/mm mark d3 indoors <the Forge, the High Seat, out the gates, the Distillery (Orgrimmar if seen): ok, or what>`
- [ ] **e3** `/mm toggle` (ours off), open Blizzard's world map: their pins are back on it. Close it, `/mm toggle` → `/mm mark e3 pins returned <ok, or what>`
- [ ] **e6** In combat (pull a mob): Gear → Quests → Quests off and on, Gear → Other addons → Questie off and on, Rotate Minimap's checkbox on and off, M and back → `/mm mark e6 combat <ok, or what blocked>`
- [ ] **e5** Only with FarmHud or SexyMap installed (neither is today; test_farmhud has it in the sim): open FarmHud: ours lets go of the Minimap (no blips sensed, no stand-in) and takes it back when it closes; with SexyMap, `/mm toggle` hands the Minimap back in SexyMap's shape → `/mm mark e5 <farmhud, sexymap: ok, or what>`
- [ ] Play on in Dun Morogh, big and small, out to the continent and back, till 10 minutes since the login. At the inn, **log out**, and quit the client.

### Segment Z: the release zip, without the data (e7 and M6's exit, ~5 min)

- [ ] The client closed, in a terminal:

      cd "/Applications/World of Warcraft/_classic_beta_"
      cp WTF/Account/*/SavedVariables/MagicMap.lua ~/mm-sv-after-e.lua
      mv Interface/AddOns/MagicMap ~/.Trash/MagicMap-route
      unzip -q ~/code/magic-map/dist/MagicMap-v2.0.0-no-questie-data.zip -d Interface/AddOns

  The copy first: the zip's build starts a new validation log. Start the client (it reads the zip's TOC). AddOns: untick Questie and QuestieDB (and the HBD addon): MagicMap 2.0.0 alone. Log in.
- [ ] **e7** Wait 10 s. One chat line, "QuestieDB isn't loaded: quests show without their mobs and items.", once; the map works: quest pins drawn, a quest's tooltip without its mobs and turn-in. `/reload`: the line once more. `/mm errors`: none. `/mm` and `/magicmap` each swap ours and Blizzard's; the rim button and the addon compartment's entry (if the client shows one) each bring ours back → `/mm mark e7 <nodata ok, zip ok, or what>`
- [ ] Quit the client. `cd ~/code/magic-map && .venv/bin/python tools/install.py` (main's build back in place of the zip).

## 4. Send back

Say **check telemetry**. The lead reads the SavedVariables and the two copies (`~/mm-sv-after-b.lua`, `~/mm-sv-after-e.lua`) with `tools/telemetry.py` (each session's `--budgets --trace`, `--shots --marks`, `--sv` for the copies), the screenshots and `Logs/` (taint.log). If a segment broke off (a crash, a disconnect, a box skipped), say which.

## 5. The sign-off (after the read)

1. The lead sends the shot pairs (each `/mm shot` beside its `ref-<id>.jpg`, the docs/parity.md rows each judges, your marks' notes) and each FAIL with its owner.
2. You answer each pair: the same, or what differs (a value to fix: M5.3 fixes values only); and "Decisions for you" 1-11 below (4 settles S31, the one row still `todo`).
3. The lead sets each docs/parity.md row `signed` (or files its fix) and fills the Sign-off table; you sign its lines (M0-M5).

## 6. Round 2: the second session a script (gate 3, another sitting, ~55 min)

Gate 3 asks two 10+ minute sessions a script; the route was the first. 2.0.0 installed as §2, `/mm check log` still on, every default layer on. Five sessions, each from a login at its start (wait 10 s), its mark first, 10+ minutes without the steps, then `/reload` (a log out before e8, to tick Questie):

- [ ] **a8** Kharanos: ride Kharanos and the roads out, wheel, drag, M and back → `/mm mark a8 session 2`
- [ ] **b21** Questing at the hub, the map shown → `/mm mark b21 session 2`
- [ ] **c8** A quest followed, big and small, riding along the line and fighting on it → `/mm mark c8 session 2`
- [ ] **d9** Ironforge, big and small, in and out of its buildings → `/mm mark d9 session 2`
- [ ] **e8** Questie on: Dun Morogh, big and small, out to the continent and back → `/mm mark e8 session 2`

Then say **check telemetry** again. Each of the ten sessions (the route's A-E and these) must read 0 errors, 8/8, perf.slow, perf.gaps, the `sensor` and `art` traces empty, 0 taint, 0 K4 drift lines.

## Decisions for you at the sign-off

1. **Budgets by map state** (M1 review round 2, ebdf22e, an agent's change): p95 ≤1 ms at rest only, ≤5 ms moving. The plan's M1 exit and §1 gate 3 read p95 ≤1 and p99 ≤5 over the whole session, which script (a)'s shape fails on the priced clock (p95 1.8, p99 4.7 ms since the M1b review's second round; at rest 0.2, zooming 4.5: docs/runtime.md). Keep it, or ask for smaller slices while moving (borders fall behind a fling: R-P1).
2. **The wheel** (a2): the MVP's since M1.14 (every event a x1.3 tick), so one trackpad flick can run to the clamp, the thing M1.8b's rationing answered ("too sensitive"). Keep it, or change it from what the `wheel` cam traces show each device sends (delta, n, dt).
3. **M in combat** (c4): blocked, the guard stays, a deviation from the spike to sign (F10, K2); not blocked, the guard goes.
4. **The sea** (a7, S31): keep the rebuild's (Data/Sea, feather masks) or port the spike's gradient coast fades (Core.lua:441-700).
5. **Subzone borders** (a1b, S33): Gaussian-smoothed, rounder, about half the points, against the spike's Douglas-Peucker 0.035 + Chaikin.
6. **Names and pins while zooming** (a1b, a2, S38, F21, F43): as the spike's since the M1b review's second round: names laid out at the zoom shown on the frame it drifts log(1.25) from theirs and the frame it lands, rares and remembered blips shown from zoom 60 the frame it's crossed, pins kept on the map through a glide. The ground goes first, so on the fastest flicks names can be chosen for a zoom a few drifts off while it lays out (priced: 3.7 drifts flicking the big window to the clamp, one frame past a drift at most otherwise), and names and pins can miss the view's edges for a few frames (4 in a trackpad's burst, 1 flicking the big window to the clamp; none on a mouse wheel's fast scroll or growing mid-zoom).
7. **The world socket** (e1, F46): Questie's pins see-through while the zoom moves.
8. **Borders zooming out fast** (a2, S30): as the spike's, the old borders are scaled and dimmed to 0.25 until the wheel stops, then laid out where the zoom is headed and crossfaded in. The spike starts that layout the frame after the last tick at 8 ms slices beside everything else; ours lays out the ground, names and pins first (the layouts share a frame's budget in turn), so it lands about 0.1 s after the spike's (8 notches out from 400, one a frame, priced: its layout starts 6 frames after the last tick and lands that frame).
9. **Slow discovery** (a3b): a blip appearing while you stand still found within ~40 s, not 0.5 s.
10. **Pins off the pixel grid** (S42-S52, S59; shots big-quests, small-town, big-places): ours don't snap, as nothing on the map does (the fix for the "slight tear when moving" mark); the spike's pin textures snapped by default, so at rest its may look crisper. Keep, or snap pins alone.
11. **Rows to compare most closely** (M5.3's audit at b0e0560: every other S row is the spike's code): S8 and S41 (each pin kind at its own level, rares and places 11 up to quests 15; the arrow's overlay +18, not +8: big-quests, small-near), S35 (dead ends: ≤4 dashes an end along the whole line, the spike restarts them each segment: small-zone), S15 (no -c60 atlases in Forever: the spike's fallback redbutton-expand: small-hover, big-hover), S36-S38 (which names win a collision: small-zone, small-town, big-zones), S53 (quest blobs: big-quests, big-quest-follow), S56 and S58 (past 160 pieces a dash's ends on whole pixels, half the dashes a frame: big-waypoint, the path GIF).

## The read (the lead)

`telemetry.py --budgets --trace` and `--shots --marks` on each session: the route's A-E (A-B's marks in `~/mm-sv-after-b.lua`, the validation log and C-E's marks in `~/mm-sv-after-e.lua`: the game keeps 64 marks and the zip's build clears the log), Z (the zip), round 2's five. Every session passes when:

- **8/8 PASS**: frame max ≤8 ms; p95 ≤1 ms at rest, p99 at rest and p95 moving ≤5 ms (by map state, docs/runtime.md: decision 1); first open ≤50 ms (target ≤20); ourKB after GC ≤64 MB (~39 expected); allocation ≤50 KB/s; load ≤250 ms; 0 errors. Sessions #8 and #9 (cd0c82c, before M1.4 and round 2 of the M1 review) were 7/8: allocation 56.7 and 108.7 KB/s.
- **perf.slow** without `map: borders`, `map: labels`, `map: draw`, `map: layout` or `game.observe` (#9 had `game.part blips` at 2.4 ms); **perf.gaps** empty; the `sensor` and `art` traces empty (a `sensor` event carries its mark); 0 taint but `/mm check combat`'s own block, if the client blocked it; `/mm check log`: 0 K4 drift lines.
- **perf.alloc**: `game.part blips` under 10 KB/s (27-30 in #8 and #9, before e60ff51); `map: layout` about one trace a start (0.37 KB in the sim since M1.12, a layout ~1.1 KB with its end and swap; the old job start cost 8.6-10.3 KB in the client); `validate.log` near 0 (3.4 KB/s in #13-#22). A session that zooms a city's big window out reads its canvases filling as allocation (~7,000 regions, ~3.6 MB, kept in their pools, made once a session: over 50 KB/s in a short session, ~6 KB/s over 10 minutes; R-P3b at the M1b gate: 7333 regions, its first pass 158.4 KB/s with 8.9 of garbage, all 76 s 65.8): the budget can't tell pool growth from garbage, so judge it over the whole session (d1).
- **The bench** (a5b, b18): `canvas.SetAlpha.moved@1000live` far under `canvas.Show.moved@1000live`, and `frame.swap` about `frame.idle`; else the swap extends in place (M1.3's fallback). Also `canvas.Show.moved.alpha0@1000live` and `canvas.Show.moved@100masked`. A minimum zoom crossed: `reveal.frame@500` and `frame.reveal.frame` (the engine's: 500 pins shown by their frame's SetAlpha) against `reveal.each@500` and `frame.reveal.each` (a SetAlpha a pin); if the frame's costs like a Show of its moved children, reveal the pins a slice a frame instead (M1b review, round 2). The path's `line.Show.moved@160` (160 lines moved hidden, each its own Show: what a new line shows in a frame, half its dashes): about 0.55 ms or less (3.5 us a line: with the layout's own Lua, ~0.2 ms at 10 ns an instruction, and its other calls, within CALL_MS), else the path shows its dashes in more, smaller slices (M3 review, round 2). Its `poi.*` lines: `poi.DrawBlob` at most about 0.06 ms a quest (with 25 quests `map: quest areas` under CALL_MS and the zoom's p95 at or under 5 ms: test_quests_priced with a planted cost passes at 0.05 ms, fails at 0.1; over it, Front's second draw is spread over frames, a frame's quests a frame), and `poi.UpdateMouseOverTooltip` (Inside's hit test) at most about 15 us (the followed quest's area target asks up to 32 a frame while you move: ≤0.5 ms; over it, ASKS comes down to fit); into `Sim.PRICES`, then test_quests_priced again.
- **byState.zoom.client** against `small`: what scaling the borders while zooming costs the client (S30, P4). `swap <layer>` under 4 ms.
- **Script (b)** (M2): 8/8 PASS with a full log; the quest-heavy first open (b12) ≤50 ms (test_quests_first_open, priced: 6 ms, its slowest call `map: rares` 5.3); b11's storm marks' `alloc` (since the mark before: `telemetry.py --marks`) ≤50 KB/s, `game.part quests` under ~40 KB/s open, nothing hidden, no `game.part offers` (test_quests_storm, priced: 39.5 KB/s, `game.part quests` 36.2, 0 hidden), `game.part quests` never in perf.slow; b19's `game.oracle: poi update` calls against `game.quests`' (one a QUEST_POI_UPDATE: each a read of the zones and the areas drawn again; test_quests_ticks: a count every 2 s, 17.8 KB/s without, 19.3 with one each time). Allocation while zooming and dragging is M1's borders (test_quests_priced's wheel and drags, that stretch alone: 443 KB/s with 25 quests, 426 without, `map: borders` ~390, `map: quest areas` 6.8): judged with M1.15 and script (a)'s reads, not blamed on quests.
- **Script (c)** (M3): 8/8 PASS; `model: route` and `map: path` never in perf.slow (route jobs: a 1 ms job, 1.01 ms its slowest resume in R-P2, none while the view moves; a search that gives up (a plateau no way climbs: ~18 s of slices, the at-rest p95 ~1.25 ms meanwhile) only once a goal and again half its way on; the path's lines made at load, a new line half its dashes a frame: a first layout across the big window priced 0.80 ms in test_path_priced_big, 0.96 with our Lua charged); 0 taint in combat toggles and waypoints (c6, c7), nor after the /way box (c2); the line against MagicMap-path-mode.gif (c1), the inspector against the spike's ZoneInfo (c2b). The big window's `zoom` p95 with a line across it is M1's engine's (test_path_priced_big: 6.25 ms priced, the line's share ~0.8; M1.15), not the path's.
- **Scripts (d) and (e)** (M4): 8/8 PASS with every default layer on, in each; the D→E login a new session (d6); 0 taint (c6's d5 part, e6). perf.slow without `game.part explored` (an Eastern Kingdoms sweep on a fresh character asks the client 16,640 times, 700 a frame: 1.00 ms of our Lua in the sim, the client's own per call unknown; if it's in perf.slow, fewer a frame), `game.part vignettes`, `game.part places`, `game.tracking` or `game.addon pins`; the `indoor` traces one a change (d3: `{ map, indoors, art, shows }`). perf.alloc: `game.tracking` ~0.7 KB/s (the client's tables, re-synced every 2 s while engaged, as the spike's); the explored sweep's garbage with d0's answer (1): a table an ask if the client returns tables. ourKB: the town services' indexes (Atlas.SpawnsIn's ~2.6 MB a continent, Atlas.Npc's rows ~1.3 MB a city) in the 64 MB; the city's first big pass with them is R-P3b's 204.8 KB/s (7,646 regions, garbage 18.7: kept, made once a session). d0's answers go into the sim's mocks (tools/tests/wowsim.lua) and their parts' nil branches.
- **M5**: two sessions of each script, 10+ minutes each (the route's A-E, then a8, b21, c8, d9, e8): in every one 0 errors, 8/8 PASS, perf.slow, perf.gaps, the `sensor` and `art` traces empty, 0 taint, 0 K4 drift lines. The sim's soak (test_soak: (a)-(e) four rounds, every layer on, 649 s priced) reads 8/8 with zoom p95 4.30 ms; with our Lua charged 5.1 (map: tiles and labels slices), and the big window zooming with a line across it 5.25 priced (6.4 with our Lua: test_path_priced_big): a zoom FAIL in (a) or (c) is M1.15's (ui/Engine.lua), not the script's owner's. FarmHud's yield (e5) and Rotate Minimap (e2) checked; the no-data build (e7).
- **M6**: Z's session, the no-data zip alone: 0 errors, `/mm`, the rim button and the compartment (e7); `/mm check report` names the zip's build (`v2.0.0`).
- **Shots**: each answered `shot <id>: WoWScrnShot_<stamp>, marked`, paired with `ref-<id>.jpg`: A small-home, small-hover, small-drag, small-near, small-seam, small-town, small-zone, big-home, big-hover, big-gear, big-settings, big-tracking, big-zones, big-shade, big-places, big-continent; B big-quests, big-quest-tip, big-quest-follow, small-quests; C big-inspector, big-waypoint, small-edge-arrow, big-picker, big-instance, big-browse, blizzard-rim, small-corpse (its ref optional); D small-indoor, big-indoor, chat-layers, and small-group, small-rare, small-vignette if the moment came; E big-addon-pins, small-addon-pins. A seam on small-seam is M1.4's seam overlap (1 px right and bottom, half-texel inset), built only if a shot shows one.

## What each item signs

The docs/parity.md rows (F, S) and docs/evidence/spike-bugs.md rows each item proves in game, and the gate that put it here. Items sharing a box share its mark.

| Item | Signs | Gate |
|---|---|---|
| a0 | L5, S15, S17 | M1 |
| a1 | F1, F2, F19, S1-S3, S9, S11, S19, S22 | M1 |
| a1h | F2, F3, S6, S10, S13, S17-S19 | M1 |
| a1d | F6, F7, S18, S28, S29 | M1 |
| a1g | F7, F15, S29, P1 | M1b |
| a1r | P1, F12 | M1 |
| a1b | F12-F16, F20, S31-S33, S35-S38, S41 | M1 |
| a1c | F19 (M1.5b) | M1 |
| a2 | F5, S26, S30, P1 | M1, M1b |
| a3 | P1, F12, F15 | M1 |
| a3b | D3, F19 | M1 |
| a3c | K1, D2, F20, F21, S51 | M4 |
| a4 | F12, plan §2 "tear" | M1 |
| a5 | F3, F10, F11, F50, S1, S2, S9-S11, S15, S16, S20, S24, S25 | M1 |
| a5g | F11, F48, F49, F55, S60, S61 | M1b |
| a5b | P4, F15, S30, S32, S34, S36 | M1, M3 |
| a6 | F24, S40, G1 | M4 |
| a7 | F5, F13, F16, S4, S26, S31 | M1 |
| a7s | F45, S39, S62 | M4 |
| a7b | F8, F9, S5, S7, S14, S23 | M1 |
| a8 | §1's budgets, P1, P3, K4 | M5 |
| b6 | F29 (Inside), L1 | M1 |
| b7 | F51, S42, S45, S50, G7, D1 | M2 |
| b8 | F31 | M2 |
| b9 | F40 | M2 |
| b10 | F28, S63 | M2 |
| b11 | F26 | M2 |
| b12 | F26, F40, S46 | M2 |
| b13 | F28, F51, S53 (hover), S63 | M2 |
| b14 | F31 | M2 |
| b15 | F29, F30, S46, S53, S54 | M2 |
| b16 | P5, L1, F29, S53 | M2 |
| b17 | F26, F40, D1 | M2 |
| b18 | S53, F29, F32 | M2, M3 |
| b19 | F29, S53 | M2 |
| b20 | F29, S53, L1 | M2 |
| b21 | §1's budgets, P3, P5 | M5 |
| c1 | F32, F33, F34, S55-S59, M1, P2 | M3 |
| c1b | S12, S58 | M3 |
| c2 | F35, F36, F37, S49, S55-S57 | M3 |
| c2b | F37, F38, S62 | M3 |
| c2c | F3, F4, F11, F14, F18, S12, S60, G2 | M3 |
| c2d | F17, S34, S36 | M3 |
| c3 | F42, F7, S49, G4 | M3 |
| c4 | F10, K2 | M1 |
| c5 | F1, F10, F52, F53, S21 | M1 |
| c6 | K2 | M1 |
| c7 | F31, K2 | M2 |
| c8 | §1's budgets, P2, K2 | M5 |
| d0 | F39, F43, F44, F45 | M4 |
| d1 | P1, P3, K4 | M1b |
| d1r | D1, F53 | M4 |
| d1t | F20, F21, S51 | M4 |
| d1p | F39, S48 | M4 |
| d2 | F23, F48, F49, F54, S12, S60, S61 | M4 |
| d2t | F22 | M4 |
| d3 | F14, F24, F44, S40, G1 | M4 |
| d4 | F41, S52 | M4 |
| d5 | F22, F24, K2 | M4 |
| d6 | F22 | M4 |
| d7 | F43, F44, F55, S50, D4, S1 | M4 |
| d8 | F54, F48, S12, S64, L5 | M4 |
| d9 | §1's budgets, P3, G1 | M5 |
| e1 | F46, G6 | M1 |
| e1c | F46, D1, D4 | M4 |
| e2 | F25, F47, G6 | M4, M5 |
| e3 | F46, G6 | M1 |
| e4 | F51, G7 | M2 |
| e5 | K3, G3 | M4, M5 |
| e6 | K2 | M4 |
| e7 | F56, F28, S63; M6's exit (the packaged zip alone) | M5, M6 |
| e8 | §1's budgets, G6, K3 | M5 |
