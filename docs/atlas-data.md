# Atlas data

Atlas bundles every static fact MagicMap needs as generated Lua data files in
`Data/`, so nothing static is read from the game or QuestieDB at runtime. Each
file is a global table, written by a generator in `tools/` from one game build
(and one QuestieDB version), with a header naming its source and layout.

## Conventions

- **Positions are tile space**: `inst` (Map.db2 instanceID: 0 Eastern Kingdoms,
  1 Kalimdor, ...) and `col, row` in 0..64 (`col = 32 - west / TILE_YARDS`,
  `row = 32 - north / TILE_YARDS`, `TILE_YARDS = 1600 / 3`). Generators project
  everything (world yards, uiMap 0..1, QuestieDB 0..100 per zone) into this once.
  Rounded to 3 decimals (~0.5 yd).
- **Point lists** are flat per instance: `{ [inst] = { c1, r1, c2, r2, ... } }`.
- **Rows are positional arrays** (compact; nil holes allowed). The index order is
  listed below and in each file's header; Atlas turns rows into named tables.
- **ID lists** are plain arrays `{ id, id, ... }`; omitted when empty.
- **Faction** is `"A"`, `"H"`, `"AH"` (both) or nil (neither / not set).
- **Names** are enUS for now.
- QuestieDB-derived files (`Npcs`, `Objects`, `Items`, `Quests`) are generated
  from the user's installed QuestieDB and **gitignored** (QuestieDB declares no
  license; don't commit or publish them until that's settled).

## Files

### Data/Sea.lua — `MagicMap_Sea` (ADT MH2O ocean + MCVT heights, minimap tiles) and Textures/Sea
`{ product, version, dir, maps = { [inst] = { shallow, deep, masks, open } } }`
- One ocean under the tiles. Sea = an "Ocean" LiquidType over the ground, per terrain
  quad (8x8 per chunk, 128x128 per tile, ~4 yd); depth = its surface − the ground.
  Lakes and rivers aren't sea (the art draws them). Off the map's tiles: deep sea.
- shallow, deep: `{ r, g, b }` sampled from the art itself (medians over sea 4–12 /
  ≥ 60 yd deep); deep ≤ shallow per channel.
- masks: `[key] = true` for tiles with a 128x128 TGA `dir .. inst .. "_" .. key .. ".tga"`:
  alpha = land (1 land, 0 sea; the coast a Gaussian feather of 2 quads; piers and
  ships over the sea kept as land), grey = shelf = exp(−depth / 28 yd), 1 at the shore
  and on land. Sea colour = deep + shelf × (shallow − deep).
- open: `[key] = true` for tiles that are all deep sea: draw no art. Any other tile is
  all land: its art as it is.
- Drawn with textures only: a solid `deep` under the map; per masked tile the mask
  opaque (blend DISABLE) tinted shallow − deep plus a solid `deep` added (ADD); then
  the art with the mask as its MaskTexture (alpha). Maps with < 4 open-sea tiles get none.
- `Atlas.Sea(inst)` → the map's entry; `Atlas.SeaTile(inst, key)` → `"coast", maskPath`
  | `"open"` | `"land"` (nil without sea). Supersedes TileColor's water masks (kept for
  the demo's `before`).

### Data/UiMaps.lua — `MagicMap_UiMaps` (UiMap + UiMapAssignment DB2)
`[uiMapID] = { name, mapType, parent, inst, col0, row0, col1, row1, areaID }`
- mapType per Enum.UIMapType (1 world, 2 continent, 3 zone, 6 orphan).
- rect from the uiMap's first assignment (OrderIndex); nil for maps without one.
  World maps (Azeroth 947) span instances: inst/rect nil.

### Data/Areas.lua — `MagicMap_Areas` (AreaTable DB2)
`[areaID] = { name, parent, inst, level, faction, uiMap }`
- parent: parent areaID (nil for zones). level: ExplorationLevel.
- faction from FactionGroupMask (2 → "A", 4 → "H").
- uiMap: the uiMap whose assignment names this area, else the nearest ancestor's.

### Data/AreaGrid.lua — `MagicMap_AreaGrid` (ADT chunk areas)
`[inst] = { [tileKey] = { palette, cells } }`, tileKey = col * 64 + row.
- palette: array of areaIDs used in the tile (≤ 52).
- cells: the 256 chunks (index iy * 16 + ix) as letters, `a`..`z` then `A`..`Z`
  = palette index 1..52, each optionally followed by a run length (as Walk.lua).
- A chunk is 1/16 tile (~33 yd). Area 0 = none.

### Data/Borders.lua — `MagicMap_Borders` (ADT chunk areas)
`[inst] = { lines, far, outlines, labels }`, positions in tile space (3 decimals).
- lines: zone borders `{ areaA, areaB, fadeStart, fadeEnd, x1, y1, x2, y2, ... }`, one
  per stretch between junctions. Traced along chunk edges between two zones' land,
  then smoothed offline (Gaussian, ~2 chunks) into curves and simplified to 0.003
  tiles. Ends stay exact: neighbours meet, three zones at one point. No subzone borders.
- fadeStart / fadeEnd: tiles over which that end fades out, 0 none. A border that
  reaches the shore runs on a few chunks over water and fades there; one that stops
  on land of no zone fades over 0.1.
- far: the same lines, simplified to 0.03 tiles (Atlas.BorderLines picks by zoom).
- outlines: `[zone areaID] = { ring, ... }`, ring `{ x1, y1, ... }` closed (last joins
  first): the zone's land, from the same smoothed chains (shared stretches match
  `lines`; the coast within 0.01). Even-odd: a ring inside another is a hole. Rings
  under 12 chunks (islets, ponds) are dropped. For hit-testing and highlighting a zone.
- labels: `{ areaID, col, row, weight, kind }`: the land chunk deepest inside each zone
  (kind 1) and subzone (kind 2, ≥ 6 chunks); weight = its land chunks.

### Data/Places.lua — `MagicMap_Places` (DB2)
- `flight[nodeID] = { name, faction, inst, col, row, areaID }` (TaxiNodes)
- `taxiPaths = { { from, to, cost }, ... }` (TaxiPath)
- `pois[poiID] = { name, description, icon, importance, inst, col, row, areaID }` (AreaPOI)
- `dungeons[instID] = { name, kind, entranceInst, col, row, minLevel, maxPlayers, bosses }`
  (Map + MapDifficulty + DungeonEncounter). kind "dungeon" | "raid" | "battleground";
  entrance from Map.Corpse / CorpseMapID; minLevel parsed from MapDifficulty's
  message; bosses = names in OrderIndex order.

### Data/ItemIcons.lua — `MagicMap_ItemIcons` (Item DB2)
`[itemID] = iconFileDataID`

### Data/Npcs.lua — `MagicMap_Npcs` (QuestieDB; gitignored)
`[npcID] = { name, subName, minLevel, maxLevel, rank, faction, flags, questStarts, questEnds, spawns, instances }`
- rank: 1 elite, 2 rare elite, 3 boss, 4 rare.
- flags: Classic npcFlags (2 quest giver, 4 vendor, 8 flight master, 16 trainer,
  128 innkeeper, 256 banker, 2048 battlemaster, 4096 auctioneer, 8192 stable
  master, 16384 repair).
- spawns: point lists per inst. instances: instIDs of dungeons it spawns inside
  (QuestieDB's -1,-1 spawns), resolved via QuestieDB's dungeon zone table.

### Data/Objects.lua — `MagicMap_Objects` (QuestieDB; gitignored)
`[objectID] = { name, kind, questStarts, questEnds, spawns, instances }`
- kind: "mailbox" | "herb" | "ore" | nil (by name: the herb list, " Vein"/" Deposit" suffix, "Mailbox").
- Nameless QuestieDB stubs are skipped.

### Data/Items.lua — `MagicMap_Items` (QuestieDB; gitignored)
`[itemID] = { name, npcDrops, objectDrops, itemDrops, vendors, startQuest, class, subClass, requiredLevel }`

### Data/Quests.lua — `MagicMap_Quests` (QuestieDB; gitignored)
`[questID] = { name, level, requiredLevel, faction, races, classes, startedBy, finishedBy, objectives, objectivesText, zone, sort, preQuestSingle, preQuestGroup, exclusiveTo, nextQuest, breadcrumbFor, triggerEnd }`
- faction from requiredRaces (Alliance-only / Horde-only races) or nil.
- startedBy = `{ npcs, objects, items }`, finishedBy = `{ npcs, objects }` (ID lists, nil when empty).
- objectives: ordered list of `{ kind, id, text }`, kind "monster" | "object" |
  "item" | "reputation" | "killcredit" | "spell"; within a kind, in QuestieDB's
  order (the game's k-th objective of a kind is the k-th of that kind here).
  killcredit id = the root NPC; reputation id = factionID.
- zone: areaID (QuestieDB zoneOrSort > 0); sort: QuestSort (zoneOrSort < 0, negated).
- triggerEnd = `{ text, spawns }` (spawns as point lists per inst).
