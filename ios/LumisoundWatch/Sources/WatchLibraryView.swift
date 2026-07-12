import SwiftUI

// MARK: - WatchLibraryView
//
// Standalone "Watch Library": lists the user's Personal Cloud Library tracks
// fetched directly from the bridge (no phone involved), shows download state,
// and starts local playback via WatchLocalPlayerManager. Tapping an
// undownloaded track downloads it first, then plays — kept as one action
// since the transport screen (WatchNowPlayingView) has no separate "download
// manager" affordance in this simple v1.

struct WatchLibraryView: View {
    @EnvironmentObject private var account: WatchAccountStore
    @EnvironmentObject private var player: WatchLocalPlayerManager

    @State private var tracks: [WatchTrack] = []
    @State private var isLoading = false
    @State private var loadErrorMessage: String?

    private var client: WatchBridgeClient {
        WatchBridgeClient(bridgeURL: account.bridgeURL, token: account.token)
    }

    var body: some View {
        NavigationStack {
            Group {
                if !account.isLoggedIn {
                    WatchLoginView()
                } else if isLoading && tracks.isEmpty {
                    ProgressView()
                } else if let loadErrorMessage {
                    VStack(spacing: 6) {
                        Text(loadErrorMessage)
                            .font(.system(size: 12))
                            .multilineTextAlignment(.center)
                        Button("Retry") { Task { await load() } }
                    }
                } else if tracks.isEmpty {
                    Text("No cloud tracks yet")
                        .foregroundStyle(.secondary)
                } else {
                    List {
                        ForEach(Array(tracks.enumerated()), id: \.element.id) { index, track in
                            trackRow(track, index: index)
                        }
                    }
                }
            }
            .navigationTitle("Watch Library")
            .task { await load() }
            .refreshable { await load() }
        }
    }

    @ViewBuilder
    private func trackRow(_ track: WatchTrack, index: Int) -> some View {
        Button {
            Task {
                if !player.isDownloaded(track) {
                    await player.download(track, client: client)
                }
                if player.isDownloaded(track) {
                    player.play(queue: tracks, startAt: index)
                }
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(track.title)
                        .font(.system(size: 13, weight: .medium))
                        .lineLimit(1)
                    Text(track.artist)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                downloadIndicator(for: track)
            }
        }
        .buttonStyle(.plain)
        .swipeActions {
            if player.isDownloaded(track) {
                Button(role: .destructive) {
                    player.deleteDownload(track)
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            }
        }
    }

    @ViewBuilder
    private func downloadIndicator(for track: WatchTrack) -> some View {
        if player.downloadingTrackIDs.contains(track.id) {
            ProgressView().scaleEffect(0.6)
        } else if player.isDownloaded(track) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 12))
        } else {
            Image(systemName: "icloud.and.arrow.down")
                .foregroundStyle(.secondary)
                .font(.system(size: 12))
        }
    }

    private func load() async {
        isLoading = true
        loadErrorMessage = nil
        do {
            tracks = try await client.fetchLibrary()
        } catch {
            loadErrorMessage = (error as? WatchBridgeError)?.message ?? error.localizedDescription
        }
        isLoading = false
    }
}
