import SwiftUI

// MARK: - StreamSearchView

struct StreamSearchView: View {

    @EnvironmentObject private var streaming: StreamingService
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var library: LibraryManager

    @State private var searchText        = ""
    @State private var selectedSource    = "youtube"
    @State private var loadingTrackID:   String? = nil
    @State private var downloadingTrackID: String? = nil
    @State private var downloadedTrackIDs: Set<String> = []
    @State private var healthOK: Bool? = nil
    @State private var showHealthToast   = false

    private let sources = ["youtube", "soundcloud"]

    var body: some View {
        NavigationStack {
            Group {
                if streaming.isConfigured {
                    configuredBody
                } else {
                    notConfiguredView
                }
            }
            .navigationTitle("Search Streaming")
            .navigationBarTitleDisplayMode(.large)
            .background(Color.clear.ignoresSafeArea())
        }
    }

    // MARK: — Not configured

    private var notConfiguredView: some View {
        VStack(spacing: 20) {
            Image(systemName: "server.rack")
                .font(.system(size: 56))
                .foregroundStyle(AppTheme.textSecondary)

            Text("Bridge Server Not Configured")
                .font(AppTheme.headlineFont(size: 18))
                .foregroundStyle(AppTheme.textPrimary)

            Text("Enter your bridge server URL in Settings → Streaming to search YouTube and SoundCloud.")
                .font(AppTheme.bodyFont(size: 14))
                .foregroundStyle(AppTheme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            NavigationLink(destination: SettingsView()) {
                Label("Open Settings", systemImage: "gearshape")
                    .font(AppTheme.bodyFont(size: 15))
                    .foregroundStyle(AppTheme.background)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(AppTheme.accent, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: — Configured body

    private var configuredBody: some View {
        VStack(spacing: 0) {
            // Source picker
            Picker("Source", selection: $selectedSource) {
                ForEach(sources, id: \.self) { src in
                    Text(src.capitalized).tag(src)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .onChange(of: selectedSource) { _ in
                if !searchText.isEmpty {
                    Task { await streaming.search(query: searchText, source: selectedSource) }
                }
            }

            // Error banner
            if let error = streaming.errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(AppTheme.warning)
                    Text(error)
                        .font(AppTheme.bodyFont(size: 13))
                        .foregroundStyle(AppTheme.warning)
                        .lineLimit(2)
                    Spacer()
                    if !searchText.isEmpty {
                        Button("Retry") {
                            Task { await streaming.search(query: searchText, source: selectedSource) }
                        }
                        .font(AppTheme.bodyFont(size: 13).weight(.semibold))
                        .foregroundStyle(AppTheme.accent)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(AppTheme.warning.opacity(0.12))
            }

            // Results
            if streaming.isSearching {
                Spacer()
                ProgressView("Searching…")
                    .tint(AppTheme.accent)
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer()
            } else if streaming.searchResults.isEmpty && !searchText.isEmpty {
                Spacer()
                Text("No results for \"\(searchText)\"")
                    .font(AppTheme.bodyFont(size: 15))
                    .foregroundStyle(AppTheme.textSecondary)
                Spacer()
            } else {
                List(streaming.searchResults) { track in
                    StreamTrackRow(
                        track: track,
                        isLoading: loadingTrackID == track.id,
                        isDownloading: downloadingTrackID == track.id,
                        isDownloaded: downloadedTrackIDs.contains(track.id),
                        onPlay: { handlePlay(track: track) },
                        onAddToQueue: { handleAddToQueue(track: track) },
                        onDownload: { handleDownload(track: track) }
                    )
                    .listRowBackground(AppTheme.surface)
                    .listRowSeparatorTint(AppTheme.background)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search YouTube, SoundCloud…"
        )
        .onSubmit(of: .search) {
            Task { await streaming.search(query: searchText, source: selectedSource) }
        }
        .onChange(of: searchText) { newValue in
            if newValue.isEmpty {
                streaming.searchResults = []
                streaming.errorMessage = nil
            }
        }
    }

    // MARK: — Actions

    private func handlePlay(track: StreamTrack) {
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

    private func handleAddToQueue(track: StreamTrack) {
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

    private func handleDownload(track: StreamTrack) {
        guard downloadingTrackID == nil else { return }
        downloadingTrackID = track.id
        Task {
            do {
                _ = try await streaming.downloadToLibrary(track: track)
                library.scanLocalDocuments()
                downloadedTrackIDs.insert(track.id)
            } catch {
                streaming.errorMessage = "Download failed: \(error.localizedDescription)"
            }
            downloadingTrackID = nil
        }
    }
}

// MARK: - StreamTrackRow

private struct StreamTrackRow: View {

    let track: StreamTrack
    let isLoading: Bool
    let isDownloading: Bool
    let isDownloaded: Bool
    let onPlay: () -> Void
    let onAddToQueue: () -> Void
    let onDownload: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            AsyncImage(url: URL(string: track.thumbnailURL)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                case .failure, .empty:
                    Image(systemName: sourceIcon)
                        .font(.system(size: 20))
                        .foregroundStyle(AppTheme.textSecondary)
                @unknown default:
                    Color.clear
                }
            }
            .frame(width: 44, height: 44)
            .background(AppTheme.elevatedSurface)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            // Title + artist
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

            // Duration
            Text(track.durationText)
                .font(AppTheme.monoFont(size: 12))
                .foregroundStyle(AppTheme.textSecondary)
                .frame(minWidth: 36, alignment: .trailing)

            // Play / spinner
            if isLoading {
                ProgressView()
                    .tint(AppTheme.accent)
                    .frame(width: 32, height: 32)
            } else {
                Button(action: onPlay) {
                    Image(systemName: "play.circle.fill")
                        .font(.title2)
                        .foregroundStyle(AppTheme.accent)
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }

            // Download button
            Button(action: onDownload) {
                if isDownloading {
                    ProgressView()
                        .tint(AppTheme.accent)
                        .frame(width: 32, height: 32)
                } else if isDownloaded {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(AppTheme.success)
                        .frame(width: 32, height: 32)
                } else {
                    Image(systemName: "arrow.down.circle")
                        .font(.title2)
                        .foregroundStyle(AppTheme.textSecondary)
                        .frame(width: 32, height: 32)
                }
            }
            .buttonStyle(.plain)
            .disabled(isDownloading || isDownloaded)

            // Queue button
            Button(action: onAddToQueue) {
                Image(systemName: "text.line.last.and.arrowtriangle.forward")
                    .font(.system(size: 14))
                    .foregroundStyle(AppTheme.textSecondary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture(perform: onPlay)
    }

    private var sourceIcon: String {
        track.source == "soundcloud" ? "cloud.fill" : "play.rectangle.fill"
    }
}
