-- Runtime, first file in the TOC: marks the load start. Runtime.lua (the
-- first file after Atlas) marks the end of Atlas loading as boot.loaded.

local _, ns = ...
ns.Runtime = { boot = { t0 = debugprofilestop(), mem0 = collectgarbage("count") } }
