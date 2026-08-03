-- Heartbeat Pulse — a `tremolo` special_mode locked to a BPM you set instead
-- of the native "Tremolo" preset's fixed 4 Hz/45% depth (no other Lua effect
-- has scripted tremolo yet). Volume pulses twice per beat (like a
-- kick-and-snare heartbeat) rather than at an arbitrary fixed rate.

local bpm = 90        -- tempo to pulse against
local depth = 0.35    -- 0.0-1.0, how deep the volume dips on each pulse

local pulses_per_beat = 2
local freq_hz = (bpm / 60.0) * pulses_per_beat

local eq_bands = {}
for i = 1, 10 do
  -- A small sub-bass emphasis so the "beat" reads as a felt thump, not just
  -- a volume flutter.
  eq_bands[i] = i <= 2 and 2.0 or 0.0
end

effect = {
  id = "heartbeat_pulse",
  name = "Heartbeat Pulse",
  icon = "waveform.path.ecg",
  eq_bands = eq_bands,
  eq_enabled = true,
  speed = 1.0,
  pitch_semitones = 0.0,
  special_mode = {
    type = "tremolo",
    freq = freq_hz,
    depth = depth,
  },
}
