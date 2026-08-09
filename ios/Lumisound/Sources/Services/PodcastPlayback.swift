import Foundation

// MARK: - PodcastPlayback
//
// Shared "start playing this episode" logic — used by PodcastEpisodesView's
// row tap and LibraryHubView's Continue Listening teaser, so both go
// through the exact same download-preferring URL + Song construction +
// resume-seek behavior instead of two near-identical copies.
@MainActor
enum PodcastPlayback {
    @discardableResult
    static func play(episode: PodcastEpisode, subscription: PodcastSubscription, savedProgress: PodcastEpisodeProgress?, player: AudioPlayerManager) -> Bool {
        // Prefer the local download when available -- same audio, no
        // network dependency to keep listening.
        guard let url = PodcastDownloadManager.shared.localURL(for: episode.guid) ?? URL(string: episode.audioURL) else { return false }
        let song = Song(
            id: episode.guid,
            title: episode.title,
            artist: subscription.title ?? "Podcast",
            album: subscription.feedURL,
            duration: TimeInterval(episode.durationSeconds ?? 0),
            url: url,
            genre: "Podcast"
        )
        player.play(song: song, in: [song])
        if let savedProgress, savedProgress.positionSeconds > 5, !savedProgress.completed {
            // Give the player a beat to actually start before seeking.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                player.seek(to: savedProgress.positionSeconds)
            }
        }
        return true
    }
}
