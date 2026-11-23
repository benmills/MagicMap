"""The time-of-day tint (ui/Tint.lua, Data/Light.lua): at Honor's Stand in the Barrens at dawn a warm multiply over
the ground, at night a cool one; on the big map too; off with Settings > Map > Ground: Time of day (or /mm tint off)."""
from test_quests import client


def tint(sim, ns):
    t = ns.UI.Tint
    return sim.state[t.tex].vertex if t.Shown() else None


def test_tint():
    L, sim, ns, G = client([])
    L.execute("local Sim = ...; Sim.player.inst, Sim.player.col, Sim.player.row = 1, 34.65, 32.83", sim)
    sim.gameTime[1], sim.gameTime[2] = 5, 50
    sim.Run(2)
    r, g, b = ns.UI.Tint.Compute(1, 34.65, 32.83, 700)
    assert r > g > b and r < 1 and b > 0.5, (r, g, b)  # dawn: warm, dimmed
    assert ns.UI.Tint.Shown()
    r, g, b = ns.UI.Tint.Compute(1, 34.65, 32.83, 2700)
    assert b > r, (r, g, b)  # night: cool
    sim.Slash("/mm tint off")
    sim.Run(1.5)
    assert not ns.UI.Tint.Shown()
    sim.Slash("/mm tint on")
    sim.Run(1.5)
    assert ns.UI.Tint.Shown()
    ns.UI.BigMap.Toggle()
    sim.Run(1.5)
    assert ns.UI.BigMap.big and ns.UI.Tint.Shown()  # both sizes
    ns.UI.Feel.Set("tint.on", False)
    sim.Run(1.5)
    assert not ns.UI.Tint.Shown()


def test_city_tint():
    """City tints (Settings > Advanced): on by default, the map in Orgrimmar takes its colour (its own look, a
    Multiply, eased in); Wash lays it over instead; walked out to Durotar it eases away, a zone's tint off until
    turned on (Zone tints > Kalimdor > Durotar), then Durotar's own; its continent's switch off, none."""
    L, sim, ns, G = client([])
    sim.player.inst, sim.player.col, sim.player.row = 1, 40.15, 28.65  # beside the Cleft of Shadow
    sim.Run(2)
    t, S, Feel = ns.UI.CityTint, sim.state, ns.UI.Feel
    c = S[t.color]
    assert t.Shown() and c.blend == "MOD" and c.color[1] > c.color[3], c.color  # its own look: shaded toward amber
    Feel.Set("cityTint.orgrimmar", False)
    sim.Run(1)
    assert not t.Shown()
    Feel.Set("cityTint.orgrimmar", True)
    Feel.Set("cityTint.orgrimmarBlend", "wash")
    sim.Run(1)
    assert t.Shown() and S[t.color].blend == "BLEND" and abs(S[t.color].color[4] - 0.3) < 1e-6
    sim.player.col, sim.player.row = 42.0, 31.0  # out in Durotar
    sim.Run(1.5)
    assert not t.Shown()
    Feel.Set("zoneTint.1411", True)
    sim.Run(1)
    assert t.Shown() and S[t.color].blend == "MOD" and abs(S[t.color].color[3] - (1 - 0.8 * 0.15)) < 1e-6
    Feel.Set("zoneTint.kalimdor", False)
    sim.Run(1)
    assert not t.Shown()
