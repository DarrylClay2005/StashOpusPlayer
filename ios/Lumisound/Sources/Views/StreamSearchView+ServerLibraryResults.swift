import SwiftUI
import UniformTypeIdentifiers

extension StreamSearchView {

    // MARK: — Server library results

    var serverResultsBody: some View {
        Group {
            if streaming.isSearchingServer {
                Spacer()
                ProgressView("Searching server library…")
                    .tint(AppTheme.dynamicAccent)
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer()
            } else if streaming.serverTracks.isEmpty && !searchText.isEmpty {
                Spacer()
                Text("No results for \"\(searchText)\"")
                    .font(AppTheme.bodyFont(size: 15))
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer()
            } else if streaming.serverTracks.isEmpty {
                Spacer()
                VStack(spacing: 12) {
                    Image(systemName: streaming.serverLibraryConfigured == false
                          ? "externaldrive.badge.xmark"
                          : "externaldrive.connected.to.line.below")
                        .font(.system(size: 44))
                        .foregroundStyle(AppTheme.textSecondary)
                    Text("Server Library")
                        .font(AppTheme.headlineFont(size: 16))
                        .foregroundStyle(AppTheme.textPrimary)
                    Text(streaming.serverLibraryConfigured == false
                         ? "No shared server library is configured. Ask the server admin to set SERVER_MUSIC_DIR to enable a shared, streamable music collection here."
                         : "Browse and stream the server's shared music collection, or search it above.")
                        .font(AppTheme.bodyFont(size: 14))
                        .foregroundStyle(AppTheme.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
                Spacer()
            } else {
                List(streaming.serverTracks) { track in
                    ServerTrackRow(
                        track: track,
                        artworkURL: streaming.serverArtworkURL(for: track),
                        isDownloading: downloadingServerTrackIDs.contains(track.id),
                        isDownloaded: downloadedServerTrackIDs.contains(track.id),
                        onPlay: { handleServerPlay(track: track) },
                        onDownload: { handleServerDownload(track: track) }
                    )
                    .listRowBackground(AppTheme.surface)
                    .listRowSeparatorTint(AppTheme.background)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
    }
}
