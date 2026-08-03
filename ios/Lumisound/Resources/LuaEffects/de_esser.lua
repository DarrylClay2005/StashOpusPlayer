-- De-Ess / Sibilance Tamer — a narrow NEGATIVE notch centered on the
-- 4-8kHz sibilance range, computed from a cosine falloff around one center
-- band (same technique as smiley_curve_generator.lua's scoop, but inverted
-- and much narrower — a dip instead of a wide boost/scoop pair) for taming
-- harsh "s"/"sh" sounds in vocal-heavy recordings, a shape none of the
-- existing curves (bass-lift, smiley, V-curve, presence-boost) target.

local depth = 5.0    -- dB cut at the notch center
local width = 0.6    -- <1 = narrower notch, >1 = wider

local band_count = 10
local center = 7.0  -- ~4kHz band, the heart of sibilance
local eq_bands = {}

for i = 1, band_count do
  local distance = math.abs(i - center) / 2.0
  distance = math.min(1.0, distance / width)
  -- cos() maps distance=0 -> full notch depth, distance=1 -> flat.
  eq_bands[i] = -depth * (0.5 + 0.5 * math.cos(distance * math.pi))
end

effect = {
  id = "de_esser",
  name = "De-Ess",
  icon = "waveform.badge.minus",
  eq_bands = eq_bands,
  eq_enabled = true,
  speed = 1.0,
  pitch_semitones = 0.0,
}
