"""The spike's bugs replayed in the sim: every "Replayable now" scenario of
docs/evidence/spike-bugs.md, one file per bug id, tools/tests/replays/R-<id>.lua
(the doc's replay column names them as test_spike_bugs.py::test_replay[<id>]).
Each sets the initial state, drives inputs frame by frame, and asserts the
outcome the table claims: PREVENTED (the failure can't happen), CONTAINED (it
happens, isolated, recorded in telemetry, the rest runs on), or for MOVED rows
the part the design does bound, with the measured rest printed (pytest -s).

This file collects them: each R-<id>.lua is a Lua chunk called with T, the
harness (harness.lua), in a Lua of its own. A new replay is a new file."""
import glob
import os

import pytest
from lupa import lua51

import sim

REPLAYS = os.path.join(sim.TESTS, "replays")

# Replays a price measured in game fails (docs/evidence/perf-m0.md), each until the package named flips it.
XFAIL = {}


def ids():
    return [pytest.param(b, marks=pytest.mark.xfail(strict=True, reason=XFAIL[b])) if b in XFAIL else b
            for b in sorted(os.path.basename(p)[len("R-"):-len(".lua")] for p in glob.glob(os.path.join(REPLAYS, "R-*.lua")))]


@pytest.mark.parametrize("bug", ids())
def test_replay(bug):
    L = lua51.LuaRuntime(encoding="latin-1", unpack_returned_tuples=True)
    T = sim.harness(L, pytest.skip)
    L.eval("function(path, T) return assert(loadfile(path))(T) end")(os.path.join(REPLAYS, f"R-{bug}.lua"), T)
