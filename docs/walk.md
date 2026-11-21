# Walk: how the way is found

The data `tools/gen_walk.py`, `gen_walk_regions.py` and `gen_walk_rough.py` bake from the game's terrain, and what
`atlas/Walk.lua` and `atlas/Route.lua` do with it. The game's own limits behind the rules: you walk up faces of at
most 50 degrees, step up 2 yd, walk down to 61.6 degrees, and fall 14.57 yd without harm.

Three levels. L0 is bake-only, L1 and L2 ship.

## L0: the fine graph (bake only, never shipped)

Terrain as the client draws it: each 4.17-yd quad is 4 triangles round its centre vertex (N: a,b,m; E: b,d,m;
S: d,c,m; W: c,a,m; a NW, b NE, c SW, d SE). MCVT: outer `h[qy*17+qx]`, centre `h[qy*17+9+qx]`, plus the chunk's z.

Triangle kinds:
- HOLE: its quad is in the MCNK hole mask (demo/export_terrain.py `holes`), or no chunk. Nothing passes.
- WATER: liquid over the quad deeper than SWIM_DEPTH 1.5 (as gen_walk today). HARMFUL: magma/slime at any depth.
  Both standable whatever the slope (you swim).
- else by the face's slope: FLAT (<= 50 deg), STEEP (50 < s <= 61.6), WALL (> 61.6).
- Standable = FLAT, WATER, HARMFUL.

Fine moves, between triangles sharing an edge (never a vertex alone). zmid(e) = mean of an edge's two vertex
heights, zc(T) = mean of a triangle's three:
1. standable <-> standable: both ways.
2. Step-up (the client's 2.0-yd step, landing on walkable ground): standable A and standable C both edge-adjacent
   to one non-standable B (not a hole), by edges e1 and e2 of B: A -> C if -14.57 <= zmid(e2) - zmid(e1) <= 2.0.
   One triangle only: steps don't chain.
3. Descent through non-standable triangles (walk down <= 61.6, drop down walls): enter non-standable B across e
   if zc(B) < zmid(e); leave B across e' if zmid(e') < zc(B); B -> B' (both non-standable) is the two together.
   Never up. WALL runs are falls: a continuous run of WALL triangles may be entered from a height z only if
   z - (the lowest exit the run can lead to by descending through WALL only) <= 14.57 (worst case, by iterative
   min-relaxation). STEEP has no height limit. Landing on WATER: no limit is fine if cheap, otherwise same rule.
   A descent ends at the first standable triangle it reaches.

Change a rule only with evidence: a named place the game lets you walk that it cuts, or a climb the game refuses
that it lets through.

## L1: parts (shipped; what A* walks)

Node = a **part**: within one 33-yd chunk (8x8 quads, 256 triangles), a set of standable triangles joined by
two-way fine moves (rules 1 and 2-both-ways) inside the chunk. At most 7 parts a chunk (0-based index p).
- class: 3 harmful if > 25% of its triangles are, else 2 water if > 50% deep, else 1 land.
- position: `centre` (the chunk's centre) if the part holds >= half the chunk's triangles; else its rep quad, the
  quad holding most of its triangles nearest its centroid, position = that quad's centre.
- node id = `gc * 8192 + gr * 8 + p` (gc, gr global chunk column, row = tile col,row * 16 + ix,iy).

Edges (directed; an edge u -> v means some fine move or descent gets you from u's triangles to v's):
- walk edges: a fine move 1/2 from a triangle of u to one of v; v in the same chunk or a 4-neighbour.
- drop edges: a descent (rule 3) from u landing in v; v anywhere (bounded flood, say within 3 chunks).
- Stored as relation bits where v is in the same chunk (intra) or the E/S/W/N neighbour; anything further is a
  **drop link** (a list per tile).
- Diagonals are derived, at bake and at runtime alike: u=(c,p) -> w=(c+(dx,dy),q) if some v in chunk c+(dx,0) has
  u->v and v->w, or some v in chunk c+(0,dy) does.
- cost(u -> v) = distance between their positions in chunks x COST[class v] (1 land, 3 water, 25 harmful). The
  heuristic is the straight distance, so it stays admissible.

Pruning: small dead-end parts (few triangles, <= 1 two-way neighbour) go; tiny
strongly connected components go too, **contracted** (u -> tiny -> v becomes u -> v) so reachability is kept.
Targets: regions per continent in the low thousands; sizes below.

### Data/Walk.lua (format 2) — kept readable by the old per-chunk readers
`D.Walk[inst][col*64+row]` = the tile's 256 chunks (iy*16+ix), a letter each, runs as letter+count (as today):
- lower case `'a' + value`: a **simple** chunk. value = class + 4 (two-way edge to the east chunk's one part)
  + 8 (same to the south). class 0: no parts. A simple chunk has exactly one part at `centre`, and its E and S
  relations are each "none" or "both ways to that neighbour's only part" (a neighbour with 0 parts: none).
- upper case `'A' + class of its biggest part`: a **complex** chunk; its record is in WalkParts.
So class-of-chunk readers (maplint, gen_labels, Walk.Cell) only learn: upper case means `ord - 65`.

### Data/WalkParts.lua (format 1)
`D.WalkParts[inst][key]` = the tile's complex chunks' records, concatenated in chunk order (iy*16+ix ascending).
Every char is `chr(48 + v)`, v in 0..63 (the writer escapes the backslash). A record:
1. `L` 2 chars (hi, lo; v = hi*64+lo): how many chars follow in this record.
2. `H1` = n + 8*nE; `H2` = nS. n parts here (1..7), nE / nS parts in the east / south chunk (0..7).
3. n x 2 chars: `P1` = qx + 8*qy (rep quad), `P2` = class + 4*centre (centre 1: position is the chunk's centre).
4. E relation: n*nE entries of 2 bits, entry (i, j) at index i*nE + j: bit 0 = part i -> east part j, bit 1 =
   east part j -> part i. Packed 3 entries a char, lowest first. ceil(n*nE/3) chars.
5. S relation: same, n*nS.
6. if n >= 2: intra, the n*(n-1) ordered pairs (i, j), i != j, in order i then j: 1 bit each (i -> j), 6 a char.
7. if n >= 2: the label map, 64 quads (qy*8+qx): which part a position in that quad snaps to (0 none, 1..n = part
   index + 1; the part holding most of the quad's standable triangles). Run-length: each char = label + 8*(run-1),
   run 1..8, until 64 quads are covered.
The W and N relations of a chunk are its west / north neighbour's E / S (letter or record).

`D.WalkDrops[inst][key]` (same file) = the tile's drop links, 8 chars each: `i_hi, i_lo` (chunk index in the tile),
`p + 8*dir`, then the other end `gc_hi, gc_lo, gr_hi, gr_lo` (global chunk), `q`. dir 0: (this chunk, p) -> other;
dir 1: other -> (this chunk, p). Every drop link is listed twice: in its source's tile (dir 0) and its target's (dir 1).

### Data/WalkRegions.lua (format 2) — from Walk.lua + WalkParts.lua + tools/walk_links.json, no game data
- `D.WalkLinks[inst] = { { ac, ar, ap, bc, br, bp, cost, name, oneway }, ... }`: hand links, node a <-> node b
  (a -> b only if oneway is true), cost in chunks (at least the straight distance between the two positions).
  walk_links.json: as today (`inst, name, a: [col,row], b: [col,row]`, optional `cost`), plus optional
  `"oneway": true`. Each end snaps to the part under that point, else the nearest part within 4 chunks.
- Region = strongly connected component of the L1 graph with the hand links, numbered by node count (1 biggest).
  `D.WalkRegions[inst][key]` = a number (every node of the tile is in that region; 0 if it has no nodes) or a
  string of `"<region>x<count>"` runs, comma separated, over the tile's **nodes** in order (chunk index, then part).
- `D.WalkReach[inst] = { hubs = H, up = { [r] = { h, ... } }, dn = { [r] = { h, ... } }, own = { [r] = { r2, ... } } }`:
  regions 1..H are hubs. up[r]: the other hubs r reaches. dn[r]: the hubs that reach r (other than r). own[r]: the
  non-hub regions r reaches without passing through a hub. Empty lists omitted.
  **a reaches b** iff a == b, or b in own[a], or some h in up[a] + (a if a <= H) has h == b or h in dn[b].

## L2: tile graph (shipped; HPA* over ADT tiles) — Data/WalkGraph.lua (format 1), same inputs as WalkRegions
Cluster = tile (16x16 chunks). An L2 node is an L1 node at a tile border (an entrance's representative) or a
cross-tile hand/drop link end.
`D.WalkGraph[inst][key] = { nodes, costs, cross }` (three strings, chars as WalkParts), for tiles with m >= 1 nodes, m <= 63:
- nodes: m x 3 chars: `i_hi, i_lo` (chunk index in the tile), `p`.
- costs: m x m x 2 chars (row a, column b): the cheapest L1 way a -> b **inside the tile** (same edges, diagonals
  and costs as the runtime's L1), in 1/8 chunks, rounded to nearest, capped at 4094; 4095 = none.
- cross: out-edges to other tiles, 6 chars each: `a`, `tkey_hi, tkey_lo` (the other tile's key), `b` (node index
  there), `cost_hi, cost_lo` (1/8 chunks). One-way; the way back is listed in the other tile.
Entrances: along each tile border group the crossing L1 edges into runs (same pair of tile-local strongly connected
components, neighbouring chunks), one representative per run, long runs (> 8 chunks) split. The graph must keep
L1's reachability: for every pair of tile-local components (A in one tile, B in the next) joined by any L1 edge
A -> B, at least one cross edge A -> B. The baker checks this and checks L2 reachability against the regions.

## Runtime API (atlas/Walk.lua, atlas/Route.lua)
- `Walk.CHUNKS` 16. `Walk.Snap(inst, col, row)` (tile coords, fractional) -> node id or nil: the part under the
  point (label map), else the nearest part by position within 4 chunks.
- `Walk.Pos(inst, id)` -> col, row (tile coords). `Walk.Class(inst, id)`. `Walk.Cell(inst, gc, gr)` -> the chunk's
  class (its biggest part's), and its part count.
- `Walk.Edges(inst, id, out, reverse)` -> n; `out[2k-1]` = neighbour id, `out[2k]` = cost. Walk, drop, diagonal and
  hand-link edges; reverse = the edges into id.
- `Walk.Region(inst, id)`, `Walk.Reach(inst, ra, rb)`, `Walk.Links(inst)`.
- `Route.Find(inst, c1, r1, s, g, c2, r2, yield, trace)` -> pts, partial, capped (s, g node ids from Snap).
  trace: `.closed` (L1 node ids closed, in order, every phase), `.nodes` (all nodes closed, L1 + L2), `.nodes2`
  (L2 nodes closed), `.raw` (the L1 node path), `.abstract` (the L2 path as L1 node ids, when the hierarchy ran),
  `.turns`, `.regions`, `.goal` (the node searched for instead), `.box`.
- Search: same or neighbouring tiles -> plain L1 A* (capped small); otherwise, or when that caps, L2: L1 Dijkstra
  from s inside its tile to the tile's L2 nodes, the same backwards from g, A* over L2, then each leg refined by
  L1 A* inside its tile. Then the line (below). Regions/Reach answer "no way" at once, with direction.

## Budgets
Walk + WalkParts <= ~2.0 MB, WalkRegions <= ~0.4 MB, WalkGraph <= ~0.6 MB (3 MB in all). Per-frame: the route
job's 1 ms slices hold (tools/tests/test_route.py: no resume over 1.1 ms), lazily decoded per tile.

## The rough mask: Data/WalkRough.lua (format 2), gen_walk_rough.py
Per quad (8x8 a chunk), from the same terrain: rough (a face over 50 degrees in it) and sheer (over 61.6: a cliff).
Each chunk is 24 chars: a 2-char index, 11 chars of rough bits, 11 of sheer bits. `Walk.RoughChunk(inst, gc, gr)`
-> (s, o); `Walk.RoughQuad(s, o, qx, qy)` (sheer bits at `o + 11`).

## The line (Route.Find, after the search)
1. Corners: the node path's corners kept where cutting them would leave the parts' ground.
2. Straighten: line of sight over the parts, then `Clear` over the rough mask: a sheer quad always stops it, rough
   ground only past `TUNE.slack` yd in a row (a rock, a bump).
3. Flush: where a leg still isn't clear, the cheapest way through ~4-yd cells in a corridor `TUNE.corridor` chunks
   either side (rough cells `TUNE.roughCost`, sheer only when nothing else will do), pulled straight. Its cells
   are numbered by their place in the run's box, in arrays filled at load and never emptied (a box up to 32768
   cells); a run drawn by the last Find is drawn the same (a re-route's far end is the last one's), not searched
   again. Riding away from the way: ~9 KB/s of garbage (tools/tests/test_route.py::test_route_stray).
4. Round: each corner cut back `TUNE.round` chunks and curved (`TUNE.roundSteps`); hand links' ends kept exact.
`Route.TUNE` and model/Route.lua's `FOLLOW` (how the line joins the way ahead of you, when it's found again) are
Settings > Route (ui/Path.lua).

Measure changes with `tools/walk_smooth.py` (the everyday line: turns, zigzags, knots over 163 seeded routes) and
`tools/walk_scorecard.py` (the hard cases: cliffs, lifts, bridges; demo/routes.html).
