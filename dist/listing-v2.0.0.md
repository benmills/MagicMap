# MagicMap 2.0.0: CurseForge / Wago listing (draft)

A draft for the user (D7: the channel is decided at the end; nothing here is uploaded). The
changelog for either site is dist/RELEASE_NOTES-v2.0.0.md without its checklist block.

## Both sites

| Field | Value |
| --- | --- |
| Name | MagicMap |
| Slug | `magicmap` (CurseForge) / `magicmap` (Wago), if free |
| Summary (≤ 140 characters) | Your minimap, zooming out to the whole world on the game's own terrain, with Blizzard's blips on it. M grows it into a big map. |
| Game | World of Warcraft: WoW Forever (`_classic_beta_`, client 1.60.1, `## Interface: 16001`). Check each site lists Forever; if not, say so in the description and pick the nearest Classic flavour only if the site requires one |
| Category | Map & Minimap (the TOC's `## Category`); also Quests & Leveling |
| Release type | Release |
| Version / file name | 2.0.0 / `MagicMap-v2.0.0.zip` (one `MagicMap/` folder; which zip is D1's: `-no-questie-data` or `-with-questie-data`) |
| Dependencies | None required. Optional, picked up when loaded: Questie, HandyNotes, GatherMate2 (HereBeDragons pins); FarmHud is yielded to |
| Licence | **To choose**: neither repo has a LICENSE. With the QuestieDB-derived data in the zip, its licence (none declared) must be settled first (D1) |
| Source | the GitHub repo, once merged (docs/release/merge-plan.md) |
| Screenshots / media | docs/images/ (2.0's in-game shots, as the README shows them) |

Later, for automatic packaging: `## X-Curse-Project-ID:` and `## X-Wago-ID:` in MagicMap.toc once the
projects exist; a `.pkgmeta` would need the gitignored Data files, so upload tools/package.sh's zip by hand.

## Description

**A minimap you can zoom out.** MagicMap takes your minimap's spot and draws the game's own minimap
terrain at any zoom, from Blizzard's closest zoom out to a whole continent. Blizzard's live blips
(herbs, ore, tracked NPCs) stay on it. Press M and it grows into a big map in the same frame.

For **WoW Forever** only.

- **See past the minimap's edge.** The next quest hub, the road, the coast, without opening the
  world map.
- **Your gathering blips stay.** Herbs, ore and Blizzard's tracking show around you, with their
  icons and tooltips, on the zoomed-out terrain.
- **One map.** The minimap and the big map are the same frame, at the same place in the world.
  Click the zone name for any continent or instance, click a zone to fly there.
- **Questing in view.** Your quests and quests to pick up, their objective areas as the game draws
  them, rich tooltips. Click a quest to follow it: a hand-inked line walks you there, around
  cliffs, lava and water.
- **Your addons come along.** Questie, HandyNotes, GatherMate and other HereBeDragons pins show on
  it, and nothing is drawn twice.
- **Rares you've seen**, remembered for every character on your account; party and raid members;
  flight points, dungeons and graveyards; waypoints and `/way` links.

`/mm` swaps it with Blizzard's minimap; `/mm help` lists every command.

**Limits:** WoW Forever only, enUS clients; Blizzard's blips reach about 230 yards around you;
north up always; walking routes only. Other minimap addons may conflict.

**Updating from 1.x:** delete the old `MagicMap` folder first. 2.0 starts with fresh settings (1.0's
saved window, layers and seen rares aren't carried over), then restart the game.
