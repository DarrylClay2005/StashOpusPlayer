# Stash Audio 7.2.0

Highlights:

- Fix: Prevent crash when playing songs from the Folders tab by resolving playback URIs safely (prefer existing content URIs, verify file paths, and only fallback to MediaStore ID when necessary).
- Feature: Added a dedicated Pitch/Semitones tab in Settings. Adjust pitch by ±12 semitones, apply changes live to the player, and persist across sessions.
- Enhancement: Playback service now restores saved speed/pitch parameters on startup.

Upgrade notes:
- No database migrations.
- No breaking changes to preferences.

Thanks for using Stash Audio!
