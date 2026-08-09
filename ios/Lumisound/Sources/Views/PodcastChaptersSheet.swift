import SwiftUI

// MARK: - PodcastChaptersSheet
//
// Chapter list for one episode (Podcasting 2.0 JSON chapters — see
// main.py's get_podcast_chapters/_fetch_podcast_chapters_sync). Tapping a
// chapter starts the episode (via the same shared `PodcastPlayback.play`
// every other podcast playback entry point uses) and seeks to that
// chapter's start time.
struct PodcastChaptersSheet: View {
    let episode: PodcastEpisode
    let subscription: PodcastSubscription
    let savedProgress: PodcastEpisodeProgress?

    @EnvironmentObject private var account: AccountService
    @EnvironmentObject private var player: AudioPlayerManager
    @Environment(\.dismiss) private var dismiss

    @State private var chapters: [PodcastChapter] = []
    @State private var isLoading = true

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if chapters.isEmpty {
                    Text("No chapters found.")
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(chapters) { chapter in
                        Button {
                            playFrom(chapter)
                        } label: {
                            HStack {
                                Text(chapter.title)
                                    .foregroundStyle(AppTheme.textPrimary)
                                Spacer()
                                Text(formattedTime(chapter.startTimeSeconds))
                                    .font(.caption)
                                    .foregroundStyle(AppTheme.textSecondary)
                            }
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Chapters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task {
            guard let url = episode.chaptersURL else { isLoading = false; return }
            chapters = await account.fetchPodcastChapters(url: url)
            isLoading = false
        }
    }

    private func playFrom(_ chapter: PodcastChapter) {
        // Resuming from a chapter mark is a deliberate choice, not a
        // continuation — always start from that timestamp rather than
        // honoring savedProgress's own position.
        let atChapter = PodcastEpisodeProgress(
            episodeGuid: episode.guid, feedURL: subscription.feedURL, title: episode.title,
            positionSeconds: chapter.startTimeSeconds, durationSeconds: savedProgress?.durationSeconds ?? 0,
            completed: false, updatedAt: nil
        )
        PodcastPlayback.play(episode: episode, subscription: subscription, savedProgress: atChapter, player: player)
        dismiss()
    }

    private func formattedTime(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 { return String(format: "%d:%02d:%02d", hours, minutes, secs) }
        return String(format: "%d:%02d", minutes, secs)
    }
}
