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
  one error naming each such file: `MagicMap: Data/UiMaps.lua is format 0, Atlas
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
- QuestieDB-derived files (`Npcs`, `Objects`, `Items`, `Quests`, `BlipServices`) are generated
  from the user's installed QuestieDB and **gitignored** (QuestieDB declares no
  license; don't commit or publish them until that's settled). QuestieDB's test and placeholder
  entities ("TEST WOLF (ALPHA FIRST)", "[PH] ...", "... UNUSED", "<NYI> ...") are dropped, and every
  reference to them, unless a quest's objective names them (tools/gen_questie.py PLACEHOLDER).
- **The data diet** (docs/v1-plan.md D3: no item tooltips, no dungeon NPCs in v1): Items and
  ItemIcons keep only the items quests reach, Npcs only the NPCs with an open-world spawn or that a
  quest, rare rank or service needs (below). Every id a kept row names is there, and
  `Atlas.QuestSources` is the same for every quest as without the diet
  (tools/tests/test_generators.py test_data_diet; `gen_questie.py --full` keeps everything).
- **Without a QuestieDB-derived file** Atlas answers as if it were empty (no error, no row, no
  sources), so callers don't check: the public build's case until D1 is settled.

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
- Read through `Atlas.Drawn` (above). The tint and edge data aren't used at run time (tiles are
  drawn as Blizzard drew them, on the map's backdrop colour).

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
  `{ mapID, name, x, y, zone, area }`, only on a continent and a zone whose map is on it (as the
  spike asks the continent's map: an instance's map has none); `Atlas.ZoneMapAt`: ZoneAt's, x and y in 0..1.

### Data/Borders.lua — `ns.Data.Borders` (ADT chunk areas)
`[inst] = { lines, z12, z30, far, z100, z200, sub, subz200, outlines, labels }`, positions in
tile space (3 decimals). Format 2 (M1.4: the levels and subzone borders).
- lines: zone borders `{ areaA, areaB, fadeStart, fadeEnd, x1, y1, x2, y2, ... }`, one
  per stretch between junctions. Traced along chunk edges between two zones' land,
  then smoothed offline (Gaussian, ~2 chunks) into curves and simplified to 0.003
  tiles. Ends stay exact: neighbours meet, three zones at one point.
- fadeStart / fadeEnd: tiles over which that end fades out, 0 none. A border that
  reaches the shore runs on a few chunks over water and fades there; one that stops
  on land of no zone fades over 0.1.
- z12, z30, far, z100, z200: the same lines simplified to 0.15, 0.05, 0.03, 0.015 and 0.0075
  tiles, each drawn below its zoom (far: 50 px per tile), where it's within about 1.5 px
  (`Atlas.BORDER_LEVELS`; Atlas.BorderLines picks by zoom). The first two are M1.4's bands;
  the rest halve the Lines a layout draws at zoom 50-200 (docs/v1-plan.md M1.4).
- sub: subzone borders `{ areaA, areaB, x1, y1, ... }`: chunk edges between two subzones of
  one zone, both on land with ≥ 4 land chunks (the spike's rule), smoothed and simplified as
  `lines`; subz200: within 0.0075 (`Atlas.SubzoneLines(inst, zoom)`: below zoom 300). The spike
  melts their steps with Douglas-Peucker at 0.035 tiles and Chaikin (Layers.lua:1424-1425,
  1503-1519); the zone borders' smoothing comes out rounder in about half the points.
- outlines: `[zone areaID] = { ring, ... }`, ring `{ x1, y1, ... }` closed (last joins
  first): the zone's land, from the same smoothed chains (shared stretches match
  `lines`; the coast within 0.01). Even-odd: a ring inside another is a hole. Rings
  under 12 chunks (islets, ponds) are dropped. For hit-testing and highlighting a zone.
- labels: `{ areaID, col, row, weight, kind }`: the land chunk deepest inside each zone
  (kind 1) and subzone (kind 2, ≥ 6 chunks); weight = its land chunks.
- `Atlas.Borders(inst)`, `Atlas.BorderLines(inst, zoom)`, `Atlas.SubzoneLines(inst, zoom)`,
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
- Only the items in Data/Items.lua (the diet): tools/gen_world.py reads it (`--items`), and leaves
  ItemIcons alone when it isn't there. gen_questie needs gen_world's UiMaps, so on a new build:
  gen_world, gen_questie, then gen_world again.
- `Atlas.Item(id).icon`.

### Packed rows (Npcs, Objects, Items, Quests: format 2)
Each row is stored as one Lua string of its table (`[id]="{...}"`), not the table: a string costs about
its length in memory, a table of tables about four times its text (the four files: 19.8 MB as tables,
7.2 MB as strings, measured in Lua 5.1). Atlas decodes a row (`loadstring`) the first time it's asked
for (`Atlas.Npc`, `Atlas.Quest`, ...) and keeps it. The scans that would decode every row use
`D.NpcLists` (in Data/Npcs.lua): `rare[inst]` the rank 2 or 4 NPCs spawning there (`Atlas.Rares`),
`flagged[inst]` those with npcFlags (`Atlas.ServiceSpawns`); `Atlas.Find` reads a row's name off its
string. The layouts below are the decoded tables.

### Data/Npcs.lua — `ns.Data.Npcs` (QuestieDB; gitignored)
`[npcID] = { name, subName, minLevel, maxLevel, rank, faction, flags, questStarts, questEnds, spawns, instances }`
- rank: 1 elite, 2 rare elite, 3 boss, 4 rare.
- flags: Classic npcFlags (2 quest giver, 4 vendor, 8 flight master, 16 trainer,
  128 innkeeper, 256 banker, 2048 battlemaster, 4096 auctioneer, 8192 stable
  master, 16384 repair).
- spawns: point lists per inst. instances: instIDs of dungeons it spawns inside
  (QuestieDB's -1,-1 spawns), resolved via QuestieDB's dungeon zone table.
- Diet: an NPC is kept when it has a spawn on an open-world map (Data/Tiles.lua: no kind; not a
  battleground), or a kept quest names it (startedBy, finishedBy, objectives, its own questStarts /
  questEnds), or a kept item does (npcDrops, vendors), or it is rare (rank 2, 4) or has a service
  flag (BlipServices'). About 9,600 of 13,200.

### Data/Objects.lua — `ns.Data.Objects` (QuestieDB; gitignored)
`[objectID] = { name, kind, questStarts, questEnds, spawns, instances }`
- kind: "mailbox" | "herb" | "ore" | nil (by name: the herb list, " Vein"/" Deposit" suffix, "Mailbox").
- Nameless QuestieDB stubs are skipped.

### Data/Items.lua — `ns.Data.Items` (QuestieDB; gitignored)
`[itemID] = { name, npcDrops, objectDrops, itemDrops, vendors, startQuest, class, subClass, requiredLevel }`
- Diet: only the items a kept quest reaches: its objectives' and startedBy's items, items whose
  startQuest is a kept quest, and the items those drop from (itemDrops, followed). About 2,800 of
  21,300, ~1.3 MB of Lua (all of them: ~10.5 MB).
- Ids QuestieDB names but has no row for (Season of Discovery NPCs in Forever's data, nameless object
  stubs) are left out of npcDrops, objectDrops, itemDrops and vendors.

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

### Data/BlipServices.lua — `ns.Data.BlipServices` (QuestieDB; gitignored)
`[name] = { service, title }`: what a Minimap blip whose tooltip says `name` is (format 2).
- service: `"innkeeper"`, `"banker"`, `"auctioneer"`, `"stablemaster"`, `"battlemaster"`, `"trainer"`,
  `"classtrainer"`, `"repair"`, `"questgiver"`, `"questender"`, `"flightmaster"` or `"mailbox"`; nil: none.
- As the spike's Blips.lua Kind(): the NPC of that name with the lowest id (LibQuestieDB's
  `IdsByName(name)[1]`), its first service flag in the spike's order
  (128 innkeeper, 256 banker, 4096 auctioneer, 8192 stable master, 2048 battlemaster, 16 trainer,
  16384 repair), else `"questgiver"` if it starts a quest, else `"questender"` if it ends one (the "?",
  Blips.lua:435), else `"flightmaster"` (flag 8); and `Mailbox` = `"mailbox"`. A trainer whose subName holds
  a class name is `"classtrainer"` (the spike's CLASS_TRAINER icon, Blips.lua:395-403).
- title: that NPC's subName (`"Innkeeper"`, `"General Supplies"`), the sensed blip's tooltip line
  (Blips.lua:436); nil: none. Names with neither aren't listed.
- `Atlas.BlipTitle(name)` → title or nil.
- `Atlas.BlipService(name)` → service or nil; without any data, `"herb"` and `"ore"` for gathering
  nodes by name (the spike's HERBS list, ` Vein` / ` Deposit`: enUS, Blips.lua:364-371, 423-426).

The QuestieDB-derived files are read through `Atlas.Npc(id)` (+ `services` from flags),
`Atlas.Object(id)`, `Atlas.Item(id)`, `Atlas.Quest(id)`, `Atlas.BlipService(name)`, `Atlas.BlipTitle(name)`,
`Atlas.Find(kind, text, limit, step)`, `Atlas.SpawnsIn(kind, inst, c0, r0, c1, r1, filter, step)`,
`Atlas.ServiceSpawns(inst, step)` (the town services' spawns only, as `[tile key] = { id, col, row, ... }`:
model/Services.lua's index, built once per inst),
`Atlas.Rares(inst, step)` and `Atlas.QuestSources(questID)` (a quest Atlas lacks: no objectives).
Those that walk every row (Find's names and its scan, SpawnsIn's, ServiceSpawns' and Rares' first use per
inst) call `step` every 128 rows, for a `Runtime.Job` (docs/structure.md "Atlas first use");
there is no name → NPC index at runtime (BlipServices is that answer, offline).

### Data/Interiors.lua — `ns.Data.Interiors` (obj0 MODF, root ADT MCVT, WMO roots and rooms, WMOMinimapTexture, WMOAreaTable)
The buildings with indoor minimap pictures on the open-world maps Data/Tiles.lua lists (ADR 0008),
committed (1,136 KB; 1.37 MB loaded). `[inst] = { tiles = { [tileKey] = { key... } }, buildings = { [key] =
{ c0, r0, c1, r1, packed } }, cities = { [uiMap] = { { key... }, { [key] = { [room] = { key, room, ... } } } } } }`.
- key: the placement's MODF unique ID (a building spanning tiles is listed once); tiles: the buildings whose
  box (c0, r0)-(c1, r1), tile space, touches that tile.
- packed: one Lua table literal (as the packed rows above), decoded on first use: `{ fid, wmoID, col, row,
  yaw, k, rooms }`: the WMO root's file, its WMO ID, the placement's tile point and turn (radians: rot.y −
  90°), k the mask cells a tile unit (TILE_YARDS / (4 · scale)); `rooms[group] = { zmin, zmax, area,
  links, x0, y0, cols, rows, mask, pics, floor, underground, over }` for each room (MOGI group index) with
  pictures: its box's floor and top (MOGI box z, its own), its subzone name (WMOAreaTable by WMO ID and the room file's MOGP group ID; nil: none), the
  rooms with pictures it has a portal to (MOPR), its floor mask (cols × rows 4-yd cells from cell (x0, y0) in
  the building's own coordinates, rows upward, `a` none `b` floor, runs as the letter and a count; from the
  pictures' alpha), its pictures, flat `fid, ox, oy, ux, uy, vx, vy, ...` in tile units, its real floor
  (world height: the area-weighted median z of the room file's upward triangles, normal z > 0.7, MOPY
  material 0xFF skipped, plus the placement's height; none: the box's), underground (that floor > 10 yd under
  the terrain at its mask's centre: MCVT, bilinear) and the rooms of the building whose masks share ≥ 3 cells
  with its (the building's frame).
- cities: per capital (uiMap 1453–1458; rect from Data/UiMaps.lua) its buildings, those whose box meets the
  rect and that have an underground room or ≥ 3,000 sq yd of floor (houses and shops left out), and per
  room the other city buildings' rooms sharing ≥ 3 4-yd cells (tile space). Today: Stormwind 1 (the city
  WMO), Orgrimmar 2, Ironforge 3, Thunder Bluff 2, Darnassus 1, Undercity 1.
- `Atlas.BuildingsAt(inst, col, row)` → the keys of the buildings whose box covers the point.
- `Atlas.Building(inst, key)` → `{ key, inst, fid, wmo, col, row, yaw, rooms = { [room] = { zmin, zmax, area,
  links = { room... }, pics = { { fid, ox, oy, ux, uy, vx, vy }... }, floor, underground, over = { room... } } } }`
  (kept): a picture's pixel (u, v) in 0..1 lands at o + u·U + v·V, U along its width, V down its height.
- `Atlas.City(inst, uiMap)` → `{ buildings = { key... }, over = { [key] = { [room] = { { key, room }... } } } }`
  (kept; nil: not a capital): `over[key]` nil when none of its rooms overlaps another building's.
- `Atlas.RoomsAt(building, col, row)` → the sorted rooms whose floor mask covers the point.
