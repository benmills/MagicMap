-- Observe phase: one observation a frame, handed to Model.Observe(obs, oracles)
-- (types/observation.lua). Game.Part(name, read): obs[name] = read(obs) each frame,
-- in registration order, so a part may read those before it: the sensor's (blips,
-- game/Blips.lua) comes first, then game/parts/ in their manifest's order.
-- Events are only buffered by their handlers; parts read here, so Model sees one
-- consistent snapshot a frame (docs/runtime.md "Events").
-- Model's saved part is handed to it here too: Game.Load("Model", Model.Load, Model.SAVED).

local _, ns = ...
local Game, Runtime, Model = ns.Game, ns.Runtime, ns.Model

local obs = { hooked = {} }
local oracles = { Inside = function() return nil end } -- (no quest areas yet: Model estimates)
local parts = {}
Game.obs = obs -- the last one handed over (Telemetry's state, the recorder)

function Game.Part(name, read) parts[#parts + 1] = { name = name, read = read } end

Game.Load("Model", Model.Load, Model.SAVED)

Runtime.Step("observe", "game.observe", function()
	obs.frame, obs.t, obs.epoch = Runtime.frames, GetTime(), time()
	for i = 1, #parts do
		local p = parts[i]
		obs[p.name] = p.read(obs)
	end
	Model.Observe(obs, oracles)
end)
