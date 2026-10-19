---@meta
-- Contract 2: Focus (UI -> Model). docs/decisions/0002-focus.md
--
-- The map UI shows, as much as Model needs to decide what to keep, what to
-- target and which slice of the route to find first. Not the camera itself:
-- how UI pans, zooms, animates and lays out is UI's.
--
-- UI calls Model.Focus(focus) from its ui step whenever any field changes
-- (or every frame: Model only compares). Model reads it in the next frame's
-- model step: focus is one frame behind, by design (Model runs before UI).
--
-- LOCKED: the call, its timing, and the fields below.
-- OPEN: new optional fields. Model must work with only `inst` set.

---@class MM.Focus
---@field inst MM.Inst         the map shown (the continent or instance)
---@field rect? MM.Rect        the tile rect in view (inst = focus.inst); nil: unknown (not laid out yet)
---@field zoom? number         pixels per tile: Model's "is this detail worth keeping/finding now"
---@field shown boolean        the map is visible at all (false: Model keeps learning, skips view-only work)
---@field follow boolean       the view follows you (Model may prefer the route near you)
---@field off? table<string, true> layers turned off (Menus.Layer keys; a new table when one changes; nil: none):
---                           Model.Target skips "corpse", "quests", "waypoint" while theirs is, and goes to the
---                           followed quest's pin (no area edge, no inside) while "questAreas" is (the spike's
---                           pinData and drawn blobs: Layers.lua:1029, 1093-1097, 1160-1168); a seen rare hides
---                           under a live vignette of its name only while "vignettes" is on (Landmarks.lua:112-117);
---                           no sensed blip within 8 yd of a pin of "quests", "offers", "flight", "dungeons",
---                           "rares", "corpse", "waypoint" while that layer is on (Blips.lua:446-470)
---@field moving? boolean      the view zooms, flies or is dragged, or its zoom hasn't settled (Camera.Settled):
---                           Model leaves the frame to the map (the route's search waits: no slice a frame)

-- The two entry points into Model that Game and UI call (LOCKED). What UI reads back,
-- and Model.Load (its saved part): types/model.lua. --------------------------------

---@class MM.ModelEntry
local Model = {}

---Game's observe step, once a frame.
---@param obs MM.Observation
---@param oracles MM.Oracles
function Model.Observe(obs, oracles) end

---UI's ui step, when focus changes.
---@param focus MM.Focus
function Model.Focus(focus) end
