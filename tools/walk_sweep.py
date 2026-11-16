"""Walk sweep: the route search measured on fixed named cases (tools/walk_cases.json) and seeded random pairs per
zone, on two walks side by side: "31", main's walk at git 5eedf63 (atlas/Walk.lua, atlas/Route.lua, Data/Walk.lua,
Data/WalkRegions.lua from demo/walk31/ if there, else `git show`), and "2", the tree's atlas as it stands (walk v2
per promo/pathing/walk-v2-spec.md once it lands; until then it is 3.1 too, and says so).

Per case and side: class (found / partial / none / capped / nosnap / error), route length (yd) and length over
straight, nodes closed, ms (Find run whole, no yield), and from the real terrain (the baker's fine cache,
<scratch>/walkfine/fine_<inst>.npz, if there): climb, the longest continuous uphill (yd) on faces over 50 degrees
(steep if > 2 yd), and wall, the yards on faces over 61.6 degrees or holes. Water and magma don't count; nor do the
yards near a hand link (a tunnel, a lift, a bridge: the line drawn there isn't on the ground).

  python tools/walk_sweep.py                       # both sides, cases + 6 random pairs a zone, seed 7
  python tools/walk_sweep.py --side 31 --json out.json
  python tools/walk_sweep.py --cases-only --inst 1
  python tools/walk_sweep.py --random 3 --seed 11
  python tools/walk_sweep.py --selfcheck           # the terrain walker on a made-up cliff and ramp
"""
from __future__ import annotations

import argparse
import json
import math
import os
import random
import statistics
import subprocess
import sys
import time

import numpy as np
from lupa import lua51

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRATCH = "/private/tmp/claude-501/-Users-benmills-code-magic-map/79566c4f-2f3a-40f6-8483-218c9c616ca1/scratchpad"
FINE = os.environ.get("WALK_FINE", os.path.join(SCRATCH, "walkfine"))
CASES = os.path.join(ROOT, "tools", "walk_cases.json")
REV31 = "5eedf63"
FROZEN = ["atlas/Walk.lua", "atlas/Route.lua", "Data/Walk.lua", "Data/WalkRegions.lua"]
SKIP = {"Data/Npcs.lua", "Data/Objects.lua", "Data/Items.lua", "Data/Quests.lua", "Data/ItemIcons.lua"}  # (not needed)

TILE_YD = 1600 / 3            # a tile's side in yards
QUAD_YD = TILE_YD / 128       # a quad's (100/3/8)
STEEP, WALL = 50.0, 61.6      # degrees
CLIMB_FLAG = 2.0              # yd climbed on steep faces that makes a route "steep"
LINK_CLEAR = 1.5 / 16         # tiles round a hand link where the terrain isn't measured
CLASSES = ["found", "partial", "none", "capped", "nosnap", "timeout", "error"]
SIDE_COLS = ["class", "len_yd", "ratio", "nodes", "ms", "climb_yd", "wall_yd", "ok", "climb_at"]


# ---------------------------------------------------------------------------------------------------- runtimes

def git_show(path: str) -> bytes:
    return subprocess.run(["git", "show", f"{REV31}:{path}"], cwd=ROOT, check=True, capture_output=True).stdout


def frozen31(rel: str) -> bytes:
    """main's copy of rel: demo/walk31/<rel> if the demo's frozen copy is there, else git show (cached)."""
    p = os.path.join(ROOT, "demo", "walk31", rel)
    if os.path.exists(p):
        with open(p, "rb") as f:
            return f.read()
    cache = os.path.join(SCRATCH, "sweep", "walk31", rel)
    if not os.path.exists(cache):
        os.makedirs(os.path.dirname(cache), exist_ok=True)
        with open(cache, "wb") as f:
            f.write(git_show(rel))
    with open(cache, "rb") as f:
        return f.read()


def load_runtime(which: str):
    """(L, Atlas) for side "31" (main's walk on the tree's atlas) or "2" (the tree as it is)."""
    L = lua51.LuaRuntime(unpack_returned_tuples=True)
    load = L.eval("function(src, name) local f, err = loadstring(src, name) if not f then error(err) end return f end")
    ns = L.table()
    if which == "31":
        listing = git_show("atlas/files.txt").decode()
    else:
        with open(os.path.join(ROOT, "atlas", "files.txt"), encoding="utf-8") as f:
            listing = f.read()
    for rel in [x.strip() for x in listing.splitlines() if x.strip() and not x.startswith("#")]:
        if rel in SKIP:
            continue
        if which == "31" and rel in FROZEN:
            src = frozen31(rel)
        else:
            path = os.path.join(ROOT, rel)
            if not os.path.exists(path):
                if rel.startswith("Data/"):
                    continue
                raise FileNotFoundError(path)
            with open(path, "rb") as f:
                src = f.read()
        load(src, "@" + rel)("MagicMap", ns)
    return L, ns.Atlas


# A tile's 256 chunk classes (iy*16+ix) as a string of digits, and its 256 zone ids: scanned in Lua (fast).
SCAN = """
local Atlas = ...
return function(inst, key)
  local tc, tr = math.floor(key / 64), key % 64
  local cls, zones = {}, {}
  for iy = 0, 15 do for ix = 0, 15 do
    local gc, gr = tc * 16 + ix, tr * 16 + iy
    cls[#cls + 1] = tostring((Atlas.Walk.Cell(inst, gc, gr)) or 0)
    local id = Atlas.AreaAt and Atlas.AreaAt(inst, (gc + 0.5) / 16, (gr + 0.5) / 16)
    local a = id and Atlas.Area(id)
    zones[#zones + 1] = a and a.zone or 0
  end end
  return table.concat(cls), zones
end
"""

# A Find that runs past its deadline errors out (a count hook: a hung search in a half-written walk can't stall
# the sweep). deadline(seconds) arms it, deadline(nil) disarms.
DEADLINE = """
local limit
debug.sethook(function()
  if limit and os.clock() > limit then limit = nil; error("sweep timeout", 2) end
end, "", 100000)
return function(sec) limit = sec and os.clock() + sec or nil end
"""


def hand_links():
    """{inst: [((ac, ar), (bc, br))]}: the hand links (tunnels, lifts, bridges) of both trees, tile coords."""
    out = {}
    srcs = [git_show("tools/walk_links.json")]
    p = os.path.join(ROOT, "tools", "walk_links.json")
    if os.path.exists(p):
        with open(p, "rb") as f:
            srcs.append(f.read())
    for src in srcs:
        try:
            for k in json.loads(src)["links"]:
                seg = (tuple(k["a"]), tuple(k["b"]))
                if seg not in out.setdefault(k["inst"], []):
                    out[k["inst"]].append(seg)
        except (ValueError, KeyError):
            pass
    return out


class Side:
    """One walk: Snap, Find, Cell, whichever API it has (v2: Atlas.Walk.Pos exists)."""

    def __init__(self, name: str):
        self.name = name
        self.L, self.A = load_runtime(name)
        self.W, self.R = self.A.Walk, self.A.Route
        self.v2 = self.W.Pos is not None
        self.api = "v2" if self.v2 else "3.1"
        self.scan = self.L.execute(SCAN, self.A)
        self.deadline = self.L.execute(DEADLINE)

    def snap(self, inst, col, row):
        if self.v2:
            return self.W.Snap(inst, col, row)
        sc, sr = self.W.Snap(inst, math.floor(col * 16), math.floor(row * 16))
        return None if sc is None else (sc, sr)

    def land(self, inst, col, row) -> bool:
        k = self.W.Cell(inst, math.floor(col * 16), math.floor(row * 16))
        k = k[0] if isinstance(k, tuple) else k
        if k != 1:
            return False
        return not self.v2 or self.snap(inst, col, row) is not None

    def find(self, inst, a, b, timeout=None) -> dict:
        try:
            s = self.snap(inst, *a)
            g = self.snap(inst, *b)
        except Exception as e:  # (the tree mid-rewrite)
            return {"class": "error", "error": str(e)[:200]}
        if s is None or g is None:
            return {"class": "nosnap"}
        tr = self.L.table()
        t = time.perf_counter()
        self.deadline(timeout)
        try:
            if self.v2:
                res = self.R.Find(inst, a[0], a[1], s, g, b[0], b[1], None, tr)
            else:
                res = self.R.Find(inst, a[0], a[1], s[0], s[1], g[0], g[1], b[0], b[1], None, tr)
        except Exception as e:  # (the tree mid-rewrite, or past the deadline)
            self.deadline(None)
            msg = str(e)
            return {"class": "timeout" if "sweep timeout" in msg else "error", "error": msg[:200],
                    "ms": (time.perf_counter() - t) * 1000}
        self.deadline(None)
        ms = (time.perf_counter() - t) * 1000
        pts, partial, capped = ((tuple(res) if isinstance(res, tuple) else (res,)) + (None, None, None))[:3]
        nodes = tr.nodes or 0
        line = [(p.col, p.row) for p in pts.values()] if pts else []
        cls = "capped" if capped else ("none" if not line else ("partial" if partial else "found"))
        end = None   # where the walk stops short of the goal: its last turn
        turns = tr.turns
        if line and (partial or capped) and turns is not None and len(turns) > 0:
            last = turns[len(turns)]
            if self.v2:
                end = tuple(self.W.Pos(inst, last))
            else:
                end = ((last // 1024 + 0.5) / 16, (last % 1024 + 0.5) / 16)
        return {"class": cls, "pts": line, "end": end, "nodes": int(nodes), "ms": ms}


# ---------------------------------------------------------------------------------------------------- terrain

class Fine:
    """The baker's fine terrain for one map: heights per quad corner and centre, kinds per quad."""

    def __init__(self, outer, inner, kind, origin):
        self.outer, self.inner, self.kind = outer, inner, kind
        self.gc0, self.gr0 = int(origin[0]), int(origin[1])
        self.R8, self.C8 = inner.shape

    @staticmethod
    def load(inst):
        p = os.path.join(FINE, f"fine_{inst}.npz")
        if not os.path.exists(p):
            return None
        try:
            z = np.load(p)
            return Fine(z["outer"], z["inner"], z["kind"], z["origin"])
        except Exception as e:  # (being written)
            print(f"fine cache {p}: {e}", file=sys.stderr)
            return None

    def at(self, col, row):
        """Ground height, the face's slope (degrees) and the quad's kind under each (col, row)."""
        lx = np.asarray(col) * 128 - self.gc0 * 8
        ly = np.asarray(row) * 128 - self.gr0 * 8
        j, i = np.floor(lx).astype(np.int64), np.floor(ly).astype(np.int64)
        ok = (i >= 0) & (i < self.R8) & (j >= 0) & (j < self.C8)
        i, j = np.where(ok, i, 0), np.where(ok, j, 0)
        fx, fy = lx - j, ly - i
        a, b = self.outer[i, j].astype(np.float64), self.outer[i, j + 1].astype(np.float64)
        c, d = self.outer[i + 1, j].astype(np.float64), self.outer[i + 1, j + 1].astype(np.float64)
        m = self.inner[i, j].astype(np.float64)
        u, v = fx - 0.5, fy - 0.5
        north, south = v <= -np.abs(u), v >= np.abs(u)
        east = ~north & ~south & (u > 0)
        # gradients per quad unit (x east, y south), each face's plane anchored on a corner of it
        gx = np.select([north, south, east], [b - a, d - c, b + d - 2 * m], 2 * m - a - c)
        gy = np.select([north, south, east], [2 * m - a - b, c + d - 2 * m, d - b], c - a)
        z = np.select([north, south, east], [a + gx * fx + gy * fy, c + gx * fx + gy * (fy - 1),
                                             b + gx * (fx - 1) + gy * fy], a + gx * fx + gy * fy)
        slope = np.degrees(np.arctan(np.hypot(gx, gy) / QUAD_YD))
        kind = np.where(ok, self.kind[i, j], 8)
        return z, slope, kind


def seg_dist(px, py, ax, ay, bx, by):
    dx, dy = bx - ax, by - ay
    L2 = dx * dx + dy * dy
    t = np.clip(((px - ax) * dx + (py - ay) * dy) / L2, 0, 1) if L2 > 0 else 0
    return np.hypot(px - (ax + t * dx), py - (ay + t * dy))


def measure(fine: Fine | None, line, links) -> tuple:
    """(max climb on steep faces, yards on walls or holes) along a polyline in tile coords, ~1 yd steps."""
    if fine is None or len(line) < 2:
        return None, None, None
    p = np.array(line, dtype=np.float64)
    seg = np.hypot(*(p[1:] - p[:-1]).T) * TILE_YD
    cum = np.concatenate([[0], np.cumsum(seg)])
    total = cum[-1]
    if total < 1:
        return 0.0, 0.0, None
    s = np.linspace(0, total, int(math.ceil(total)) + 1)
    x, y = np.interp(s, cum, p[:, 0]), np.interp(s, cum, p[:, 1])
    z, _, _ = fine.at(x, y)
    mx, my = (x[1:] + x[:-1]) / 2, (y[1:] + y[:-1]) / 2
    _, slope, kind = fine.at(mx, my)
    step = np.diff(s)
    clear = np.ones(len(mx), dtype=bool)
    for (ax, ay), (bx, by) in links:
        clear &= seg_dist(mx, my, ax, ay, bx, by) > LINK_CLEAR
    swim = (kind & 3) != 0
    hole = (kind & 12) != 0
    steep = clear & ~swim & ~hole & (slope > STEEP)
    wall = clear & ((~swim & ~hole & (slope > WALL)) | hole)
    # a climb: within a continuous run of steep steps, how far above the run's lowest point so far it gets
    best, at, low, low_i = 0.0, None, None, 0
    zs = z.tolist()
    for i, st in enumerate(steep.tolist()):
        if not st or zs[i] != zs[i] or zs[i + 1] != zs[i + 1]:   # (off steep ground, or a NaN height)
            low = None
            continue
        if low is None or zs[i] < low:
            low, low_i = zs[i], i
        if zs[i + 1] - low > best:
            best, at = zs[i + 1] - low, (round(float(x[low_i]), 4), round(float(y[low_i]), 4))
    return round(best, 1), round(float(step[wall].sum()), 1), at


def selfcheck():
    """The walker on made-up ground: flat, a 20-yd 70-degree cliff, flat; and a 30-degree ramp."""
    R8 = C8 = 64
    xs = np.arange(C8 + 1) * QUAD_YD
    def ground(h):
        outer = np.tile(h(xs)[None, :], (R8 + 1, 1)).astype(np.float32)
        inner = np.tile(h((np.arange(C8) + 0.5) * QUAD_YD)[None, :], (R8, 1)).astype(np.float32)
        return Fine(outer, inner, np.zeros((R8, C8), np.uint8), (0, 0))
    cliff = ground(lambda x: np.clip((x - 100) * math.tan(math.radians(70)), 0, 20))
    ramp = ground(lambda x: np.clip((x - 50) * math.tan(math.radians(30)), 0, 60))
    row = 30 / 128
    east = [(10 / TILE_YD, row), (250 / TILE_YD, row)]
    west = east[::-1]
    c1, w1 , _ = measure(cliff, east, [])
    c2, w2 , _ = measure(cliff, west, [])
    c3, w3 , _ = measure(ramp, east, [])
    z, sl, _ = cliff.at(np.array([102 / TILE_YD]), np.array([row]))
    print(f"cliff east: climb {c1} wall {w1}; west (down): climb {c2}; ramp: climb {c3} wall {w3}; face {sl[0]:.1f} deg")
    assert c1 is not None and 18 <= c1 <= 21 and w1 > 3, "the cliff climbed"
    assert c2 == 0, "going down isn't a climb"
    assert c3 == 0 and w3 == 0, "a 30-degree ramp is fine"
    assert 69 < sl[0] < 71
    # the four faces of a quad meet: heights continuous across its diagonals and edges
    rnd = np.random.default_rng(1)
    f = Fine(rnd.random((9, 9)).astype(np.float32) * 10, rnd.random((8, 8)).astype(np.float32) * 10,
             np.zeros((8, 8), np.uint8), (0, 0))
    t = np.linspace(0.001, 0.999, 400) / 128 * 8
    for off in (0.0, 1e-7):
        za, _, _ = f.at(t + off, t)          # along a diagonal
        zb, _, _ = f.at(t, t + off)
        assert np.max(np.abs(za - zb)) < 1e-3, "faces meet on the diagonal"
    print("selfcheck ok")


# ---------------------------------------------------------------------------------------------------- pairs

def scan(sides, inst):
    """{chunk (gc, gr): zone} for chunks every side calls land, and the zones that touch each zone."""
    A = sides[0].A
    keys = sorted(int(k) for k in A.Tiles(inst).keys()) if A.Tiles(inst) else []
    land, zone_of = {}, {}
    for key in keys:
        cls_all = []
        zones = None
        for sd in sides:
            c, z = sd.scan(inst, key)
            cls_all.append(c)
            zones = zones or z
        tc, tr = key // 64, key % 64
        for k in range(256):
            gc, gr = tc * 16 + k % 16, tr * 16 + k // 16
            zid = zones[k + 1]
            if zid:
                zone_of[(gc, gr)] = zid
            if zid and all(c[k] == "1" for c in cls_all):
                land[(gc, gr)] = zid
    near = {}
    for (gc, gr), z in zone_of.items():
        for d in ((1, 0), (0, 1)):
            z2 = zone_of.get((gc + d[0], gr + d[1]))
            if z2 and z2 != z:
                near.setdefault(z, set()).add(z2)
                near.setdefault(z2, set()).add(z)
    return land, near


def random_pairs(sides, insts, n, seed):
    rnd = random.Random(seed)
    A = sides[0].A
    out = []
    for inst in insts:
        land, near = scan(sides, inst)
        byzone = {}
        for ch, z in sorted(land.items()):
            byzone.setdefault(z, []).append(ch)
        for z in sorted(byzone):
            chunks = byzone[z]
            if len(chunks) < 40:
                continue
            ok_zones = {z} | near.get(z, set())
            name = A.Area(z).name if A.Area(z) else str(z)
            got = 0
            for _ in range(n * 60):
                if got >= n:
                    break
                gc, gr = rnd.choice(chunks)
                a = ((gc + rnd.random()) / 16, (gr + rnd.random()) / 16)
                d, ang = rnd.uniform(0.5, 6), rnd.uniform(0, 2 * math.pi)
                b = (a[0] + d * math.cos(ang), a[1] + d * math.sin(ang))
                if land.get((math.floor(b[0] * 16), math.floor(b[1] * 16))) not in ok_zones:
                    continue
                if not all(sd.land(inst, *a) and sd.land(inst, *b) for sd in sides):
                    continue
                got += 1
                out.append({"name": f"{name} #{got}", "inst": inst, "zone": name, "kind": "random",
                            "a": [round(a[0], 4), round(a[1], 4)], "b": [round(b[0], 4), round(b[1], 4)]})
    return out


# ---------------------------------------------------------------------------------------------------- the sweep

def path_len(line):
    return sum(math.hypot(q[0] - p[0], q[1] - p[1]) for p, q in zip(line, line[1:])) * TILE_YD


def judge(expect, r):
    """None (no expectation), True, or the reasons it failed."""
    if not expect:
        return None
    bad = []
    want = expect.get("class")
    if want:
        okc = {"nofound": ("partial", "none")}.get(want, (want,))
        if r["class"] not in okc:
            bad.append(f"class {r['class']} (want {want})")
    if expect.get("max_ratio") and r.get("ratio") and r["ratio"] > expect["max_ratio"]:
        bad.append(f"ratio {r['ratio']:.2f} > {expect['max_ratio']}")
    if expect.get("steep") is False and r.get("climb") is not None and r["climb"] > CLIMB_FLAG:
        bad.append(f"climbs {r['climb']} yd")
    return bad or True


def run_case(side, case, fine, links, timeout=None):
    r = side.find(case["inst"], case["a"], case["b"], timeout)
    line = r.pop("pts", None) or []
    end = r.pop("end", None)
    if r["class"] in ("partial", "capped") and len(line) > 2:
        # short of the goal the last leg is drawn straight on, not walked (its rounded corner too): cut the line
        # where it passes nearest the walk's last turn, and end it there
        line = line[:-1]
        if end:
            k = min(range(len(line)), key=lambda i: (line[i][0] - end[0]) ** 2 + (line[i][1] - end[1]) ** 2)
            line = line[:k + 1] + [end]
    straight = math.hypot(case["b"][0] - case["a"][0], case["b"][1] - case["a"][1]) * TILE_YD
    if line:
        r["len"] = round(path_len(line), 1)
        if r["class"] == "found" and straight > 1:
            r["ratio"] = round(r["len"] / straight, 3)
    r["climb"], r["wall"], r["climb_at"] = measure(fine, line, links) if line else (None, None, None)
    r["ok"] = judge(case.get("expect"), r)
    return r


def pct(xs, q):
    xs = sorted(x for x in xs if x is not None)
    if not xs:
        return None
    return xs[min(len(xs) - 1, int(round(q * (len(xs) - 1))))]


def summarize(rows, names):
    out = {}
    for sn in names:
        rs = [row["s"][sn] for row in rows if sn in row["s"]]
        if not rs:
            continue
        counts = {c: sum(1 for r in rs if r["class"] == c) for c in CLASSES}
        measured = [r for r in rs if r.get("climb") is not None]
        judged = [r for r in rs if r.get("ok") is not None]
        out[sn] = {
            "n": len(rs), "counts": counts,
            "ratio_med": pct([r.get("ratio") for r in rs], 0.5), "ratio_p90": pct([r.get("ratio") for r in rs], 0.9),
            "nodes_med": pct([r.get("nodes") for r in rs], 0.5), "nodes_p90": pct([r.get("nodes") for r in rs], 0.9),
            "ms_med": pct([r.get("ms") for r in rs], 0.5), "ms_p90": pct([r.get("ms") for r in rs], 0.9),
            "ms_max": pct([r.get("ms") for r in rs], 1.0),
            "steep_share": (round(sum(1 for r in measured if r["climb"] > CLIMB_FLAG) / len(measured), 3)
                            if measured else None),
            "steep10_share": (round(sum(1 for r in measured if r["climb"] > 10) / len(measured), 3)
                              if measured else None),
            "climb_med": pct([r["climb"] for r in measured], 0.5), "climb_p90": pct([r["climb"] for r in measured], 0.9),
            "measured": len(measured),
            "error": next((r["error"] for r in rs if r.get("error")), None),
            "expect_pass": sum(1 for r in judged if r["ok"] is True), "expect_n": len(judged),
        }
    return out


def fmt(v, w, nd=0):
    if v is None:
        return "-".rjust(w)
    if isinstance(v, float):
        return f"{v:.{nd}f}".rjust(w)
    return str(v).rjust(w)


def side_cells(r):
    if r is None:
        return " " * 44
    ok = r.get("ok")
    mark = " " if ok is None else ("+" if ok is True else "X")
    return (f"{r['class'][:7]:>7} {fmt(r.get('len'), 6)} {fmt(r.get('ratio'), 5, 2)} {fmt(r.get('nodes'), 6)} "
            f"{fmt(r.get('ms'), 6, 1)} {fmt(r.get('climb'), 5, 1)} {fmt(r.get('wall'), 5)} {mark}")


def print_table(rows, names, sides_api):
    head = f"{'case':36} {'i':>1} {'str_yd':>6} |"
    sub = " " * 47 + "|"
    for sn in names:
        head += f" {('side ' + sn + ' (' + sides_api[sn] + ')'):^44}|"
        sub += f" {'class':>7} {'len':>6} {'ratio':>5} {'nodes':>6} {'ms':>6} {'climb':>5} {'wall':>5}  |"
    print(head)
    print(sub)
    for row in rows:
        st = math.hypot(row["b"][0] - row["a"][0], row["b"][1] - row["a"][1]) * TILE_YD
        line = f"{row['name'][:36]:36} {row['inst']:>1} {st:6.0f} |"
        for sn in names:
            line += " " + side_cells(row["s"].get(sn)) + "|"
        print(line)


def print_summary(label, summ):
    print(f"\n== {label}")
    for sn, s in summ.items():
        c = s["counts"]
        cnt = " ".join(f"{k} {v}" for k, v in c.items() if v)
        print(f"side {sn}: n {s['n']}: {cnt}")
        print(f"   ratio med {fmt(s['ratio_med'], 0, 3)} p90 {fmt(s['ratio_p90'], 0, 3)} | nodes med {s['nodes_med']} "
              f"p90 {s['nodes_p90']} | ms med {fmt(s['ms_med'], 0, 1)} p90 {fmt(s['ms_p90'], 0, 1)} max "
              f"{fmt(s['ms_max'], 0, 0)} | steep (>2 yd) {fmt(s['steep_share'], 0, 3)}, >10 yd "
              f"{fmt(s['steep10_share'], 0, 3)} of {s['measured']} measured (climb med {s['climb_med']} "
              f"p90 {s['climb_p90']})"
              + (f" | expectations met {s['expect_pass']}/{s['expect_n']}" if s["expect_n"] else ""))
        if s["error"]:
            print(f"   first error: {s['error'].splitlines()[0]}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--side", choices=["31", "2", "both"], default="both")
    ap.add_argument("--cases-only", action="store_true")
    ap.add_argument("--random", type=int, default=6, help="random pairs per zone (default 6)")
    ap.add_argument("--seed", type=int, default=7)
    ap.add_argument("--inst", type=int, action="append", help="only this map (repeatable); default 0 and 1")
    ap.add_argument("--json", help="write {about, columns, rows, summary} here")
    ap.add_argument("--timeout", type=float, default=20, help="seconds a Find may run (CPU) before it counts as timeout")
    ap.add_argument("--selfcheck", action="store_true")
    args = ap.parse_args()
    if args.selfcheck:
        selfcheck()
        return
    insts = args.inst or [0, 1]
    t0 = time.perf_counter()
    sides = {"31": Side("31")}
    try:
        sides["2"] = Side("2")
    except Exception as e:  # (the tree mid-rewrite: sweep 3.1 alone)
        print(f"side 2: the tree's atlas doesn't load: {str(e)[:300]}", file=sys.stderr)
    names = [n for n in (["31", "2"] if args.side == "both" else [args.side]) if n in sides]
    api = {n: sides[n].api for n in sides}
    print(f"sides: " + ", ".join(f"{n} = {api[n]}" + (" (tree)" if n == "2" else f" (git {REV31})") for n in sides)
          + f"; fine cache: {FINE}", file=sys.stderr)

    with open(CASES, encoding="utf-8") as f:
        cases = [dict(c, kind="case") for c in json.load(f)["cases"] if c["inst"] in insts]
    rows = cases
    if not args.cases_only and args.random > 0:
        rows = cases + random_pairs(list(sides.values()), insts, args.random, args.seed)
    fines = {inst: Fine.load(inst) for inst in insts}
    for inst, fz in fines.items():
        if fz is None:
            print(f"no fine cache for {inst}: climb and wall left empty", file=sys.stderr)
    links = hand_links()

    for n, row in enumerate(rows):
        row["s"] = {}
        for sn in names:
            row["s"][sn] = run_case(sides[sn], row, fines[row["inst"]], links.get(row["inst"], []), args.timeout)
        if n % 25 == 0:
            print(f"  {n}/{len(rows)}", file=sys.stderr, flush=True)
    print_table(rows, names, api)

    groups = {"all": rows, "cases": [r for r in rows if r["kind"] == "case"],
              "random": [r for r in rows if r["kind"] == "random"]}
    summary = {g: summarize(rs, names) for g, rs in groups.items() if rs}
    for g, s in summary.items():
        print_summary(f"{g} ({len(groups[g])})", s)
    changed = []
    if len(names) == 2:
        for row in rows:
            a, b = row["s"]["31"]["class"], row["s"]["2"]["class"]
            if a != b:
                changed.append({"name": row["name"], "inst": row["inst"], "a": row["a"], "b": row["b"],
                                "31": a, "2": b})
        print(f"\n== class changed 31 -> 2: {len(changed)}")
        for c in changed:
            print(f"  {c['name']:40} {c['31']:>8} -> {c['2']:<8} inst {c['inst']} {c['a']} -> {c['b']}")
    failed = [(row["name"], sn, row["s"][sn]["ok"]) for row in rows for sn in names
              if isinstance(row["s"][sn].get("ok"), list)]
    if failed:
        print(f"\n== expectations missed: {len(failed)}")
        for name, sn, why in failed:
            print(f"  [{sn}] {name}: {'; '.join(why)}")
    print(f"\n({time.perf_counter() - t0:.1f} s)", file=sys.stderr)

    if args.json:
        def pack(r):
            ok = r.get("ok")
            return [r["class"], r.get("len"), r.get("ratio"), r.get("nodes"),
                    None if r.get("ms") is None else round(r["ms"], 1), r.get("climb"), r.get("wall"),
                    ok if ok is None or ok is True else "; ".join(ok),
                    list(r["climb_at"]) if r.get("climb_at") and (r.get("climb") or 0) > CLIMB_FLAG else None]
        out_rows = []
        for row in rows:
            o = {k: row[k] for k in ("name", "inst", "a", "b", "kind") if k in row}
            for k in ("zone", "note", "expect"):
                if k in row:
                    o[k] = row[k]
            o["s"] = {sn: pack(row["s"][sn]) for sn in names}
            out_rows.append(o)
        doc = {
            "about": {"tool": "tools/walk_sweep.py", "sides": {n: api[n] for n in names}, "rev31": REV31,
                      "seed": args.seed, "random_per_zone": 0 if args.cases_only else args.random, "insts": insts,
                      "fine_cache": {str(i): fines[i] is not None for i in insts},
                      "when": time.strftime("%Y-%m-%d %H:%M"),
                      "notes": "s[side] = columns; len_yd for partial/capped is the walked part (no last straight leg); "
                               "ratio only when found; climb_yd = longest continuous climb on faces > 50 deg (steep if > 2); "
                               "wall_yd = yards on faces > 61.6 deg or holes; ok = true | null | the reasons missed"},
            "columns": SIDE_COLS, "rows": out_rows, "summary": summary, "changed": changed,
        }
        with open(args.json, "w", encoding="utf-8") as f:
            json.dump(doc, f, separators=(",", ":"))
        print(f"wrote {args.json} ({os.path.getsize(args.json) // 1024} KB)", file=sys.stderr)


if __name__ == "__main__":
    main()
