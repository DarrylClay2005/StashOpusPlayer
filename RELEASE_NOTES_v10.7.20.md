# Release v10.7.20 (2025-10-05 UTC)

Fixes
- Startup crash fixed: aligned app theme to MaterialComponents, replaced incompatible widgets, and applied theme overlays to Material views. Split splash theme for Android 12+ vs older devices to ensure consistent inflation.
- Settings accuracy: App Volume and Crossfade labels now reflect live values even when changed elsewhere; volume shows both UI percent and effective output level with the perceptual curve.

Improvements
- Audio settings now listen to preference changes and update sliders/labels in real time.

Included from prior v10.7.19
- ReplayGain cache (in-memory + disk) and info dialog in Now Playing.
- Skip-silence toggle applied to player.
- Stability guard in service.

