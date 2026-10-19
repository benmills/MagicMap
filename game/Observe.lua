-- Observe phase: one observation a frame, handed to Model.Observe(obs, oracles)
-- (types/observation.lua). Game.Part(name, read, keep): obs[name] = read(obs) each frame,
-- in registration order (game/parts/files.txt: you, blips, minimap), so a part may
-- read those before it. Each part and Model.Observe is its own wrapped call
-- ("game.part <name>", "model.observe"): timed and its KB counted apart (perf.alloc
-- tells the sensor from Model), and isolated (a failing part leaves its field nil
-- this frame, or keep: the table a per-frame part refills, so `you` is always there;
-- the rest and Model still run). game.observe only calls them.
-- Events are only buffered by their handlers; parts read here, so Model sees one
-- consistent snapshot a frame (docs/runtime.md "Events").
-- Model's saved part is handed to it here too: Game.Load("Model", Model.Load, Model.SAVED).

local _, ns = ...
local Game, Runtime, Model = ns.Game, ns.Runtime, ns.Model

local obs = { hooked = {} }
local oracles = { Inside = function() return nil end } -- backed by game/Oracles.lua
local parts = {}
Game.obs = obs -- the last one handed over (Telemetry's state, the recorder)
Game.oracles = oracles

function Game.Part(name, read, keep)
	parts[#parts + 1] = { name = name, read = Runtime.Wrap("game.part " .. name, read), keep = keep }
end

Game.Load("Model", Model.Load, Model.SAVED)

local Observe = Runtime.Wrap("model.observe", function(o, r) Model.Observe(o, r) end)

Runtime.Step("observe", "game.observe", function()
	obs.frame, obs.t, obs.epoch = Runtime.frames, GetTime(), time()
	for i = 1, #parts do
		local p = parts[i]
		obs[p.name] = p.read(obs) or p.keep
	end
	Observe(obs, oracles)
end, { budgetMs = false })
