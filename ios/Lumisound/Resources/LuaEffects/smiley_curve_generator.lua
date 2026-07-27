-- Smiley Curve Generator — procedurally builds a symmetric "smiley" EQ
-- curve (boosted bass and treble, scooped mids) from a cosine falloff
-- around the center band, instead of 10 hand-picked values. `width`
-- controls how wide the scoop is and `depth` how many dB the boost/scoop
-- peaks at — tweak either and the whole curve reshapes itself.

local depth = 4.0   -- dB at the two ends
local width = 1.15  -- >1 = wider scoop, <1 = narrower

local band_count = 10
local center = (band_count + 1) / 2.0  -- 5.5 for 10 bands
local eq_bands = {}

for i = 1, band_count do
  -- Normalized distance from center, 0 at the middle band, 1 at the ends.
  local distance = math.abs(i - center) / (center - 1)
  distance = math.min(1.0, distance * width)
  -- cos() maps distance=0 -> -depth (scoop), distance=1 -> +depth (boost).
  eq_bands[i] = -depth * math.cos(distance * math.pi)
end

effect = {
  id = "smiley_curve",
  name = "Generated Smiley",
  icon = "waveform.path.ecg",
  eq_bands = eq_bands,
  eq_enabled = true,
  speed = 1.0,
  pitch_semitones = 0.0,
}
