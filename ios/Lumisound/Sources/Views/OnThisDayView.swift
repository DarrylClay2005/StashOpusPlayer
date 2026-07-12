import SwiftUI

// MARK: - OnThisDayView
//
// "On This Day" — tracks played on today's month/day in previous years (GET
// /user/on-this-day), reconstructed server-side straight from play history
// rather than a fresh search, grouped by year.

struct OnThisDayView: View {
    @EnvironmentObject private var account: AccountService
    @EnvironmentObject private var streaming: StreamingService
    @EnvironmentObject private var player: AudioPlayerManager

    @State private var groups: [OnThisDayGroup] = []
    @State private var isLoading = false
    @State private var loadingTrackID: String?

    var body: some View {
        List {
            if isLoading && groups.isEmpty {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowBackground(Color.clear)
            } else if groups.isEmpty {
                EmptyStateView(
                    icon: "clock.arrow.circlepath",
                    title: "Nothing from past years yet",
                    message: "Once you've been listening for a year or more, tracks you played on this date will show up here."
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(groups) { group in
                    Section {
                        ForEach(group.tracks) { track in
                            OnThisDayRow(
                                track: track,
                                isLoading: loadingTrackID == track.id,
                                onPlay: { play(track: track) },
                                onAddToQueue: { addToQueue(track: track) }
                            )
                            .listRowBackground(AppTheme.surface.opacity(0.5))
                        }
                    } header: {
                        Text("\(group.yearsAgo) YEAR\(group.yearsAgo == 1 ? "" : "S") AGO")
                            .font(AppTheme.bodyFont(size: 11))
                            .foregroundStyle(AppTheme.textSecondary)
                            .kerning(0.8)
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(GalleryBackgroundView().ignoresSafeArea())
        .navigationTitle("On This Day")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        isLoading = true
        groups = await account.fetchOnThisDay()
        isLoading = false
    }

    private func play(track: StreamTrack) {
        guard loadingTrackID == nil else { return }
        loadingTrackID = track.id
        Task {
            defer { loadingTrackID = nil }
            do {
                let url = try await streaming.streamURL(for: track)
                let song = streaming.toSong(track: track, streamURL: url)
                player.play(song: song, in: [song])
            } catch {
                streaming.errorMessage = error.localizedDescription
            }
        }
    }

    private func addToQueue(track: StreamTrack) {
        guard loadingTrackID == nil else { return }
        loadingTrackID = track.id
        Task {
            defer { loadingTrackID = nil }
            do {
                let url = try await streaming.streamURL(for: track)
                let song = streaming.toSong(track: track, streamURL: url)
                player.appendToQueue(song: song)
            } catch {
                streaming.errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - OnThisDayRow

private struct OnThisDayRow: View {
    let track: StreamTrack
    let isLoading: Bool
    let onPlay: () -> Void
    let onAddToQueue: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: track.source == "soundcloud" ? "cloud.fill" : "play.rectangle.fill")
                .font(.system(size: 16))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(width: 44, height: 44)
                .background(AppTheme.elevatedSurface)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .font(AppTheme.bodyFont(size: 14))
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                Text(track.artist)
                    .font(AppTheme.bodyFont(size: 12))
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if isLoading {
                ProgressView()
            } else {
                Button(action: onAddToQueue) {
                    Image(systemName: "text.line.first.and.arrowtriangle.forward")
                        .foregroundStyle(AppTheme.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !isLoading else { return }
            onPlay()
        }
    }
}
