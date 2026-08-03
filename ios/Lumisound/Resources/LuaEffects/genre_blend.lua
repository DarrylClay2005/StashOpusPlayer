-- Genre Blend — a different scripting technique from every other Lua
-- effect here: instead of GENERATING a curve from a formula, this
-- interpolates between two existing hardcoded reference curves (Rock's V
-- and Jazz's flat-warm curve, mirroring the native presets) via a single
-- `blend` knob. 0.0 = pure Jazz, 1.0 = pure Rock, anything between is a
-- genuinely new in-between curve no static preset offers.

local blend = 0.5  -- 0.0-1.0

local rock = { 4.0, 2.5, -1.0, -2.0, -1.0, 1.0, 2.5, 3.0, 2.0, 1.5 }
local jazz = { 1.5, 1.0, 0.5, 0.5, 0, 0, 0.5, 1.0, 1.5, 1.0 }

local eq_bands = {}
for i = 1, 10 do
  eq_bands[i] = jazz[i] + (rock[i] - jazz[i]) * blend
end

effect = {
  id = "genre_blend",
  name = "Genre Blend",
  icon = "slider.horizontal.3",
  eq_bands = eq_bands,
  eq_enabled = true,
  speed = 1.0,
  pitch_semitones = 0.0,
}
