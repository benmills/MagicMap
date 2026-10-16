"""/mma bench regions and /mma check art in the sim: the bench's result has its shape and
came from a job that gave frames back; a missing atlas is one `art` trace, at login and on demand."""
from test_addon import boot, errors

CANVAS = ["canvas." + op + "@" + at for at in ("100live", "1000live", "1000hidden")
          for op in ("SetPoint", "SetScale", "SetAlpha", "Hide", "Show")]
OPS = ["CreateTexture", "CreateLine", "CreateFontString", "SetPoint", "SetStartPoint",
       "SetParent.park", "SetParent.unpark"] + CANVAS


def test_bench_regions():
    L, sim, ns = boot()  # the counted clock: 3 us a widget call
    sim.Slash("/mma bench regions")
    sim.Run(5)
    r = ns.Game.Bench.result
    assert r.build == "1.60.1.70009" and r.t > 0
    assert sorted(r.ops.keys()) == sorted(OPS)
    for op in OPS:  # each a single widget call, timed alone
        o = r.ops[op]
        assert o.n == (20 if op.startswith("canvas.") else 100) and o.us == 3, op
    assert ns.Runtime.Perf()[0]["bench: regions"].n > 5  # a job, resumed over many frames
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


def test_check_art():
    L, sim, ns = boot()
    ns.UI.Art.atlases[len(ns.UI.Art.atlases) + 1] = "no-such-atlas"
    art = lambda: [e.d for e in ns.Runtime.TraceCopy().values() if e.k == "art"]  # noqa: E731
    sim.Run(5)
    assert art() == []  # inside login's grace
    sim.Run(2)
    assert art() == ["no-such-atlas"]
    sim.Slash("/mma check art")
    assert art() == ["no-such-atlas"] * 2 and "no-such-atlas" in str(list(sim.prints.values()))
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))
