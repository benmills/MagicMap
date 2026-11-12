# The 3.0.0 play-test

One sitting before tagging 3.0.0 (about 40 minutes), on the installed build (`.venv/bin/python tools/install.py`, then restart the client: 3.0.0 adds a file). It checks what changed since 2.2.1. The 2.0 route this file used to hold is in git history (`git log -- docs/playtest-final.md`).

- **Marks**: `/mm mark <id> ok`, or `/mm mark <id> <what you saw>`. One mark per box. Mark anything wrong the moment you see it.
- **Shots**: `/mm shot <id>` standing still, cursor off the window.
- Questie (with QuestieDB) on; other addons as you play.

## 0. Before

- [ ] A character with quests in progress in an open zone, near a town with a vendor, a trainer and a mailbox. A gathering profession if it has one.
- [ ] `/mm errors`: none. The TOC says 3.0.0 at the character select.

## A. Blizzard's blips (~10 min)

- [ ] **a1** Small map, following you: herbs or ore, the mailbox, trainers and quest givers' `!` and `?` drawn where Blizzard's minimap has them. Wheel in and out: each notch steps to Blizzard's next zoom, the blips staying on their spots. Past the widest or closest zoom, the blips hide and the zoom glides; back in, they return.
- [ ] **a2** Hover a herb or ore: the item icon, its name in your skill colour, the skill it needs in a pill, the profession under it. Hover a vendor: the title ("General Goods") under the name. Hover a quest giver: its quests for you, each in its difficulty colour, with `!` or `?`.
- [ ] **a3** M (the big map): no blips, our arrow. M again: the blips are back.
- [ ] **a4** Path to an icon: while the line shows, the blips hide and the zoom is smooth. Arrive or stop: the blips come back.
- [ ] **a5** Die and release: tracking (Find Herbs or Minerals) back on after you resurrect. Gear → Keep tracking shows it.
- [ ] **a6** If you can, enter a dungeon: Blizzard's own minimap, ground and all. Leave: ours again.

## B. Quests and the quest pill (~10 min)

- [ ] **b1** Small map: quest pins with no names or counts. Big map: none either. Settings → Pins → Quest → Names on big map on: each pin's quest name under it, in its difficulty colour, its progress under that, smaller and muted; the small map still shows neither until Names on small map is on.
- [ ] **b2** The pill is off by default. Settings → Quest pill → Shows: what you track. Click a quest, then Track: the pill bottom left shows the quest's icon and progress (`3/8`), then the distance, smaller and muted. The bar fills as you get closer. → `/mm shot pill`
- [ ] **b3** Hover the pill: the quest's tooltip. Click it: its popup. The `×` stops following; the pill hides.
- [ ] **b4** Track any other icon, then Path to one: the pill shows it, and its `×` stops tracking or pathing. As a ghost: your corpse, with no `×`.
- [ ] **b5** Settings → Quest pill: Shows Off hides the pill at once; back on. Change Says: the pill follows your order.

## C. Menus and settings (~10 min)

- [ ] **c1** Gear: Map, Tracking, Keep tracking, Other addons, then Use Blizzard's minimap, Reset to defaults, Settings. Map lists every layer, with dividers and an "All" box. Tracking matches Blizzard's own tracking menu.
- [ ] **c2** Point at the map (with MagicMap replacing the minimap; not replacing, there's none and Blizzard's minimap is untouched): the AddOns button appears left of the gear. Click it: your addon buttons, then the calendar and clock. Each row works, and its tooltip shows. → `/mm shot addons`
- [ ] **c3** In a capital, big map: the city's buildings and area names drawn, with no option to turn them off.
- [ ] **c4** Settings: no Resources or Grouping page. Diagnostics has no Indoor row. `/mm indoor` still reports rooms (again: off).
- [ ] **c5a** Pan or zoom the small map and move the cursor off: 3 s later it glides back to you at the default zoom. Again, then click the pin above the reset arrow (yellow): it holds; click again and it returns. Pinned, Track something: unpinned.
- [ ] **c5b** Gear → Default zoom (small map only): Auto and each of Blizzard's zooms in yards across; a pick goes there and is where the reset and the return go.
- [ ] **c5** Settings → General → Zoom per notch: hover for its tip. It changes zoom steps only past Blizzard's zooms or on the big map.

## D. Other addons (~5 min)

- [ ] **d1** Small map: hover a Questie pin over Blizzard's blips: Questie's tooltip.
- [ ] **d2** Big map, zoomed in on a zone: Questie's pins, which you can hover and click. Zoom out past about two zones across: they go. Zoom back in: they return.

## E. Send back

- [ ] `/mm errors`: none. `/reload`, then say **check telemetry**.
