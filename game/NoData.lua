-- Without QuestieDB's data (Data/Npcs, Objects, Items, Quests, BlipServices: NOTICE.md) Atlas's
-- indexes are empty and the map runs on: one chat line says so, at load (QuestInfo.lua:71-75).

local _, ns = ...

if not ns.Atlas.Data.Quests then ns.Game.Say("QuestieDB isn't loaded: quests show without their mobs and items.") end
