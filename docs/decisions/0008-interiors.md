# 0008 Interiors: Blizzard's indoor minimap pictures, placed by us

Status: accepted (2026-10-20), proven by an offline mockup and an in-game test addon on Ironforge
(prototype: [docs/evidence/indoors/](../evidence/indoors/)). Replaces the indoor renderers of M4.2
and M4.4 (View.renderer `"ours+art"` and `"blizzard"`, spike-bugs G1). Types:
[types/observation.lua](../../types/observation.lua), [types/model.lua](../../types/model.lua),
[types/view.lua](../../types/view.lua).

## Context

Indoors our terrain tiles show the ground above you. Until now the window showed either the world
map's painting of the map you're on (cities and dungeon floors, ≤1,600 yd) or Blizzard's whole
Minimap over black. The user rejects both: the painting isn't a minimap, and the borrowed Minimap
isn't ours (round, centred on you, about 300 yd, none of our pins or zoom). Drawing our own floor
plans from the room geometry was judged a non-starter.

Every second level in the world is a building model (WMO): a terrain tile stores one height per
spot. Blizzard's minimap draws each indoor room ("group") from its own pictures, listed in
`WMOMinimapTexture.db2`. We place those same pictures on our canvas, by the building's placement,
like terrain tiles.

## The data (proven on Ironforge: file 7801267, WMO ID 20884, 104 rooms, 108 pictures)

- **Where a building is**: each terrain tile's `obj0` file, chunk `MODF` (64 bytes an entry: file
  ID, unique ID, position, rotation, box min, box max, flags, doodad set, name set, scale/1024). A
  building spanning tiles is listed in each: dedupe by unique ID.
- **The placement** (noggit's): file-space point = pos + Ry(rot.y − 90°) · (lx, lz, −ly) · scale,
  with Ry(θ): x' = x cos θ + z sin θ, z' = −x sin θ + z cos θ. File-space x and z divided by
  533.33 are our tile col and row. Checked: the root box's 8 corners through it give the MODF box
  to 0.0 yd.
- **The building's root** (`MOHD`): its WMO ID is the u32 at offset 32. `MOGI` (32 bytes a room):
  flags (0x2000 indoor, 0x8 outdoor), box min, box max (local x, y, z; z up), name offset.
  `GFID`: the rooms' file IDs, the first nGroups of them LOD 0. Each room file's `MOGP` holds its
  global group ID (u32 at offset 56), which `WMOAreaTable` keys on. `MOPT`/`MOPV`/`MOPR`: portals
  (doorways) and the rooms each joins.
- **The pictures** (`WMOMinimapTexture`, file 1323241): rows of room, block x, block y (256 + the
  block's row), picture file ID; the WMO ID is in the db2's relationship section
  (`read_wdc5(relation=True)`). **2 px a yard.** A block is 256 px = 128 yd. Block (bx, by) starts
  at the room box's min corner + 128·(bx, by), and its content sits in the picture's bottom-left
  corner: pixel (px, py) of a w × h picture is local (x0 + 128 bx + px/2, y0 + 128 by + (h − py)/2).
  The pictures have real alpha (only floors draw), aren't mirrored, and look good in the game.
- **Room names** (`WMOAreaTable`, file 1355528): WMO ID, group ID → name ("The Great Forge",
  "The High Seat"). Indoors, `GetSubZoneText()` is the name of the room you're in.
- **Real floors**: a room's box zmin is its lowest geometry, not its floor (Ironforge's Commons ring:
  box −91, floor about −5). The floor is the area-weighted median z of the room file's upward-facing
  triangles (normal z > 0.7; MOPY material 0xFF, collision-only, skipped): after MOGP's 68-byte header,
  MOVT/MOVI/MOPY. 97 of Ironforge's 103 rooms are within 22 yd of the median. In world height (the
  placement's y + z · scale; rotation is yaw only) so buildings compare: Ironforge's sits at 506.7.
- **Underground**: the floor more than 10 yd under the terrain (root ADT MCVT) at the mask's centre. Under a
  city WMO the terrain is a placeholder under holes: Orgrimmar's lies 10 to 100 yd below its floors, so its
  Cleft of Shadow (rooms 74, 75, 137 of the city WMO) isn't underground by this test.
- **Capitals**: Stormwind City and Undercity are each one WMO (288, 196 rooms); Orgrimmar one (138 rooms,
  the Cleft of Shadow among them) and an unnamed 12-room one at its east edge, 25 to 100 yd under the terrain; Ironforge's city WMO and two small
  ones in the mountain; Darnassus one (54 rooms); Thunder Bluff the Pools of Vision and a one-room cave.
- **Scale**: Eastern Kingdoms 665 buildings with pictures (3,537 pictures), Kalimdor 381 (2,133).
  Half are single-picture houses.

## What the client tells us at runtime

- Your 2D position (UnitPosition), not your height (it isn't real on this client).
- `GetSubZoneText()`: the room's name.
- `NEW_WMO_CHUNK` fires when you enter or leave a **building**, not a room.
- `IsIndoors()` means "can't mount", so it's false in Ironforge.
- Inside instances there's no position, so they're out of scope.

## Decision

- **Atlas** ships every open-world map's buildings with pictures (generated, like the tiles):
  per building its placement, and per room its box's floor and top (zmin, zmax), its real floor, whether
  it's underground, the rooms of the building it overlaps, the subzone name, the rooms
  it has a portal to, its floor mask (4-yd cells in the building's own coordinates, from the
  pictures' alpha) and its pictures (each as an origin and two edge vectors in tile space). Packed
  per building and decoded on first use. Per capital, its buildings (an underground room or ≥ 3,000
  sq yd of floor) and the rooms of other buildings each of their rooms overlaps.
- **Which room you're in** (Game, each change of position; proven in game):
  1. the rooms whose floor mask covers your spot;
  2. of those, the ones named like your subzone, if any;
  3. the room you were in, if it's still one of them;
  4. otherwise the ones your room has a portal to, if any;
  5. one left: your room. Several: unsure (the candidates kept).
  - No mask covers you: stay. That way a seam between masks doesn't drop the room.
  - 2 s with no mask under you: out of the building (no room).
- **Drawing** (UI), while you're in a building:
  - the terrain tiles dimmed (×0.35 tested);
  - the building's rooms drawn over them, under quest areas and pins;
  - a room hidden when its floor is more than **22 yd** above yours (tuned in Ironforge; box zmin,
    not the real floor). Unsure: measured from the highest candidate's floor, so it never hides
    the room you may be in;
  - your room, or every candidate, drawn over every other room (the Forge hall's picture covers
    the High Seat's).
  - Outside a building, nothing extra: the terrain tiles show its roof, as now.
- **Gone**:
  - the world map's indoor art (game/parts/IndoorArt.lua, ui/IndoorArt.lua, obs.indoorArt);
  - Blizzard's whole Minimap in the window (`Game.Whole`, its backdrop, View.renderer `"blizzard"`);
  - the ≤1,600 yd rule and `OPEN_CITIES`, unless the user's Orgrimmar check says otherwise.
- Where a place has no pictures, the view is ours, as outdoors.

Locked: none yet. Open: the 22 yd threshold beyond Ironforge (real floor heights from the room
geometry if it doesn't hold); Orgrimmar and other open-air cities the Minimap calls indoor.
