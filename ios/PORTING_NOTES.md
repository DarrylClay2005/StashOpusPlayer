# iOS Porting Notes

## Salvaged From Android

- `Song` model semantics: display title fallback, unknown artist/album labels, duration formatting.
- Playlist/favorites shape: separate user-created playlists and per-song favorite state.
- Playback intent: queue-first playback, shuffle, repeat modes, speed, pitch, 10-band EQ, background controls.
- Library intent: scan local library, support imported files, keep offline-first behavior.
- Artwork direction: deterministic cache keys and future online lookup through MusicBrainz/Cover Art Archive/iTunes.
- LRC parsing logic for future synced lyrics support.
- Theme tokens: dark blue-gray surfaces with pink accent and explicit success/warning/error colors.

## Rebuilt Natively

- Android Media3/ExoPlayer -> `AVAudioEngine`, `AVAudioPlayerNode`, `AVAudioUnitTimePitch`, `AVAudioUnitEQ`.
- Android MediaStore -> `MPMediaLibrary` plus document import into app storage.
- Android notification/session controls -> iOS Now Playing info and `MPRemoteCommandCenter`.
- XML layouts/fragments -> SwiftUI tabs and lists.
- Gradle/APK release flow -> XcodeGen + `xcodebuild` archive/export script.

## Still To Do

- Generate and check in a real app icon set.
- Open in Xcode on macOS, set signing team, and fix any Xcode-only compiler diagnostics.
- Add persisted playlists/favorites/settings with SwiftData or SQLite.
- Add artwork extraction/cache and online artwork lookup.
- Add a robust library refresh strategy for deleted/imported files.
- Add tests for `LrcParser`, file import, queue behavior, and settings persistence.
- Decide what, if anything, from YouTube/search/download features is acceptable for an iOS IPA.

## Avoid Porting Directly

- Android update installer, APK/AAB release scripts, widgets, `MANAGE_EXTERNAL_STORAGE`, Seal/NewPipe intents.
- Android `audiofx` effect classes; iOS audio effects should stay AVFoundation/DSP-native.
- YouTube downloader internals until policy and distribution boundaries are explicit.
