-- Analog Wow & Flutter — a slow, deep pitch wobble that emulates tape/vinyl
-- drift, scripted via the `vibrato` special_mode (unused by any other Lua
-- effect so far — the native "Vibrato" preset is a flat 4.5 Hz/±0.35
-- semitone LFO; this one is far slower and deeper, computed from a single
-- `tape_age` knob instead of hardcoded numbers), paired with a warm low-mid
-- EQ lift for tape-saturation character.

local tape_age = 0.6  -- 0.0 = pristine, 1.0 = well-worn cassette

local wobble_hz = 0.5 + tape_age * 0.4        -- 0.5-0.9 Hz: slow drift, not a vibrato shimmer
local wobble_depth = 0.15 + tape_age * 0.55    -- semitones of pitch wander

local eq_bands = {}
for i = 1, 10 do
  if i <= 4 then
    -- Warm low-end lift, tapering off through the low-mids.
    eq_bands[i] = 2.5 * tape_age * (1 - (i - 1) / 4)
  elseif i >= 8 then
    -- Worn tape loses top-end sparkle.
    eq_bands[i] = -3.0 * tape_age
  else
    eq_bands[i] = 0.0
  end
end

effect = {
  id = "analog_wow_flutter",
  name = "Analog Wow & Flutter",
  icon = "waveform.path",
  eq_bands = eq_bands,
  eq_enabled = true,
  speed = 1.0,
  pitch_semitones = 0.0,
  special_mode = {
    type = "vibrato",
    freq = wobble_hz,
    pitch_depth = wobble_depth,
  },
}
