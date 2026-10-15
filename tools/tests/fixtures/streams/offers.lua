-- Fixture stream (types/observation.lua MM.ObsOffer[]): quests to pick up on the maps
-- Game asked about, for Model alone (tools/tests/replay.lua). Not asked yet (nil); then
-- Elwynn Forest's; A Fishy Peril is taken (gone from the list); browsing Westfall adds
-- its; then the client hides them (known and empty).
-- On-change parts keep their table while nothing changes: a new table is a change.

local function At(frame, col, row, offers)
	return { frame = frame, t = frame / 60, epoch = 1792077412 + math.floor(frame / 60), hooked = {}, offers = offers,
		you = { inst = 0, col = col, row = row, facing = 0, uiMap = 1429, level = 8, faction = "A" } }
end
local function Offer(questID, name, col, row, line)
	return { questID = questID, name = name, line = line, pos = { inst = 0, col = col, row = row } }
end

local princess = Offer(88, "Princess Must Die!", 31.377, 50.553)
local necklace = Offer(85, "Lost Necklace", 31.366, 50.543)
local linen = Offer(83, "Red Linen Goods", 34.292, 49.872)
local fishy = Offer(40, "A Fishy Peril", 31.863, 49.806, "The Lost Guards")
local elwynn = { princess, necklace, linen, fishy }
local taken = { princess, necklace, linen }
local westfall = { princess, necklace, linen, Offer(22, "Goretusk Liver Pie", 30.046, 50.96),
	Offer(36, "Westfall Stew", 30.27, 50.48), Offer(64, "The Forgotten Heirloom", 30.278, 50.472) }

return {
	At(1, 31.95, 49.75, nil),
	At(30, 31.95, 49.75, elwynn),
	At(90, 31.9, 49.79, elwynn),
	At(150, 31.87, 49.8, taken),
	At(300, 31.87, 49.8, westfall),
	At(360, 31.87, 49.8, westfall),
	At(420, 31.87, 49.8, {}),
}
