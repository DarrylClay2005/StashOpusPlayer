import SwiftUI

// MARK: - PodcastEpisodesView
//
// Episode list for one subscription — merges the live-parsed episode list
// (GET /user/podcasts/episodes) with saved per-episode positions (GET
// /user/podcasts/episode-progress) by guid. Tapping an episode plays it
// directly from its host's audio URL (no download/yt-dlp pipeline — a
// podcast enclosure URL is already a direct, playable file), constructed as
// a plain Song with genre = "Podcast" and album repurposed to carry the
// feed URL (see AudioPlayerManager+PositionTracking.pushPodcastProgressIfNeeded
// for why, and where progress actually gets saved during playback).
struct PodcastEpisodesView: View {
    let subscription: PodcastSubscription

    @EnvironmentObject private var account: AccountService
    @EnvironmentObject private var player: AudioPlayerManager

    @State private var episodes: [PodcastEpisode] = []
    @State private var progress: [String: PodcastEpisodeProgress] = [:]
    @State private var isLoading = true

    var body: some View {
        Group {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if episodes.isEmpty {
                Text("No episodes found in this feed.")
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(episodes) { episode in
                    Button {
                        play(episode)
                    } label: {
                        episodeRow(episode)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(subscription.title ?? "Episodes")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .refreshable { await reload() }
    }

    private func episodeRow(_ episode: PodcastEpisode) -> some View {
        let episodeProgress = progress[episode.guid]
        return HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(episode.title)
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if let published = episode.publishedAt {
                        Text(published.prefix(10))
                    }
                    if let duration = episode.durationSeconds, duration > 0 {
                        Text("• \(duration / 60) min")
                    }
                    if episodeProgress?.completed == true {
                        Text("• Played")
                    } else if let p = episodeProgress, p.positionSeconds > 5 {
                        Text("• In Progress")
                    }
                }
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
            }
            Spacer()
            Image(systemName: "play.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(AppTheme.dynamicAccent)
        }
    }

    private func play(_ episode: PodcastEpisode) {
        guard let url = URL(string: episode.audioURL) else { return }
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
        if let saved = progress[episode.guid], saved.positionSeconds > 5, !saved.completed {
            // Give the player a beat to actually start before seeking —
            // matches the same pattern AppDelegate's playback-transfer
            // handler uses for a freshly-resolved remote URL.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                player.seek(to: saved.positionSeconds)
            }
        }
    }

    private func reload() async {
        isLoading = true
        async let episodesResult = account.fetchPodcastEpisodes(feedURL: subscription.feedURL)
        async let progressResult = account.fetchPodcastEpisodeProgress(feedURL: subscription.feedURL)
        episodes = await episodesResult
        progress = await progressResult
        isLoading = false
    }
}
