import SwiftUI

// MARK: - PodcastEpisodesView
//
// Episode list for one subscription — merges the live-parsed episode list
// (GET /user/podcasts/episodes) with saved per-episode positions (GET
// /user/podcasts/episode-progress) by guid. Tapping an episode plays it via
// the shared `PodcastPlayback.play` (also used by LibraryHubView's Continue
// Listening teaser) — directly from its host's audio URL, no download/
// yt-dlp pipeline involved, since a podcast enclosure URL is already a
// direct, playable file. See that type's doc comment for the Song
// genre/album repurposing, and AudioPlayerManager+PositionTracking
// .pushPodcastProgressIfNeeded for where progress actually gets saved
// during playback.
struct PodcastEpisodesView: View {
    let subscription: PodcastSubscription

    @EnvironmentObject private var account: AccountService
    @EnvironmentObject private var player: AudioPlayerManager
    @ObservedObject private var downloads = PodcastDownloadManager.shared

    @State private var episodes: [PodcastEpisode] = []
    @State private var progress: [String: PodcastEpisodeProgress] = [:]
    @State private var isLoading = true
    @State private var chaptersEpisode: PodcastEpisode?

    var body: some View {
        Group {
            if isLoading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if episodes.isEmpty {
                Text("No episodes found in this feed.")
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Not wrapped in an outer Button: episodeRow contains its
                // own download/delete Button, and nesting a Button inside
                // another Button's label is a known SwiftUI trap (the tap
                // targets can conflict/swallow each other in a List row) --
                // a tap gesture + explicit content shape on the row itself
                // avoids that entirely while the inner button still works.
                List(episodes) { episode in
                    episodeRow(episode)
                        .contentShape(Rectangle())
                        .onTapGesture { play(episode) }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(subscription.title ?? "Episodes")
        .navigationBarTitleDisplayMode(.inline)
        .task { await reload() }
        .refreshable { await reload() }
        .sheet(item: $chaptersEpisode) { episode in
            PodcastChaptersSheet(episode: episode, subscription: subscription, savedProgress: progress[episode.guid])
        }
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
                    if downloads.isDownloaded(episode.guid) {
                        Text("• Downloaded")
                    }
                }
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
            }
            Spacer()
            if episode.chaptersURL != nil {
                Button {
                    chaptersEpisode = episode
                } label: {
                    Image(systemName: "list.bullet.rectangle")
                        .font(.system(size: 20))
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .buttonStyle(.plain)
            }
            downloadButton(for: episode)
            Image(systemName: "play.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(AppTheme.dynamicAccent)
        }
    }

    @ViewBuilder
    private func downloadButton(for episode: PodcastEpisode) -> some View {
        if downloads.isDownloading(episode.guid) {
            ProgressView()
        } else if downloads.isDownloaded(episode.guid) {
            Button {
                downloads.deleteDownload(guid: episode.guid)
            } label: {
                Image(systemName: "trash.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .buttonStyle(.plain)
        } else {
            Button {
                downloads.download(episode: episode)
            } label: {
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 20))
                    .foregroundStyle(AppTheme.textSecondary)
            }
            .buttonStyle(.plain)
        }
    }

    private func play(_ episode: PodcastEpisode) {
        PodcastPlayback.play(episode: episode, subscription: subscription, savedProgress: progress[episode.guid], player: player)
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
