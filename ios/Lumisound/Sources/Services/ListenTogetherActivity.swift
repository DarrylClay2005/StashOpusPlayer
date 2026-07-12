import GroupActivities

/// The SharePlay `GroupActivity` Lumisound proposes when a user taps the
/// SharePlay button in `NowPlayingView`'s track-info row (see
/// `GroupActivitySharingButton` usage in `NowPlayingView+TrackInfo.swift`).
/// This app doesn't hand playback to a system-coordinated `AVPlayer` timeline
/// (`AVPlaybackCoordinator`) — its player is a hand-built `AVAudioEngine` graph
/// with EQ/effects/crossfade, which has no such integration point — so sync
/// across participants is done manually via `SharePlayCoordinator`, which
/// exchanges track-identity and transport-command messages over a
/// `GroupSessionMessenger` rather than a shared timeline. That means playback
/// position can drift slightly between participants' devices (network
/// latency, independent stream buffering) rather than being frame-accurate —
/// acceptable for "everyone's hearing the same song together", not intended to
/// be sample-accurate.
struct ListenTogetherActivity: GroupActivity, Codable {
    var songTitle: String
    var artistName: String

    var metadata: GroupActivityMetadata {
        var metadata = GroupActivityMetadata()
        metadata.title = "Listening to \(songTitle)"
        metadata.subtitle = artistName
        metadata.type = .listenTogether
        metadata.fallbackURL = nil
        return metadata
    }
}
