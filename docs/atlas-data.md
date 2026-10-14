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
