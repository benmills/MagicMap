"""Overlapping pins grouped (ui/Cluster.lua): five pins at one spot draw as one pill, none of them alone; with
"Group overlapping icons" off (UI.saved.cluster), all five draw and no pill does."""
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

    ns.UI.saved.cluster = False  # the gear's setting, off: laid out again
    t.rev = 2
    sim.Run(0.5)
    assert shown(t.layer, "pin") == 5 and shown(pills, "pill") == 0
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))
