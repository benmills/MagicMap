"""/mma bench regions and /mma check art in the sim: the bench's result has its shape and
came from a job that gave frames back; a missing atlas, chain or font is one `art` trace, at login
and on demand, and the art UI draws on Forever none."""
from test_addon import boot, errors

CANVAS = ["canvas." + op + "@" + at for at in ("100live", "1000live", "1000hidden")
          for op in ("SetPoint", "SetScale", "SetAlpha", "Hide", "Show")]
MOVED = ["canvas.Show.moved@1000live", "canvas.Show.moved.alpha0@1000live", "canvas.SetAlpha.moved@1000live",
         "canvas.Show.moved@100masked"]  # the swap's question (M1.3)
FRAMES = ["frame.idle", "frame.moved.alpha0", "frame.moved.hidden"]  # the whole frame: what the client defers to drawing
OPS = ["CreateTexture", "CreateLine", "CreateFontString", "SetPoint", "SetStartPoint",
       "SetParent.park", "SetParent.unpark"] + CANVAS + MOVED + FRAMES


def test_bench_regions():
    L, sim, ns = boot()  # the counted clock: 3 us a widget call
    sim.Slash("/mma bench regions")
    sim.Run(5)
    r = ns.Game.Bench.result
    assert r.build == "1.60.1.70009" and r.t > 0
    assert sorted(r.ops.keys()) == sorted(OPS)
    for op in OPS:  # each a single widget call, timed alone (a frame: the sim's frames cost what our calls do)
        o = r.ops[op]
        assert o.n == (20 if op.startswith(("canvas.", "frame.")) else 100) and (op in FRAMES or o.us == 3), op
    assert ns.Runtime.Perf()[0]["bench: regions"].n > 5  # a job, resumed over many frames
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


def test_check_art():
    """As on Forever: the mode button's chains are there by their fallbacks (no `-c60` atlas), the
    fonts by SetFont (GetFileIDFromPath knows none); a chain with none of it is one miss, its first."""
    L, sim, ns = boot()
    art, normal = ns.UI.Art, ns.UI.Controls.mode.GetNormalTexture(ns.UI.Controls.mode)
    assert sim.atlases["redbutton-expand-c60"] is None and normal.GetAtlas(normal) == "redbutton-expand"
    art.atlases[len(art.atlases) + 1] = L.table("no-such-atlas", "nor-this")
    art.fonts[len(art.fonts) + 1] = "Fonts\\NOPE.TTF"
    traced = lambda: [e.d for e in ns.Runtime.TraceCopy().values() if e.k == "art"]  # noqa: E731
    sim.Run(5)
    assert traced() == []  # inside login's grace
    sim.Run(2)
    assert traced() == ["no-such-atlas", "Fonts\\NOPE.TTF"]
    sim.Slash("/mma check art")
    assert traced() == ["no-such-atlas", "Fonts\\NOPE.TTF"] * 2
    assert list(sim.prints.values())[-1] == "  art missing: no-such-atlas, Fonts\\NOPE.TTF"
    art.atlases[len(art.atlases)] = None
    art.fonts[len(art.fonts)] = None
    sim.Slash("/mma check art")
    assert len(traced()) == 4 and "art: all" in list(sim.prints.values())[-1]
    sim.Slash("/mma toggle")  # the labels draw in the fonts checked
    sim.Run(1)
    labels = ns.UI.Labels.front.pools.label
    drawn = {labels[i].GetFont(labels[i])[0] for i in range(1, labels.n + 1)}
    assert drawn and drawn <= set(art.fonts.values()), drawn
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))
