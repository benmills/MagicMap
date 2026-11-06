# Play-test: the pins / tracking / tooltips / settings run (2026-11-06)

This covers the run's seven commits on main since v2.1.2, issues #15 to #21. None of it has been tried in the real client yet; every change passes the full check in the sim. Install it with `tools/install.py`, then **restart the client** rather than `/reload`, because there are new files. The issues stay open until these checks pass.

## Bugs (#21)
- [ ] **Gathered nodes:** gather a herb or vein, then stand still. Its pin goes within about a second. Do another and ride off at once: also about a second. Ride past herbs you don't gather: none vanish or flicker.
- [ ] **No ghost dots:** die, release, then rez, or get rezzed near a party member. No gold dots appear on you, your corpse, party members or pets. `/mm blips` while dead lists none of your group's names.
- [ ] **No false herbs:** in Razor Hill with Find Herbs on, Swart is not a herb. Run `/mm blips` beside him and note the name it shows. Real herbs and veins keep their icons.
- [ ] **Vendor icon:** no "art missing" message at login. `/mm check art` reports everything present. General goods vendors, such as K'waii, show the vendor sack.
- [ ] **One Banker:** gear > Nearby shows one Banker row, and it switches banker tracking.
- [ ] **Tracking types:** run this and check whether it lists Banker twice:
  `/run for i=1,C_Minimap.GetNumTrackingTypes() do local f,n=C_Minimap.GetTrackingFilter(i),C_Minimap.GetTrackingInfo(i) print(i,n and n.name,f.filterID,f.spellID) end`

## Settings (#15) and the Pins page (#16)
- [ ] **Every page:** visit every page. The checkbox, slider, dropdown and undo art look right, and the sidebar fits.
- [ ] **Controls:**
  - Sliders update their value as you drag and with the steppers.
  - Dropdowns pick.
  - A colour swatch applies, and Custom… opens the colour picker (OK applies, Cancel reverts).
  - Dependent rows show and hide.
  - The undo mark, page Reset and Reset all each work.
  - Changed values are kept across a `/reload`.
- [ ] **New General rows:** Return to you, Return after, Zoom per notch and Buttons at rest.
- [ ] **Pins page:**
  - Each type's icon matches the map.
  - The plus buttons open and close.
  - Pin size, a family's size and a type's size each apply on the minimap, the big map and in a pill.
  - A type's Icon choice, hiding a type or all pins, Group off for a rare, and Reset each work.
- [ ] **Your arrow:** it is now the client's own art. Check it at every zoom, turning, and with Map > Your arrow.
- [ ] **Saved sizes:** if you had changed the Quest icon size, quest pins keep that size.

## Quest tooltips (#20)
- [ ] Hover a quest that needs an item dropped by mobs, such as Kobold Candles. No sword or skull lines appear. An item found in a crate shows "From …".

## Resource nodes (#18)
- [ ] **On at login:** a herbalist logs in and Find Herbs comes on by itself, with no "blocked" message.
- [ ] **Keep tracking:**
  - After dying, it comes back once you're alive, not while you're a ghost.
  - After a loading screen or `/reload`, it comes back.
  - In combat it waits, without spamming.
- [ ] **Your own picks:**
  - Picking Find Minerals in Blizzard's menu makes gear > "Keep tracking: Find Minerals" the new choice, and it survives a death.
  - Off means nothing comes back.
- [ ] **Badges:** herb and vein icons are tinted by difficulty (red, orange, yellow, green, grey) to match your skill, and still read as a leaf and a nugget; the letter sits top left (P, M, C, T) with no outline and stays legible on the map. Forever's own herbs keep their gold. Colour by difficulty, Letter and Letter size under Settings > Resources apply; a group's pill shows the tints too.
- [ ] **One tracker or several:** turn on Find Herbs and Find Minerals together in Blizzard's menu. If both stay on, this client allows several, and the setting could become a toggle per type.

## Track and Path to (#17)
- [ ] **Track:** a mailbox's Track shows no line, just the gold arrow about 48 px out, pointing along the walk.
  - Turning in place doesn't move it.
  - Walking up, it settles by the pin, then fades.
  - Behind a cliff or river, it follows the route's first leg, not the straight bearing.
- [ ] **Path to:** shows the line, and the minimap zooms and pans so you and the target are both in view.
  - If you drag or zoom it yourself, then move the cursor off the map, it glides back after about 6 s.
  - Walking in, the zoom steps back in, never past where you started.
  - On the big map, the line shows with no framing.
  - `/reload` keeps it pathed.
- [ ] **Quests:** Track quest, Path to quest and Stop pathing each work.
- [ ] **Your corpse:** gets the line, and the view comes back to you.
- [ ] **Settings:** Settings > Tracking holds the arrow's Size, Opacity, Distance and Frame the way. Pathing holds the line. There is no Focus ring.

## Title and minimap buttons (#19)
- [ ] **Title as before:** at rest it shows Zone · Subzone. Hovering adds coordinates and the target. The big map's Follow me hint and the `/mm debug` line are kept.
- [ ] **New pieces:** in Settings > Frame title, add Day or night and Local time. The sun or moon picture shows, and the Clock row's 12/24 setting applies.
- [ ] **Minimap buttons:**
  - Gear > Minimap buttons lists the LibDBIcon addons (Questie, DBM, Details…) with their icons.
  - Left- and right-clicks work, and their tooltips show.
  - The addon compartment's entries are listed, without MagicMap.
  - Calendar and Clock open Blizzard's.
  - An addon's plain rim button appears under its addon's name.
