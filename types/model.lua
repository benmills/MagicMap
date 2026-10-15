---@meta
-- Contract 6: Model's read API (UI reads Model), and how Game hands Model its
-- saved part. docs/decisions/0006-model-read-api.md
--
-- UI reads Model only through these. Everything else in Model (merge state,
-- indexes, caches) is internal.
--
-- LOCKED (one-way door):
--   * Known(kind) -> list, rev: every pin-like thing Model knows, one shape for
--     all kinds, so a new kind is a Model file that fills it and a UI layer that
--     draws it (plus Atlas data if static), with no change here
--   * Model.you, Model.hooked, Target(), Route() and their meanings
--   * Model.Load(saved) / Model.SAVED: Game.Load("Model", Model.Load, Model.SAVED)
-- OPEN: new kinds (strings), new optional MM.Known fields, Target / Route shapes
-- beyond the fields below (not built yet).

---@alias MM.KnownKind "blips"|string

---One thing Model knows, of any kind.
---@class MM.Known
---@field key string           stable within its kind across frames (and /reload, for remembered ones)
---@field kind MM.KnownKind
---@field pos MM.Pos
---@field name string
---@field icon? MM.Icon        how the game shows it; nil: the kind's default look
---@field live boolean         sensed now (false: remembered from before)
---@field t? MM.Epoch          last seen, for remembered ones
---@field text? string         a line for its tooltip

---@class MM.ModelYou
---@field inst? MM.Inst
---@field col? MM.Col          last known (kept while unknown)
---@field row? MM.Row
---@field facing? number
---@field stale boolean        the position is the last known, not this frame's

---What to go to (not built yet: OPEN beyond these fields).
---@class MM.Target
---@field kind MM.KnownKind|"quest"|"corpse"|"waypoint"
---@field key string
---@field pos MM.Pos

---@class MM.ModelRead
---@field you MM.ModelYou
---@field hooked MM.HookedInput[]  this frame's hooked keys, handed on from obs.hooked unchanged (ADR 0003)
---@field SAVED MM.SavedSpec       Model's saved part's spec (types/saved.lua MM.SavedModel)
local Model = {}

---What Model knows of `kind`: every instance, or for a kind built from Atlas on
---demand (e.g. rares), only Focus's instance; UI filters by inst either way. The same
---list table until it changes; rev goes up by one each time it does (a layer
---redraws when rev changes). An unknown kind: {}, 0. Never errors.
---@param kind MM.KnownKind
---@return MM.Known[] list
---@return integer rev
function Model.Known(kind) end

---@return MM.Target|false|nil  false: none; nil: not known yet
function Model.Target() end

---The way to the target: points in tile space, you first; nil while not found.
---@return MM.Pos[]|nil
function Model.Route() end

---Game's loader for Model's saved part (Game.Load("Model", Model.Load, Model.SAVED)),
---once SavedVariables are loaded. Model keeps the table and mutates it in place.
---@param saved MM.SavedModel
function Model.Load(saved) end
