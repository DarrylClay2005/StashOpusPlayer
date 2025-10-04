# Release v10.7.19 (2025-10-04 UTC)

Highlights
- ReplayGain caching
  - Added in-memory LRU + disk cache (SharedPreferences) for parsed ReplayGain/R128 tags.
  - Avoids re-parsing on subsequent plays and across sessions.
- ReplayGain info dialog
  - Now Playing overflow menu -> "Show ReplayGain Info" shows tag values and computed gain:
    - Track/Album gain, peak, preamp, fallback, prevent clipping/allow boost flags
    - Computed target dB, player volume factor, and LoudnessEnhancer boost (if enabled)
- Playback polish
  - Skip silence toggle supported and applied to the player.
  - Kept exact-seek preference for future Media3 upgrade; stored now.
- Stability
  - Defensive guard around service foreground checks to avoid crashes on some devices.

Notes
- Positive gain uses LoudnessEnhancer if the device supports it; otherwise it safely falls back (no boost).
- Exact seeks preference will be applied once Media3 API version is upgraded to expose SeekParameters in this build.

