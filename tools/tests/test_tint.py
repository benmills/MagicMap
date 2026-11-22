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
    """Settings > Advanced > City tints: Orgrimmar's on, the map in Orgrimmar takes its colour (a wash at its opacity,
    eased in); Multiply shades instead; walked out to Durotar it eases away."""
    L, sim, ns, G = client([])
    sim.player.inst, sim.player.col, sim.player.row = 1, 40.15, 28.65  # beside the Cleft of Shadow
    sim.Run(2)
    t, S = ns.UI.CityTint, sim.state
    assert not t.Shown()  # off until turned on
    ns.UI.Feel.Set("cityTint.orgrimmar", True)
    sim.Run(1)
    c = S[t.color]
    assert t.Shown() and c.blend == "BLEND" and abs(c.color[4] - 0.2) < 1e-6, c.color
    ns.UI.Feel.Set("cityTint.orgrimmarBlend", "multiply")
    sim.Run(0.2)
    assert S[t.color].blend == "MOD" and S[t.color].color[1] > S[t.color].color[3]  # red: shaded toward it
    sim.player.col, sim.player.row = 42.0, 31.0  # out in Durotar
    sim.Run(1.5)
    assert not t.Shown()
