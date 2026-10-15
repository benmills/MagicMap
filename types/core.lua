---@meta
-- Shared shapes every contract uses. Not loaded by the TOC: LuaLS reads it
-- (.luarc.json). See docs/decisions/ for why each contract is the way it is.
--
-- LOCKED (one-way door): tile space, the nil/false rule, the time kinds.

-- Positions ---------------------------------------------------------------------

---Map.db2 instanceID: 0 Eastern Kingdoms, 1 Kalimdor, dungeons and raids their own.
---@alias MM.Inst integer

---Tile column, 0..64 float, grows east (docs/atlas-data.md "Conventions").
---@alias MM.Col number

---Tile row, 0..64 float, grows south.
---@alias MM.Row number

---A point in Atlas tile space. The only kind of position that crosses a
---boundary: no world yards, no uiMap 0..1, no screen pixels.
---@class MM.Pos
---@field inst MM.Inst
---@field col MM.Col
---@field row MM.Row

---A tile-space box on one instance (c0 <= c1, r0 <= r1).
---@class MM.Rect
---@field inst MM.Inst
---@field c0 MM.Col
---@field r0 MM.Row
---@field c1 MM.Col
---@field r1 MM.Row

-- Ids (the game's own numbers, so Atlas rows join on them) --------------------

---@alias MM.QuestID integer
---@alias MM.NpcID integer
---@alias MM.AreaID integer     AreaTable id (Atlas.Area)
---@alias MM.UiMapID integer    UiMap id (Atlas.UiMap)
---@alias MM.FileID integer|string  a texture FileDataID, or a path
---@alias MM.Faction "A"|"H"|"AH"   as in Atlas data; nil: neither / not known

---How a pin looks, as the game names it: an atlas name or a texture, and a tint.
---UI may ignore any of it; Game fills what the game says.
---@class MM.Icon
---@field atlas? string
---@field texture? MM.FileID
---@field color? number[]  { r, g, b } 0..1

-- Time ----------------------------------------------------------------------------

---Runtime.frames: frames run since load. Orders things within a session.
---@alias MM.Frame integer

---GetTime(): seconds, session-monotonic float. For ages and timeouts in a session.
---@alias MM.Time number

---time(): epoch seconds, integer. The only time kind that is saved.
---@alias MM.Epoch integer

-- The nil / false rule (LOCKED) --------------------------------------------------
--
-- In every contract:
--   nil    unknown: not read yet, not readable (instances hide your position),
--          or the read failed this frame. Keep the last belief.
--   false  known to be none (no corpse, no waypoint).
--   {}     known, and empty (no quests in the log).
-- A field typed `X|false` uses false for "known none"; plain `X?` fields only
-- distinguish known from unknown.
