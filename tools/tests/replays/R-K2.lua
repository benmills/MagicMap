-- K2: "action blocked" in combat, from hiding Blizzard's frames from insecure code. MOVED (Game
-- still hides the Minimap's cluster), bounded here: no protected call in combat, whatever takes or
-- gives back the Minimap (T.Invariants checks every frame, and that the cluster never shows while
-- the takeover has it). In combat the cluster can't be shown or hidden, so engaging fades it and
-- the hide waits; releasing gives back the rest at once and the show waits (Blizzard's minimap
-- comes back as combat ends). /mma toggle both ways, the rim button and the compartment, the
-- gear's "Use Blizzard's minimap", M and Escape, a /reload and a logout in combat. And a quest
-- followed in combat (a click on its pin or area: the follow Command) super-tracks and watches it
-- from insecure code, which Blizzard's objective tracker (secure item buttons) follows: recorded
-- (Sim.trackerCalls), not refused; whether the client blocks or taints is docs/playtest-final.md c7.
local T = ...

local function Leave(sim)
	sim.inCombat = false
	sim.FireEvent("PLAYER_REGEN_ENABLED")
	sim.Run(0.5)
end
local function State(ns)
	return ns.Game.minimap.engaged, MinimapCluster:IsShown(), MinimapCluster:GetAlpha()
end
local function Is(ns, what, engaged, shown, alpha)
	local e, s, a = State(ns)
	assert(e == engaged and s == shown and a == alpha, string.format("%s: engaged %s, cluster shown %s, alpha %s",
		what, tostring(e), tostring(s), tostring(a)))
end

local sim, ns = T.Boot()
sim.Run(1)
Is(ns, "hidden at login", false, true, 1)
sim.Slash("/mma toggle")
sim.Run(0.5)
Is(ns, "taken", true, false, 1)

-- Off then on in combat, combat over, off: the show waited, and isn't lost to the re-engage.
sim.inCombat = true
sim.Slash("/mma toggle")
sim.Run(0.5)
Is(ns, "released in combat: its show waits", false, false, 1)
sim.Slash("/mma toggle")
sim.Run(0.5)
Is(ns, "taken again in combat", true, false, 1)
Leave(sim)
Is(ns, "combat over, still taken", true, false, 1)
sim.Slash("/mma toggle")
sim.Run(0.5)
Is(ns, "released", false, true, 1)

-- Taken in combat (the compartment): faded, big and small, through M; hidden as combat ends.
sim.inCombat = true
MagicMapAtlasOnAddonCompartmentClick()
sim.Run(0.5)
Is(ns, "taken in combat: faded", true, true, 0)
ns.UI.BigMap.Toggle() -- big and back: the home fade leaves it faded
sim.Run(0.5)
assert(ns.UI.BigMap.big and select(3, State(ns)) == 0)
assert(sim.Escape())
sim.Run(0.5)
Is(ns, "small again", true, true, 0)
sim.Press("M") -- Blizzard's opens (hiding it is blocked) and is closed again
sim.Step()
sim.Press("M")
sim.Run(0.5)
Leave(sim)
Is(ns, "combat over: hidden", true, false, 1)
sim.Slash("/mma toggle")
sim.Run(0.5)
Is(ns, "released", false, true, 1)

-- Taken in combat, given back by the gear's "Use Blizzard's minimap", the rim button, the compartment.
sim.inCombat = true
sim.Slash("/mma toggle")
sim.Run(0.5)
sim.Click(ns.UI.Controls.gear)
for _, e in ipairs(sim.MenuItems("button")) do
	if e.text == "Use Blizzard's minimap" then e.onSelect() end
end
sim.Run(0.5)
Is(ns, "the gear's Blizzard minimap, in combat", false, true, 1)
local button
for _, f in ipairs(sim.Frames()) do
	for _, r in ipairs({ f:GetRegions() }) do
		if r.GetTexture and r:GetTexture() == [[Interface\Icons\INV_Misc_Map_01]] then button = f end
	end
end
sim.Click(button)
sim.Run(0.5)
Is(ns, "the rim button, in combat", true, true, 0)
MagicMapAtlasOnAddonCompartmentClick()
sim.Run(0.5)
Is(ns, "the compartment, in combat", false, true, 1)
ns.Game.Command({ kind = "follow", quest = 60 }) -- (the sim's log)
ns.Game.Command({ kind = "follow", quest = false })
sim.Step()
local calls = {}
for _, c in ipairs(sim.trackerCalls) do calls[#calls + 1] = c.call end
T.Print("K2: a follow and an unfollow in combat: %s (the tracker's, recorded: in game c7)", table.concat(calls, ", "))
assert(table.concat(calls, ",") == "AddQuestWatch,SetSuperTrackedQuestID,SetSuperTrackedQuestID", table.concat(calls, ","))
sim.Slash("/mma toggle")
sim.Run(0.5)
sim.FireEvent("PLAYER_LOGOUT") -- logging out (or reloading) in combat

-- A /reload in combat, the map shown at login (a first login's): taken faded; hidden once it ends.
sim, ns = T.Boot("MagicMapAtlasDB = nil")
sim.inCombat = true
sim.Run(1)
Is(ns, "reloaded in combat", true, true, 0)
Leave(sim)
Is(ns, "combat over", true, false, 1)
sim.inCombat = true
sim.FireEvent("PLAYER_LOGOUT")
sim.Step()
T.Print("K2: no protected call in combat (%d frames), the cluster hidden or faded while taken", sim.frame)
local errs = T.Errors(sim, ns)
assert(#errs == 0, table.concat(errs, "\n"))
