"""Overlapping pins grouped (ui/Cluster.lua): five pins at one spot draw as one pill, none of them alone; with
"Group overlapping icons" off (UI.saved.cluster), all five draw and no pill does; the tracked one always draws alone.

test_pill_members_new_tables: the same five, their entries made anew twice within the regroup's 0.5 s (as
model/Blips.lua's Live() does each sensor change), with the harness's one-thing-one-pin check on every frame
(T.strictPins: docs/hardening-plan.md T1): today each draws alone beside the pill holding it (P1)."""
import pytest
from lupa import lua51

import sim as simmod
from test_addon import boot, errors

# A clustered test layer: n pins at (cx, cy), all one spot.
LAYER = """function(Pins, n, cx, cy)
    local t = { rev = 1, list = {} }
    for i = 1, n do
        t.list[i] = { key = "c" .. i, kind = "test", name = "Pin " .. i, text = "", live = true,
            pos = { inst = 0, col = cx, row = cy } }
    end
    t.layer = Pins.Layer("clustertest", 7, function(put)
        for _, e in ipairs(t.list) do put(e, { size = 14, icon = { color = { 1, 1, 1 } } }) end
    end, function() return t.rev end, { cluster = true })
    return t
end"""

# The regions a layer's front canvas shows, of one kind (0 when it shows none).
SHOWN = """function(layer, kind)
    local c = layer.front
    local p = c and c.alpha > 0 and c.pools[kind]
    return p and p.n or 0
end"""


def test_five_overlapping_pins_one_pill():
    L, sim, ns = boot()
    ns.UI.saved.cluster = True  # (the tests' saved state has it off)
    sim.Slash("/mm toggle")
    sim.Run(1)
    cam = ns.UI.Camera.cam
    t = L.eval(LAYER)(ns.UI.Pins, 5, cam.cx, cam.cy)
    sim.Run(0.5)
    shown, layers = L.eval(SHOWN), ns.UI.Engine.layers
    pills = next(lay for lay in layers.values() if lay.name == "clusters")
    assert shown(pills, "pill") >= 1 and shown(t.layer, "pin") == 0  # a pill for them (Goldshire's own pins may group too); none drawn

    # The one you track leaves the pill: drawn alone at once (ui/Track.lua's Focus), the rest still grouped.
    ns.UI.Track.Start(t.list[3])  # (the waypoint at it, as the menu's Track)
    sim.Run(0.5)
    assert shown(t.layer, "pin") == 1 and shown(pills, "pill") >= 1
    ns.UI.Track.Stop()
    sim.Run(0.5)
    assert shown(t.layer, "pin") == 0

    ns.UI.saved.cluster = False  # the gear's setting, off: laid out again
    t.rev = 2
    sim.Run(0.5)
    assert shown(t.layer, "pin") == 5 and shown(pills, "pill") == 0
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


# The entries made anew, the same keys (model/Blips.lua's Live(): new tables each sensor change).
RENEW = """function(t)
    local new = {}
    for i, e in ipairs(t.list) do
        new[i] = { key = e.key, kind = e.kind, name = e.name, text = "", live = true,
            pos = { inst = e.pos.inst, col = e.pos.col, row = e.pos.row } }
    end
    t.list, t.rev = new, t.rev + 1
end"""


@pytest.mark.xfail(strict=True, raises=lua51.LuaError,
                   reason="P1: Cluster hides members by entry table; new tables with the same keys draw alone beside their pill until the next regroup")
def test_pill_members_new_tables():
    L, sim, ns, T = simmod.checked()
    ns.UI.saved.cluster = True
    sim.Slash("/mm toggle")
    sim.Run(1)
    cam = ns.UI.Camera.cam
    t = L.eval(LAYER)(ns.UI.Pins, 5, cam.cx, cam.cy)
    T.strictPins = True
    try:
        sim.Run(1)  # grouped: one pill, no pin alone (the check holds before the trigger)
    except lua51.LuaError as e:
        raise AssertionError(f"one thing, one pin, before any update: {e}")
    shown = L.eval(SHOWN)
    assert shown(t.layer, "pin") == 0 and shown(T.Layer(ns, "clusters"), "pill") >= 1
    renew = L.eval(RENEW)
    renew(t)  # regrouped at once (over 0.5 s since the last)
    sim.Run(0.1)
    renew(t)  # within REGROUP: not regrouped
    sim.Run(0.6)  # T.OneThing: "Pin 1 drawn twice: clustertest c1 ... and clusters c1 ..."
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))
