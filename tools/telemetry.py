"""Read what MagicMapAtlas left on disk: play, /reload, run this (docs/telemetry.md).

  .venv/bin/python tools/telemetry.py                  # sessions, errors, marks, shots, validation, logs
  .venv/bin/python tools/telemetry.py --errors --full  # one section (--errors --marks --shots --validation --logs)
  .venv/bin/python tools/telemetry.py --since 30       # last 30 minutes (or an ISO time)
  .venv/bin/python tools/telemetry.py --json           # everything, machine-readable
  .venv/bin/python tools/telemetry.py --budgets        # newest session's perf against docs/runtime.md: PASS/FAIL

The install is "/Applications/World of Warcraft" (MAGICMAP_WOW, --wow), flavor _classic_beta_
(--flavor); SavedVariables is the newest WTF/Account/*/SavedVariables/MagicMapAtlas.lua (--sv).
"""
from __future__ import annotations

import argparse
import datetime as dt
import glob
import json
import os
import re
import sys
import time

from lupa import lua51

ADDON = "MagicMapAtlas"
NOW = time.time()
DAY = 86400
SECTIONS = ("errors", "marks", "shots", "validation", "logs")

# docs/runtime.md "Budgets": (label, value from a session's perf, limit, unit).
BUDGETS = (
    ("frame cost p95", lambda p: p.get("p95"), 1.0, "ms"),
    ("frame cost p99", lambda p: p.get("p99"), 5.0, "ms"),
    ("frame cost max (outside graces)", lambda p: p.get("max"), 8.0, "ms"),
    ("first map open, slowest frame", lambda p: (p.get("grace") or {}).get("map"), 50.0, "ms"),
    ("load (Data + Atlas)", lambda p: p.get("loadMs"), 250.0, "ms"),
    ("our Lua memory at logout", lambda p: p.get("ourKB") and p["ourKB"] / 1024, 64.0, "MB"),
    ("Lua allocation (outside graces)", lambda p: p.get("kbPerSec"), 50.0, "KB/s"),
    ("errors per hour", lambda p: p.get("errorsPerHour"), 0, "/h"),
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
    return f"{v:g}" if isinstance(v, float) else str(v)


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


OURS = re.compile(r'\[string "@?(Interface[/\\]AddOns[/\\])?' + ADDON + r'[/\\]([^"]*)"\]|Interface[/\\]AddOns[/\\]' + ADDON + r'[/\\]')


def trim(stack: str, full: bool) -> list[str]:
    lines = (stack or "").splitlines()
    return lines if full else [OURS.sub(lambda m: m.group(2) or "", l) for l in lines if ADDON in l]


# Collecting ----------------------------------------------------------------------------------

STAMP = re.compile(r"WoWScrnShot_(\d{6}_\d{6})\.\w+$")


def stamp_time(stamp: str):
    try:
        return dt.datetime.strptime(stamp, "%m%d%y_%H%M%S").timestamp()
    except ValueError:
        return None


def shots(flavor: str, marks: list, since: float):
    files = []
    for p in glob.glob(os.path.join(flavor, "Screenshots", "WoWScrnShot_*")):
        m = STAMP.search(p)
        if m and stamp_time(m.group(1)):
            files.append((stamp_time(m.group(1)), os.path.abspath(p)))
    used, out = set(), []
    for mk in (m for m in marks if m.get("kind") == "shot"):
        t = stamp_time(mk.get("stamp") or "") or mk.get("t", 0)
        near = min(files, key=lambda f: abs(f[0] - t), default=None)
        path = near[1] if near and abs(near[0] - t) <= 3 else None
        used.add(path)
        out.append({"t": mk.get("t"), "stamp": mk.get("stamp"), "note": mk.get("note"), "file": path})
    unmarked = sorted((f for f in files if f[1] not in used and f[0] >= since), reverse=True)[:5]
    return out, [{"t": t, "file": p} for t, p in unmarked]


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


def collect(db, flavor, since, log_since):
    tel = (db or {}).get("telemetry") or {}
    marks = [m for m in reversed(tel.get("marks") or []) if m.get("t", 0) >= since]
    errors = sorted((e for e in (tel.get("errors") or {}).values() if e.get("last", 0) >= since), key=lambda e: -e.get("last", 0))
    shot_marks, unmarked = shots(flavor, marks, since)
    return {
        "telemetry": bool(tel),
        "sessions": [s for s in reversed(tel.get("sessions") or []) if isinstance(s, dict) and s.get("started", 0) >= since],
        "errors": errors, "marks": marks, "shots": shot_marks, "unmarked_screenshots": unmarked,
        "validation": validation((db or {}).get("validation")), "logs": logs(flavor, log_since, loaded(tel)),
    }


def loaded(tel):
    """When our addon was loaded, from its sessions: each from its start to the next one's (or now)."""
    starts = sorted(s["started"] for s in tel.get("sessions") or [] if isinstance(s, dict) and s.get("started"))
    return [(a, b) for a, b in zip(starts, starts[1:] + [NOW + DAY])] if starts else None


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
            + (f"; alloc p95 {num(p.get('kbFrameP95'))} KB/frame, {num(p.get('kbPerSec'))} KB/s"
               if p.get("kbPerSec") is not None else "")
            + "".join(f"\n      slow: {s.get('name')} x{s.get('n')} max {num(s.get('max'))} ms" for s in p.get("slow") or []))


def budgets(sessions) -> int:
    """The newest session with perf against BUDGETS: a PASS/FAIL line each; 1 if any FAIL."""
    s = next((s for s in sessions if isinstance(s.get("perf"), dict)), None)
    if not s:
        print("! no session with perf yet: /reload in game")
        return 1
    p, failed = s["perf"], 0
    print(f"== budgets: session #{s.get('id')} {s.get('version')}, {p.get('frames', 0)} frames (docs/runtime.md)")
    for label, get, limit, unit in BUDGETS:
        v = get(p)
        if v is None:
            print(f"  ----  {label:<34} no data (limit {num(limit)} {unit})")
            continue
        ok = v <= limit
        failed += not ok
        print(f"  {'PASS' if ok else 'FAIL'}  {label:<34} {v:.2f} {unit} (limit {num(limit)})")
    return 1 if failed else 0


def show(out, sections, args, shot_files):
    say = print
    if "sessions" in sections:
        say(f"== sessions ({len(out['sessions'])})")
        for s in out["sessions"][:3]:
            say(f"  #{s.get('id')} {s.get('version')} build {s.get('build')}  {when(s.get('started'))}  {boot(s.get('boot'))}"
                f"  {s.get('frames', 0)} frames  {', '.join(s.get('zones') or []) or '-'}")
            say(f"    {perf(s.get('perf'))}")
        if not out["sessions"]:
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
                say(f"    file {shot_files.get(m.get('stamp')) or 'NONE (no screenshot with stamp ' + str(m.get('stamp')) + ')'}")
            trace = m.get("trace") or []
            if trace:
                say(f"    trace (last {min(args.trace, len(trace))} of {len(trace)}):")
                for e in trace[-args.trace:]:
                    say(f"      {event(e)}")
        if not out["marks"]:
            say("  none")
    if "shots" in sections:
        say(f"== shots ({len(out['shots'])})")
        for s in out["shots"]:
            say(f"  {when(s['t'])}  {s.get('note') or ''}\n    {s['file'] or 'NO FILE for stamp ' + str(s.get('stamp'))}")
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


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--wow", default=os.environ.get("MAGICMAP_WOW", "/Applications/World of Warcraft"))
    ap.add_argument("--flavor", default="_classic_beta_")
    ap.add_argument("--sv", help="SavedVariables file (default: the newest account's)")
    ap.add_argument("--since", type=since_arg, help="minutes ago, or an ISO time")
    for s in SECTIONS:
        ap.add_argument("--" + s, action="store_true", help=f"show only {s} (combinable)")
    ap.add_argument("--json", action="store_true", help="everything, as JSON")
    ap.add_argument("--budgets", action="store_true", help="newest session's perf against the budgets; exit 1 on a FAIL")
    ap.add_argument("--trace", type=int, default=40, help="trace events per mark (default 40)")
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
    out = collect(db, flavor, since, args.since or NOW - DAY)
    out.update(sv=sv, missing=missing)
    if args.budgets:
        return budgets(out["sessions"])
    if args.json:
        json.dump(out, sys.stdout, indent=1, default=str)
        print()
        return 0
    sections = [s for s in SECTIONS if getattr(args, s)] or ["sessions", *SECTIONS]
    if sv and os.path.exists(sv):
        print(f"{sv}  (written {ago(os.path.getmtime(sv))})")
    for m in missing:
        print("! " + m)
    show(out, sections, args, {s["stamp"]: s["file"] for s in out["shots"]})
    return 0


if __name__ == "__main__":
    sys.exit(main())
