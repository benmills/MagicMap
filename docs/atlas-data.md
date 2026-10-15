# Atlas data

Atlas bundles every static fact MagicMap needs as generated Lua data files in
`Data/`, so nothing static is read from the game or QuestieDB at runtime. Each
file is one dataset, `ns.Data.<Name>`, written by a generator in `tools/` from one
game build (and one QuestieDB version), with a header naming its source and layout.

## The wrapper: no globals

A global is shared with every addon: the rebuild's old `MagicMap_*` data globals had
the MagicMap spike's names and broke it 2980 times in one session
(docs/evidence/spike-bugs.md E1). So no Data file sets a global. After its header
comments each starts

```lua
local _, ns = ...
local D = ns.Data or {}; ns.Data = D
D.formats = D.formats or {}; D.formats.Tiles = 1
D.Tiles = { ... }
```

- **`ns.Data.<Name>`** is the dataset (the headings below); Atlas reads only that
  (`local Data = ns.Data` in each atlas/ file). Nothing else reads ns.Data
  (tools/luacheck.py NS_RULES); tests see which loaded through `Atlas.Data`.
- **`ns.Data.formats.<Name>`** is the file's format, a whole number bumped when the
  dataset's shape changes. It lives beside the dataset, not in it, so `pairs` over an
  ID-keyed dataset never meets it. The numbers are `FORMATS` in
  tools/mmtools/luaout.py (the generators, via `data_head`) and `Atlas.FORMATS` in
  atlas/Coords.lua, one row per Data file in both (a package adds or bumps only its
  own); tools/tests/test_atlas.py checks they agree. At load
  atlas/Coords.lua drops any dataset whose format isn't the one Atlas reads (Atlas then
  answers as if the file were missing, as for the gitignored QuestieDB files) and raises
  one error naming each such file: `MagicMapAtlas: Data/UiMaps.lua is format 0, Atlas
  reads 1: regenerate (README, tools/gen_*.py)`. Not a cascade of nil indexes.
- Python reads a Data file the way WoW does, called with `(addon, ns)`:
  `tools/mmtools/luaout.py load_data(lua, path)` returns `ns`
  (tools/atlas_lua.py loads them all, then Atlas, into one ns).

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
  license; don't commit or publish them until that's settled). QuestieDB's test and placeholder
  entities ("TEST WOLF (ALPHA FIRST)", "[PH] ...", "... UNUSED", "<NYI> ...") are dropped, and every
  reference to them, unless a quest's objective names them (tools/gen_questie.py PLACEHOLDER).

## Files

Listed in Atlas's load order (`atlas/files.txt`), each with the Atlas calls
that read it.

### Data/Tiles.lua — `ns.Data.Tiles` (WDT MAID chunks, Map DB2)
`{ product, version, maps = { [inst] = { name, bg, kind, continent, tiles } } }`
- tiles[key] = minimap FileDataID of `map<col>_<row>`, key = col * 64 + row: exactly the
  tiles this build's WDT lists. Every open-world map, dungeon and raid with minimap tiles.
- bg = `{ r, g, b }`: median colour of the water along the map's outer edge (the backdrop).
- kind = "dungeon" | "raid" for instances (nil: open world); continent = the instanceID
  of the entrance's continent.
- `Atlas.Maps()` → `{ inst, name, kind, continent, bg }` sorted by inst;
  `Atlas.Tiles(inst)`; `Atlas.TileBounds(inst)` → c0, r0, c1, r1;
  `Atlas.TileInfo(inst, key)` → `{ fdid, tint, edge, sea }` (with TileColor);
  `Atlas.Drawn(inst, key)`.

### Data/TileColor.lua — `ns.Data.TileColor` (minimap tiles)
`[inst] = { tint, edge, sea }`, key = col * 64 + row
- tint[key] = `{ mr, mg, mb, ar, ag, ab }`: drawn = texel * m + a, for tiles whose baked
  lighting is off from their neighbours' (open-world maps; only those that need it).
- edge[key] = `{ l = {r,g,b}, ... }`: the median of the outer 0.08 tile on each side facing
  open space (no tile or a sea tile), after the tint.
- sea[key] = true: open-sea tiles (the art's flat deep water all over, or that plus a frame):
  not drawn; `Atlas.Drawn` is false there. The art's own water is otherwise left as it is.
- Read through `Atlas.TileInfo` and `Atlas.Drawn` (above).

### Data/Sea.lua — `ns.Data.Sea` (minimap tiles, ADT MH2O ocean + MCVT heights) and Textures/Sea
`{ product, version, dir, variants, gain, feather, maps = { [inst] = { tint, far, coast } } }`
- The open sea beyond the tiles (no tile, or TileColor sea[]), continuing the art's own water:
  the art is drawn as it is and the sea fills the rest. Open-world maps with ≥ 4 open-sea
  tiles and ocean in the terrain (Eastern Kingdoms, Kalimdor).
- dir is relative to the addon's folder (`Textures\Sea\<product>\`); Atlas prefixes
  `Atlas.ROOT` (`Interface\AddOns\<the addon's folder name>\`), so a rename needs no regeneration.
- `dir .. inst .. "_ocean" .. v .. ".blp"`, v = 0..variants-1: 256 px grey DXT1 BLPs with mips,
  seamless, one repeat per tile, mean `gain`: brightness synthesised from the map's own water
  (art over ocean 6–45 yd deep: the seabed showing through; the art's deep sea is one flat
  colour), rocks and wrecks removed. Every variant equals variant 0 near its edges, so any
  variant sits beside any other. `Atlas.SeaVariant(col, row)` picks one per cell by a hash.
- `dir .. inst .. "_tint.tga"`: the sea's colour / gain, 4 px per tile (stretched to power-of-two
  sides, as WoW textures must be) over
  tint = `{ col0, row0, col1, row1 }` (the tiles and 8 around): along each coast side the art's
  own water there (by quarter tile), fading within about a tile to the art's open-sea colour,
  a little darker far out and gently varied. far = its border colour (0..255), for beyond it.
- coast[key] = code: tiles with a side (bits 1 l, 2 r, 4 t, 8 b) or only a corner (16 tl, 32 tr,
  64 bl, 128 br) touching the sea; `dir .. "feather_" .. code .. ".tga"` (64 px, white) is the
  art's mask: 0 at those sides, smoothstep to 1 over `feather` of a tile.
- Drawn with textures only: per sea cell its variant (world-anchored); over the view variant 0
  REPEAT at a repeat every 2.7 tiles, turned a quarter, at alpha 0.35; the tint map with
  SetBlendMode("MOD"); then the tiles, coast tiles with their feather as MaskTexture. See
  tools/gen_sea.py and demo/tiles.js.
- `Atlas.Sea(inst)` → `{ textures, gain, tint, rect, far }` (far 0..1) or nil;
  `Atlas.SeaVariant(col, row)` → 1..variants; `Atlas.SeaFeather(inst, key)` → mask path or nil.

### Data/UiMaps.lua — `ns.Data.UiMaps` (UiMap + UiMapAssignment DB2)
`[uiMapID] = { name, mapType, parent, inst, col0, row0, col1, row1, areaID }`
- mapType per Enum.UIMapType (1 world, 2 continent, 3 zone, 6 orphan).
- rect from the uiMap's first assignment (OrderIndex); nil for maps without one.
  World maps (Azeroth 947) span instances: inst/rect nil.
- `Atlas.UiMap(id)`, `Atlas.MapRect(id)`, `Atlas.MapToTile(id, x, y)`, `Atlas.TileToMap(id, col, row)`,
  `Atlas.Zones(inst)` (zone uiMaps by name), `Atlas.Continent(inst)` → the continent's uiMapID.

### Data/Areas.lua — `ns.Data.Areas` (AreaTable DB2)
`[areaID] = { name, parent, inst, level, faction, uiMap }`
- parent: parent areaID (nil for zones). level: ExplorationLevel.
- faction from FactionGroupMask (2 → "A", 4 → "H").
- uiMap: the uiMap whose assignment names this area, else the nearest ancestor's.
- `Atlas.Area(id)` → named row + `zone` (its top ancestor); `Atlas.ZoneLevels(zone)` → min, max
  (from its subzones' levels).

### Data/AreaGrid.lua — `ns.Data.AreaGrid` (ADT chunk areas)
`[inst] = { [tileKey] = { palette, cells } }`, tileKey = col * 64 + row.
- palette: array of areaIDs used in the tile (≤ 52).
- cells: the 256 chunks (index iy * 16 + ix) as letters, `a`..`z` then `A`..`Z`
  = palette index 1..52, each optionally followed by a run length (as Walk.lua).
- A chunk is 1/16 tile (~33 yd). Area 0 = none.
- `Atlas.AreaAt(inst, col, row)` → areaID; `Atlas.ZoneAt(inst, col, row)` →
  `{ mapID, name, x, y, zone, area }`.

### Data/Borders.lua — `ns.Data.Borders` (ADT chunk areas)
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
- `Atlas.Borders(inst)`, `Atlas.BorderLines(inst, zoom)` (far below `Atlas.BORDER_FAR_ZOOM`),
  `Atlas.ZoneOutline(inst, zone)`; Data/Labels.lua ranks these labels with the
  continent's name and AreaPOI towns and landmarks (Places).

### Data/Walk.lua — `ns.Data.Walk` (ADT MCVT heights, MH2O liquids)
`[inst] = { [tileKey] = cells }`, open-world maps with ≥ 20 terrain tiles.
- cells: the tile's 256 chunks (index iy * 16 + ix) as letters `'a' + value`, each
  optionally followed by a run length. value = class (0 blocked: mostly too steep,
  1 land, 2 water: mostly deeper than swimming depth, 3 magma/slime) + 4 (can cross
  into the chunk east) + 8 (south). Terrain only: buildings and bridges (WMOs) read as
  what's under them.
- Global chunk (gc, gr) = tile (col, row) * 16. `Atlas.Walk.Cell(inst, gc, gr)` → class,
  east, south; `Atlas.Walk.CanMove(inst, gc, gr, dx, dy)` (8 ways);
  `Atlas.Walk.Snap(inst, gc, gr)` → the nearest standable chunk within 4.

### Data/Places.lua — `ns.Data.Places` (DB2)
- `flight[nodeID] = { name, faction, inst, col, row, areaID }` (TaxiNodes)
- `taxiPaths = { { from, to, cost }, ... }` (TaxiPath)
- `pois[poiID] = { name, description, icon, importance, inst, col, row, areaID }` (AreaPOI)
- `dungeons[instID] = { name, kind, entranceInst, col, row, minLevel, maxPlayers, bosses }`
  (Map + MapDifficulty + DungeonEncounter). kind "dungeon" | "raid" | "battleground";
  entrance from Map.Corpse / CorpseMapID; minLevel parsed from MapDifficulty's
  message; bosses = names in OrderIndex order.
- `Atlas.FlightPoints(inst)`, `Atlas.TaxiPaths()`, `Atlas.POIs(inst)` (sorted by id),
  `Atlas.Dungeon(instID)`, `Atlas.Dungeons(entranceInst)`.

### Data/Labels.lua — `ns.Data.Labels` (Data/Tiles, Walk, UiMaps, Areas, Borders, Places)
`[inst] = { { text, col, row, tier, size, areaID, poiID }, ... }` in rank order (1 first)
- Every map name as a ranked anchor, ranked offline by tools/gen_labels.py from the
  other Data files: it was Atlas.Labels' first-use work, ~50 ms for the two continents in
  lupa and the play-test's first-open FAIL (docs/v1-plan.md §2); a lookup now, ~0.1 ms each.
  Regenerate it after any of them: tools/tests/test_generators.py fails while it's stale.
- tier, most important first: `continent` (its name, at the land's visual centre: the
  land sample, 4 per tile side, farthest from deep water or the map's edge by a chamfer
  distance transform), `zone` (Borders labels of kind 1), `town` (AreaPOI icons 4 town,
  5 capital, or 2/6 with importance ≥ 2), `subzone` (Borders labels of kind 2), `poi`
  (AreaPOI icons 2/6 otherwise). POIs with a description (events, world-PvP states) are
  left out. Within a tier by score, high first (zone, subzone: land chunks; town:
  importance × 10, + 2 capital, + 1 town), then by text.
- A town and the subzone label of its name within 0.5 tiles are one name: the town, at its
  POI, keeping the subzone's size and areaID. A landmark that duplicates one is skipped.
- size: the land named (continent: its zones'; zone, subzone: its chunks) as the side of
  a square, in tiles; nil for towns and landmarks that aren't also a subzone. 4 decimals,
  so `floor((size * 16)^2 + 0.5)` is the label's land chunks (the spike's `weight`).
- Every inst with a name: the open-world maps, and instances with POIs (Alterac Valley).
- `Atlas.Labels(inst)` → `{ text, col, row, tier, rank, size?, areaID?, poiID? }` in rank
  order (named rows, per inst at first use); tools/tests/test_atlas.py holds it to the
  golden of the ranking it replaced.

### Data/ItemIcons.lua — `ns.Data.ItemIcons` (Item DB2)
`[itemID] = iconFileDataID`
- `Atlas.Item(id).icon`.

### Data/Npcs.lua — `ns.Data.Npcs` (QuestieDB; gitignored)
`[npcID] = { name, subName, minLevel, maxLevel, rank, faction, flags, questStarts, questEnds, spawns, instances }`
- rank: 1 elite, 2 rare elite, 3 boss, 4 rare.
- flags: Classic npcFlags (2 quest giver, 4 vendor, 8 flight master, 16 trainer,
  128 innkeeper, 256 banker, 2048 battlemaster, 4096 auctioneer, 8192 stable
  master, 16384 repair).
- spawns: point lists per inst. instances: instIDs of dungeons it spawns inside
  (QuestieDB's -1,-1 spawns), resolved via QuestieDB's dungeon zone table.

### Data/Objects.lua — `ns.Data.Objects` (QuestieDB; gitignored)
`[objectID] = { name, kind, questStarts, questEnds, spawns, instances }`
- kind: "mailbox" | "herb" | "ore" | nil (by name: the herb list, " Vein"/" Deposit" suffix, "Mailbox").
- Nameless QuestieDB stubs are skipped.

### Data/Items.lua — `ns.Data.Items` (QuestieDB; gitignored)
`[itemID] = { name, npcDrops, objectDrops, itemDrops, vendors, startQuest, class, subClass, requiredLevel }`

### Data/Quests.lua — `ns.Data.Quests` (QuestieDB; gitignored)
`[questID] = { name, level, requiredLevel, faction, races, classes, startedBy, finishedBy, objectives, objectivesText, zone, sort, preQuestSingle, preQuestGroup, exclusiveTo, nextQuest, breadcrumbFor, triggerEnd }`
- faction from requiredRaces (Alliance-only / Horde-only races) or nil.
- startedBy = `{ npcs, objects, items }`, finishedBy = `{ npcs, objects }` (ID lists, nil when empty).
- objectives: ordered list of `{ kind, id, text }`, kind "monster" | "object" |
  "item" | "reputation" | "killcredit" | "spell"; within a kind, in QuestieDB's
  order (the game's k-th objective of a kind is the k-th of that kind here).
  killcredit id = the root NPC; reputation id = factionID.
- zone: areaID (QuestieDB zoneOrSort > 0); sort: QuestSort (zoneOrSort < 0, negated).
- triggerEnd = `{ text, spawns }` (spawns as point lists per inst).

The four QuestieDB-derived files are read through `Atlas.Npc(id)` (+ `services` from
flags), `Atlas.Object(id)`, `Atlas.Item(id)`, `Atlas.Quest(id)`, `Atlas.NpcsByName(name)`,
`Atlas.Find(kind, text, limit)`, `Atlas.SpawnsIn(kind, inst, c0, r0, c1, r1, filter)` and
`Atlas.QuestSources(questID)`.
