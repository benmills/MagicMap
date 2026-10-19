"""The spike's bugs replayed in the sim: every "Replayable now" scenario of
docs/evidence/spike-bugs.md, one file per bug id, tools/tests/replays/R-<id>.lua
(the doc's replay column names them as test_spike_bugs.py::test_replay[<id>]).
Each sets the initial state, drives inputs frame by frame, and asserts the
outcome the table claims: PREVENTED (the failure can't happen), CONTAINED (it
happens, isolated, recorded in telemetry, the rest runs on), or for MOVED rows
the part the design does bound, with the measured rest printed (pytest -s).

This file collects them: each R-<id>.lua is a Lua chunk called with T, the
harness (harness.lua), in a Lua of its own. A new replay is a new file.

test_replay_no_data: each again without the QuestieDB-derived data (D1: a build without it works;
parity F56), where it's here (CI's checkout has none: test_replay is that run there). Every boot of
either ends with no error but those its replay makes on purpose (ERRORS), and says NOTICE in chat
once without the data, never with it. R-G5 draws the pins and reads the reduced quest tooltip."""
import glob
import os

import pytest
from lupa import lua51

import luacheck
import sim

REPLAYS = os.path.join(sim.TESTS, "replays")

# Replays a price measured in game fails (docs/evidence/perf-m0.md), each until the package named flips it.
XFAIL = {}

# The errors a replay makes on purpose (and checks itself), by Runtime's name.
ERRORS = {"E1": {"map: borders"}, "E2": {"game.part vignettes"}, "E7": {"map: borders", "test.every-frame"}}
# game/NoData.lua's line (QuestInfo.lua:74, in Game.Say's prefix).
NOTICE = "|cffffd100MagicMapAtlas|r: QuestieDB isn't loaded: quests show without their mobs and items."


def ids():
    return [pytest.param(b, marks=pytest.mark.xfail(strict=True, reason=XFAIL[b])) if b in XFAIL else b
            for b in sorted(os.path.basename(p)[len("R-"):-len(".lua")] for p in glob.glob(os.path.join(REPLAYS, "R-*.lua")))]


def replay(bug, data):
    L = lua51.LuaRuntime(encoding="latin-1", unpack_returned_tuples=True)
    T = L.eval("function(path, ...) return assert(loadfile(path))(...) end")(
        os.path.join(sim.TESTS, "harness.lua"), sim.TESTS, L.table_from(sim.files(data)), print, pytest.skip, sim.TEST_UI)
    boots = L.eval("""function(T)
        local boots, boot = {}, T.Boot
        T.Boot = function(...)
            local sim, ns = boot(...)
            boots[#boots + 1] = { sim, ns }
            return sim, ns
        end
        return boots
    end""")(T)
    L.eval("function(path, T) return assert(loadfile(path))(T) end")(os.path.join(REPLAYS, f"R-{bug}.lua"), T)
    for b in boots.values():
        s, ns = b[1], b[2]
        assert {str(e.name) for e in ns.Runtime.errors.values()} == ERRORS.get(bug, set()) and not list(s.errors.values()), \
            "\n\n".join(sim.errors(s, ns))
        notices = sum(1 for line in s.prints.values() if line == NOTICE)
        assert notices == (0 if ns.Atlas.Data.Quests else 1), f"{notices} notices"


@pytest.mark.parametrize("bug", ids())
def test_replay(bug):
    replay(bug, True)


@pytest.mark.parametrize("bug", ids())
def test_replay_no_data(bug):
    if not any(os.path.exists(os.path.join(luacheck.ROOT, f)) for f in sim.QUESTIE):
        pytest.skip("no QuestieDB-derived data here: test_replay ran without it")
    replay(bug, False)
