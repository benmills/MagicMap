#!/usr/bin/env python3
"""Score the finished map: what each of our layers does to its straight edges. Nothing here changes the map.

Two tests. Seams, on the art: gen_seams.py's test (every row's biggest step on one chunk line, for two chunks or more) on the
tiles alone, then after each layer in draw order, with the same test off the grid (half a chunk over) as the false alarms' rate:
so what each layer added and removed, in its footprint or not. Hard edges, on the layer's own pictures, whatever the art: alpha
going from nothing to something in one pixel along a straight stretch. A mask faded on only two sides shows up here though it's on
no chunk line. A soft seam's piece is whole on its line by design (it's mirrored there, so it meets itself): so each edge is
also scored by the step it leaves on the map; only one that shows is "visible". An edge on flat art may not show today and
still counts as raw.

--check is the gate: nonzero if a layer goes over its allowance in tools/seamcheck_baseline.json. --detect asks whether a rule
could pick the ground to rebuild instead of the review (docs/map-review.json): precision and recall, by chunk and by issue.

  python3 tools/seamcheck.py local "/Applications/World of Warcraft" wow_classic_beta --out /tmp/seamcheck
  python3 tools/seamcheck.py local "/Applications/World of Warcraft" wow_classic_beta --check
  python3 tools/seamcheck.py local "/Applications/World of Warcraft" wow_classic_beta --detect --out /tmp/seamcheck
"""
from __future__ import annotations

import argparse
import json
import math
import os
import sys
import tempfile

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from gen_clouds import KINDS, components, grow, places
from gen_fill import Ground
from gen_seams import PX, STEP, agreement, lines, mosaic, runs
from mmtools.log import log
from mmtools.sources import add_source_args, source_from_args

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASELINE = os.path.join(ROOT, "tools", "seamcheck_baseline.json")
LAYERS = ("sea", "fill", "ground", "relief", "seams")  # draw order; those not baked yet are passed over
NONE = 8            # alpha (0-255) that's nothing
HARD = 32           # ...and what it must reach, in one pixel, to be a hard edge (the softest of our fades don't, at this reach)
MIN_RUN = .5        # chunks a hard edge runs straight, at least
MIN_PX = 4          # ...and px: the sea's are half a chunk, a px or two of them is no line
SHOWS = 1.5         # a visible edge's step: over STEP, and this many times the step on the lines beside it
RISES = (2, 5, 10, 20, 40)  # --detect's rise>N
LEVEL = (.01, .5, 1, 2)     # ...and rise<=N: dead level terrain under flat art
SHARE = .5          # an issue is picked with this share of its chunks picked
NEAR = 2            # chunks: a patch's edge lies on the flat's, not in it


def seams_of(img: np.ndarray) -> dict:
    """gen_seams' test on a mosaic: lines down the rows (v), along the columns (h), and the same half a chunk off the grid."""
    turned = img.transpose(1, 0, 2)
    return {"v": lines(agreement(img)), "h": lines(agreement(turned)),
            "off": int(lines(agreement(img, PX // 2)).sum() + lines(agreement(turned, PX // 2)).sum())}


def picture(e: dict) -> np.ndarray:
    return e["rgba"] if "rgba" in e else np.asarray(Image.open(e["path"]).convert("RGBA"))


def lay(img: np.ndarray, layer: dict) -> np.ndarray:
    """A layer over a mosaic, as gen_seams.mosaic() lays the fill; returns the chunks it shows on."""
    n = 16 * PX
    shown = np.zeros(img.shape[:2], bool)
    if layer.get("deep"):  # past the sea's picture: its colour, over everything (demo/clouds.js, ui/Sea.lua)
        past = np.ones(img.shape[:2], bool)
        for e in layer["pics"]:
            past[int(round(e["row"] * n)):int(round((e["row"] + e["h"]) * n)), int(round(e["col"] * n)):int(round((e["col"] + e["w"]) * n))] = False
        img[past] = layer["deep"]
    for e in layer["pics"]:
        w, h = int(round(e["w"] * n)), int(round(e["h"] * n))
        x, y = int(round(e["col"] * n)), int(round(e["row"] * n))
        rgba = picture(e)
        p = np.asarray(Image.fromarray(rgba).resize((w, h), Image.BOX if rgba.shape[1] >= w else Image.BILINEAR), np.float32)  # (the sea's px are bigger than ours: a browser smooths them)
        a = p[..., 3:] / 255
        img[y:y + h, x:x + w] = (img[y:y + h, x:x + w] * (1 - a) + p[..., :3] * a).astype(np.uint8)
        shown[y:y + h, x:x + w] |= a[..., 0] > .05
    N = img.shape[0] // PX
    return shown.reshape(N, PX, img.shape[1] // PX, PX).any((1, 3))


def alpha_edges(a: np.ndarray, min_run: int) -> list[tuple[int, int, int, int, float]]:
    """A picture's hard edges (across, line, from, to, alpha): across 0: a line between rows; line i is above row i, so 0 and h are the picture's own box."""
    out = []
    for across, A in ((0, a), (1, a.T)):
        P = np.pad(A.astype(np.int16), ((1, 1), (0, 0)))
        lo, hi = np.minimum(P[:-1], P[1:]), np.maximum(P[:-1], P[1:])
        J = (lo <= NONE) & (hi >= HARD)
        for i in np.nonzero(J.sum(1) >= min_run)[0]:
            on = np.flatnonzero(np.diff(np.r_[0, J[i].astype(np.int8), 0]))
            for s, t in zip(on[::2], on[1::2]):
                if t - s >= min_run:
                    out.append((across, int(i), int(s), int(t), float(hi[i, s:t].mean())))
    return out


def step_along(img: np.ndarray, across: int, px: int, a: int, b: int) -> float:
    """The median step (three channels' sum) across a line of the mosaic."""
    size = img.shape[across]
    if px < 1 or px >= size or b <= a:
        return 0.
    if across == 0:
        one, two = img[px - 1, a:b], img[px, a:b]
    else:
        one, two = img[a:b, px - 1], img[a:b, px]
    return float(np.median(np.abs(one.astype(np.int16) - two).sum(-1)))


def edge_step(img: np.ndarray, e: dict) -> tuple[float, bool]:
    """What an edge leaves on the map: its step, and whether that shows against the lines beside it. (Between two of a mosaic's px, the line each side: a mosaic's px are two of a picture's. On one, that line alone: a px either way is the art's own blur, which a mirrored piece carries with it.)"""
    across = 0 if e["along"] == "h" else 1
    at = (e["row"] if across == 0 else e["col"]) * 16 * PX
    a = int(round((e["col"] if across == 0 else e["row"]) * 16 * PX))
    b = a + max(1, int(round(e["chunks"] * PX)))
    px = int(round(at))
    step = max(step_along(img, across, px + d, a, b) for d in ((0,) if abs(at - px) < .01 else (0, 1 if at > px else -1)))
    beside = max(step_along(img, across, px + d, a, b) for d in (-4, -3, 3, 4))
    return step, step > STEP and step > SHOWS * beside


def hard_edges(layer: dict, img: np.ndarray) -> list[dict]:
    """A layer's hard edges, each placed in tiles and scored on img, the map with this layer on."""
    out = []
    for e in layer["pics"]:
        rgba = picture(e)
        h, w = rgba.shape[:2]
        ppc = w / (e["w"] * 16)  # a picture's px a chunk
        for across, line, s, t, alpha in alpha_edges(rgba[..., 3], max(MIN_PX, int(round(MIN_RUN * ppc)))):
            if layer.get("deep") and line in (0, h if across == 0 else w):
                continue  # (it runs on into its backdrop)
            d = {"layer": layer["name"], "file": e.get("file", ""), "along": "h" if across == 0 else "v", "chunks": round((t - s) / ppc, 3), "alpha": round(alpha, 1),
                 "box": line in (0, h if across == 0 else w), "grid": line % max(1, int(round(ppc))) == 0}
            d["col"] = round(e["col"] + (s if across == 0 else line) / ppc / 16, 4)
            d["row"] = round(e["row"] + (line if across == 0 else s) / ppc / 16, 4)
            step, shows = edge_step(img, d)
            d["step"], d["visible"] = round(step, 1), shows
            out.append(d)
    return sorted(out, key=lambda d: (d["col"], d["row"], d["along"]))


def on_footprint(e: np.ndarray, foot: np.ndarray) -> np.ndarray:
    """The chunks of a line (e[n, x], left of chunk x) touching a footprint."""
    f = foot.copy()
    f[:, 1:] |= foot[:, :-1]
    return e & f


def account(base: np.ndarray, layers: list[dict]) -> dict:
    """The tiles, then each layer in order: seams at every stage, what each layer added and removed, its hard edges."""
    img = base.copy()
    now = seams_of(img)
    stages = [{"stage": "tiles", "grid": int(now["v"].sum() + now["h"].sum()), "off": now["off"]}]
    edges, added = [], []
    v0, h0 = now["v"], now["h"]
    v_add, h_add = np.zeros_like(v0), np.zeros_like(h0)
    for layer in layers:
        foot = lay(img, layer)
        now = seams_of(img)
        pv, ph = v0, h0
        v0, h0 = now["v"], now["h"]
        new_v, new_h, gone_v, gone_h = v0 & ~pv, h0 & ~ph, pv & ~v0, ph & ~h0
        in_new = int(on_footprint(new_v, foot).sum() + on_footprint(new_h, foot.T).sum())
        in_gone = int(on_footprint(gone_v, foot).sum() + on_footprint(gone_h, foot.T).sum())
        n_new, n_gone = int(new_v.sum() + new_h.sum()), int(gone_v.sum() + gone_h.sum())
        hard = hard_edges(layer, img)
        edges += hard
        v_add, h_add = (v_add | new_v) & v0, (h_add | new_h) & h0  # (added by a layer and still there)
        for along, e in (("v", new_v), ("h", new_h)):
            for x, n0, n1 in runs(e):
                added.append({"layer": layer["name"], "along": along, "col": x if along == "v" else n0, "row": n0 if along == "v" else x, "chunks": n1 - n0})
        stages.append({"stage": layer["name"], "grid": int(v0.sum() + h0.sum()), "off": now["off"], "added": n_new, "added_in_footprint": in_new, "removed": n_gone,
                       "removed_in_footprint": in_gone, "footprint": int(foot.sum()), **hard_summary(hard)})
    for e in edges:
        e["final_step"], e["final_visible"] = (lambda s: (round(s[0], 1), s[1]))(edge_step(img, e))
    return {"stages": stages, "edges": edges, "added": sorted(added, key=lambda a: (a["layer"], a["col"], a["row"])), "img": img, "v": v0, "h": h0, "v_add": v_add, "h_add": h_add}


def hard_summary(hard: list[dict]) -> dict:
    total = lambda f: round(sum(e["chunks"] for e in hard if f(e)), 2)
    return {"hard_edges": len(hard), "hard_chunks": total(lambda e: True), "hard_visible": total(lambda e: e["visible"]), "hard_box": total(lambda e: e["box"]), "hard_off_grid": total(lambda e: not e["grid"])}


def failures(stages: list[dict], baseline: dict) -> list[str]:
    """What the gate fails on: a layer over its allowance, a continent's or (stage["inst"]) any."""
    out = []
    allow = baseline["allow"]
    for s in stages:
        if s["stage"] == "tiles":
            continue
        a = {**allow.get("*", {}), **allow.get(s["stage"], {})}
        for key in ("hard_visible", "hard_chunks", "added_in_footprint"):
            if s.get(key, 0) > a.get(key, 0):
                out.append(f"{s['stage']}{' [' + str(s['inst']) + ']' if 'inst' in s else ''}: {key} {s[key]} over its allowance {a.get(key, 0)}")
    return out


def load_layers(names: list[str], inst: int, demo: str) -> list[dict]:
    """The baked layers there are, as gen_seams --bake leaves them: <name>/<name>.json, a continent's list of {file,col,row,w,h}; the sea's is one picture ({maps: {...}})."""
    out = []
    for name in names:
        path = os.path.join(demo, name, f"{name}.json")
        if not os.path.exists(path):
            log(f"{name}: not baked, passed over")
            continue
        d = json.load(open(path))
        pics = [d["maps"][str(inst)]] if "maps" in d else d.get(str(inst), [])
        out.append({"name": name, "deep": d.get("deep"), "pics": [{**e, "path": os.path.join(demo, name, e["file"])} for e in pics]})
    return out


def tiles_only(g: Ground, tiles: dict, sea: dict, inst: int, cache: str) -> tuple[np.ndarray, np.ndarray]:
    """The tiles' mosaic and land, kept in the cache: reading them is most of a run's time."""
    path = os.path.join(cache, f"seamcheck{inst}.npz")
    if os.path.exists(path):
        z = np.load(path)
        return z["img"], z["land"]
    img, land, _ = mosaic(g, tiles, sea, None, None)
    os.makedirs(cache, exist_ok=True)
    np.savez(path, img=img, land=land)
    return img, land


def box_of(mask: np.ndarray, pad: int = 8) -> tuple[int, int, int, int]:
    ys, xs = np.nonzero(mask)
    return max(0, ys.min() - pad), min(mask.shape[0], ys.max() + pad + 1), max(0, xs.min() - pad), min(mask.shape[1], xs.max() + pad + 1)


def draw_seams(path: str, r: dict, land: np.ndarray) -> None:
    """The final map, 4 px a chunk: seams yellow, those a layer added magenta; hard edges: visible cyan, not visible blue."""
    S = 4
    img = r["img"][::PX // S, ::PX // S].copy()
    chunks = np.kron(land, np.ones((16, 16), bool))
    for v, h, c in ((r["v"], r["h"], (255, 230, 0)), (r["v_add"], r["h_add"], (255, 0, 255))):
        n, x = np.nonzero(v)
        for n_, x_ in zip(n, x):
            img[n_ * S:(n_ + 1) * S, max(0, x_ * S - 1):x_ * S + 1] = c
        n, x = np.nonzero(h)
        for n_, x_ in zip(n, x):
            img[max(0, x_ * S - 1):x_ * S + 1, n_ * S:(n_ + 1) * S] = c
    for e in r["edges"]:
        c = (0, 255, 255) if e["final_visible"] else (60, 110, 255)
        x, y = int(round(e["col"] * 16 * S)), int(round(e["row"] * 16 * S))
        length = max(1, int(round(e["chunks"] * S)))
        if e["along"] == "h":
            img[max(0, y - 1):y + 1, x:x + length] = c
        else:
            img[y:y + length, max(0, x - 1):x + 1] = c
    y0, y1, x0, x1 = box_of(chunks)
    Image.fromarray(img[y0 * S:y1 * S, x0 * S:x1 * S]).save(path, optimize=True)


def wilson(k: int, n: int) -> list[float]:
    """A share's 95% interval."""
    if not n:
        return [0., 0.]
    z, p = 1.96, k / n
    d = 1 + z * z / n
    mid, half = (p + z * z / (2 * n)) / d, z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return [round(max(0, mid - half), 3), round(min(1, mid + half), 3)]


def scores(tp: int, fp: int, fn: int) -> dict:
    p, r = tp / max(1, tp + fp), tp / max(1, tp + fn)
    return {"tp": tp, "fp": fp, "fn": fn, "precision": round(p, 3), "recall": round(r, 3), "f1": round(2 * p * r / max(1e-9, p + r), 3), "precision_95": wilson(tp, tp + fp), "recall_95": wilson(tp, tp + fn)}


def rules_of(m) -> dict:
    out = {"flat": m.flat, "flat & uniform": m.flat & m.uniform}
    for n in RISES:
        out[f"flat & rise>{n}"] = m.flat & (m.rise > n)
        out[f"flat & uniform & rise>{n}"] = m.flat & m.uniform & (m.rise > n)
    for n in LEVEL:
        out[f"flat & rise<={n}"] = m.flat & (m.rise <= n)
        out[f"flat & uniform & rise<={n}"] = m.flat & m.uniform & (m.rise <= n)
    return out


def detect(rows: list[tuple], issues: list, decisions: dict, out: str) -> dict:
    """rows: (inst, m, land, base). Every rule against the review: by chunk, by issue (SHARE of its chunks picked; or NEAR chunks of a pick, for an edge)."""
    labelled = [i for i in issues if i["kind"] in KINDS and decisions.get(i["id"], {}).get("status") in ("accepted", "rejected")]
    by_rule, cases = {}, []
    for i in labelled:
        cases.append({"id": i["id"], "kind": i["kind"], "zone": i.get("zone", "-"), "inst": i["inst"], "accepted": decisions[i["id"]]["status"] == "accepted", "hits": {}, "near": {}})
    masks = {}
    for inst, m, land, _ in rows:
        rules = rules_of(m)
        for case, i in zip(cases, labelled):
            if i["inst"] != inst:
                continue
            cells = places([i], {i["id"]: {"status": "accepted"}}, inst) & m.land
            case["chunks"] = int(cells.sum())
            case["rise"] = float(np.median(m.rise[cells])) if cells.any() else 0.
            case["uniform"] = float(m.uniform[cells].mean()) if cells.any() else 0.
            case["flat"] = float(m.flat[cells].mean()) if cells.any() else 0.
            masks[i["id"]] = cells
        for name, pick in rules.items():
            near = grow(pick, NEAR)
            for case in cases:
                if case["inst"] == inst and masks[case["id"]].any():
                    cells = masks[case["id"]]
                    case["hits"][name] = float(pick[cells].mean())
                    case["near"][name] = float(near[cells].mean())
    # chunk by chunk: a chunk both accepted and rejected counts for neither
    def chunks(kinds, name):
        tp = fp = fn = picks = outside = 0
        for inst, m, land, _ in rows:
            pick = rules_of(m)[name]
            pos = places([i for i in issues if i["kind"] in kinds], decisions, inst) & m.land
            flipped = {k: {"status": "accepted"} for k, v in decisions.items() if v.get("status") == "rejected"}
            neg = places([i for i in issues if i["kind"] in kinds], flipped, inst) & m.land
            pos, neg = pos & ~neg, neg & ~pos
            everything = places(issues, {i["id"]: {"status": "accepted"} for i in issues}, inst)
            tp, fp, fn = tp + int((pick & pos).sum()), fp + int((pick & neg).sum()), fn + int((pos & ~pick).sum())
            picks, outside = picks + int(pick.sum()), outside + int((pick & ~everything).sum())
        return {**scores(tp, fp, fn), "picks": picks, "picks_unreviewed": outside}

    def by_issue(kinds, name, near=False, of=None):
        tp = fp = fn = 0
        for c in of if of is not None else cases:
            if c["kind"] not in kinds or name not in c["hits"]:
                continue
            picked = (c["near"] if near else c["hits"])[name] >= SHARE
            tp, fp, fn = tp + (picked and c["accepted"]), fp + (picked and not c["accepted"]), fn + (not picked and c["accepted"])
        return scores(int(tp), int(fp), int(fn))

    names = list(rules_of(rows[0][1]))
    flat_kind, all_kinds = ("flat-land",), KINDS
    table = {n: {"flat_land_issues": by_issue(flat_kind, n), "all_issues_near": by_issue(all_kinds, n, near=True), "flat_land_chunks": chunks(flat_kind, n), "all_chunks": chunks(all_kinds, n)} for n in names}
    # how much of the score is choosing the rule on the answers: each flat-land issue judged by the rule best on the others
    usable = [c for c in cases if c["kind"] in flat_kind and c["hits"]]
    tp = fp = fn = 0
    for c in usable:
        rest = [o for o in usable if o is not c]
        best = max(names, key=lambda n: (by_issue(flat_kind, n, of=rest)["f1"], n))
        picked = c["hits"][best] >= SHARE
        tp, fp, fn = tp + (picked and c["accepted"]), fp + (picked and not c["accepted"]), fn + (not picked and c["accepted"])
    best = max(names, key=lambda n: (table[n]["flat_land_issues"]["f1"], table[n]["flat_land_issues"]["precision"]))
    groups = {}
    for c in cases:
        g = groups.setdefault(c["kind"], {"accepted": 0, "rejected": 0, "zones_accepted": set(), "zones_rejected": set(), "empty": 0})
        w = "accepted" if c["accepted"] else "rejected"
        g[w] += 1
        g["zones_" + w].add(c["zone"])
        g["empty"] += not c["hits"]
    for g in groups.values():
        g["zones_accepted"], g["zones_rejected"] = len(g["zones_accepted"]), len(g["zones_rejected"])
    medians = {}
    for key in ("rise", "uniform", "flat"):
        for kind in KINDS:
            for acc in (True, False):
                v = [c[key] for c in cases if c.get("chunks") and c["kind"] == kind and c["accepted"] == acc]
                medians[f"{key} {kind} {'accepted' if acc else 'rejected'}"] = round(float(np.median(v)), 2) if v else None
    for inst, m, land, base in rows:
        draw_picks(os.path.join(out, f"detect_{inst}.png"), rules_of(m)[best], m, base, issues, decisions, inst)
    return {"best": best, "best_loo": scores(int(tp), int(fp), int(fn)), "labelled": groups, "medians": medians, "rules": table,
            "cases": [{k: (round(v, 3) if isinstance(v, float) else v) for k, v in c.items() if k not in ("hits", "near")} | {"best_share": round(c["hits"].get(best, 0), 3)} for c in cases]}


def draw_picks(path: str, pick: np.ndarray, m, base: np.ndarray, issues: list, decisions: dict, inst: int) -> None:
    """A rule's picks on the tiles, 4 px a chunk: green accepted ground picked, red rejected ground picked, blue accepted ground missed, yellow picked and never reviewed."""
    S = 4
    flipped = {k: {"status": "accepted"} for k, v in decisions.items() if v.get("status") == "rejected"}
    pos, neg = places(issues, decisions, inst) & m.land, places(issues, flipped, inst) & m.land
    img = (base[::PX // S, ::PX // S] * .55).astype(np.uint8)
    for mask, c in ((pick & ~pos & ~neg, (255, 220, 0)), (pos & ~pick, (40, 110, 255)), (pick & neg, (255, 40, 40)), (pick & pos, (40, 230, 70))):
        ys, xs = np.nonzero(mask)
        for y, x in zip(ys, xs):
            img[y * S + 1:(y + 1) * S, x * S + 1:(x + 1) * S] = c
    y0, y1, x0, x1 = box_of(m.land)
    Image.fromarray(img[y0 * S:y1 * S, x0 * S:x1 * S]).save(path, optimize=True)


def summary(report: dict) -> str:
    lines_ = []
    for inst, cont in report["continents"].items():
        lines_.append(f"[{inst}] seam chunks on the grid / off it; what each layer did")
        for s in cont["stages"]:
            more = "" if s["stage"] == "tiles" else (f"  +{s['added']} ({s['added_in_footprint']} in its footprint) -{s['removed']}  hard edges {s['hard_edges']}: {s['hard_chunks']} chunks, "
                                                      f"{s['hard_visible']} visible, {s['hard_box']} on a picture's box, {s['hard_off_grid']} off the grid")
            lines_.append(f"  {s['stage']:7} {s['grid']:6} / {s['off']:<5}{more}")
    return "\n".join(lines_)


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    add_source_args(ap)
    ap.add_argument("--layers", default=",".join(LAYERS), help="in draw order; those not baked are passed over")
    ap.add_argument("--demo", default=os.path.join(ROOT, "demo"), help="where the baked layers are")
    ap.add_argument("--cache", default=os.path.join(tempfile.gettempdir(), "mm-fill"), help="the terrain read so far")
    ap.add_argument("--out", default=os.path.join(tempfile.gettempdir(), "mm-seamcheck"), help="the report and pictures go here")
    ap.add_argument("--check", action="store_true", help="the gate: nonzero if a layer goes over tools/seamcheck_baseline.json")
    ap.add_argument("--baseline", default=BASELINE)
    ap.add_argument("--detect", action="store_true", help="only the automatic detection against the review")
    ns = ap.parse_args()
    src = source_from_args(ap, ns)
    import flatmap
    import maplint
    data = maplint.Data(os.path.join(ROOT, "Data"))
    os.makedirs(ns.out, exist_ok=True)
    if ns.detect:
        issues, decisions = json.load(open(os.path.join(ROOT, "demo", "lint", "issues.json")))["issues"], json.load(open(os.path.join(ROOT, "docs", "map-review.json")))["decisions"]
        rows = []
        for inst in (0, 1):
            g = Ground(src, inst, data.tiles[inst], data.sea[inst], ns.cache)
            base, land = tiles_only(g, data.tiles[inst], data.sea[inst], inst, ns.cache)
            rows.append((inst, flatmap.read(src, inst, data.tiles[inst], data.sea[inst], ns.cache), land, base))
        result = detect(rows, issues, decisions, ns.out)
        path = os.path.join(ns.out, "detect.json")
        with open(path, "w") as f:
            json.dump(result, f, indent=1, sort_keys=True)
        print(f"best: {result['best']}  labelled: {result['labelled']}")
        for name, t in result["rules"].items():
            a, b, c = t["flat_land_issues"], t["all_issues_near"], t["flat_land_chunks"]
            print(f"{name:28} flat-land issues p {a['precision']:.2f} r {a['recall']:.2f} (tp {a['tp']} fp {a['fp']} fn {a['fn']})  all issues, near p {b['precision']:.2f} r {b['recall']:.2f}  chunks p {c['precision']:.2f} r {c['recall']:.2f} picks {c['picks']} unreviewed {c['picks_unreviewed']}")
        print(path)
        return
    report, fails = {"continents": {}}, []
    baseline = json.load(open(ns.baseline)) if ns.check else None
    for inst in (0, 1):
        g = Ground(src, inst, data.tiles[inst], data.sea[inst], ns.cache)
        base, land = tiles_only(g, data.tiles[inst], data.sea[inst], inst, ns.cache)
        r = account(base, load_layers(ns.layers.split(","), inst, ns.demo))
        report["continents"][str(inst)] = {"stages": r["stages"], "added": r["added"], "edges": r["edges"]}
        if not ns.check:
            draw_seams(os.path.join(ns.out, f"seamcheck_{inst}.png"), r, land)
        else:
            fails += failures([{**s, "inst": inst} for s in r["stages"]], baseline)
    print(summary(report))
    if ns.check:
        for f in fails:
            print("FAIL", f)
        print("seamcheck: over its allowance" if fails else "seamcheck: within its allowance")
        sys.exit(1 if fails else 0)
    path = os.path.join(ns.out, "seamcheck.json")
    with open(path, "w") as f:
        json.dump(report, f, indent=1, sort_keys=True)
    print(path)


if __name__ == "__main__":
    main()
