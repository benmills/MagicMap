# Play-testing MagicMap: a 20-minute guide

Thanks for trying MagicMap! It replaces your minimap with one you can zoom out to a whole continent,
and press M to grow into a big map. This guide takes about 20 minutes. There are no wrong answers:
anything that looks odd, feels slow or confuses you is exactly what we want to hear about.

## Before you start (2 minutes)

1. Install it as the release page says: unzip so you have
   `World of Warcraft/_classic_beta_/Interface/AddOns/MagicMap/MagicMap.toc`, then **restart the game**.
2. At the character select, AddOns: tick **MagicMap**. Other addons can stay as you like them, but
   if something breaks, try once with MagicMap alone.
3. Log in and wait a few seconds. The square map on your minimap's spot is MagicMap.

**The one command to remember:** the moment something looks wrong, type

    /mm mark <what you saw>

for example `/mm mark the herb icon is in the wrong place`. It saves what the map was doing at that
moment. A screenshot (Print Screen) as well helps a lot.

## The basics (5 minutes, anywhere)

- **Zoom** with the mouse wheel over the map, or the + and − buttons that show when you hover it.
  Zoom all the way out and back in. Is it smooth?
- After zooming, a small **reset button** appears above +. Click it: the zoom goes back to normal.
- **Drag** the map to look around. Let go and wait 6 seconds: it glides back to you.
- Press **M**: the map grows into a big map. Press M (or Escape) to shrink it. Try it a few times.
- On the big map, **click the zone name** at the top to pick another zone or continent. Hover a
  zone to light it up, click it to fly there. Right-click the map and choose Follow me to come back.
- **Right-click** the big map anywhere: it tells you what's there (zone, level, distance, quests).
- Open the **gear** button (top right, while hovering): turn a few things off and on. Is each
  option clear? Settings → Reset window position if you lose the map.
- Type `/mm` to swap back to Blizzard's normal minimap, and `/mm` again to bring MagicMap back.

## A quest hub (5 minutes)

Go where you're questing, with a few quests in your log.

- Your quests show as icons, with their areas drawn as the game draws them. Hover them: do the
  tooltips make sense?
- **Click a quest** to follow it: a dotted line shows the way there, around cliffs and water.
  The line at the bottom left of the map shows its progress. Walk along it for a bit.
- Where icons crowd together they group into a small **pill**. Click it: all of its icons open in
  a little grid. Is that handy, or in the way?
- Herbs, ore and mailboxes (if you track them) should show near you.

## A cave or mine (3 minutes)

Walk into a cave or mine near you (in Dun Morogh, Elwynn or Durotar there are several by the early
quests). Many show Blizzard's own indoor map, laid over the darkened ground; some only show the plain
ground. Either way: does what you see match where you're walking? Mark the cave's name if it looks wrong.

## A capital city (5 minutes)

Visit **Ironforge** (Alliance) or **Orgrimmar** (Horde).

- Walk through a few buildings and halls on the small map. The floor you're on should show clearly,
  the floors above and below fainter. Does it line up with the walls and streets?
- Press **M** for the big map: the whole city's buildings show at once, with the city's area names
  (The Great Forge, The Military Ward... or the Valley of Strength, the Cleft of Shadow...).
- In Ironforge, go up to The High Seat and down into The Great Forge; in Orgrimmar, go down into the
  Cleft of Shadow. Does it ever get confusing which level you're on?
- Walk out of the city gates: does the map change back to the outdoors cleanly?

## When you're done (1 minute)

1. Type `/reload` (or log out) so the game saves MagicMap's notes to disk.
2. Send us this file:

       World of Warcraft/_classic_beta_/WTF/Account/<your account name>/SavedVariables/MagicMap.lua

   and any screenshots from `World of Warcraft/_classic_beta_/Screenshots/`.
3. A few words on how it felt: what you liked, what got in the way, anything you'd turn off.

The addon doesn't send anything anywhere: the file only holds what MagicMap noted on your computer.
