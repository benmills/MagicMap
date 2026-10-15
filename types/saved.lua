---@meta
-- Contract 4: SavedVariables, per owner. docs/decisions/0004-saved-variables.md
-- The mechanism (Game.Load and Open, game/Game.lua) and its failure cases:
-- docs/runtime.md "Saved data".
--
-- One account-wide SavedVariable, MagicMapAtlasDB (MagicMapDB once merged into
-- MagicMap): a table of owners. Each system owns its part; Game only loads it
-- (Game.Load(owner, fn, spec)) and the client saves it.
--
-- LOCKED (one-way door: it's on players' disks):
--   * the root is a table keyed by owner name; Game leaves owners it doesn't
--     know alone
--   * every part carries `_v` (integer), the owner's version, stamped by Game
--   * the migration rule, applied by Game before the owner sees its part:
--       not a table, or `_v` not a number   reset to {} then defaults
--       `_v` older (absent = 0)              spec.migrate(saved, from); if it errors: wiped, defaults
--       `_v` newer (a downgrade)             left untouched on disk; the session runs on defaults, unsaved
--       a top-level key of the wrong type    that key's default
--     never an error the rest of the addon sees (the loader is wrapped)
--   * saved positions are tile space (col, row, 3 decimals, by inst), saved
--     times are MM.Epoch
--   * the field names and meanings below, per version
-- OPEN: anything an owner adds in a new version (with its migrate, or
-- accepting defaults for it).

---What an owner hands Game.Load.
---@class MM.SavedSpec
---@field version? integer            default 1
---@field defaults? table             top-level keys and their default values (copied)
---@field migrate? fun(saved: table, from: integer)  bring an older part up to `version` in place

---@class MM.SavedRoot
---@field Game? MM.SavedGame
---@field UI? MM.SavedUI
---@field Model? MM.SavedModel
---@field telemetry? MM.SavedTelemetry
---@field validation? MM.SavedValidation
---@field recording? MM.SavedRecording

---@class MM.SavedPart
---@field _v integer

-- Game ---------------------------------------------------------------------------------

---@class MM.SavedGame: MM.SavedPart
---@field _v 1
---@field trackingOff table<integer, true>  Blizzard tracking filter ids Game turned off: turned back on after a /reload or crash
---@field buttonAngle? number               the minimap button's place on the rim, degrees

-- UI -----------------------------------------------------------------------------------

---@class MM.SavedUI: MM.SavedPart
---@field _v 1
---@field window? MM.ScreenRect     the small window's rect; nil: on the Minimap's home spot
---@field shown boolean             the window was shown
---@field zoom number               the small window's pixels per tile
---@field follow boolean
---@field inst? MM.Inst             the map shown when not following
---@field center? { col: MM.Col, row: MM.Row }  where it was when not following
---@field layers table<string, boolean>  every toggle the user changed; a missing key: the layer's default
---@field minimap MM.MinimapMode    "blizzard": the user chose Blizzard's minimap
---@field button boolean            the minimap button is shown
---@field tint boolean              tile colour correction

-- Model --------------------------------------------------------------------------------

---@class MM.SavedModel: MM.SavedPart
---@field _v 1
---@field rares table<MM.Inst, table<string, MM.SavedRare>>  key "npc:<id>", else "at:<col*64 rounded>:<row*64 rounded>"
---@field blips table<MM.Inst, table<string, MM.SavedBlip>>  key "<name>:<col*64 rounded>:<row*64 rounded>"; at most 200 an instance, the oldest dropped

---@class MM.SavedRare
---@field name string
---@field npcID? MM.NpcID
---@field col MM.Col
---@field row MM.Row
---@field t MM.Epoch   last seen

---A blip seen (a mailbox, a town service), for when you're away.
---@class MM.SavedBlip
---@field name string
---@field icon MM.FileID   the tracking icon it was matched to: shown only while that tracking is on
---@field col MM.Col
---@field row MM.Row
---@field t MM.Epoch       last seen

-- telemetry (docs/telemetry.md is the full contract; tools/telemetry.py reads it) ---

---@class MM.SavedTelemetry: MM.SavedPart
---@field _v 1
---@field sessions table[]               newest last, 10 kept
---@field errors table<string, table>    by key, 50 kept
---@field marks table[]                  newest last, 20 kept

-- validation (game/Validate.lua: a spike, deleted when Atlas holds) -------------------

---@class MM.SavedValidation: MM.SavedPart
---@field _v 1
---@field on? boolean
---@field samples integer
---@field counts table<string, integer>
---@field log table[]
---@field dropped integer

-- recording (game/Record.lua: /mma record, a dev tool for replaying Model) ----------

---@class MM.SavedRecording: MM.SavedPart
---@field _v 1
---@field on boolean
---@field obs table[]   observations as handed to Model (you, blips, frame, t, epoch), one per change in what the sensor knows; capped
