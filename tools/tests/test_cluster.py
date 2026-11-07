"""Overlapping pins grouped (ui/Cluster.lua): five pins at one spot draw as one pill, none of them alone; with
"Group overlapping icons" off (UI.saved.cluster) or at the minimap's size, all five draw and no pill does; the tracked one always draws alone.

test_pill_members_new_tables: the same five, their entries made anew twice within the regroup's 0.5 s (as
model/Blips.lua's Live() does each sensor change), with the harness's one-thing-one-pin check on every frame
(T.strictPins: docs/hardening-plan.md T1): none draws alone beside the pill holding it (P1).

test_grid_close_is_spent: the click that closes a pill's grid does nothing else (I2); a click on a grid pin is still
its own, after its entry was made anew.

test_layer_rares_takes_vignettes: /mm layer rares turns vignettes with it, as the gear's row does (S5)."""
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
    sim.Press("M")  # (grouped on the big map only)
    sim.Run(1)
    cam = ns.UI.Camera.cam
    t = L.eval(LAYER)(ns.UI.Pins, 5, cam.cx + 0.05, cam.cy)  # (~27 yd off you: tracking one isn't arriving)
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

    ns.UI.saved.cluster = True  # on again, but the minimap's size: never grouped
    sim.Press("M")
    t.rev = 3
    sim.Run(1)
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


def test_pill_members_new_tables():
    L, sim, ns, T = simmod.checked()
    ns.UI.saved.cluster = True
    sim.Slash("/mm toggle")
    sim.Run(1)
    sim.Press("M")  # (grouped on the big map only)
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


# The screen point of a region placed at (acol, arow), for the cursor.
AT = """function(UI, o)
    local cam, view = UI.Camera.cam, UI.Window.view
    local s = view:GetEffectiveScale()
    local w, h = UI.Window.Size()
    return (view:GetLeft() + w / 2 + (o.acol - cam.cx) * cam.zoom) * s, (view:GetTop() - h / 2 - (o.arow - cam.cy) * cam.zoom) * s
end"""

# The pill holding key, on the front canvas.
PILL = """function(layer, key)
    local p = layer.front.pools.pill
    for i = 1, p.n do
        for _, m in ipairs(p[i].cluster.members) do
            if m[1].key == key then return p[i] end
        end
    end
end"""


def test_grid_close_is_spent():
    L, sim, ns, T = simmod.checked()
    UI = ns.UI
    UI.saved.cluster = True
    sim.Slash("/mm toggle")
    sim.Run(1)
    sim.Press("M")  # (grouped on the big map only)
    sim.Run(1)
    cam, view = UI.Camera.cam, UI.Window.view
    t = L.eval(LAYER)(UI.Pins, 5, cam.cx, cam.cy)
    sim.Run(1)
    ran = L.eval("""function(UI) local t = { n = 0 }; UI.ZoneInfo.Tap = function() t.n = t.n + 1 end; return t end""")(UI)
    at = L.eval(AT)
    sim.FireScript(view, "OnEnter", False)  # (the view has the mouse: pins hover)

    def click(x, y):
        sim.cursorX, sim.cursorY = x, y
        sim.Run(0.2)
        sim.Click(view, "LeftButton", x, y, "screen")
        sim.Step()
    x, y = at(UI, L.eval(PILL)(T.Layer(ns, "clusters"), "c1"))
    click(x, y)  # the pill: its grid
    grid = T.Layer(ns, "grid clustertest")
    sim.Run(0.2)
    assert L.eval(SHOWN)(grid, "pin") == 5 and ran.n == 0
    click(x + 150, y - 150)  # off the grid: closed, and nothing else
    assert L.eval(SHOWN)(grid, "pin") == 0 and ran.n == 0
    click(x + 150, y - 150)  # the next click is the map's
    assert ran.n == 1

    click(x, y)  # open again, the entries made anew: a click on a grid pin is still its own
    L.eval(RENEW)(t)
    sim.Run(0.7)
    assert L.eval(SHOWN)(grid, "pin") == 5
    click(*at(UI, grid.front.pools.pin[1]))  # its popup (ui/Popup.lua)
    assert ns.UI.Popup.IsOpen() and L.eval(SHOWN)(grid, "pin") == 5 and ran.n == 1
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


def test_layer_rares_takes_vignettes():
    L, sim, ns = boot()
    E = ns.UI.Engine
    sim.Slash("/mm layer rares")
    assert not E.LayerOn("rares") and not E.LayerOn("vignettes")
    sim.Slash("/mm layer rares")
    assert E.LayerOn("rares") and E.LayerOn("vignettes")
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))
