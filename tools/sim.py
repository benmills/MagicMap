"""The simulated WoW Forever client (tools/tests/wowsim.lua) with MagicMapAtlas loaded and logged
in, on the counted clock, for scripts and the shell. The tests boot through it too (load:
test_addon.boot; harness: the replays' T, test_spike_bugs.py).

    import sim                                 # (tools/ on sys.path)
    s = sim.boot(priced=True)                  # + Sim.Price: what the client charges (docs/evidence/perf-m0.md)
    s.slash("/mma toggle"); s.run(3)           # the map open, past its first-open grace
    s.wheel(3); s.drag(200, 0, 20); s.walk(10, "east"); s.press("M")
    s.perf(); s.errors(); s.layers()           # FrameStats (+ names: Runtime.Perf), errors, live regions per layer
    s.lua("local sim, ns = ... return ns.UI.Camera.cam.zoom")
    s.L, s.sim, s.ns, s.T                      # the Lua, wowsim's Sim, the addon's ns, the harness (T.Fresh, T.Ours, ...)

    .venv/bin/python tools/sim.py --priced --run 'slash /mma toggle; run 3; wheel 3; run 2; perf; layers'

Script commands, ';' or newline apart (Lua needs no ';'):
    run SECONDS | step [N] | slash LINE | press KEY | wheel N [FRAME] | drag DX DY [FRAMES]
    walk SECONDS [north|east|south|west|RADIANS] [YD/S, default 7] | lua CODE (gets sim, ns as ...)
    perf | errors | layers
Exits 1 if the sim or Runtime caught an error (listed last).
"""
import argparse
import json
import math
import os
import sys

from lupa import lua51

import luacheck

TESTS = os.path.join(os.path.dirname(os.path.abspath(__file__)), "tests")
# No saved data given: the map's window as the tests have it (UI's saved part, ui/View.lua): hidden
# at login (/mma toggle opens it), 720x520 in the screen's middle, 96 px a tile. A first login's shows
# on the minimap's spot (test_chrome.py).
TEST_UI = "MagicMapAtlasDB = { UI = { _v = 1, shown = false, zoom = 96, window = { left = 600, top = 800, w = 720, h = 520 } } }"
FACING = {"north": 0, "east": math.pi / 2, "south": math.pi, "west": 3 * math.pi / 2}  # the sim's


def files():
    """The TOC's files that exist (test_luacheck flags what's missing)."""
    return [os.path.join(luacheck.ROOT, f) for f in luacheck.toc_files() if os.path.exists(os.path.join(luacheck.ROOT, f))]


def load(saved=None):
    """A simulated client with MagicMapAtlas loaded and logged in: (Lua, Sim, ns), on the counted clock
    (Sim.Counted: what a budgeted call or job gets done is the same on every machine).
    saved: Lua source for the SavedVariables (MagicMapAtlasDB = ...) found at load (default TEST_UI)."""
    L = lua51.LuaRuntime(encoding="latin-1", unpack_returned_tuples=True)
    sim = L.eval("function(path) return assert(loadfile(path))() end")(os.path.join(TESTS, "wowsim.lua"))
    sim.Counted()
    ns = L.table()
    run = L.eval("""function(path, ns)
        local chunk, err = loadfile(path)
        if not chunk then error(err, 0) end
        return Sim.Call("loading " .. path:match("[^/]+/[^/]+$"), chunk, "MagicMapAtlas", ns)
    end""")
    for path in files():
        run(path, ns)
    L.execute(saved or TEST_UI)
    sim.FireEvent("ADDON_LOADED", "MagicMapAtlas")
    sim.FireEvent("PLAYER_LOGIN")
    sim.FireEvent("PLAYER_ENTERING_WORLD", True, False)
    return L, sim, ns


def errors(sim, ns):
    out = [str(e) for e in sim.errors.values()]
    out += [f"{e.name}: {e.err}" for e in ns.Runtime.errors.values()]
    return out


def harness(L, skip=None):
    """The replays' T (tools/tests/harness.lua) in L; T.Print prints, T.Skip is skip."""
    return L.eval("function(path, ...) return assert(loadfile(path))(...) end")(
        os.path.join(TESTS, "harness.lua"), TESTS, L.table_from(files()), print, skip, TEST_UI)


def py(v, depth=8):
    """A Lua value as Python's: a table a list (keys 1..n) or a dict, `depth` deep."""
    if lua51.lua_type(v) != "table":
        return v
    if depth == 0:
        return "<table>"
    d = {k: py(x, depth - 1) for k, x in v.items()}
    return [d[i] for i in range(1, len(d) + 1)] if d and all(i in d for i in range(1, len(d) + 1)) else d


class Client:
    """A booted client: L (the Lua), sim (wowsim's Sim), ns (the addon's), T (the replays' harness)."""

    def __init__(self, saved=None, priced=False):
        self.L, self.sim, self.ns = load(saved)
        self.T = harness(self.L)
        self.sim.Price(priced)

    def run(self, seconds):
        """Frames at 60 fps."""
        self.sim.Run(seconds)

    def step(self, n=1):
        for _ in range(n):
            self.sim.Step()

    def slash(self, line):
        """A typed chat command: the chat lines it printed."""
        n = len(self.sim.prints)
        self.sim.Slash(line)
        return [self.sim.prints[i] for i in range(n + 1, len(self.sim.prints) + 1)]

    def press(self, key):
        """A key binding: M, L, ESCAPE."""
        self.sim.Press(key)

    def frame(self, at=None):
        """at: a frame, a named frame's name, or None: the map's view."""
        if at is None:
            return self.ns.UI.Window.view
        return self.sim.Named(at) if isinstance(at, str) else at

    def wheel(self, n, at=None):
        """n notches over `at` (negative: out), a frame apart."""
        f = self.frame(at)
        for _ in range(abs(n)):
            self.sim.Wheel(f, 1 if n > 0 else -1)
            self.sim.Step()

    def drag(self, dx, dy, frames=20, at=None):
        """Press, move (dx, dy) px over `frames` frames, release (Sim.Drag)."""
        self.sim.Drag(self.frame(at), dx, dy, frames)

    def walk(self, seconds, facing=0.0, speed=7):
        """Move for `seconds` at `speed` yd/s (7 running, 14 mounted), facing radians (0 north, pi/2
        east: the sim's) or a direction's name, then stop."""
        p = self.sim.player
        p.facing, p.speed = FACING.get(facing, facing), speed
        self.sim.Run(seconds)
        p.speed = 0

    def lua(self, code, *args):
        """A Lua chunk run with (sim, ns, *args) as `...`: what it returns."""
        return self.L.execute(code, self.sim, self.ns, *args)

    def perf(self):
        """Runtime.FrameStats() (p95, byState, alloc, ledger, ...: runtime/Runtime.lua) as a dict;
        names: Runtime.Perf()'s per-name calls (n, max, over, kb, ...)."""
        out = py(self.ns.Runtime.FrameStats())
        out["names"] = py(self.ns.Runtime.Perf()[0])
        return out

    def errors(self):
        """The sim's errors and Runtime's, as strings."""
        return errors(self.sim, self.ns)

    def layers(self):
        """Live regions per map layer on its shown canvas (T.Live)."""
        return {lay.name: self.T.Live(lay) for lay in self.ns.UI.Engine.layers.values()}


def boot(saved=None, priced=False):
    return Client(saved, priced)


def digest(p):
    """perf() in a few lines: its numbers, a line per table (the ledger's frames without their
    events, gaps without stacks), and the 10 slowest calls by name."""
    names = p.pop("names")
    for f in p.get("ledger") or []:
        f.pop("events")
    for g in p.get("gaps") or []:
        g.pop("stack", None)
    rows = [" ".join(f"{k} {v}" for k, v in sorted(p.items()) if not isinstance(v, (dict, list)))]
    rows += [f"{k}: {json.dumps(v)}" for k, v in sorted(p.items()) if isinstance(v, (dict, list)) and v]
    slow = sorted(names.items(), key=lambda kv: -kv[1]["max"])[:10]
    rows.append("slowest calls (max ms, n, over): " + ", ".join(f"{k} {v['max']:.2f} {v['n']:g} {v['over']:g}" for k, v in slow))
    return "\n".join(rows)


def command(s, line):
    """One script command: what it prints, if anything."""
    name, _, rest = line.partition(" ")
    a = rest.split()
    if name == "run":
        s.run(float(a[0]))
    elif name == "step":
        s.step(int(a[0]) if a else 1)
    elif name == "slash":
        return "\n".join(s.slash(rest))
    elif name == "press":
        s.press(a[0])
    elif name == "wheel":
        s.wheel(int(a[0]), a[1] if len(a) > 1 else None)
    elif name == "drag":
        s.drag(float(a[0]), float(a[1]), int(a[2]) if len(a) > 2 else 20)
    elif name == "walk":
        facing = a[1] if len(a) > 1 else "north"
        s.walk(float(a[0]), facing if facing in FACING else float(facing), float(a[2]) if len(a) > 2 else 7)
    elif name == "lua":
        got = s.lua(rest)
        return json.dumps(py(got) if not isinstance(got, tuple) else [py(v) for v in got], default=str)
    elif name == "perf":
        return digest(s.perf())
    elif name == "errors":
        return "\n".join(s.errors()) or "none"
    elif name == "layers":
        return " ".join(f"{k} {v:g}" for k, v in s.layers().items())
    else:
        raise SystemExit(f"unknown command: {line}")


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--priced", action="store_true", help="Sim.Price on from login")
    ap.add_argument("--saved", help="Lua source for the SavedVariables found at load (default: the map hidden, sim.TEST_UI)")
    ap.add_argument("--run", action="append", default=[], help="a script (above); several run in turn")
    args = ap.parse_args(argv)
    s = boot(args.saved, args.priced)
    for line in (c.strip() for script in args.run for c in script.replace("\n", ";").split(";")):
        out = command(s, line) if line else None
        if out:
            print(f"> {line}\n{out}")
    errs = s.errors()
    if errs:
        print(f"> {len(errs)} errors\n" + "\n\n".join(errs))
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main())
