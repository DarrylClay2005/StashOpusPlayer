-- Parametric Bass Boost — unlike the native "Bass Boost" preset (10 fixed
-- dB values), this curve is COMPUTED from a single `intensity` knob via an
-- exponential decay across the 10 bands, plus a small compensating dip
-- through the low-mids so it reads as "more bass" rather than "muddier" at
-- any intensity. Change `intensity` (0.0-1.0) and every band updates
-- together — the point of scripting the curve instead of hand-tuning 10
-- numbers.

local intensity = 0.8  -- 0.0 = flat, 1.0 = maximum boost

-- Band center frequencies, for reference/comment purposes only:
-- 32, 64, 125, 250, 500, 1k, 2k, 4k, 8k, 16k Hz
local band_count = 10
local eq_bands = {}

-- Peak gain at the sub-bass band, decaying exponentially toward the
-- low-mids, then a small negative dip to avoid muddiness, then flat.
local peak_gain = 10.0 * intensity
local decay = 0.55

for i = 1, band_count do
  if i <= 3 then
    -- Sub-bass through low-bass: exponential falloff from peak_gain.
    eq_bands[i] = peak_gain * (decay ^ (i - 1))
  elseif i <= 6 then
    -- Low-mids: a small compensating dip, tapering back toward flat.
    eq_bands[i] = -1.5 * intensity * (1 - (i - 3) / 4)
  else
    -- Mids and up: untouched.
    eq_bands[i] = 0.0
  end
end

effect = {
  id = "parametric_bass_boost",
  name = "Parametric Bass",
  icon = "speaker.wave.3.fill",
  eq_bands = eq_bands,
  eq_enabled = true,
  speed = 1.0,
  pitch_semitones = 0.0,
}
