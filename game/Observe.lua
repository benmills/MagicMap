-- Observe phase: one observation a frame, handed to Model.Observe(obs, oracles)
-- (types/observation.lua). Game.Part(name, read): obs[name] = read(obs) each frame,
-- in registration order (game/parts/files.txt: you, blips, minimap), so a part may
-- read those before it. Each part and Model.Observe is its own wrapped call
-- ("game.part <name>", "model.observe"): timed and its KB counted apart (perf.alloc
-- tells the sensor from Model), and isolated (a failing part leaves its field nil
-- this frame; the rest and Model still run). game.observe only calls them.
-- Events are only buffered by their handlers; parts read here, so Model sees one
-- consistent snapshot a frame (docs/runtime.md "Events").
-- Model's saved part is handed to it here too: Game.Load("Model", Model.Load, Model.SAVED).

local _, ns = ...
local Game, Runtime, Model = ns.Game, ns.Runtime, ns.Model

local obs = { hooked = {} }
local oracles = { Inside = function() return nil end } -- (no quest areas yet: Model estimates)
local parts = {}
Game.obs = obs -- the last one handed over (Telemetry's state, the recorder)

function Game.Part(name, read) parts[#parts + 1] = { name = name, read = Runtime.Wrap("game.part " .. name, read) } end

Game.Load("Model", Model.Load, Model.SAVED)

local Observe = Runtime.Wrap("model.observe", function(o, r) Model.Observe(o, r) end)

Runtime.Step("observe", "game.observe", function()
	obs.frame, obs.t, obs.epoch = Runtime.frames, GetTime(), time()
	for i = 1, #parts do
		local p = parts[i]
		obs[p.name] = p.read(obs)
	end
	Observe(obs, oracles)
end, { budgetMs = false })
