-- G5: wrong or missing data from runtime sources. PREVENTED: with no QuestieDB loaded, Atlas has
-- the NPC services, item icons and quest objectives offline.
local T = ...
local _, ns = T.Boot()
local A = ns.Atlas
assert(QuestieDB == nil and QuestieLoader == nil)
if A.Npc(295) == nil then T.Skip("no QuestieDB-derived data (tools/gen_questie.py)") end
local innkeeper = false
for _, s in pairs(A.Npc(295).services) do innkeeper = innkeeper or s == "innkeeper" end
assert(innkeeper) -- Innkeeper Farley, Goldshire
assert(A.Item(750).icon ~= nil) -- Tough Wolf Meat (quest 33's objective)
local o = A.Quest(33).objectives[1]
assert(o.kind == "item" and o.id == 750)
