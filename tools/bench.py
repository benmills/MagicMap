#!/usr/bin/env python3
"""Benchmark the addon's per-frame work on the simulated client, with the
real Forever data: Lua time and widget calls per frame (calls into the
engine are what an addon's frame cost is mostly made of), and how often zone
borders failed to cover the view ("lines not keeping up").

  python3 tools/bench.py                 # every bench
  python3 tools/bench.py fast_pan -v     # one, with the busiest widget calls

Lua time here is the addon's own Lua on this machine; the client adds its
engine-side cost per call on top, so compare calls first and time second.
--call-us charges each widget call that many microseconds on the addon's
clock (debugprofilestop), so time-sliced work like the border builder takes
as many frames as it would in the client, and gaps show it.
"""
from __future__ import annotations

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from smoketest import TESTS, boot, new_client  # noqa: E402

PROBE = """
local Sim, ns, callUs = ...
local frames = {}
if callUs > 0 then
    function debugprofilestop() return os.clock() * 1000 + Sim.callTotal * callUs / 1000 end
end
local step = Sim.Step
Sim.Step = function(elapsed)
    local calls0, t0 = Sim.callTotal, os.clock()
    step(elapsed)
    local f = { ms = (os.clock() - t0) * 1000, calls = Sim.callTotal - calls0 }
    -- Did the borders on screen cover the whole view?
    local g = ns.GeometryInfo and ns.GeometryInfo()
    if g then
        local w, h = ns.viewport:GetSize()
        local st = ns.state
        local hw, hh = w / 2 / st.zoom, h / 2 / st.zoom
        local r = g.region
        f.gap = not (r and st.cx - hw >= r[1] and st.cy - hh >= r[2] and st.cx + hw <= r[3] and st.cy + hh <= r[4])
        f.building = g.building
    end
    frames[#frames + 1] = f
end
return frames
"""


def run(name: str, verbose: bool, call_us: float = 0) -> dict:
    L, sim = new_client("forever")
    ns = boot(L, sim)
    sim.Run(3)  # settle after login
    sim.CountCalls()
    frames = L.eval("function(src, ...) return assert(loadstring(src))(...) end")(PROBE, sim, ns, call_us)
    benches = L.eval("function(path, ...) return assert(loadfile(path))(...) end")(
        os.path.join(TESTS, "bench.lua"), sim, ns)
    benches[name]()
    rows = [frames[i] for i in range(1, len(frames) + 1)]
    ms = sorted(r["ms"] for r in rows)
    calls = sorted(r["calls"] for r in rows)
    errors = [str(e) for e in sim.errors.values()]

    def pct(xs, p):
        return xs[min(len(xs) - 1, int(len(xs) * p))]

    result = {
        "frames": len(rows),
        "ms_mean": sum(ms) / len(ms), "ms_p95": pct(ms, 0.95), "ms_max": ms[-1],
        "calls_mean": sum(calls) / len(calls), "calls_p95": pct(calls, 0.95), "calls_max": calls[-1],
        "gap_frames": sum(1 for r in rows if r["gap"]),
        "errors": errors,
    }
    if verbose:
        busiest = sorted(((v, k) for k, v in sim.calls.items()), reverse=True)[:12]
        result["busiest"] = [(k, v) for v, k in busiest]
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("benches", nargs="*", default=["follow_ride", "fast_pan", "continent_pan", "wheel_zoom"])
    parser.add_argument("-v", "--verbose", action="store_true")
    parser.add_argument("--call-us", type=float, default=0, help="client cost per widget call, microseconds")
    ns = parser.parse_args()
    print(f"{'bench':15} {'frames':>6} {'ms mean':>8} {'p95':>6} {'max':>7} {'calls mean':>11} {'p95':>6} {'max':>6} {'border gaps':>12}")
    for name in ns.benches:
        r = run(name, ns.verbose, ns.call_us)
        print(f"{name:15} {r['frames']:6d} {r['ms_mean']:8.2f} {r['ms_p95']:6.2f} {r['ms_max']:7.2f} "
              f"{r['calls_mean']:11.0f} {r['calls_p95']:6d} {r['calls_max']:6d} {r['gap_frames']:5d} frames")
        for k, v in r.get("busiest", []):
            print(f"    {k:28} {v}")
        for e in r["errors"]:
            print("    ERROR " + e.split("\nstack traceback:")[0])


if __name__ == "__main__":
    main()
