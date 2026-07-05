import SwiftUI

// MARK: - TrackedPlaylistDetailView
//
// Resolves a tracked playlist to its tracks and lets the user download any of
// them into the local library. Every download is gated by a fresh local
// dir+subdir scan and a combined source-ID / title-artist duplicate check, so a
// track that already exists on the device can't be downloaded twice — the check
// runs BEFORE yt-dlp is ever invoked.

struct TrackedPlaylistDetailView: View {
    let playlist: TrackedPlaylist

    @EnvironmentObject private var library: LibraryManager
    @EnvironmentObject private var streaming: StreamingService
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var account: AccountService
    @ObservedObject private var trackedStore = TrackedPlaylistStore.shared

    @State private var tracks: [StreamTrack] = []
    @State private var isResolving = false
    @State private var errorText: String?

    @State private var localCopyIDs: Set<String> = []   // already on device
    @State private var downloadingIDs: Set<String> = []  // in flight
    @State private var playingTrackID: String?

    @State private var isDownloadingAll = false
    @State private var downloadAllDone = 0
    @State private var downloadAllTotal = 0

    @AppStorage("autoCloudBackup") private var autoCloudBackup = false

    private var newCount: Int { tracks.filter { !localCopyIDs.contains($0.id) }.count }

    var body: some View {
        List {
            headerSection

            if isResolving && tracks.isEmpty {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .listRowBackground(Color.clear)
            } else if let errorText, tracks.isEmpty {
                EmptyStateView(icon: "exclamationmark.triangle", title: "Couldn't load playlist", message: errorText)
                    .listRowBackground(Color.clear)
            } else if tracks.isEmpty {
                EmptyStateView(icon: "music.note.list", title: "No tracks", message: "This playlist returned no tracks.")
                    .listRowBackground(Color.clear)
            } else {
                Section {
                    ForEach(tracks) { track in
                        trackRow(track)
                    }
                } header: {
                    Text("\(tracks.count) TRACKS · \(newCount) NOT DOWNLOADED")
                        .font(AppTheme.bodyFont(size: 11))
                        .foregroundStyle(AppTheme.textSecondary)
                        .kerning(0.8)
                }
                .listRowBackground(AppTheme.surface.opacity(0.5))
            }
        }
        // `.plain`, not `.insetGrouped` — see FavoritesView's identical fix;
        // `.insetGrouped` splits each Section into a separate floating card
        // with the gallery background showing fully through the gaps.
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(GalleryBackgroundView().ignoresSafeArea())
        .navigationTitle(playlist.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await resolve() }
        .refreshable { await resolve() }
    }

    // MARK: Header

    private var headerSection: some View {
        Section {
            Button {
                Task { await downloadAllNew() }
            } label: {
                HStack {
                    if isDownloadingAll {
                        ProgressView()
                        Text("Downloading \(downloadAllDone)/\(downloadAllTotal)…")
                    } else {
                        Image(systemName: "arrow.down.circle.fill")
                        Text(newCount > 0 ? "Download \(newCount) New Track\(newCount == 1 ? "" : "s")" : "All Tracks Downloaded")
                    }
                    Spacer()
                }
                .foregroundStyle(newCount > 0 && !isDownloadingAll ? AppTheme.dynamicAccent : AppTheme.textSecondary)
            }
            .disabled(isDownloadingAll || newCount == 0)

            if isDownloadingAll && downloadAllTotal > 0 {
                ProgressView(value: Double(downloadAllDone), total: Double(downloadAllTotal))
                    .tint(AppTheme.dynamicAccent)
            }

            Toggle(isOn: Binding(
                get: { trackedStore.playlists.first { $0.id == playlist.id }?.isAutoDownload ?? false },
                set: { trackedStore.setAutoDownload(id: playlist.id, $0) }
            )) {
                Label("Auto-download new tracks", systemImage: "arrow.triangle.2.circlepath.circle")
                    .foregroundStyle(AppTheme.textPrimary)
            }
            .tint(AppTheme.dynamicAccent)
        } footer: {
            Text("Tracks already in your library are skipped automatically — Lumisound rescans the local Imported Music folder (and its subfolders) before each download so nothing is fetched twice. With auto-download on, new tracks added to this playlist are fetched automatically when you open the app.")
        }
        .listRowBackground(AppTheme.surface)
    }

    // MARK: Track Row

    @ViewBuilder
    private func trackRow(_ track: StreamTrack) -> some View {
        let isLocal = localCopyIDs.contains(track.id)
        HStack(spacing: 12) {
            thumbnail(for: track)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.title)
                    .foregroundStyle(AppTheme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    if !track.artist.isEmpty {
                        Text(track.artist)
                            .lineLimit(1)
                    }
                    if track.durationSeconds > 0 {
                        Text(track.durationText)
                    }
                }
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
            }

            Spacer()

            if downloadingIDs.contains(track.id) {
                ProgressView()
            } else if isLocal {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppTheme.success)
                    .accessibilityLabel("In library")
            } else {
                Button {
                    Task { await downloadOne(track) }
                } label: {
                    Image(systemName: "arrow.down.circle")
                        .font(.title3)
                        .foregroundStyle(AppTheme.dynamicAccent)
                }
                .buttonStyle(.plain)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { Task { await play(track) } }
        .overlay(alignment: .trailing) {
            if playingTrackID == track.id { ProgressView().offset(x: 28) }
        }
    }

    @ViewBuilder
    private func thumbnail(for track: StreamTrack) -> some View {
        if let url = URL(string: track.thumbnailURL), !track.thumbnailURL.isEmpty {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image): image.resizable().aspectRatio(contentMode: .fill)
                default: placeholderThumb
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        } else {
            placeholderThumb.frame(width: 44, height: 44)
        }
    }

    private var placeholderThumb: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(AppTheme.elevatedSurface)
            .overlay {
                Image(systemName: "music.note")
                    .foregroundStyle(AppTheme.textSecondary)
            }
    }

    // MARK: Actions

    private func resolve() async {
        isResolving = true
        errorText = nil
        defer { isResolving = false }

        // Make sure the local library reflects every file on disk (root +
        // Imported Music + any subfolders) BEFORE we compute duplicate status.
        await library.scanLocalDocumentsAsync()

        let resolved = await streaming.fetchPlaylistTracks(url: playlist.url, existingSongs: [])
        guard !resolved.isEmpty else {
            errorText = streaming.errorMessage ?? "The playlist couldn't be resolved. Check the URL and try again."
            return
        }
        tracks = resolved
        recomputeLocalCopies()
        TrackedPlaylistStore.shared.updateMetadata(
            id: playlist.id,
            trackCount: resolved.count,
            thumbnailURL: resolved.first?.thumbnailURL
        )
    }

    /// Re-derives which tracks already exist locally. Assumes the caller has
    /// just scanned, so `library.allSongs` is current.
    ///
    /// Builds the fast-path lookups ONCE before checking every track — the
    /// naive `tracks.filter { library.hasLocalCopy(of: $0) }` called
    /// `hasLocalCopy` (O(library) per call) once per track, which for a big
    /// playlist (hundreds of tracks) against a sizeable library was an
    /// O(tracks × library) main-thread hang long enough to trip the iOS
    /// watchdog — the "opening a big playlist crashes" bug. Same fix as
    /// `StreamSearchView.refreshDownloadedStatus`.
    private func recomputeLocalCopies() {
        let ids = library.localSourceIDs()
        let index = library.importedIdentityIndex()
        localCopyIDs = Set(
            tracks
                .filter { library.hasLocalCopy(of: $0, localSourceIDs: ids, identityIndex: index) }
                .map { $0.id }
        )
    }

    private func downloadOne(_ track: StreamTrack) async {
        guard !downloadingIDs.contains(track.id) else { return }
        downloadingIDs.insert(track.id)
        defer { downloadingIDs.remove(track.id) }

        // Re-scan + re-check immediately before invoking yt-dlp so a copy that
        // appeared since the initial resolve (or lives in a subfolder) is caught.
        await library.scanLocalDocumentsAsync()
        if library.hasLocalCopy(of: track) {
            localCopyIDs.insert(track.id)
            ToastCenter.shared.show("\"\(track.title)\" is already in your library", category: .info, icon: "checkmark.circle")
            return
        }

        do {
            let localURL = try await streaming.downloadToLibrary(track: track, existingSongs: library.allSongs)
            library.scanLocalDocuments()
            localCopyIDs.insert(track.id)
            await maybeCloudBackup(track: track, localURL: localURL)
            ToastCenter.shared.show("Downloaded \"\(track.title)\"", category: .download)
        } catch {
            ToastCenter.shared.show("Failed to download \"\(track.title)\"", category: .error)
        }
    }

    private func downloadAllNew() async {
        guard !isDownloadingAll else { return }
        isDownloadingAll = true
        defer { isDownloadingAll = false }

        await library.scanLocalDocumentsAsync()
        recomputeLocalCopies()

        let toDownload = tracks.filter { !localCopyIDs.contains($0.id) }
        guard !toDownload.isEmpty else { return }

        downloadAllDone = 0
        downloadAllTotal = toDownload.count

        // Snapshot the library once on the main actor so the @Sendable task-group
        // children don't reach back into the @MainActor LibraryManager.
        let existing = library.allSongs

        // Bounded concurrency matching the bridge's yt-dlp semaphore (4).
        let maxConcurrent = 4
        var nextIndex = 0
        var failed = 0

        await withTaskGroup(of: (track: StreamTrack, localURL: URL?).self) { group in
            func launchNext() {
                guard nextIndex < toDownload.count else { return }
                let track = toDownload[nextIndex]
                nextIndex += 1
                downloadingIDs.insert(track.id)
                group.addTask {
                    let url = try? await streaming.downloadToLibrary(track: track, existingSongs: existing)
                    return (track, url)
                }
            }

            for _ in 0..<min(maxConcurrent, toDownload.count) { launchNext() }

            for await result in group {
                downloadingIDs.remove(result.track.id)
                if let localURL = result.localURL {
                    localCopyIDs.insert(result.track.id)
                    await maybeCloudBackup(track: result.track, localURL: localURL)
                } else {
                    failed += 1
                }
                downloadAllDone += 1
                launchNext()
            }
        }

        library.scanLocalDocuments()
        recomputeLocalCopies()

        if failed == 0 {
            ToastCenter.shared.show("Downloaded \(toDownload.count) track\(toDownload.count == 1 ? "" : "s")", category: .download)
        } else {
            ToastCenter.shared.show("Downloaded \(toDownload.count - failed), \(failed) failed", category: .error)
        }
    }

    private func play(_ track: StreamTrack) async {
        guard playingTrackID == nil else { return }
        playingTrackID = track.id
        defer { playingTrackID = nil }
        do {
            let url = try await streaming.streamURL(for: track)
            let song = streaming.toSong(track: track, streamURL: url)
            player.play(song: song, in: [song])
        } catch {
            streaming.errorMessage = error.localizedDescription
        }
    }

    private func maybeCloudBackup(track: StreamTrack, localURL: URL) async {
        guard autoCloudBackup, account.isLoggedIn, let token = account.token else { return }
        try? await streaming.uploadTrack(
            fileURL: localURL,
            token: token,
            metadata: TrackMetadata(title: track.title, artist: track.artist, durationSeconds: track.duration)
        )
    }
}
