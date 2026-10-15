-- Model alone, in plain Lua (no wowsim: Model sees only what it's handed):
-- Replay.Model(root) loads model/*.lua in TOC order with Atlas's coordinates
-- (atlas/Coords.lua) and returns ns.Model, ready for Model.Load(saved) and
-- Model.Observe(obs, oracles) fed from a recorded stream (/mma record:
-- tools/tests/fixtures/blips_stream.lua). Replay.Dump(v) writes a value as Lua
-- source (keys sorted), for fixtures and SavedVariables.

local Replay = {}

function Replay.Model(root)
	local ns = { Atlas = {}, Runtime = {} }
	local files = { "atlas/Coords.lua" }
	for line in io.lines(root .. "/MagicMapAtlas.toc") do
		if line:match("^model\\") then files[#files + 1] = line:gsub("\\", "/") end
	end
	for _, f in ipairs(files) do assert(loadfile(root .. "/" .. f))("MagicMapAtlas", ns) end
	return ns.Model
end

function Replay.Dump(v, indent)
	indent = indent or ""
	if type(v) == "string" then return string.format("%q", v) end
	if type(v) ~= "table" then return tostring(v) end
	local keys = {}
	for k in pairs(v) do keys[#keys + 1] = k end
	table.sort(keys, function(a, b)
		if type(a) == type(b) then return a < b end
		return type(a) == "number"
	end)
	local inner, out = indent .. "\t", {}
	for _, k in ipairs(keys) do
		local key = type(k) == "string" and k:match("^[%a_][%w_]*$") and k or "[" .. Replay.Dump(k) .. "]"
		out[#out + 1] = inner .. key .. " = " .. Replay.Dump(v[k], inner) .. ","
	end
	if #out == 0 then return "{}" end
	return "{\n" .. table.concat(out, "\n") .. "\n" .. indent .. "}"
end

return Replay
