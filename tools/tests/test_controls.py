"""The map's controls (ui/Controls.lua) on the simulated client:

  test_pill_and_recenter: the quest pill says the followed quest's pieces in the order chosen on its page (by
    default its name, its progress and the yards to it; the time to arrive on offer), over a faint fill of how far
    you've come since you began going to it (off on its page); the reset shows while the map isn't following
    you, and its click glides back and follows; the mode button is Blizzard's expand small, its condense big.
"""
import re

from test_addon import errors
from test_quests import CANDLES, client


def test_pill_and_recenter():
    L, sim, ns, G = client([CANDLES], followed=60)
    UI = ns.UI
    ctl, Feel = UI.Controls, UI.Feel
    line, fill, recenter = ctl.questLine, ctl.questFill, ctl.zoomReset

    def text():
        s = sim.state[[r for r in line.GetRegions(line) if sim.state[r].text][0]].text
        return s.encode("latin-1").decode("utf-8")  # (the Lua string's bytes are UTF-8)

    sim.Run(1)
    assert re.fullmatch(r"Kobold Candles  3/8  ·  \d+ yd", text()), text()
    Feel.Set("pills.quest", "distance,name,time")
    sim.Run(0.5)
    assert re.fullmatch(r"\d+ yd  ·  Kobold Candles  ·  (<1 min|\d+ min)", text()), text()
    Feel.Set("pills.quest", Feel.Default("pills.quest"))

    # The fill: empty where you began, about half once you've come half the way; off on its page.
    assert not fill.IsShown(fill)
    yd = int(text().split()[-2])
    sim.player.row = (sim.player.row + CANDLES["row"]) / 2
    sim.Run(1)
    assert int(text().split()[-2]) < yd and fill.IsShown(fill)
    share = (sim.state[fill].width + 15) / line.GetWidth(line)  # (the middle's width, and the caps' 15 px)
    assert 0.3 < share < 0.7, share
    Feel.Set("pills.questBar", False)
    sim.Run(0.5)
    assert not fill.IsShown(fill)
    Feel.Set("pills.questBar", True)

    # The reset: shown while not following; its click back to you.
    UI.Motion.SetZoom(UI.DefaultZoom())
    sim.Step()
    assert UI.Camera.follow and not recenter.IsShown(recenter)
    UI.Motion.SetFollow(False)
    sim.Step()
    assert recenter.IsShown(recenter)
    sim.Click(recenter)
    sim.Run(1)
    assert UI.Camera.follow and not recenter.IsShown(recenter)

    # The mode button points the way it goes.
    mode = ctl.mode
    assert mode.GetNormalTexture(mode).GetAtlas(mode.GetNormalTexture(mode)) == "redbutton-expand"
    UI.BigMap.Toggle()
    sim.Run(0.5)
    assert mode.GetNormalTexture(mode).GetAtlas(mode.GetNormalTexture(mode)) == "redbutton-condense"
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))
