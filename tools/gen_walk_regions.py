#!/usr/bin/env python3
"""Generate Data/WalkRegions.lua and Data/WalkGraph.lua from Data/Walk.lua, Data/WalkParts.lua and
tools/walk_links.json (no game data): the hand links, the regions (what a walk can join up), the region reach
table, and the tile graph the route search's long walks go over (walk v2: promo/pathing/walk-v2-spec.md; formats:
docs/atlas-data.md, tools/mmtools/walkdata.py).

  python3 tools/gen_walk_regions.py -o Data/WalkRegions.lua [--graph Data/WalkGraph.lua] [--check]

- Hand links (walk_links.json: {"inst", "name", "a": [col, row], "b": [col, row]}, optional "cost" in chunks and
  "oneway": true): each end snaps as Atlas.Walk.Snap (the part under the point, else the nearest within 4 chunks);
  the cost is at least the straight distance between the two parts.
- Regions: the strongly connected components of the parts graph with the hand links, numbered by node count (1 the
  biggest; ties by the lowest node id). Two parts in different regions: a walk from one reaches the other only if
  WalkReach says so (one-way drops), else not at all.
- WalkReach: regions 1..H are hubs (H chosen to keep the lists short); per region the hubs it reaches (up), the hubs
  that reach it (dn), and (non-hubs) the non-hubs it reaches without a hub between (own).
- WalkGraph: per ADT tile, its entrances (one part per run of crossing edges between the same two tile-local
  components, runs of at most 8 chunks), the cheapest walk inside the tile between each two, and the crossing
  edges to other tiles. --check compares its reach and costs with the parts graph's (random pairs; slow).

Output is deterministic: the same inputs always give the same files.
"""
from __future__ import annotations

import argparse
import heapq
import json
import math
import os
import random
import sys

import numpy as np

from mmtools import walkdata as wd
from mmtools.luaout import data_head
from mmtools.walkdata import CHUNKS, node_id, split_id

TOOLS = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(TOOLS)
RUN = 8           # chunks: an entrance run longer than this is split
MAX_L2 = 63       # L2 nodes a tile
CAP = 4094        # costs in 1/8 chunks; 4095 = none


def c64(x: int) -> str:
    assert 0 <= x < 64, x
    return chr(48 + x)


def lua_chars(s: str) -> str:
    return '"' + s.replace("\\", "\\\\") + '"'


def tkey(u: int) -> int:
    gc, gr, _ = split_id(u)
    return wd.tile_key(gc, gr)


def tindex(u: int) -> int:
    gc, gr, _ = split_id(u)
    return (gr % CHUNKS) * CHUNKS + gc % CHUNKS


# --- links, regions, reach ---------------------------------------------------------------------------------

def links_for(W: wd.Walk, inst: int, links: list[dict]) -> list[tuple]:
    """(a, b, cost, name, oneway) for the map's links, their ends snapped."""
    out = []
    for k in links:
        if k["inst"] != inst:
            continue
        ends = []
        for col, row in (k["a"], k["b"]):
            s = W.snap(col, row)
            if s is None:
                raise SystemExit(f"walk_links.json: {k['name']}: nowhere to stand near {col}, {row}")
            ends.append(s)
        a, b = ends
        ax, ay = W.pos_chunks(a)
        bx, by = W.pos_chunks(b)
        cost = round(max(k.get("cost", 0), math.hypot(bx - ax, by - ay)), 2)
        out.append((a, b, cost, k["name"], bool(k.get("oneway", False))))
    return out


def components(nodes: list[int], adj: dict) -> tuple[list[int], int]:
    ix = {v: i for i, v in enumerate(nodes)}
    start, flat = [0], []
    for u in nodes:
        flat += [ix[w] for w, _ in adj[u] if w in ix]
        start.append(len(flat))
    return wd.scc(len(nodes), start, flat)


def regions(nodes: list[int], adj: dict):
    """({node: region}, Tarjan's comp per node, {comp: region}): regions by size, 1 the biggest."""
    comp, k = components(nodes, adj)
    size = [0] * k
    low = [None] * k
    for u, c in zip(nodes, comp):
        size[c] += 1
        if low[c] is None or u < low[c]:
            low[c] = u
    order = sorted(range(k), key=lambda c: (-size[c], low[c]))
    num = {c: i + 1 for i, c in enumerate(order)}
    return {u: num[c] for u, c in zip(nodes, comp)}, comp, num


def reach_table(nodes, adj, comp, num):
    """WalkReach: {hubs, up, dn, own} with the H that keeps it smallest; and the full reach bitsets (checks)."""
    k = len(num)
    succ = [set() for _ in range(k)]
    cu = dict(zip(nodes, comp))
    for u in nodes:
        a = cu[u]
        for w, _ in adj[u]:
            b = cu.get(w)
            if b is not None and b != a:
                succ[a].add(b)
    # Tarjan numbers a component after everything it reaches: ascending = sinks first
    R = [0] * k
    for c in range(k):
        r = 1 << num[c]
        for d in succ[c]:
            r |= R[d]
        R[c] = r
    full = {num[c]: R[c] for c in range(k)}  # region -> bitset of regions it reaches (bit r)
    rsucc = {num[c]: sorted(num[d] for d in succ[c]) for c in range(k)}
    best = None
    for H in sorted({0, 1, 2, 3, 4, 6, 8, 12, 16, 24, 32, 48, 64, 96, 128, 192, 256, 384, 512}):
        if H > k:
            continue
        t = build_reach(H, k, full, rsucc, num, succ)
        n = sum(len(v) for part in ("up", "dn", "own") for v in t[part].values())
        if best is None or n < best[0]:
            best = (n, H, t)
    return best[2], full


def build_reach(H, k, full, rsucc, num, succ):
    hubs = range(1, H + 1)
    up = {r: [h for h in hubs if h != r and full[r] >> h & 1] for r in range(1, k + 1)}
    dn = {r: [h for h in hubs if h != r and full[h] >> r & 1] for r in range(1, k + 1)}
    # own: non-hubs reached through non-hubs only (regions in Tarjan order: sinks first)
    own_bits = {}
    for c in range(k):
        r = num[c]
        if r <= H:
            continue
        b = 1 << r
        for d in succ[c]:
            rd = num[d]
            if rd > H:
                b |= own_bits[rd]
        own_bits[r] = b
    own = {}
    for r, b in own_bits.items():
        b &= ~(1 << r)
        lst = []
        while b:
            low = b & -b
            lst.append(low.bit_length() - 1)
            b ^= low
        own[r] = lst
    return {"hubs": H, "up": {r: v for r, v in up.items() if v}, "dn": {r: v for r, v in dn.items() if v},
            "own": {r: v for r, v in own.items() if v}}


def encode_regions(reg: dict, tile_nodes: list[int]) -> str | int:
    vals = [reg[u] for u in tile_nodes]
    if not vals:
        return 0
    if all(x == vals[0] for x in vals):
        return vals[0]
    out, i = [], 0
    while i < len(vals):
        j = i
        while j < len(vals) and vals[j] == vals[i]:
            j += 1
        out.append(f"{vals[i]}x{j - i}" if j - i > 1 else str(vals[i]))
        i = j
    return ",".join(out)


# --- the tile graph ----------------------------------------------------------------------------------------

def inside(tile_nodes: list[int], adj: dict):
    """The tile's own edges: (index {node: i}, eu, ev, ew arrays)."""
    ix = {u: i for i, u in enumerate(tile_nodes)}
    eu, ev, ew = [], [], []
    for u in tile_nodes:
        for w, c in adj[u]:
            j = ix.get(w)
            if j is not None:
                eu.append(ix[u])
                ev.append(j)
                ew.append(c)
    return ix, np.array(eu, np.int64), np.array(ev, np.int64), np.array(ew, np.float64)


def multi_source(n: int, eu, ev, ew, sources: list[int]):
    """[len(sources), n] cheapest costs from each source over the edges (Bellman-Ford, vectorised)."""
    m = len(sources)
    dist = np.full((m, n), np.inf)
    dist[np.arange(m), sources] = 0.0
    if len(eu) == 0:
        return dist
    order = np.argsort(ev, kind="stable")
    eu, ev, ew = eu[order], ev[order], ew[order]
    tgt, starts = np.unique(ev, return_index=True)
    while True:
        cand = dist[:, eu] + ew
        best = np.minimum.reduceat(cand, starts, axis=1)
        cur = dist[:, tgt]
        better = best < cur - 1e-9
        if not better.any():
            return dist
        dist[:, tgt] = np.where(better, best, cur)


def tile_components(tile_nodes, eu, ev):
    """The tile's own strongly connected components: (comp per node, reach bitset per comp)."""
    adj = {i: [] for i in range(len(tile_nodes))}
    for a, b in zip(eu.tolist(), ev.tolist()):
        adj[a].append((b, 0))
    comp, k = components(list(range(len(tile_nodes))), adj)
    succ = [set() for _ in range(k)]
    for a, b in zip(eu.tolist(), ev.tolist()):
        if comp[a] != comp[b]:
            succ[comp[a]].add(comp[b])
    reach = [0] * k
    for c in range(k):  # sinks first
        r = 1 << c
        for d in succ[c]:
            r |= reach[d]
        reach[c] = r
    return comp, reach


def runs(edges, coarse: bool):
    """Edges (u, v, cost) of one group in runs: chunks next to each other (u's), at most RUN chunks a run."""
    if coarse:
        return [edges]
    cells = sorted({split_id(u)[:2] for u, _, _ in edges})
    parent = {c: c for c in cells}

    def find(c):
        while parent[c] != c:
            parent[c] = parent[parent[c]]
            c = parent[c]
        return c
    cs = set(cells)
    for x, y in cells:
        for dx in (-1, 0, 1):
            for dy in (-1, 0, 1):
                o = (x + dx, y + dy)
                if o in cs:
                    a, b = find((x, y)), find(o)
                    if a != b:
                        parent[max(a, b)] = min(a, b)
    groups: dict = {}
    for c in cells:
        groups.setdefault(find(c), []).append(c)
    out = []
    for root in sorted(groups):
        members = sorted(groups[root])
        for k in range(0, len(members), RUN):
            block = set(members[k:k + RUN])
            out.append([e for e in edges if split_id(e[0])[:2] in block])
    return out


def build_graph(W: wd.Walk, adj: dict):
    """{tile key: (nodes, costs, cross)} strings for WalkGraph, and the decoded form for the checks."""
    keys = sorted(W.walk)
    tnodes = {k: W.tile_nodes(k) for k in keys}
    tiles = {}
    for k in keys:
        ix, eu, ev, ew = inside(tnodes[k], adj)
        tiles[k] = (ix, eu, ev, ew, tile_components(tnodes[k], eu, ev))
    cross_edges: dict[tuple[int, int], list] = {}
    lo, _ = W._links()
    for k in keys:
        for u in tnodes[k]:
            # derived diagonals don't cross on their own: both their legs are stored edges, so the side tile's
            # entrances already carry them
            stored = set(W.rel_out(u)) | set(W.drop_out(u)) | {w for w, _ in lo.get(u, ())}
            for w, c in adj[u]:
                kw = tkey(w)
                if kw != k and w in stored:
                    cross_edges.setdefault((k, kw), []).append((u, w, c))
    coarse: set[int] = set()
    while True:
        l2 = {k: set() for k in keys}
        reps = []
        for (ka, kb) in sorted(cross_edges, key=lambda p: (min(p), max(p), p[0] > p[1])):
            es = cross_edges[(ka, kb)]
            (ca, ra), (cb, rb) = tiles[ka][4], tiles[kb][4]
            ia, ib = tiles[ka][0], tiles[kb][0]
            groups: dict = {}
            for u, w, c in es:
                groups.setdefault((ca[ia[u]], cb[ib[w]]), []).append((u, w, c))
            # a pair of components another kept pair already covers (x reaches x2 in its tile, y2 reaches y in its
            # own, x2 -> y2 kept) needs no entrance: what reaches what stays the same
            kept = []
            for g in sorted(groups, key=lambda g: (-len(groups[g]), g)):
                x, y = g
                if any(ra[x] >> x2 & 1 and rb[y2] >> y & 1 for x2, y2 in kept):
                    continue
                kept.append(g)
            for g in sorted(kept):
                for run in runs(groups[g], ka in coarse or kb in coarse):
                    run = sorted(run, key=lambda e: (split_id(e[0])[:2], e[0], e[1]))
                    # an entrance already there (either end) serves again; else the run's middle
                    mid = len(run) // 2
                    e = min(enumerate(run), key=lambda t: (-(t[1][0] in l2[ka]) - (t[1][1] in l2[kb]), abs(t[0] - mid), t[0]))[1]
                    reps.append((ka, kb, e))
                    l2[ka].add(e[0])
                    l2[kb].add(e[1])
        over = {k for k in keys if len(l2[k]) > MAX_L2} - coarse
        if not over:
            break
        coarse |= over
    still = [k for k in keys if len(l2[k]) > MAX_L2]
    if still:
        raise SystemExit(f"tiles with more than {MAX_L2} entrances even coarse: {still}")
    out, dec = {}, {}
    order = {k: sorted(l2[k], key=lambda u: (tindex(u), split_id(u)[2])) for k in keys}
    pos = {k: {u: i for i, u in enumerate(order[k])} for k in keys}
    for k in keys:
        nodes = order[k]
        if not nodes:
            continue
        ix, eu, ev, ew, _ = tiles[k]
        dist = multi_source(len(tnodes[k]), eu, ev, ew, [ix[u] for u in nodes])
        costs = [[min(CAP, int(round(dist[a, ix[b]] * 8))) if np.isfinite(dist[a, ix[b]]) else wd.NONE_COST
                  for b in nodes] for a in range(len(nodes))]
        cross = sorted((pos[ka][e[0]], kb, pos[kb][e[1]], min(CAP, int(round(e[2] * 8)))) for ka, kb, e in reps if ka == k)
        ns = "".join(c64(tindex(u) // 64) + c64(tindex(u) % 64) + c64(split_id(u)[2]) for u in nodes)
        cs = "".join(c64(x // 64) + c64(x % 64) for row in costs for x in row)
        xs = "".join(c64(a) + c64(kb // 64) + c64(kb % 64) + c64(b) + c64(c // 64) + c64(c % 64) for a, kb, b, c in cross)
        out[k] = (ns, cs, xs)
        dec[k] = (nodes, [[None if x == wd.NONE_COST else x for x in row] for row in costs], cross)
    return out, dec, len(coarse)


# --- checks ------------------------------------------------------------------------------------------------

def dijkstra(adj, s, allowed=None, targets=None):
    dist = {s: 0.0}
    pq = [(0.0, s)]
    left = set(targets) if targets else None
    while pq:
        d, u = heapq.heappop(pq)
        if d > dist[u]:
            continue
        if left is not None:
            left.discard(u)
            if not left:
                break
        for w, c in adj[u]:
            if allowed is not None and tkey(w) != allowed:
                continue
            nd = d + c
            if nd < dist.get(w, math.inf):
                dist[w] = nd
                heapq.heappush(pq, (nd, w))
    return dist


def l2_out(dec, n):
    k, i = n
    ns, costs, cross = dec[k]
    for j, c in enumerate(costs[i]):
        if j != i and c is not None:
            yield (k, j), c / 8
    for a, kb, b, c in cross:
        if a == i:
            yield (kb, b), c / 8


def l2_cost(adj, radj, dec, s, g):
    """The route search's long way: s to its tile's entrances inside the tile, over the tile graph, the
    entrances of g's tile to g inside it (or s to g inside one tile). inf: no way."""
    ks, kg = tkey(s), tkey(g)
    best = math.inf
    ds = dijkstra(adj, s, allowed=ks)
    if ks == kg and g in ds:
        best = ds[g]
    if ks not in dec or kg not in dec:
        return best
    dg = dijkstra(radj, g, allowed=kg)
    start = {(ks, i): ds[u] for i, u in enumerate(dec[ks][0]) if u in ds}
    goal = {(kg, i): dg[u] for i, u in enumerate(dec[kg][0]) if u in dg}
    dist = dict(start)
    pq = [(d, n) for n, d in start.items()]
    heapq.heapify(pq)
    while pq:
        d, n = heapq.heappop(pq)
        if d > dist[n] or d >= best:
            continue
        if n in goal:
            best = min(best, d + goal[n])
        for m, c in l2_out(dec, n):
            nd = d + c
            if nd < dist.get(m, math.inf):
                dist[m] = nd
                heapq.heappush(pq, (nd, m))
    return best


def reverse(adj, nodes):
    radj: dict[int, list] = {u: [] for u in nodes}
    for u in nodes:
        for w, c in adj[u]:
            radj[w].append((u, c))
    return radj


def check(W, adj, reg, reach, dec, nodes, rng, pairs=200, sources=20):
    """L2 reach == regions' reach on random pairs; L2 cost / L1 cost on random pairs (median, worst)."""
    radj = reverse(adj, nodes)

    def l2(s, g):
        return l2_cost(adj, radj, dec, s, g)

    agree = disagree = 0
    for _ in range(pairs):
        s, g = rng.choice(nodes), rng.choice(nodes)
        want = wd.reaches(reach, reg[s], reg[g])
        got = l2(s, g) < math.inf
        if want == got:
            agree += 1
        else:
            disagree += 1
    ratios = []
    main = [u for u in nodes if reg[u] == 1]
    for _ in range(sources):
        s = rng.choice(main)
        d = dijkstra(adj, s)
        for g in rng.sample(main, pairs // sources):
            if g in d and d[g] > 2:
                ratios.append(l2(s, g) / d[g])
    ratios.sort()
    return agree, disagree, ratios


# --- output ------------------------------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--walk", default=os.path.join(ROOT, "Data", "Walk.lua"))
    parser.add_argument("--parts", default=os.path.join(ROOT, "Data", "WalkParts.lua"))
    parser.add_argument("--links", default=os.path.join(TOOLS, "walk_links.json"))
    parser.add_argument("-o", "--output", required=True, help="Data/WalkRegions.lua")
    parser.add_argument("--graph", help="Data/WalkGraph.lua (default: next to --output)")
    parser.add_argument("--check", action="store_true", help="check the tile graph against the parts graph (slow)")
    ns = parser.parse_args()
    graph_path = ns.graph or os.path.join(os.path.dirname(ns.output), "WalkGraph.lua")
    maps = wd.load_walk(ns.walk, ns.parts)
    with open(ns.links, encoding="utf-8") as f:
        links = json.load(f)["links"]
    head = "-- GENERATED by tools/gen_walk_regions.py from Data/Walk.lua, Data/WalkParts.lua and tools/walk_links.json. Do not edit.\n"
    wl, wr, wreach, wg = [], [], [], []
    for inst, W in sorted(maps.items()):
        lk = links_for(W, inst, links)
        W.links = [(a, b, c, o) for a, b, c, _, o in lk]
        nodes = list(W.nodes())
        adj = W.adjacency()
        reg, comp, num = regions(nodes, adj)
        reach, full = reach_table(nodes, adj, comp, num)
        if lk:
            wl.append(f"  [{inst}] = {{\n")
            for a, b, c, nm, o in lk:
                (ac, ar, ap), (bc, br, bp) = split_id(a), split_id(b)
                wl.append(f"    {{ {ac}, {ar}, {ap}, {bc}, {br}, {bp}, {c:g}, {json.dumps(nm)}, {'true' if o else 'false'} }},\n")
            wl.append("  },\n")
        wr.append(f"  [{inst}] = {{\n")
        for key in sorted(W.walk):
            enc = encode_regions(reg, W.tile_nodes(key))
            wr.append(f"    [{key}] = {enc},\n" if isinstance(enc, int) else f"    [{key}] = \"{enc}\",\n")
        wr.append("  },\n")
        wreach.append(f"  [{inst}] = {{ hubs = {reach['hubs']},\n")
        for part in ("up", "dn", "own"):
            rows = reach[part]
            wreach.append(f"    {part} = {{\n")
            for r in sorted(rows):
                wreach.append(f"      [{r}] = {{ {', '.join(map(str, rows[r]))} }},\n")
            wreach.append("    },\n")
        wreach.append("  },\n")
        g, dec, coarse = build_graph(W, adj)
        wg.append(f"  [{inst}] = {{\n")
        for key in sorted(g):
            a, b, c = g[key]
            wg.append(f"    [{key}] = {{ {lua_chars(a)}, {lua_chars(b)}, {lua_chars(c)} }},\n")
        wg.append("  },\n")
        msg = (f"[{inst}] {len(nodes)} nodes, {len(lk)} links, {len(num)} regions (biggest {sum(1 for u in nodes if reg[u] == 1)}), "
               f"hubs {reach['hubs']}, L2 nodes {sum(len(d[0]) for d in dec.values())} in {len(dec)} tiles "
               f"(max {max((len(d[0]) for d in dec.values()), default=0)}, coarse {coarse})")
        print(msg, file=sys.stderr)
        # the reach rule against the full reach sets
        regs = sorted(full)
        rng = random.Random(inst)
        for _ in range(2000):
            a, b = rng.choice(regs), rng.choice(regs)
            assert wd.reaches(reach, a, b) == bool(full[a] >> b & 1), (inst, a, b)
        if ns.check:
            agree, disagree, ratios = check(W, adj, reg, reach, dec, nodes, rng)
            if ratios:
                print(f"  check: L2 reach agrees with regions on {agree} of {agree + disagree} pairs; L2/L1 cost on "
                      f"{len(ratios)} pairs: median {ratios[len(ratios) // 2]:.3f}, 90% {ratios[int(len(ratios) * .9)]:.3f}, "
                      f"worst {ratios[-1]:.3f}", file=sys.stderr)
            else:
                print(f"  check: L2 reach agrees with regions on {agree} of {agree + disagree} pairs", file=sys.stderr)
    with open(ns.output, "w", encoding="utf-8", newline="\n") as out:
        out.write(head)
        out.write("-- WalkLinks[inst] = { { ac, ar, ap, bc, br, bp, cost, name, oneway }, ... }: hand links, part (gc, gr, p) a to b\n")
        out.write("--   (and back unless oneway), cost in chunks. WalkRegions[inst][col * 64 + row] = the region of every part of the\n")
        out.write("--   tile (a number), or runs \"<region>x<count>\" over its parts in order (chunk iy * 16 + ix, then part).\n")
        out.write("-- WalkReach[inst] = { hubs = H, up, dn, own }: regions 1..H are hubs; a reaches b iff a == b, b in own[a], or some h\n")
        out.write("--   in up[a] (and a itself if a <= H) is b or in dn[b]. docs/atlas-data.md, tools/mmtools/walkdata.py\n")
        out.write(data_head("WalkRegions"))
        out.write("D.WalkLinks = {\n" + "".join(wl) + "}\n")
        out.write("D.WalkRegions = {\n" + "".join(wr) + "}\n")
        out.write("D.WalkReach = {\n" + "".join(wreach) + "}\n")
    with open(graph_path, "w", encoding="utf-8", newline="\n") as out:
        out.write(head)
        out.write("-- WalkGraph[inst][col * 64 + row] = { nodes, costs, cross }: the tile's entrances (3 chars each: chunk index hi, lo,\n")
        out.write("--   part), the cheapest walk inside the tile between each two (m x m, 2 chars, 1/8 chunks, 4095 none), the edges\n")
        out.write("--   to other tiles (6 chars: a, tile key hi, lo, b, cost hi, lo). Chars chr(48 + v). docs/atlas-data.md\n")
        out.write(data_head("WalkGraph"))
        out.write("D.WalkGraph = {\n" + "".join(wg) + "}\n")


if __name__ == "__main__":
    main()
