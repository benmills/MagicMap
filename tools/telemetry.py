"""Read what MagicMapAtlas left on disk: play, /reload, run this (docs/telemetry.md).

  .venv/bin/python tools/telemetry.py                  # sessions, perf, kept, errors, marks, shots, validation, logs
  .venv/bin/python tools/telemetry.py --errors --full  # one section (--perf --kept --errors --marks --shots --validation --logs)
  .venv/bin/python tools/telemetry.py --trace          # every event of each ring, each mark's motion ring frame by frame
  .venv/bin/python tools/telemetry.py --since 30       # last 30 minutes (or an ISO time)
  .venv/bin/python tools/telemetry.py --json           # everything, machine-readable
  .venv/bin/python tools/telemetry.py --budgets        # newest session's perf against docs/runtime.md: PASS/FAIL, owners
  .venv/bin/python tools/telemetry.py --budgets --trace  # ... and the perf, kept and marks they were judged from
  .venv/bin/python tools/telemetry.py --compare 3 5    # two sessions side by side (an id, or FILE:id for another SV file)

The install is "/Applications/World of Warcraft" (MAGICMAP_WOW, --wow), flavor _classic_beta_
(--flavor); SavedVariables is the newest WTF/Account/*/SavedVariables/MagicMapAtlas.lua (--sv).
Shot marks pair with reference shots docs/evidence/shots/ref-<id>.* (--refs; tools/refshots.py) by the note's first word.
"""
from __future__ import annotations

import argparse
import collections
import datetime as dt
import glob
import json
import math
import os
import re
import sys
import time

from lupa import lua51

ADDON = "MagicMapAtlas"
NOW = time.time()
DAY = 86400
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REFS = os.path.join(ROOT, "docs", "evidence", "shots")
SECTIONS = ("perf", "kept", "errors", "marks", "shots", "validation", "logs")
KEPT = ("taint", "art", "sensor")  # game/Telemetry.lua KEEP: each one a bug, kept past the ring
BENCH = "bench: regions"  # game/Bench.lua's job: a timed call can't be split, so its overruns and gaps aren't bugs


# Owners: who to look at for a FAIL, from what the session measured (old sessions lack the M0 fields).

def ledger(p) -> list:
    return sorted(p.get("ledger") or [], key=lambda e: -(e.get("ms") or 0))


def alloc(p) -> list:
    return sorted(p.get("alloc") or [], key=lambda a: -(a.get("kbPerSec") or 0))


def in_frame(e) -> str:
    """A ledger frame's own events, short: 'swap borders 6.2 ms 1012 live, layout borders'."""
    out = []
    for ev in e.get("events") or []:
        if ev.get("f") == e.get("frame") and ev.get("k") not in ("spike", "slow"):
            d = ev.get("d")
            what = (d.get("layer") or d.get("name") or d.get("job") or d.get("e")) if isinstance(d, dict) else d
            if ev.get("k") == "swap" and isinstance(d, dict) and d.get("ms") is not None:
                what = f"{what} {num(d['ms'])} ms {d.get('live')} live"
            out.append(f"{ev.get('k')} {what}" if what is not None else ev.get("k"))
    return ", ".join(dict.fromkeys(out))


def worst_swap(s) -> str:
    """The session's costliest swap (stats: each field's max, so ms and live may be two swaps')."""
    swaps = [(k.split(" ", 1)[-1], x) for k, x in (s.get("stats") or {}).items()
             if k.startswith("swap") and x.get("ms") is not None]
    if not swaps:
        return ""
    layer, x = max(swaps, key=lambda kv: kv[1].get("ms") or 0)
    return (f"swap {layer} {num(x.get('ms'))} ms max, {x.get('live')} live"
            + (f", {x.get('parked')} parked" if x.get("parked") else "") + " (stats)")


def owner_frames(which):
    def owner(p, s, errs):
        bits = []
        states = p.get("byState") or {}
        if states:
            st, v = max(((k, x.get(which) or 0) for k, x in states.items()), key=lambda kv: kv[1])
            bits.append(f"state '{st}' worst at {which} {num(v)} ms")
        worst = ledger(p)
        if worst:
            name, n = collections.Counter(e.get("top") for e in worst).most_common(1)[0]
            w = worst[0]
            bits.append(f"{name} slowest in {n} of the {len(worst)} worst frames (worst f{w.get('frame')} {num(w.get('ms'))} ms"
                        + (f": {in_frame(w)})" if in_frame(w) else ")"))
        gaps = but_bench(p.get("gaps"), "job")
        if gaps:
            g = max(gaps, key=lambda g: g.get("ms") or 0)
            bits.append(f"job {g.get('job')} ran {num(g.get('ms'))} ms between yields")
        if worst_swap(s):
            bits.append(worst_swap(s))
        return "; ".join(bits) or "unattributed: no perf.byState / ledger / gaps (a build before M0)"
    return owner


def owner_max(p, s, errs):
    worst = ledger(p)
    if not worst:
        slow = p.get("slow") or []
        return f"{slow[0].get('name')} (most overruns; no perf.ledger: a build before M0)" if slow else "unattributed: no perf.ledger"
    w = worst[0]
    return (f"{w.get('top')} {num(w.get('topMs'))} ms in the worst frame f{w.get('frame')} ({num(w.get('ms'))} ms"
            + (f"; with {in_frame(w)}" if in_frame(w) else "") + ")" + (f"; {worst_swap(s)}" if worst_swap(s) else ""))


def owner_open(p, s, errs):
    top = (p.get("graceTop") or {}).get("map")
    if top:
        return f"{top.get('top')} ({num(top.get('topMs'))} ms: the slowest call in the first open's slowest frame, perf.graceTop)"
    slow = sorted(but_bench(p.get("slow"), "name") or [], key=lambda x: -(x.get("max") or 0))
    return (f"{slow[0].get('name')} (slowest call, {num(slow[0].get('max'))} ms: perf.slow; no perf.graceTop: an older build)"
            if slow else "unattributed: no perf.graceTop, and no call overran (perf.slow)")


def owner_load(p, s, errs):
    b = s.get("boot") or {}
    return f"Data + Atlas at load: {(b.get('loadKB') or 0) / 1024:.1f} MB of Lua (boot.loadKB)"


def owner_memory(p, s, errs):
    load, out, top = p.get("ourKBLoad"), p.get("ourKB"), alloc(p)
    if not load:
        return "Data + Atlas or growth: no perf.ourKBLoad (a build before M0.4)"
    grew = (out or load) - load
    return (f"Data + Atlas: {load / 1024:.1f} MB at load after GC; {grew / 1024:+.1f} MB by logout"
            + (", retained (not attributed: perf.alloc is garbage made, not kept)" if grew > 1024 else ""))


def owner_alloc(p, s, errs):
    top = alloc(p)
    if not top:
        return "unattributed: no perf.alloc (a build before M0.3)"
    return (", ".join(f"{a.get('name')} {num(a.get('kbPerSec'))} KB/s" for a in top[:2])
            + " (perf.alloc: the top makers, each a lower bound)")


def owner_errors(p, s, errs):
    mine = sorted((e for e in errs if e.get("session") == s.get("id")), key=lambda e: -(e.get("count") or 0))
    return f"{mine[0].get('name')} x{mine[0].get('count')}" if mine else "see == errors"


# docs/runtime.md "Budgets": (label, value from a session's perf, limit, unit, owner(perf, session, errors)).
# Frames by map state (docs/runtime.md "Budgets"): at rest the map draws next to nothing; moving (the wheel's
# zoom, a drag) a layout slice runs back to back (4-5 ms), so a session's p95 would be how much of it moved.
REST, MOVING = ("small", "big", "closed"), ("zoom", "drag")


def by_state(p, which, states, session):
    """The worst `which` among `states` in perf.byState; the session's `session` without byState (a build before M0)."""
    st = p.get("byState")
    if not st:
        return p.get(session)
    vals = [x.get(which) or 0 for k, x in st.items() if k in states]
    return max(vals) if vals else None


BUDGETS = (
    ("frame cost p95 at rest", lambda p: by_state(p, "p95", REST, "p95"), 1.0, "ms", owner_frames("p95")),
    ("frame cost p99 at rest, p95 moving", lambda p: max(v for v in (by_state(p, "p99", REST, "p99"),
                                                                       by_state(p, "p95", MOVING, "p99"), 0) if v is not None),
     5.0, "ms", owner_frames("p99")),
    ("frame cost max (outside graces)", lambda p: p.get("max"), 8.0, "ms", owner_max),
    ("first map open, slowest frame", lambda p: (p.get("grace") or {}).get("map"), 50.0, "ms", owner_open),
    ("load (Data + Atlas)", lambda p: p.get("loadMs"), 250.0, "ms", owner_load),
    ("our memory at logout, after GC", lambda p: p.get("ourKB") and p["ourKB"] / 1024, 64.0, "MB", owner_memory),
    ("Lua allocation (outside graces)", lambda p: p.get("kbPerSec"), 50.0, "KB/s", owner_alloc),
    ("errors per hour", lambda p: p.get("errorsPerHour"), 0, "/h", owner_errors),
)


def kept(s, kind):
    return None if "kept" not in s else [e for e in s.get("kept") or [] if e.get("k") == kind]


def but_bench(xs, key):
    return None if xs is None else [x for x in xs if x.get(key) != BENCH]


# docs/v1-plan.md §1 gate 3/4: what must be empty; (label, list from (perf, session) or None: not recorded, line).
GATE = (
    ("perf.slow", lambda p, s: but_bench(p.get("slow"), "name"), lambda x: f"{x.get('name')} x{x.get('n')} max {num(x.get('max'))} ms"),
    ("perf.gaps", lambda p, s: but_bench(p.get("gaps"), "job"), lambda x: f"{x.get('job')} {num(x.get('ms'))} ms between yields"
                                                                         + (f" (x{x['n']})" if x.get("n") else "")),
    *((k, lambda p, s, k=k: kept(s, k), lambda e: detail(e.get("d"))) for k in KEPT),
)


# Loading -------------------------------------------------------------------------------------

def py(v):
    """A Lua value as Python: 1..n tables become lists, other tables dicts."""
    if lua51.lua_type(v) != "table":
        return v
    d = {k: py(x) for k, x in v.items()}
    return [d[i] for i in range(1, len(d) + 1)] if all(i in d for i in range(1, len(d) + 1)) else d


def load_sv(path: str):
    """MagicMapAtlasDB from a SavedVariables file, run in a fresh runtime with an empty environment."""
    L = lua51.LuaRuntime(register_eval=False, register_builtins=False)
    run = L.eval("""function(src, name)
        local f, err = loadstring(src, name)
        if not f then error(err, 0) end
        local env = {}
        setfenv(f, env)()
        return env.MagicMapAtlasDB
    end""")
    with open(path, "rb") as f:
        return py(run(f.read(), "@" + os.path.basename(path)))


def find_sv(flavor: str):
    paths = glob.glob(os.path.join(flavor, "WTF", "Account", "*", "SavedVariables", ADDON + ".lua"))
    return max(paths, key=os.path.getmtime) if paths else None


def sessions_of(db) -> list:
    """Newest first."""
    tel = (db or {}).get("telemetry") or {}
    return [s for s in reversed(tel.get("sessions") or []) if isinstance(s, dict)]


# Formatting ----------------------------------------------------------------------------------

def ago(t) -> str:
    s = NOW - t
    for unit, n in (("d", DAY), ("h", 3600), ("m", 60)):
        if s >= n:
            return f"{s / n:.0f}{unit} ago"
    return f"{max(s, 0):.0f}s ago"


def when(t) -> str:
    return f"{dt.datetime.fromtimestamp(t):%m-%d %H:%M:%S} ({ago(t)})" if t else "?"


def num(v) -> str:
    """A float to 4 decimals at most, trailing zeros dropped (ms since login stay whole: 1101166.7)."""
    if not isinstance(v, float):
        return str(v)
    s = f"{v:.4f}".rstrip("0").rstrip(".")
    return "0" if s == "-0" else s


def detail(d) -> str:
    if not isinstance(d, (dict, list)):
        return "" if d is None else num(d)
    if isinstance(d, list):
        return " ".join(map(num, d))
    pos = [num(d[i]) for i in sorted(k for k in d if isinstance(k, int))]
    kv = [f"{k}={num(v)}" for k, v in sorted(d.items(), key=str) if not isinstance(k, int)]
    return " ".join(pos + (["{" + " ".join(kv) + "}"] if kv else []))


def event(e) -> str:
    return f"f{e.get('f', '?')} +{num(e.get('ms', '?'))}ms {e.get('k', '?')} {detail(e.get('d'))}".rstrip()


def state(s) -> list[str]:
    out = []
    you, m = s.get("you") or {}, s.get("map") or {}
    if you:
        out.append(f"you inst {you.get('inst')} {num(you.get('col'))},{num(you.get('row'))} facing {num(you.get('facing'))}")
    out.append(f"zone {s.get('zone', '?')} / {s.get('subzone') or '-'}")
    if m:
        out.append(f"map {'shown' if m.get('shown') else 'hidden'} inst {m.get('inst')} at {num(m.get('cx'))},{num(m.get('cy'))}"
                   f" zoom {num(m.get('zoom'))} follow {'on' if m.get('follow') else 'off'} {m.get('w')}x{m.get('h')}")
    for layer in s.get("layers") or []:
        out.append(f"layer {layer.get('name')}{' busy' if layer.get('busy') else ''} zoom {num(layer.get('zoom'))}"
                   f" region {layer.get('region')}")
    return out


def stamp(a) -> str:
    """A shot mark's stamp (what the screenshot shows)."""
    if not a:
        return "no stamp (a build before M0.4)"
    where = f" at {num(a.get('left'))},{num(a.get('top'))}" if a.get("left") is not None else " (hidden)"
    return (f"zoom {num(a.get('zoom'))} camera {num(a.get('cx'))},{num(a.get('cy'))} inst {a.get('inst')}"
            f" view {num(a.get('w'))}x{num(a.get('h'))}{where} {'big' if a.get('big') else 'small'};"
            f" UI scale {num(a.get('uiScale'))}, screen {num(a.get('screenW'))}x{num(a.get('screenH'))}")


def layouts(trace) -> list[dict]:
    """Each layout in a ring: its start, its end (ms, regions) and the swap that showed it."""
    rows, building, ended = [], {}, {}
    for e in trace:
        d = e.get("d")
        if not isinstance(d, dict):
            continue
        layer = d.get("layer")
        if e.get("k") == "layout" and d.get("e") == "start":
            building[layer] = {"layer": layer, "start": e}
        elif e.get("k") == "layout" and d.get("e") in ("end", "failed"):
            r = building.pop(layer, None) or {"layer": layer, "start": None}
            r["end"] = e
            rows.append(r)
            if d.get("e") == "end":
                ended[layer] = r
        elif e.get("k") == "swap" and layer in ended:
            ended.pop(layer)["swap"] = e
    return rows


def layout_line(r) -> str:
    s, e, w = r.get("start"), r["end"], r.get("swap")
    d = e.get("d") or {}
    head = f"{r['layer']:<10} " + (f"f{s.get('f')}" if s else "(start before the ring)")
    if d.get("e") == "failed":
        return f"{head} -> f{e.get('f')} failed, retry in {num(d.get('retry'))} s"
    wd = (w or {}).get("d") or {}
    swap = (f"+{w.get('f') - e.get('f')} f +{num(round(w.get('ms') - e.get('ms'), 1))} ms"
            + (f", swap {num(wd['ms'])} ms {wd.get('live')} live" if wd.get("ms") is not None else "") if w else "no swap in the ring")
    return f"{head} -> f{e.get('f')} {num(d.get('ms'))} ms {d.get('regions')} regions | end->swap {swap}"


def pct(xs, q):
    xs = sorted(xs)
    return xs[min(len(xs) - 1, int(q * len(xs)))] if xs else 0


def motion(rows, full: bool) -> list[str]:
    """A mark's motion ring: a summary line; frame by frame with full (Δ camera and you - camera in screen px)."""
    if not rows:
        return []
    a, b = rows[0], rows[-1]
    dts = [y["ms"] - x["ms"] for x, y in zip(rows, rows[1:])]

    def dist(x0, y0, x1, y1):
        return math.hypot((x1 or 0) - (x0 or 0), (y1 or 0) - (y0 or 0))
    off = [dist(r.get("cx"), r.get("cy"), r.get("px"), r.get("py")) * (r.get("zoom") or 0)
           for r in rows if r.get("px") is not None]
    cols = [f"col {math.floor(x['cx'])}|{math.floor(y['cx'])} f{y['f']}" for x, y in zip(rows, rows[1:])
            if math.floor(x["cx"]) != math.floor(y["cx"])]
    cols += [f"row {math.floor(x['cy'])}|{math.floor(y['cy'])} f{y['f']}" for x, y in zip(rows, rows[1:])
             if math.floor(x["cy"]) != math.floor(y["cy"])]
    zooms = [r.get("zoom") or 0 for r in rows]
    out = [f"motion ({len(rows)} frames f{a['f']}-f{b['f']}, {(b['ms'] - a['ms']) / 1000:.2f} s): frame ms p50 "
           f"{num(round(pct(dts, 0.5), 1))} max {num(round(max(dts, default=0), 1))}; zoom {num(min(zooms))}-{num(max(zooms))};"
           f" camera moved {dist(a['cx'], a['cy'], b['cx'], b['cy']):.4f} tiles, you"
           f" {dist(a.get('px'), a.get('py'), b.get('px'), b.get('py')):.4f}; you off camera max {max(off, default=0):.1f} px"
           f"; crossed {', '.join(cols) or 'no tile edge'}"]
    if full:
        prev = None
        for r in rows:
            z = r.get("zoom") or 0
            step = (f"{((r['cx'] - prev['cx']) * z):+.2f},{((r['cy'] - prev['cy']) * z):+.2f}" if prev else "-")
            youcam = (f"{((r['px'] - r['cx']) * z):+.2f},{((r['py'] - r['cy']) * z):+.2f}" if r.get("px") is not None else "-")
            edge = (" |" + ("col" if math.floor(prev["cx"]) != math.floor(r["cx"]) else "row")
                    if prev and (math.floor(prev["cx"]) != math.floor(r["cx"]) or math.floor(prev["cy"]) != math.floor(r["cy"]))
                    else "")
            out.append(f"  f{r['f']} +{num(r['ms'])}ms dt {num(round(r['ms'] - prev['ms'], 1)) if prev else '-'}"
                       f" cam {num(r['cx'])},{num(r['cy'])} z{num(z)} {num(r.get('w'))}x{num(r.get('h'))}"
                       f" you {num(r.get('px'))},{num(r.get('py'))}  step {step} px  you-cam {youcam} px{edge}")
            prev = r
    return out


OURS = re.compile(r'\[string "@?(Interface[/\\]AddOns[/\\])?' + ADDON + r'[/\\]([^"]*)"\]|Interface[/\\]AddOns[/\\]' + ADDON + r'[/\\]')


def trim(stack: str, full: bool) -> list[str]:
    lines = (stack or "").splitlines()
    return lines if full else [OURS.sub(lambda m: m.group(2) or "", l) for l in lines if ADDON in l]


# Collecting ----------------------------------------------------------------------------------

STAMP = re.compile(r"WoWScrnShot_(\d{6}_\d{6})\.\w+$")
IMAGE = (".jpg", ".jpeg", ".png", ".tga")


def stamp_time(stamp: str):
    try:
        return dt.datetime.strptime(stamp, "%m%d%y_%H%M%S").timestamp()
    except ValueError:
        return None


def shots(flavor: str, marks: list, since: float, refs: str):
    """Shot marks with their screenshot file and, by id (the note's first word), the reference shot;
    the newest screenshots no mark claims; the reference ids no shot mark has."""
    files = []
    for p in glob.glob(os.path.join(flavor, "Screenshots", "WoWScrnShot_*")):
        m = STAMP.search(p)
        if m and stamp_time(m.group(1)):
            files.append((stamp_time(m.group(1)), os.path.abspath(p)))
    ref = {re.sub(r"^ref-", "", os.path.splitext(f)[0]): os.path.join(refs, f) for f in sorted(os.listdir(refs))
           if f.lower().endswith(IMAGE)} if os.path.isdir(refs) else {}
    used, out = set(), []
    for mk in (m for m in marks if m.get("kind") == "shot"):
        t = stamp_time(mk.get("stamp") or "") or mk.get("t", 0)
        near = min(files, key=lambda f: abs(f[0] - t), default=None)
        path = near[1] if near and abs(near[0] - t) <= 3 else None
        used.add(path)
        sid = (mk.get("note") or "").split(" ", 1)[0] or None
        out.append({"t": mk.get("t"), "stamp": mk.get("stamp"), "note": mk.get("note"), "file": path,
                    "id": sid, "ref": ref.get(sid), "at": mk.get("shot")})
    unmarked = sorted((f for f in files if f[1] not in used and f[0] >= since), reverse=True)[:5]
    return out, [{"t": t, "file": p} for t, p in unmarked], sorted(set(ref) - {s["id"] for s in out})


LOGLINE = re.compile(r"^(\d+)/(\d+) (\d+):(\d+):(\d+)\.\d+\s+(.*)")


def log_time(m) -> float:
    mo, d, h, mi, s = map(int, m.groups()[:5])
    t = dt.datetime(dt.datetime.now().year, mo, d, h, mi, s)
    if t.timestamp() > NOW + DAY:
        t = t.replace(year=t.year - 1)
    return t.timestamp()


# Another addon's error: its file in the first line. It's flagged shared when it may be ours
# too: the addon shares our prefix (the MagicMap spike) or it names a MagicMap_ global. E1
# (docs/evidence/spike-bugs.md): our data globals broke the spike, whose errors named only its files.
OTHER = re.compile(r"Interface[/\\]AddOns[/\\]([^/\\\]\"]+)[/\\]")
SHARED = re.compile(r"\bMagicMap_\w+")


def other_addon(text: str, more: list[str]):
    """(addon, shared) for an error line in another addon's file, else None."""
    m = OTHER.search(text)
    if not m or m.group(1) == ADDON or not re.search(r"\[E\]|error", text, re.I):
        return None
    return m.group(1), m.group(1).startswith("MagicMap") or bool(SHARED.search(text + "\n".join(more)))


def logs(flavor: str, since: float, loaded=None):
    """Client Logs/*.log entries (a timestamped line and its continuation lines) and Errors/* lines
    from files touched since `since` that mention the addon, deduped: [{file, t, n, text, more}].
    Also other addons' errors while ours was loaded (`loaded`: [(start, end)], our sessions;
    None: any time), with addon = its name and shared = see OTHER."""
    seen = {}

    def add(file, t, text, more, addon=None, shared=False):
        key = (file, text)
        e = seen.setdefault(key, {"file": file, "t": t, "n": 0, "text": text, "more": more,
                                  "addon": addon, "shared": shared})
        e["n"], e["t"] = e["n"] + 1, max(e["t"], t)

    def ours_loaded(t):
        return loaded is None or any(a <= t < b for a, b in loaded)

    for path in glob.glob(os.path.join(flavor, "Logs", "*.log")):
        if os.path.getmtime(path) < since:
            continue
        entries, name = [], os.path.basename(path)
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                m = LOGLINE.match(line.rstrip("\n"))
                if m:
                    entries.append([log_time(m), m.group(6), []])
                elif entries:
                    entries[-1][2].append(line.rstrip("\n"))
        for t, text, more in entries:
            if t < since:
                continue
            if ADDON in text + "".join(more):
                add(name, t, text, more)
            elif ours_loaded(t) and (other := other_addon(text, more)):
                add(name, t, text, more, *other)
    for path in glob.glob(os.path.join(flavor, "Errors", "*")):
        t = os.path.getmtime(path)
        if t < since:
            continue
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                if ADDON in line:
                    add("Errors/" + os.path.basename(path), t, line.strip(), [])
    return sorted(seen.values(), key=lambda e: -e["t"])


def validation(v):
    if not v:
        return None
    pairs = {}
    for e in v.get("log") or []:
        key = f"{e.get('kind')}: atlas {e.get('atlas')!r} | game {e.get('game')!r}"
        p = pairs.setdefault(key, {"pair": key, "n": 0, "example": e})
        p["n"] += 1
    return {"on": bool(v.get("on")), "samples": v.get("samples", 0), "logged": len(v.get("log") or []),
            "dropped": v.get("dropped", 0),
            "counts": dict(sorted((v.get("counts") or {}).items(), key=lambda kv: -kv[1])),
            "pairs": sorted(pairs.values(), key=lambda p: -p["n"])}


def collect(db, flavor, since, log_since, refs=REFS):
    tel = (db or {}).get("telemetry") or {}
    marks = [m for m in reversed(tel.get("marks") or []) if m.get("t", 0) >= since]
    errors = sorted((e for e in (tel.get("errors") or {}).values() if e.get("last", 0) >= since), key=lambda e: -e.get("last", 0))
    shot_marks, unmarked, unshot = shots(flavor, marks, since, refs)
    return {
        "telemetry": bool(tel),
        "sessions": [s for s in sessions_of(db) if s.get("started", 0) >= since],
        "errors": errors, "marks": marks, "shots": shot_marks, "unmarked_screenshots": unmarked,
        "refs": refs, "refs_unshot": unshot,
        "validation": validation((db or {}).get("validation")), "logs": logs(flavor, log_since, loaded(tel)),
    }


def loaded(tel):
    """When our addon was loaded, from its sessions: each from its start to the next one's (or now)."""
    starts = sorted(s["started"] for s in tel.get("sessions") or [] if isinstance(s, dict) and s.get("started"))
    return [(a, b) for a, b in zip(starts, starts[1:] + [NOW + DAY])] if starts else None


def newest(sessions):
    """The newest session with perf."""
    return next((s for s in sessions if isinstance(s.get("perf"), dict)), None)


# Printing ------------------------------------------------------------------------------------

def boot(b):
    b = b or {}
    if isinstance(b, list):
        b = dict(zip(("loadMs", "loadKB", "loginMs"), b))
    return f"load {num(round(b.get('loadMs', 0)))} ms {num(round(b.get('loadKB', 0)))} KB, login {num(round(b.get('loginMs', 0)))} ms"


def perf(p) -> str:
    if not isinstance(p, dict):
        return "no perf"
    g = p.get("grace") or {}
    kb = "-".join(f"{v / 1024:.0f}" for v in (p.get("kbMin"), p.get("kbMax")) if v)
    return (f"frame ms p50 {num(p.get('p50'))} p95 {num(p.get('p95'))} p99 {num(p.get('p99'))} max {num(p.get('max'))},"
            f" {p.get('overruns', 0)} over, graces " + (" ".join(f"{k} {num(v)}" for k, v in sorted(g.items())) or "-")
            + f"; {p.get('errors', 0)} errors ({num(p.get('errorsPerHour', 0))}/h); Lua {kb or '?'} MB,"
            f" ours {num(round((p.get('ourKB') or 0) / 1024))} MB"
            + (f" ({num(round(p['ourKBLoad'] / 1024))} at load), after GC" if p.get("ourKBLoad") else "")
            + (f"; alloc p95 {num(p.get('kbFrameP95'))} KB/frame"
               + (f" (max {num(p['kbFrameMax'])} KB/frame over {p.get('kbFrames')} frames)" if p.get("kbFrameMax") is not None else "")
               + f", {num(p.get('kbPerSec'))} KB/s" if p.get("kbPerSec") is not None else "")
            + "".join(f"\n      slow: {s.get('name')} x{s.get('n')} max {num(s.get('max'))} ms" for s in p.get("slow") or [])
            + "".join(f"\n      slow, a collector step: {s.get('name')} x{s.get('n')}" for s in p.get("slowGc") or []))


def bar(v, limit, width=20) -> str:
    """v against limit: `width` chars to the limit ('|'), up to twice it."""
    n = min(2 * width, round((v or 0) / limit * width))
    return "".join("|" if i == width else ("#" if i < n else " ") for i in range(2 * width + 1)).rstrip()


def show_perf(s, args) -> list[str]:
    """The newest session's attribution: alloc, gaps, ledger, by state, memory, layouts, bench."""
    p, full, out = s["perf"], args.trace == 0, []
    out.append(f"session #{s.get('id')} {s.get('version')} build {s.get('build')}, {p.get('frames', 0)} frames")
    tops = p.get("graceTop") or {}
    out.append("graces (slowest frame; its slowest call): " + (", ".join(
        f"{k} {num(v)} ms" + (f" ({tops[k].get('top')} {num(tops[k].get('topMs'))} ms)" if tops.get(k) else "")
        for k, v in sorted((p.get("grace") or {}).items())) or "none"))
    top = alloc(p)
    out.append(f"alloc (top {len(top)} by KB/s, of {num(p.get('kbPerSec'))}):" if top else "alloc: none (no perf.alloc)")
    out += [f"  {a.get('name'):<28} {num(a.get('kbPerSec')):>8} KB/s  max {num(a.get('kbMax'))} KB/call  {a.get('calls')} calls"
            for a in top]
    gaps = p.get("gaps")
    out.append(f"gaps (job yields over budget): {len(gaps)}" if gaps else
               f"gaps: {'none' if gaps is not None else 'not recorded'}")
    for g in gaps or []:
        out.append(f"  {g.get('job')} {num(g.get('ms'))} ms" + (f" (x{g['n']})" if g.get("n") else ""))
        out += [f"      {line}" for line in trim(g.get("stack"), args.full)][:None if full else 3]
    worst = ledger(p)
    out.append(f"ledger (worst {len(worst)} frames outside graces):" if worst else "ledger: none")
    for e in worst:
        kinds = collections.Counter(ev.get("k") for ev in e.get("events") or [])
        out.append(f"  f{e.get('frame')} {num(e.get('ms'))} ms  top {e.get('top')} {num(e.get('topMs'))} ms"
                   + (f"  [{', '.join(f'{k} x{n}' for k, n in kinds.most_common())}]" if kinds else ""))
        if full:
            out += [f"      {event(ev)}" for ev in e.get("events") or []]
    states = p.get("byState") or {}
    if states:
        out.append("by map state (frame ms, ours; the client's whole frame beside it; bar: our p95 against its 1 ms budget '|'):")
        out.append(f"  {'state':<8} {'frames':>7} {'p50':>6} {'p95':>6} {'p99':>6} {'max':>6}   client {'p50':>6} {'p95':>6} {'p99':>6} {'max':>6}")
        for st, x in sorted(states.items(), key=lambda kv: -(kv[1].get("frames") or 0)):
            c = x.get("client") or {}
            out.append(f"  {st:<8} {x.get('frames', 0):>7} " + " ".join(f"{num(x.get(q)):>6}" for q in ("p50", "p95", "p99", "max"))
                       + "          " + " ".join(f"{num(c[q]) if c.get(q) is not None else '-':>6}" for q in ("p50", "p95", "p99", "max"))
                       + f"  {bar(x.get('p95'), 1.0)}")
    else:
        out.append("by map state: none (no perf.byState)")
    load, kb = p.get("ourKBLoad"), p.get("ourKB")
    out.append("memory (ours, after a full collect): "
               + (f"{load / 1024:.1f} MB at load, " if load else "at load not recorded, ")
               + (f"{kb / 1024:.1f} MB at logout" if kb else "at logout not recorded")
               + f"; boot.loadKB {((s.get('boot') or {}).get('loadKB') or 0) / 1024:.1f} MB")
    stats = s.get("stats") or {}
    if stats:
        out.append("layouts, swaps, sweeps (session: n, each number's max; swap lag = frames after its layout's end):")
        for key, x in sorted(stats.items()):
            out.append(f"  {key:<16} n {x.get('n'):<5} " + " ".join(f"{k}={num(v)}" for k, v in sorted(x.items()) if k != "n"))
    for build, b in sorted((s.get("bench") or {}).items()):
        ops = sorted((b.get("ops") or {}).items(), key=lambda kv: -(kv[1].get("us") or 0))
        out.append(f"bench {build} ({when(b.get('t'))}): {len(ops)} ops, µs each")
        out += [f"  {op:<28} {num(x.get('us')):>8} µs  n {x.get('n')}  {num(x.get('ms'))} ms" for op, x in ops]
    return out


def budgets(sessions, errs) -> int:
    """The newest session with perf against BUDGETS and GATE: a PASS/FAIL line each, an owner for each FAIL; 1 if any FAIL."""
    s = newest(sessions)
    if not s:
        print("! no session with perf yet: /reload in game")
        return 1
    p, failed = s["perf"], 0
    print(f"== budgets: session #{s.get('id')} {s.get('version')}, {p.get('frames', 0)} frames (docs/runtime.md)")
    for label, get, limit, unit, owner in BUDGETS:
        v = get(p)
        if v is None:
            print(f"  ----  {label:<34} no data (limit {num(limit)} {unit})")
            continue
        ok = v <= limit
        failed += not ok
        print(f"  {'PASS' if ok else 'FAIL'}  {label:<34} {v:.2f} {unit} (limit {num(limit)})")
        if not ok:
            print(f"        owner: {owner(p, s, errs)}")
    print("== gate: empty (docs/v1-plan.md §1)")
    for label, get, line in GATE:
        items = get(p, s)
        if items is None:
            print(f"  ----  {label:<10} not recorded (a build before M0)")
            continue
        failed += bool(items)
        print(f"  {'FAIL' if items else 'PASS'}  {label:<10} {len(items)}")
        for x in items[:5]:
            print(f"        owner: {line(x)}")
    return 1 if failed else 0


def compare(a, b) -> None:
    """Two sessions side by side: budgets, memory, states, allocators, bench ops; B - A."""
    pa, pb = a.get("perf") or {}, b.get("perf") or {}
    print(f"== compare: A #{a.get('id')} {a.get('version')} build {a.get('build')} ({when(a.get('started'))})")
    print(f"            B #{b.get('id')} {b.get('version')} build {b.get('build')} ({when(b.get('started'))})")
    rows = [(f"{label} ({unit})", get(pa), get(pb)) for label, get, _, unit, _ in BUDGETS]
    rows += [("frames", pa.get("frames"), pb.get("frames")),
             ("ours at load, after GC (MB)", *(p.get("ourKBLoad") and p["ourKBLoad"] / 1024 for p in (pa, pb)))]
    for st in sorted(set(pa.get("byState") or {}) | set(pb.get("byState") or {})):
        for q in ("p95", "p99", "max"):
            rows.append((f"state {st} {q} (ms)", *(((p.get("byState") or {}).get(st) or {}).get(q) for p in (pa, pb))))
        for q in ("p95", "max"):
            rows.append((f"state {st} client {q} (ms)",
                         *((((p.get("byState") or {}).get(st) or {}).get("client") or {}).get(q) for p in (pa, pb))))
    names = list(dict.fromkeys(x.get("name") for p in (pa, pb) for x in alloc(p)))
    for n in names:
        rows.append((f"alloc {n} (KB/s)", *(next((x.get("kbPerSec") for x in alloc(p) if x.get("name") == n), None)
                                            for p in (pa, pb))))
    ops = [{op: x.get("us") for bench in (s.get("bench") or {}).values() for op, x in (bench.get("ops") or {}).items()}
           for s in (a, b)]
    for op in sorted(set(ops[0]) | set(ops[1])):
        rows.append((f"bench {op} (µs)", ops[0].get(op), ops[1].get(op)))
    print(f"  {'':<40} {'A':>10} {'B':>10} {'B-A':>10}")
    for label, x, y in rows:
        fmt = lambda v: "-" if v is None else f"{v:.2f}" if isinstance(v, float) else str(v)  # noqa: E731
        delta = ("" if not all(isinstance(v, (int, float)) for v in (x, y)) else
                 f"{y - x:+d}" if all(isinstance(v, int) for v in (x, y)) else f"{y - x:+.2f}")
        print(f"  {label:<40} {fmt(x):>10} {fmt(y):>10} {delta:>10}")


def show(out, sections, args, shot_files):
    say = print
    full = args.trace == 0
    if "sessions" in sections:
        say(f"== sessions ({len(out['sessions'])})")
        for s in out["sessions"][:3]:
            say(f"  #{s.get('id')} {s.get('version')} build {s.get('build')}  {when(s.get('started'))}  {boot(s.get('boot'))}"
                f"  {s.get('frames', 0)} frames  {', '.join(s.get('zones') or []) or '-'}")
            say(f"    {perf(s.get('perf'))}")
        if not out["sessions"]:
            say("  none")
    if "perf" in sections:
        s = newest(out["sessions"])
        say("== perf")
        for line in show_perf(s, args) if s else ["none"]:
            say(f"  {line}")
    if "kept" in sections:
        s = newest(out["sessions"]) or (out["sessions"] or [{}])[0]
        say(f"== kept ({', '.join(KEPT)}: each a bug)")
        if "kept" not in s:
            say("  not recorded (a build before M0.4): see the marks' traces")
        for e in s.get("kept") or []:
            say(f"  {event(e)}")
        if s.get("kept") == []:
            say("  none")
    if "errors" in sections:
        say(f"== errors ({len(out['errors'])})")
        for e in out["errors"]:
            say(f"  x{e.get('count')} {e.get('name')}  last {when(e.get('last'))}, first {when(e.get('first'))}  {e.get('version')}")
            say(f"    {e.get('msg')}")
            for line in trim(e.get("stack"), args.full):
                say(f"      {line}")
        if not out["errors"]:
            say("  none")
    if "marks" in sections:
        say(f"== marks ({len(out['marks'])})")
        for m in out["marks"]:
            say(f"  [{m.get('kind')}] {when(m.get('t'))}  {m.get('version')}  f{m.get('frame')}  {m.get('note') or ''}".rstrip())
            for line in state(m.get("state") or {}):
                say(f"    {line}")
            if m.get("kind") == "shot":
                say(f"    shot {stamp(m.get('shot'))}")
                say(f"    file {shot_files.get(m.get('stamp')) or 'NONE (no screenshot with stamp ' + str(m.get('stamp')) + ')'}")
            for line in motion(m.get("motion") or [], full):
                say(f"    {line}")
            trace = m.get("trace") or []
            rows = layouts(trace)
            if rows:
                say("    layouts (start -> end, end->swap):")
                for r in rows:
                    say(f"      {layout_line(r)}")
            if trace:
                say(f"    trace (all {len(trace)}):" if full else f"    trace (last {min(args.trace, len(trace))} of {len(trace)}):")
                for e in trace[-args.trace:]:
                    say(f"      {event(e)}")
        if not out["marks"]:
            say("  none")
    if "shots" in sections:
        refs = os.path.relpath(out["refs"], ROOT) if out["refs"].startswith(ROOT) else out["refs"]
        say(f"== shots ({len(out['shots'])}; reference shots: {refs}/ref-<id>.*)")
        for s in out["shots"]:
            say(f"  {when(s['t'])}  {s.get('note') or ''}\n    {s['file'] or 'NO FILE for stamp ' + str(s.get('stamp'))}")
            say(f"    {s.get('id') or '(no id)'}: {stamp(s.get('at'))}")
            say(f"    reference {s['ref'] or 'NONE for ' + str(s.get('id'))}")
        if out["refs_unshot"]:
            say(f"  reference shots with no shot mark ({len(out['refs_unshot'])}): {', '.join(out['refs_unshot'])}")
        if out["unmarked_screenshots"]:
            say("  newest screenshots with no shot mark:")
            for s in out["unmarked_screenshots"]:
                say(f"    {when(s['t'])}  {s['file']}")
        if not out["shots"] and not out["unmarked_screenshots"]:
            say("  none")
    if "validation" in sections:
        v = out["validation"]
        say("== validation")
        if not v:
            say("  none (/mma check log in game)")
        else:
            say(f"  logging {'on' if v['on'] else 'off'}, {v['samples']} samples, {v['logged']} logged ({v['dropped']} over the cap)")
            for kind, n in v["counts"].items():
                say(f"  {kind:<22} {n:5} failing samples")
            for p in v["pairs"][:10]:
                e = p["example"]
                say(f"  x{p['n']:<4} {p['pair']}  (e.g. inst {e.get('inst')} {num(e.get('col'))} {num(e.get('row'))})")
    if "logs" in sections:
        ours = [e for e in out["logs"] if not e.get("addon")]
        others = [e for e in out["logs"] if e.get("addon")]
        say(f"== client logs ({len(ours)})")
        for e in ours:
            say(f"  {when(e['t'])} x{e['n']} {e['file']}: {e['text']}")
            for line in trim("\n".join(e["more"]), args.full):
                say(f"      {line}")
        if not ours:
            say("  none mentioning " + ADDON)
        if others:
            say(f"== other addons' errors while {ADDON} was loaded ({len(others)}; SHARED: may be a name both use)")
            for e in sorted(others, key=lambda e: (not e["shared"], -e["t"])):
                say(f"  {'SHARED ' if e['shared'] else ''}{e['addon']}: {when(e['t'])} x{e['n']} {e['file']}: {e['text']}")
                for line in e["more"][:None if args.full else 3]:
                    say(f"      {line}")


def since_arg(s: str) -> float:
    try:
        return NOW - float(s) * 60
    except ValueError:
        return dt.datetime.fromisoformat(s).timestamp()


def session_arg(spec: str, sessions: list):
    """An id in the SavedVariables read, or FILE:id in another."""
    path, _, sid = spec.rpartition(":")
    found = next((s for s in (sessions_of(load_sv(path)) if path else sessions) if str(s.get("id")) == sid), None)
    if not found:
        sys.exit(f"no session {sid} in {path or 'the SavedVariables'}")
    return found


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--wow", default=os.environ.get("MAGICMAP_WOW", "/Applications/World of Warcraft"))
    ap.add_argument("--flavor", default="_classic_beta_")
    ap.add_argument("--sv", help="SavedVariables file (default: the newest account's)")
    ap.add_argument("--refs", default=REFS, help="reference shots, ref-<id>.jpg|png (default docs/evidence/shots)")
    ap.add_argument("--since", type=since_arg, help="minutes ago, or an ISO time")
    for s in SECTIONS:
        ap.add_argument("--" + s, action="store_true", help=f"show only {s} (combinable)")
    ap.add_argument("--json", action="store_true", help="everything, as JSON")
    ap.add_argument("--budgets", action="store_true", help="newest session's perf against the budgets; exit 1 on a FAIL")
    ap.add_argument("--compare", nargs=2, metavar=("A", "B"), help="two sessions side by side: ids, or FILE:id")
    ap.add_argument("--trace", type=int, nargs="?", const=0, default=40,
                    help="trace events per mark (default 40); alone: every event, ledger events, motion rings frame by frame")
    ap.add_argument("--full", action="store_true", help="full stacks and log entries, not just our frames")
    args = ap.parse_args(argv)

    flavor = os.path.join(args.wow, args.flavor)
    missing = []
    if not os.path.isdir(flavor):
        missing.append(f"no client at {flavor} (--wow / MAGICMAP_WOW, --flavor)")
    sv = args.sv or find_sv(flavor)
    db = None
    if not sv or not os.path.exists(sv):
        missing.append(f"no SavedVariables yet: /reload in game (looked for {sv or os.path.join(flavor, 'WTF/Account/*/SavedVariables', ADDON + '.lua')})")
    else:
        db = load_sv(sv)
        if not db:
            missing.append(f"{sv} has no MagicMapAtlasDB: /reload in game")
        elif not db.get("telemetry"):
            missing.append("no telemetry in SavedVariables yet: install a build with Telemetry (tools/install.py) and /reload")
    since = args.since or 0
    out = collect(db, flavor, since, args.since or NOW - DAY, args.refs)
    out.update(sv=sv, missing=missing)
    shot_files = {s["stamp"]: s["file"] for s in out["shots"]}
    if args.compare:
        compare(*(session_arg(spec, sessions_of(db)) for spec in args.compare))
        return 0
    if args.budgets:
        rc = budgets(out["sessions"], out["errors"])
        if args.trace == 0:
            show(out, ["perf", "kept", "marks"], args, shot_files)
        return rc
    if args.json:
        json.dump(out, sys.stdout, indent=1, default=str)
        print()
        return 0
    sections = [s for s in SECTIONS if getattr(args, s)] or ["sessions", *SECTIONS]
    if sv and os.path.exists(sv):
        print(f"{sv}  (written {ago(os.path.getmtime(sv))})")
    for m in missing:
        print("! " + m)
    show(out, sections, args, shot_files)
    return 0


if __name__ == "__main__":
    sys.exit(main())
