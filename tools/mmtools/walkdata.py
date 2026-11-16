"""The walk data as shipped (Data/Walk.lua, WalkParts.lua, WalkRegions.lua, WalkGraph.lua), read back in plain
Python: the reference reader the generators, the tests, the sweep and the Lua side (atlas/Walk.lua, Route.lua)
agree with. The contract: promo/pathing/walk-v2-spec.md; the formats: docs/atlas-data.md.

Readings this module fixes where the spec leaves a choice (the Lua reader does the same):

- Node id = gc * 8192 + gr * 8 + p (gc, gr global chunk, p the part, 0 = the chunk's biggest).
- A simple chunk's (Walk.lua lower case, class > 0) one part covers the whole chunk for Snap, and so does a
  complex chunk's with n = 1 (it has no label map).
- A part's position, in chunks: the chunk's centre (gc + 0.5, gr + 0.5) when `centre`, else its rep quad's centre
  (gc + (qx + 0.5) / 8, gr + (qy + 0.5) / 8). Tile coords = chunks / 16.
- Snap(col, row): the chunk (floor(col * 16), floor(row * 16)); if it has parts: n = 1, part 0; else the label
  map's part at the quad (floor of the eighths), if not 0. Otherwise the nearest part by position (squared
  distance in chunks) over the chunks dc, dr in -4..4 (a 9x9 window, not a radius), visited gr ascending, then gc
  ascending, then p; the first of equals wins. Nothing there: None.
- Edges out of u = (c, i), in this order: intra (i -> j, j ascending), east, south, west, north (each: the
  neighbour's parts ascending), the tile's drop links (as listed), the derived diagonals (in DIAGS' order: (+1,+1),
  (+1,-1), (-1,+1), (-1,-1); each its targets ascending), then hand links (WalkLinks order). A target reached two
  ways is listed once, at the first (so a hand link to a node u already has an edge to is dropped).
- Derived diagonal u -> w (w in chunk c + (dx, dy)): some v in chunk c + (dx, 0) with u -> v and v -> w stored
  (relation bits, not drop links), or some v in c + (0, dy). Only the 4-neighbour relation edges count as
  the two legs (not drop links, not other diagonals, not hand links).
- cost(u -> v) = the distance between their positions, in chunks, x COST[class of v]; hand links their own cost.
- WalkReach: own[r] is listed for non-hub regions only (a hub's own reach is through itself: up/dn).
- WalkGraph costs: 1/8 chunks, rounded to nearest (round half to even, Python's round), capped at 4094;
  4095 none. The diagonal entry (a -> a) is 0.
"""
from __future__ import annotations

import math
import re

CHUNKS = 16
COST = {1: 1.0, 2: 3.0, 3: 25.0}
SNAP = 4
DIAGS = ((1, 1), (1, -1), (-1, 1), (-1, -1))  # (dx, dy)
NONE_COST = 4095


def node_id(gc: int, gr: int, p: int) -> int:
    return gc * 8192 + gr * 8 + p


def split_id(i: int) -> tuple[int, int, int]:
    return i // 8192, (i // 8) % 1024, i % 8


def tile_key(gc: int, gr: int) -> int:
    return (gc // CHUNKS) * 64 + gr // CHUNKS


def v(ch: str) -> int:
    return ord(ch) - 48


# --- reading the Lua files ----------------------------------------------------------------------------------

def read_tables(path: str) -> dict[str, dict[int, dict[int, object]]]:
    """{name: {inst: {key: value}}} for each `D.<name> = {` table of a generated Data file whose entries are
    `[key] = "string",` or `[key] = number,` lines under `[inst] = {` lines (the walk files' shape)."""
    out: dict[str, dict] = {}
    name = inst = None
    with open(path, encoding="utf-8") as f:
        for line in f:
            m = re.match(r"D\.(\w+) = \{", line)
            if m:
                name, inst = m.group(1), None
                out[name] = {}
                continue
            m = re.match(r"  \[(\d+)\] = \{", line)
            if m and name:
                inst = int(m.group(1))
                out[name][inst] = {}
                continue
            m = re.match(r'    \[(\d+)\] = "((?:[^"\\]|\\.)*)",', line)
            if m and inst is not None:
                out[name][inst][int(m.group(1))] = m.group(2).replace("\\\\", "\\")
                continue
            m = re.match(r"    \[(\d+)\] = (\d+),", line)
            if m and inst is not None:
                out[name][inst][int(m.group(1))] = int(m.group(2))
    return out


def scc(n, start, adj):
    """Strongly connected components of the graph with nodes 0..n-1 and out-edges adj[start[u]:start[u+1]]
    (iterative Tarjan). Returns (comp, count): comp[u] in 0..count-1, numbered in the order Tarjan closes them
    (a component closes after every component it reaches: reverse topological order)."""
    index = [-1] * n
    low = [0] * n
    comp = [-1] * n
    on = [False] * n
    stack = []
    count = 0
    counter = 0
    for root in range(n):
        if index[root] >= 0:
            continue
        work = [(root, start[root])]
        index[root] = low[root] = counter
        counter += 1
        stack.append(root)
        on[root] = True
        while work:
            u, i = work[-1]
            end = start[u + 1]
            pushed = False
            while i < end:
                w = adj[i]
                i += 1
                if index[w] < 0:
                    work[-1] = (u, i)
                    index[w] = low[w] = counter
                    counter += 1
                    stack.append(w)
                    on[w] = True
                    work.append((w, start[w]))
                    pushed = True
                    break
                if on[w] and index[w] < low[u]:
                    low[u] = index[w]
            if pushed:
                continue
            work.pop()
            if low[u] == index[u]:
                while True:
                    w = stack.pop()
                    on[w] = False
                    comp[w] = count
                    if w == u:
                        break
                count += 1
            if work:
                p = work[-1][0]
                if low[u] < low[p]:
                    low[p] = low[u]
    return comp, count


# --- L1 -------------------------------------------------------------------------------------------------------

class Chunk:
    """A chunk decoded: parts [(cls, centre, rep)], E and S relations [i][j] (2 bits: 1 i -> j, 2 j -> i),
    intra {(i, j)}, labels (64, or None)."""
    __slots__ = ("parts", "E", "S", "intra", "labels", "simple")

    def __init__(self):
        self.parts, self.E, self.S, self.intra, self.labels, self.simple = [], None, None, set(), None, True


def decode_letters(enc: str) -> list[str]:
    out = []
    for letter, n in re.findall(r"([a-zA-Z])(\d*)", enc):
        out += [letter] * int(n or 1)
    assert len(out) == 256, len(out)
    return out


def decode_tile(letters: str, parts: str | None) -> list[Chunk]:
    """The tile's 256 chunks (iy * 16 + ix) from its Walk.lua letters and WalkParts.lua records."""
    out = []
    pos = 0
    for letter in decode_letters(letters):
        c = Chunk()
        if letter.islower():
            val = ord(letter) - 97
            cls = val & 3
            if cls:
                c.parts = [(cls, True, 0)]
            c.E, c.S = val & 4, val & 8  # simple: "both ways to that neighbour's only part"
        else:
            c.simple = False
            L = v(parts[pos]) * 64 + v(parts[pos + 1])
            rec = parts[pos + 2:pos + 2 + L]
            pos += 2 + L
            k = 0
            h1, h2 = v(rec[0]), v(rec[1])
            n, nE, nS = h1 % 8, h1 // 8, h2
            k = 2
            for _ in range(n):
                rep, b = v(rec[k]), v(rec[k + 1])
                c.parts.append((b % 4, b // 4 == 1, rep))
                k += 2
            for m, attr in ((nE, "E"), (nS, "S")):
                cnt = n * m
                bits = []
                for _ in range((cnt + 2) // 3):
                    x = v(rec[k])
                    k += 1
                    bits += [x & 3, (x >> 2) & 3, (x >> 4) & 3]
                setattr(c, attr, [[bits[i * m + j] for j in range(m)] for i in range(n)])
            if n >= 2:
                pairs = [(i, j) for i in range(n) for j in range(n) if i != j]
                bits = []
                for _ in range((len(pairs) + 5) // 6):
                    x = v(rec[k])
                    k += 1
                    bits += [(x >> s) & 1 for s in range(6)]
                c.intra = {pairs[t] for t in range(len(pairs)) if bits[t]}
                lab = []
                while len(lab) < 64:
                    x = v(rec[k])
                    k += 1
                    lab += [x % 8] * (x // 8 + 1)
                assert len(lab) == 64
                c.labels = lab
            assert k == L, (k, L)
        out.append(c)
    assert parts is None or pos == len(parts), (pos, len(parts or ""))
    return out


class Walk:
    """One map's L1 graph, from Data/Walk.lua + Data/WalkParts.lua (D.Walk[inst], D.WalkParts[inst],
    D.WalkDrops[inst]), decoded lazily per tile."""

    def __init__(self, walk: dict[int, str], parts: dict[int, str] | None = None, drops: dict[int, str] | None = None,
                 links=None):
        self.walk, self.partstr, self.dropstr = walk, parts or {}, drops or {}
        self._tiles: dict[int, list | None] = {}
        self._drops: dict[int, tuple] = {}
        self.links = links or []  # [(a, b, cost, oneway)], node ids (WalkRegions' hand links)
        self._lk_out: dict[int, list] | None = None
        self._lk_in: dict[int, list] | None = None

    # chunks and parts
    def tile(self, key: int):
        t = self._tiles.get(key, 0)
        if t == 0:
            enc = self.walk.get(key)
            t = decode_tile(enc, self.partstr.get(key)) if enc is not None else None
            self._tiles[key] = t
        return t

    def chunk(self, gc: int, gr: int) -> Chunk | None:
        if gc < 0 or gr < 0:
            return None
        t = self.tile(tile_key(gc, gr))
        return t[(gr % CHUNKS) * CHUNKS + gc % CHUNKS] if t else None

    def parts(self, gc: int, gr: int) -> list:
        c = self.chunk(gc, gr)
        return c.parts if c else []

    def nodes(self):
        """Every node id, tile by tile (key order), in the tile's chunk order, then part."""
        for key in sorted(self.walk):
            t = self.tile(key)
            col, row = key // 64, key % 64
            for i, c in enumerate(t):
                for p in range(len(c.parts)):
                    yield node_id(col * CHUNKS + i % CHUNKS, row * CHUNKS + i // CHUNKS, p)

    def tile_nodes(self, key: int) -> list[int]:
        t = self.tile(key)
        if not t:
            return []
        col, row = key // 64, key % 64
        return [node_id(col * CHUNKS + i % CHUNKS, row * CHUNKS + i // CHUNKS, p)
                for i, c in enumerate(t) for p in range(len(c.parts))]

    def part(self, i: int):
        gc, gr, p = split_id(i)
        ps = self.parts(gc, gr)
        return ps[p] if p < len(ps) else None

    def pos_chunks(self, i: int) -> tuple[float, float]:
        gc, gr, p = split_id(i)
        cls, centre, rep = self.parts(gc, gr)[p]
        if centre:
            return gc + 0.5, gr + 0.5
        return gc + (rep % 8 + 0.5) / 8, gr + (rep // 8 + 0.5) / 8

    def pos(self, i: int) -> tuple[float, float]:
        x, y = self.pos_chunks(i)
        return x / CHUNKS, y / CHUNKS

    def cls(self, i: int) -> int:
        gc, gr, p = split_id(i)
        return self.parts(gc, gr)[p][0]

    def cell(self, gc: int, gr: int) -> tuple[int, int]:
        """(class of the chunk's biggest part, part count)."""
        ps = self.parts(gc, gr)
        return (ps[0][0] if ps else 0), len(ps)

    def cost(self, a: int, b: int) -> float:
        ax, ay = self.pos_chunks(a)
        bx, by = self.pos_chunks(b)
        return math.hypot(bx - ax, by - ay) * COST[self.cls(b)]

    # stored edges
    def _rel(self, gc, gr, attr, i, other_n):
        """Pairs (j, bits) of chunk (gc, gr)'s E or S relation for its part i."""
        c = self.chunk(gc, gr)
        if not c or not c.parts:
            return []
        if c.simple:
            return [(0, 3)] if getattr(c, attr) and other_n == 1 else []
        return [(j, b) for j, b in enumerate(getattr(c, attr)[i]) if b]

    def _rel_in(self, gc, gr, attr, j):
        """Pairs (i, bits) of chunk (gc, gr)'s E or S relation towards the other chunk's part j."""
        c = self.chunk(gc, gr)
        if not c or not c.parts:
            return []
        if c.simple:
            return [(0, 3)] if getattr(c, attr) and j == 0 else []
        return [(i, row[j]) for i, row in enumerate(getattr(c, attr)) if j < len(row) and row[j]]

    def rel_out(self, u: int) -> list[int]:
        """u's stored edges to its own chunk and the 4 neighbours (intra, E, S, W, N)."""
        gc, gr, i = split_id(u)
        c = self.chunk(gc, gr)
        if not c or i >= len(c.parts):
            return []
        out = [node_id(gc, gr, j) for j in range(len(c.parts)) if (i, j) in c.intra]
        out += [node_id(gc + 1, gr, j) for j, b in self._rel(gc, gr, "E", i, len(self.parts(gc + 1, gr))) if b & 1]
        out += [node_id(gc, gr + 1, j) for j, b in self._rel(gc, gr, "S", i, len(self.parts(gc, gr + 1))) if b & 1]
        out += [node_id(gc - 1, gr, j) for j, b in self._rel_in(gc - 1, gr, "E", i) if b & 2]
        out += [node_id(gc, gr - 1, j) for j, b in self._rel_in(gc, gr - 1, "S", i) if b & 2]
        return out

    def rel_in(self, u: int) -> list[int]:
        gc, gr, i = split_id(u)
        c = self.chunk(gc, gr)
        if not c or i >= len(c.parts):
            return []
        out = [node_id(gc, gr, j) for j in range(len(c.parts)) if (j, i) in c.intra]
        out += [node_id(gc + 1, gr, j) for j, b in self._rel(gc, gr, "E", i, len(self.parts(gc + 1, gr))) if b & 2]
        out += [node_id(gc, gr + 1, j) for j, b in self._rel(gc, gr, "S", i, len(self.parts(gc, gr + 1))) if b & 2]
        out += [node_id(gc - 1, gr, j) for j, b in self._rel_in(gc - 1, gr, "E", i) if b & 1]
        out += [node_id(gc, gr - 1, j) for j, b in self._rel_in(gc, gr - 1, "S", i) if b & 1]
        return out

    def drops(self, key: int) -> tuple[dict, dict]:
        """The tile's drop links: ({u: [v, ...]} out of its nodes, {u: [v, ...]} into them)."""
        d = self._drops.get(key)
        if d is None:
            s = self.dropstr.get(key, "")
            col, row = key // 64, key % 64
            outs, ins = {}, {}
            for k in range(0, len(s), 8):
                e = [v(ch) for ch in s[k:k + 8]]
                i = e[0] * 64 + e[1]
                p, d_ = e[2] % 8, e[2] // 8
                here = node_id(col * CHUNKS + i % CHUNKS, row * CHUNKS + i // CHUNKS, p)
                other = node_id(e[3] * 64 + e[4], e[5] * 64 + e[6], e[7])
                (outs if d_ == 0 else ins).setdefault(here, []).append(other)
            d = (outs, ins)
            self._drops[key] = d
        return d

    def drop_out(self, u: int) -> list[int]:
        gc, gr, _ = split_id(u)
        return self.drops(tile_key(gc, gr))[0].get(u, [])

    def drop_in(self, u: int) -> list[int]:
        gc, gr, _ = split_id(u)
        return self.drops(tile_key(gc, gr))[1].get(u, [])

    def stored_out(self, u: int) -> list[int]:
        return self.rel_out(u) + self.drop_out(u)

    def diag_out(self, u: int) -> list[int]:
        gc, gr, _ = split_id(u)
        rel = self.rel_out(u)
        out = []
        for dx, dy in DIAGS:
            got = []
            for v_ in rel:
                vc, vr, _ = split_id(v_)
                if (vc, vr) in ((gc + dx, gr), (gc, gr + dy)):
                    for w in self.rel_out(v_):
                        wc, wr, _ = split_id(w)
                        if (wc, wr) == (gc + dx, gr + dy) and w not in got:
                            got.append(w)
            out += sorted(got)
        return out

    def diag_in(self, u: int) -> list[int]:
        gc, gr, _ = split_id(u)
        rel = self.rel_in(u)
        out = []
        for dx, dy in DIAGS:
            got = []
            for v_ in rel:
                vc, vr, _ = split_id(v_)
                if (vc, vr) in ((gc + dx, gr), (gc, gr + dy)):
                    for w in self.rel_in(v_):
                        wc, wr, _ = split_id(w)
                        if (wc, wr) == (gc + dx, gr + dy) and w not in got:
                            got.append(w)
            out += sorted(got)
        return out

    def _links(self):
        if self._lk_out is None:
            self._lk_out, self._lk_in = {}, {}
            for a, b, cost, oneway in self.links:
                self._lk_out.setdefault(a, []).append((b, cost))
                self._lk_in.setdefault(b, []).append((a, cost))
                if not oneway:
                    self._lk_out.setdefault(b, []).append((a, cost))
                    self._lk_in.setdefault(a, []).append((b, cost))
        return self._lk_out, self._lk_in

    def edges(self, u: int, reverse: bool = False) -> list[tuple[int, float]]:
        """[(neighbour, cost)]: walk, drop, diagonal and hand-link edges out of u (reverse: into u; the cost is
        still that of the edge, neighbour -> u)."""
        if reverse:
            ns = self.rel_in(u) + self.drop_in(u) + self.diag_in(u)
        else:
            ns = self.rel_out(u) + self.drop_out(u) + self.diag_out(u)
        return self._finish(u, ns, reverse)

    def _finish(self, u, ns, reverse):
        out, seen = [], set()
        for w in ns:
            if w not in seen and w != u:
                seen.add(w)
                out.append((w, self.cost(w, u) if reverse else self.cost(u, w)))
        lo, li = self._links()
        for w, cost in (li if reverse else lo).get(u, ()):
            if w not in seen and w != u:
                seen.add(w)
                out.append((w, cost))
        return out

    def adjacency(self) -> dict[int, list[tuple[int, float]]]:
        """{u: edges(u)} for every node, at once (the same lists, faster than one by one)."""
        nodes = list(self.nodes())
        rel = {u: self.rel_out(u) for u in nodes}
        out = {}
        for u in nodes:
            gc, gr, _ = split_id(u)
            ru = rel[u]
            diag = []
            for dx, dy in DIAGS:
                got = []
                for v_ in ru:
                    vc, vr, _ = split_id(v_)
                    if (vc, vr) in ((gc + dx, gr), (gc, gr + dy)):
                        for w in rel.get(v_, ()):
                            wc, wr, _ = split_id(w)
                            if (wc, wr) == (gc + dx, gr + dy) and w not in got:
                                got.append(w)
                diag += sorted(got)
            out[u] = self._finish(u, ru + self.drop_out(u) + diag, False)
        return out

    # snapping
    def snap(self, col: float, row: float) -> int | None:
        x, y = col * CHUNKS, row * CHUNKS
        gc, gr = math.floor(x), math.floor(y)
        c = self.chunk(gc, gr)
        if c and c.parts:
            if len(c.parts) == 1:
                return node_id(gc, gr, 0)
            qx, qy = min(7, int((x - gc) * 8)), min(7, int((y - gr) * 8))
            lab = c.labels[qy * 8 + qx]
            if lab:
                return node_id(gc, gr, lab - 1)
        best = None
        for r in range(gr - SNAP, gr + SNAP + 1):
            for cc in range(gc - SNAP, gc + SNAP + 1):
                for p in range(len(self.parts(cc, r))):
                    i = node_id(cc, r, p)
                    px, py = self.pos_chunks(i)
                    d = (px - x) ** 2 + (py - y) ** 2
                    if best is None or d < best[0]:
                        best = (d, i)
        return best[1] if best else None


def load_walk(walk_path: str, parts_path: str) -> dict[int, Walk]:
    """{inst: Walk} from Data/Walk.lua and Data/WalkParts.lua."""
    w = read_tables(walk_path)["Walk"]
    p = read_tables(parts_path)
    return {inst: Walk(tiles, p.get("WalkParts", {}).get(inst), p.get("WalkDrops", {}).get(inst)) for inst, tiles in w.items()}


# --- regions, reach, the tile graph ----------------------------------------------------------------------

def decode_regions(enc) -> list[int] | int:
    """A tile's WalkRegions entry: a number (every node), or the per-node list."""
    if isinstance(enc, int):
        return enc
    out = []
    for part in enc.split(","):
        r, _, n = part.partition("x")
        out += [int(r)] * int(n or 1)
    return out


def reaches(reach: dict, a: int, b: int) -> bool:
    """WalkReach's rule: a reaches b."""
    if a == b:
        return True
    H = reach["hubs"]
    if b in reach["own"].get(a, ()):
        return True
    dn = reach["dn"].get(b, ())
    for h in list(reach["up"].get(a, ())) + ([a] if a <= H else []):
        if h == b or h in dn:
            return True
    return False


def decode_graph(entry: tuple[str, str, str]) -> tuple[list, list, list]:
    """A tile's WalkGraph entry: (nodes [(chunk index, p)], costs [a][b] in 1/8 chunks or None,
    cross [(a, tile key, b, cost in 1/8 chunks)])."""
    ns, cs, xs = entry
    nodes = [(v(ns[k]) * 64 + v(ns[k + 1]), v(ns[k + 2])) for k in range(0, len(ns), 3)]
    m = len(nodes)
    costs = [[None] * m for _ in range(m)]
    for a in range(m):
        for b in range(m):
            k = (a * m + b) * 2
            c = v(cs[k]) * 64 + v(cs[k + 1])
            costs[a][b] = None if c == NONE_COST else c
    cross = []
    for k in range(0, len(xs), 6):
        e = [v(ch) for ch in xs[k:k + 6]]
        cross.append((e[0], e[1] * 64 + e[2], e[3], e[4] * 64 + e[5]))
    return nodes, costs, cross
