"""The map's controls (ui/Controls.lua) on the simulated client:

  test_pill_and_recenter: the quest pill says the followed quest's pieces in the order chosen on its page (by
    default its progress, then the yards to it, smaller; its name, the yards to it and the time to arrive on offer), over a fill of how far
    you've come since you began going to it (off on its page); its x lets go of what it shows; the reset shows while the map isn't following
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
    assert not line.IsShown(line)  # (off by default)
    Feel.Set("pills.questShow", "followed")

    def parts():
        """The pill's texts, the first piece's then the rest's (smaller, muted)."""
        return [sim.state[r].text.encode("latin-1").decode("utf-8")  # (the Lua string's bytes are UTF-8)
                for r in line.GetRegions(line) if sim.state[r].text]

    def text():
        return "  ·  ".join(parts())

    sim.Run(1)
    assert re.fullmatch(r"3/8  ·  \d+ yd", text()), text()  # (by default its progress, then the yards to it)
    Feel.Set("pills.quest", "name,progress,distance")
    sim.Run(0.5)
    assert re.fullmatch(r"Kobold Candles  ·  3/8  ·  \d+ yd", text()), text()
    Feel.Set("pills.quest", "distance,name,time")
    sim.Run(0.5)
    assert re.fullmatch(r"\d+ yd  ·  Kobold Candles  ·  (<1 min|\d+ min)", text()), text()
    Feel.Set("pills.quest", "name,progress,distance")

    # The fill: empty where you began, about half once you've come half the way; off on its page.
    assert not fill.IsShown(fill)
    yd = int(text().split()[-2])
    sim.player.row = (sim.player.row + CANDLES["row"]) / 2
    sim.Run(1)
    assert int(text().split()[-2]) < yd and fill.IsShown(fill)
    share = sim.state[fill].width / line.GetWidth(line)  # (the fill: one texture cut at its share)
    assert 0.3 < share < 0.7, share
    Feel.Set("pills.questBar", False)
    sim.Run(0.5)
    assert not fill.IsShown(fill)
    Feel.Set("pills.questBar", True)

    # The x: shown while it shows what you follow; its click lets the quest go (the follow Command, unfollowing).
    close = ctl.questClose
    assert close.IsShown(close) and UI.Track.ClearLabel() == "Stop following"
    sim.Click(close)
    sim.Run(1)
    assert sim.superTracked in (0, None) and not close.IsShown(close) and not line.IsShown(line)  # (nothing to show)

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
