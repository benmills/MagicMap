# MagicMap 3.0: CurseForge / Wago listing

Replaces dist/listing-v2.1.0.md's description (its field table still holds, version and zip name aside). The
changelog for either site is the version's dist/RELEASE_NOTES-v3.0.x.md.

| Field | Value |
| --- | --- |
| Summary (≤ 140 characters) | A minimap that zooms out to the whole continent, any size or shape, with Blizzard's own blips. Click any icon to track it or path to it. |
| Version / file name | 3.0.x / `MagicMap-v3.0.x.zip` |
| Dependencies | None required. Optional: Questie, HandyNotes, GatherMate2 (HereBeDragons pins); FarmHud is yielded to |

## Description

**A minimap you can zoom out.** MagicMap replaces your minimap and draws the game's own terrain at any zoom, from
Blizzard's closest zoom out to a whole continent. Press M and it grows into a big map in the same frame.

For **WoW Forever** only. [Try it in your browser](https://magic-map-outdoor.exe.xyz) ·
[Every feature](https://github.com/benmills/MagicMap/blob/main/docs/features.md) · Free and open source (GPLv3)

- **Blizzard's own blips, on our map.** Herbs, ore, mailboxes, trainers and quest givers' `!` and `?` are drawn by
  Blizzard's minimap over ours, with richer tooltips: a herb's or ore's skill in your skill-up colour, an NPC's
  title and the quests they have for you.
- **See past the minimap's edge.** Wheel out to the next hub, the road, the coast. Left alone, it comes back to you
  at your default zoom; pin it to keep a view.
- **Any size, any shape.** Drag its corner: a tall tower, a strip across the top of the screen, or tiny. Drag
  its border (or Alt-drag the map) to put it anywhere.
- **Floor plans indoors.** Undercity, Ironforge and caves show the floor you're on.
- **Quests in view.** Your quests and their objective areas as the game draws them, with tooltips saying what's left
  and who takes it in. Click one to Track it (Blizzard's gold arrow) or Path to it (a line around cliffs and water). Names and
  progress under each pin, on the big map, the small map or both, if you want them.
- **Your addons come along.** Questie, HandyNotes and GatherMate pins show on it, never twice. Your minimap's addon
  buttons, calendar and clock sit behind one AddOns button.
- **Choose what it replaces:** your minimap, the world map, both or neither. A Settings window tunes the look, live.
- **Rares you've seen**, remembered for every character; party and raid; flight points, dungeons, graveyards;
  waypoints and `/way` links.

`/mm` swaps it with Blizzard's minimap; `/mm help` lists every command.

**Limits:** WoW Forever only, English clients. Blizzard's blips show only around you, as on its minimap: not on
the big map, not while a path's line is drawn, not zoomed out past its widest. North up always. Other minimap
addons (SexyMap, ElvUI's minimap) may conflict.

**AI-repainted map art:** some clearly broken parts of the game's map art, flat unfinished blocks, are patched with
repaints made using AI image generation from the surrounding game art. It's a setting, on by default ("Repair
broken map art", under Map in Settings); off, or on a game build they weren't made for, you see Blizzard's map as it is.
