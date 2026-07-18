import SwiftUI
import UniformTypeIdentifiers

extension StreamSearchView {

    // MARK: — Server library results

    var serverResultsBody: some View {
        Group {
            if streaming.isSearchingServer {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        ProgressView()
                            .tint(AppTheme.dynamicAccent)
                            .scaleEffect(0.8)
                        Text("Searching server library…")
                            .font(AppTheme.bodyFont(size: 13).weight(.semibold))
                            .foregroundStyle(AppTheme.textSecondary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    SkeletonList()
                }
            } else if streaming.serverTracks.isEmpty && !searchText.isEmpty {
                VStack(spacing: 0) {
                    Spacer()
                    CloudEmptyStateView(
                        icon: "magnifyingglass",
                        title: "No Results",
                        message: "Nothing on the server library matched \"\(searchText)\"."
                    )
                    Spacer()
                }
            } else if streaming.serverTracks.isEmpty {
                VStack(spacing: 0) {
                    Spacer()
                    CloudEmptyStateView(
                        icon: streaming.serverLibraryConfigured == false
                            ? "externaldrive.badge.xmark"
                            : "externaldrive.connected.to.line.below",
                        title: "Server Library",
                        message: streaming.serverLibraryConfigured == false
                            ? "No shared server library is configured. Ask the server admin to set SERVER_MUSIC_DIR to enable a shared, streamable music collection here."
                            : "Browse and stream the server's shared music collection, or search it above."
                    )
                    Spacer()
                }
            } else {
                // `Array(...enumerated())` gives each row its stagger index in
                // O(1) — a per-row `firstIndex(where:)` lookup here would be
                // O(n) each, an O(n²) main-thread hang on a big server library
                // (the same class of bug fixed elsewhere for big playlists).
                List(Array(streaming.serverTracks.enumerated()), id: \.element.id) { index, track in
                    ServerTrackRow(
                        track: track,
                        artworkURL: streaming.serverArtworkURL(for: track),
                        isDownloading: downloadingServerTrackIDs.contains(track.id),
                        isDownloaded: downloadedServerTrackIDs.contains(track.id),
                        onPlay: { handleServerPlay(track: track) },
                        onDownload: { handleServerDownload(track: track) }
                    )
                    // Row supplies its own floating glass-card background —
                    // see StreamingResults for the same pattern.
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))
                    .modifier(StaggeredFadeInModifier(index: min(index, 12), token: resultsAnimationToken))
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }
}
