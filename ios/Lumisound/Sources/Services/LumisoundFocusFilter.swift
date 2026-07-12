import AppIntents

// MARK: - Lumisound Focus Filter
//
// Conforming to `SetFocusFilterIntent` (AppIntents, iOS 16+) is enough for this
// type to be picked up automatically under Settings -> Focus -> [a Focus] ->
// Focus Filters -> Lumisound — no Info.plist entry or entitlement needed,
// unlike widgets/Live Activities. iOS calls `perform()` whenever the user's
// chosen Focus (configured with this filter) activates, and is expected to
// call it again with the *previous* configuration when the Focus deactivates
// (Apple's Focus Filter model round-trips the intent's parameter values so the
// app can both "apply" and "revert" the same way) — this repo has no Xcode/iOS
// SDK available to verify that round-trip against a real Focus toggle
// end-to-end, so treat the deactivation path as needing on-device testing.
//
// Deliberately conservative in what it does: it only ever *starts* playback of
// the chosen playlist (mirroring `PlayPlaylistIntent`) when one is configured,
// and only if nothing is already playing — a Focus turning on shouldn't yank
// control away from music the user already started manually. There's no
// "pause on deactivate" behavior, since silently stopping someone's music when
// they leave a Focus (e.g. driving) would be more surprising than helpful.
struct LumisoundFocusFilter: SetFocusFilterIntent {
    static var title: LocalizedStringResource = "Lumisound Playback"
    static var description = IntentDescription(
        "Automatically starts a chosen playlist in Lumisound when this Focus turns on."
    )

    @Parameter(title: "Auto-Play Playlist")
    var playlist: PlaylistEntity?

    var displayRepresentation: DisplayRepresentation {
        if let playlist {
            return DisplayRepresentation(title: "Auto-play \"\(playlist.name)\"")
        }
        return DisplayRepresentation(title: "No playlist selected")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        guard let playlist else {
            // No playlist configured for this Focus — nothing to do (also the
            // path taken on deactivation for a filter that never had one set).
            return .result()
        }
        guard let library = LibraryManager.shared, let player = AudioPlayerManager.shared else {
            // The app may not have launched yet when a Focus activates outside
            // of any app interaction. Unlike the other intents in
            // LumisoundAppIntents.swift, Focus Filters don't set
            // `openAppWhenRun` (that flag doesn't apply here — the OS invokes
            // this silently, it never foregrounds the app), so there is no way
            // to force the launch sequence that populates `.shared`. Failing
            // silently is the only reasonable option.
            return .result()
        }
        guard !player.isPlaying else {
            // Don't interrupt music already playing when the Focus turns on.
            return .result()
        }
        guard let match = library.playlists.first(where: { $0.id == playlist.id }) else {
            return .result()
        }
        let songs = library.songs(for: match)
        guard !songs.isEmpty else {
            return .result()
        }
        player.setQueue(songs, startIndex: 0, autoplay: true)
        return .result()
    }
}
