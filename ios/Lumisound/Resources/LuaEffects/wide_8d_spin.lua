-- Wide 8D Spin — a scripted special-mode example (the rotation LFO the
-- native "8D Audio" preset uses) paired with a gentle scripted-EQ air lift,
-- computed from a single `speed` variable rather than the fixed 0.18 Hz the
-- native preset hardcodes.

local speed = 0.24  -- rotation cycles-per-second

local eq_bands = {}
for i = 1, 10 do
  -- A light lift on the top 3 bands (8k/16k + a touch of 4k) for extra
  -- "airiness" while the sound rotates; everything else flat.
  if i >= 8 then
    eq_bands[i] = 1.5
  else
    eq_bands[i] = 0.0
  end
end

effect = {
  id = "wide_8d_spin",
  name = "Wide 8D Spin",
  icon = "rotate.3d",
  eq_bands = eq_bands,
  eq_enabled = true,
  speed = 1.0,
  pitch_semitones = 0.0,
  special_mode = {
    type = "rotation",
    hz = speed,
  },
}
