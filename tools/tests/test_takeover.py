"""Game's side of the takeover in the sim (docs/v1-plan.md M1.6): the keys Blizzard owns, caught
for UI (M keeps WorldMapFrame hidden and hands "worldmap" on; L opens Blizzard's; Escape only
while big), none of it a protected call in combat (spike-bugs K2); the minimap button (dragged
round the rim, its angle across a /reload, a click or the compartment "toggle"); the home spot
(read again on a UI scale change); and a release putting back every property the takeover, the
rim and the home fade changed. Tooltips: replays/R-G7.lua."""
import math

from test_addon import boot, errors
from test_blips import lua_tools

ICON = "Interface\\Icons\\INV_Misc_Map_01"

# Lua helpers: our button (the one with the map icon), and every property a release must put back.
HELPERS = r"""
local Sim = ...
local H = {}
function H.Button()
	for _, f in ipairs(Sim.Frames()) do
		for _, r in ipairs({ f:GetRegions() }) do
			if r.GetTexture and r:GetTexture() == [[%s]] then return f end
		end
	end
end
local function Points(f)
	local out = {}
	for i = 1, f:GetNumPoints() do
		local p, rel, rp, x, y = f:GetPoint(i)
		out[i] = string.format("%%s %%s %%s %%.3f %%.3f", p, rel and (rel:GetName() or tostring(rel)) or "-", rp, x, y)
	end
	return table.concat(out, "; ")
end
function H.Snapshot()
	local mm, c, b, lib = Minimap, MinimapCluster, H.Button(), Sim.minimapButton
	return table.concat({
		"parent " .. mm:GetParent():GetName(), "points " .. Points(mm), "size " .. mm:GetWidth() .. "x" .. mm:GetHeight(),
		"scale " .. mm:GetScale(), "strata " .. mm:GetFrameStrata() .. " " .. mm:GetFrameLevel(), "alpha " .. mm:GetAlpha(),
		"mouse " .. tostring(mm:IsMouseEnabled()) .. " " .. tostring(mm:IsMouseWheelEnabled()), "zoom " .. mm:GetZoom(),
		"shown " .. tostring(mm:IsShown()), "ground " .. tostring(Sim.minimapGround), "unrotated " .. tostring(Sim.minimapUnrotated),
		"cluster " .. tostring(c:IsShown()) .. " " .. c:GetAlpha(), "rings " .. tostring(Sim.BlobRingsAt(1)),
		"inset " .. tostring(Sim.rimInset), "lib " .. lib:GetParent():GetName() .. " " .. Points(lib),
		"button " .. tostring(b:GetParent() == mm) .. " " .. Points(b) .. " " .. b:GetFrameStrata() .. " " .. tostring(b:IsVisible()),
		"worldmap " .. tostring(WorldMapFrame:IsShown()), "escape " .. tostring(MagicMapAtlasEscape:IsShown()),
	}, "\n")
end
-- The rect a frame covers, in UIParent units (as obs.minimap.home).
function H.Rect(f)
	local s = f:GetEffectiveScale() / UIParent:GetEffectiveScale()
	return f:GetLeft() * s, f:GetTop() * s, f:GetWidth() * s, f:GetHeight() * s
end
return H
""" % ICON


def kinds(ns):
    return [h.kind for h in ns.Model.hooked.values()]


def escape(sim):
    """Escape pressed: whether it closed one of UISpecialFrames."""
    return sim.Escape()[0]


def test_hooks():
    """M, L and Escape, out of combat and in it (no protected call: K2)."""
    L, sim, ns = boot()
    wm, view = L.globals().WorldMapFrame, ns.UI.View()
    shown = lambda: wm.IsShown(wm)  # noqa: E731
    sim.Run(1)
    sim.Press("M")  # the map closed: M is Blizzard's
    sim.Step()
    assert shown() and kinds(ns) == []
    sim.Press("M")
    sim.Step()
    assert not shown()

    sim.Slash("/mma map")
    sim.Run(1)
    sim.Press("M")  # shown: Blizzard's hidden again at once, "worldmap" through Model for a frame
    assert not shown()
    sim.Step()
    assert kinds(ns) == ["worldmap"]
    sim.Step()
    assert kinds(ns) == []
    sim.Press("L")  # the quest log opens Blizzard's map; M closes it, nothing caught
    sim.Step()
    assert shown() and kinds(ns) == []
    sim.Press("M")
    sim.Step()
    assert not shown() and kinds(ns) == []

    assert not escape(sim)  # Escape: nothing of ours while small
    view.window.big = True
    sim.Step()
    assert escape(sim)
    sim.Step()
    assert kinds(ns) == ["escape"]
    sim.Step()  # still big (UI didn't shrink): caught again
    assert escape(sim)
    sim.Step()
    assert kinds(ns) == ["escape"]
    view.window.big = False  # shrunk: the catcher goes, no "escape"
    sim.Run(0.1)
    assert kinds(ns) == [] and not escape(sim)

    # In combat: M opens Blizzard's as usual (hiding it is blocked), Escape still shrinks, the
    # rim, home fade and catcher change nothing protected.
    sim.inCombat = True
    sim.Press("M")
    sim.Step()
    assert shown() and kinds(ns) == []
    sim.Press("M")
    sim.Step()
    view.window.big, view.window.homeAlpha = True, 0
    view.chrome = L.table(rimArrows=False, questRing=False)
    sim.Step()
    assert escape(sim)
    sim.Step()
    assert kinds(ns) == ["escape"]
    view.window.big, view.window.homeAlpha, view.chrome = False, 1, None
    sim.Run(1)
    sim.inCombat = False
    assert len(sim.protectedCalls) == 0, [c.call for c in sim.protectedCalls.values()]
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))


def test_button_home_release():
    """The button's art, drag and angle (across a /reload), toggle; home; a release puts all back."""
    L, sim, ns = boot()
    G, Game, view = L.globals(), ns.Game, ns.UI.View()
    H, same = L.execute(HELPERS, sim), L.eval("function(a, b) return a == b end")
    sim.Run(1)
    button, mm = H.Button(), G.Minimap

    def at(angle):  # on the rim at angle degrees, as placed
        p, rel, rp, x, y = button.GetPoint(button)
        r = mm.GetWidth(mm) / 2 + 6
        a = math.radians(angle)
        return p == "CENTER" and same(rel, mm) and abs(x - math.cos(a) * r) < 1e-6 and abs(y - math.sin(a) * r) < 1e-6

    assert button.IsVisible(button) and at(215) and button.GetFrameStrata(button) == "MEDIUM"
    view.button = False
    sim.Step()
    assert not button.IsShown(button)
    view.button = True
    sim.Step()
    sim.Click(button)  # click, and the compartment entry: "toggle" for UI
    assert kinds(ns) == ["toggle"]
    G.MagicMapAtlasOnAddonCompartmentClick()
    sim.Step()
    assert kinds(ns) == ["toggle"]
    mx, my = mm.GetCenter(mm)
    bx, by = button.GetCenter(button)
    sim.Drag(button, mx - bx, my + 100 - by)  # dragged to straight above the Minimap
    assert abs(Game.saved.buttonAngle - 90) < 1e-6 and at(90)

    # The map shown, big, the rim's parts hidden, the home faded: the Minimap taken.
    before, home = H.Snapshot(), H.Rect(mm)
    sim.Slash("/mma map")
    view.window.big, view.window.homeAlpha = True, 0
    view.chrome = L.table(rimArrows=False, questRing=False)
    sim.Run(1)
    m, stand, cluster = Game.obs.minimap, G.MagicMapAtlasMinimapStandIn, G.MinimapCluster
    assert Game.minimap.engaged and not button.IsVisible(button) and same(button.GetParent(button), stand)
    assert sim.BlobRingsAt(0) and sim.rimInset == 1000 and cluster.GetAlpha(cluster) == 0
    # home: where the Minimap was (the stand-in holds it), with the cluster's strata
    assert (m.home.left, m.home.top, m.home.w, m.home.h) == home == H.Rect(stand)
    assert m.homeStrata == cluster.GetFrameStrata(cluster)
    kept = m.home
    sim.Run(0.5)
    assert same(Game.obs.minimap.home, kept)  # cached: the same table
    G.UIParent.SetScale(G.UIParent, 0.8)  # the UI's scale: read again, from the stand-in holding the spot
    sim.FireEvent("UI_SCALE_CHANGED")
    sim.Step()
    m = Game.obs.minimap
    assert not same(m.home, kept) and (m.home.left, m.home.top, m.home.w, m.home.h) == H.Rect(stand)
    assert abs(m.home.w - kept.w) < 1e-9 and abs(m.home.left - kept.left) > 1
    G.UIParent.SetScale(G.UIParent, 1)
    sim.FireEvent("UI_SCALE_CHANGED")

    # Hidden (UI snaps back: not big, home at 1): released, every property as it was.
    view.window.big, view.window.homeAlpha = False, 1
    sim.Slash("/mma map")
    sim.Run(0.5)
    assert not Game.minimap.engaged and H.Snapshot() == before, (before, H.Snapshot())
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))

    # /reload: the angle kept.
    sim.FireEvent("PLAYER_LOGOUT")
    saved = "MagicMapAtlasDB = " + lua_tools(L).Dump(G.MagicMapAtlasDB)
    L, sim, ns = boot(saved)
    sim.Run(0.5)
    button, mm, same = L.execute(HELPERS, sim).Button(), L.globals().Minimap, L.eval("function(a, b) return a == b end")
    assert abs(ns.Game.saved.buttonAngle - 90) < 1e-6 and at(90) and button.IsVisible(button)
    assert not errors(sim, ns), "\n\n".join(errors(sim, ns))
