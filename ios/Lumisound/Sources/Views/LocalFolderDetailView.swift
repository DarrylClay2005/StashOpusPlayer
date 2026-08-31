import SwiftUI
import UIKit
import PhotosUI

// MARK: - LocalFolderDetailView
//
// Shows every song whose file lives anywhere inside `folderURL`, matched by
// filesystem path prefix rather than album metadata.  This means all tracks
// the user placed in a folder are visible here — regardless of whether their
// embedded album tag matches the folder name or not.

// MARK: - Sort Order

private enum FolderSortOrder: String, CaseIterable {
    case trackOrder = "Track Order"
    case title      = "Title"
    case artist     = "Artist"
    case duration   = "Duration"
    case dateAdded  = "Date Added"
}

struct LocalFolderDetailView: View {
    let folderName: String
    let folderURL: URL

    @EnvironmentObject private var library: LibraryManager
    @EnvironmentObject private var player: AudioPlayerManager

    @AppStorage("folderDetail_columns") private var columns: Int = 1
    @AppStorage("folderDetail_sortOrder") private var sortOrderRaw: String = FolderSortOrder.trackOrder.rawValue

    private var sortOrder: FolderSortOrder {
        FolderSortOrder(rawValue: sortOrderRaw) ?? .trackOrder
    }

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: columns)
    }

    @State private var songs: [Song] = []

    // Multi-select (list layout only — mirrors LibraryView/SongsTab, which
    // also drop out of selection when switching to a grid layout).
    @State private var isSelecting = false
    @State private var selectedIDs: Set<String> = []

    // Total on-disk size across every song in the folder — computed off the
    // main actor (same pattern as DownloadsManagementView.computeSizes())
    // since it means an attributesOfItem(atPath:) call per file.
    @State private var totalSizeBytes: Int64 = 0
    @State private var sizeComputeTask: Task<Void, Never>?

    // Custom, device-local folder cover art (see FolderCoverArtService).
    @State private var customCover: UIImage? = nil

    // Sheets
    @State private var showDuplicatesSheet = false
    @State private var showCreatePlaylistSheet = false

    /// Off the render path (see `.task(id:)` below) so large libraries don't
    /// re-filter the entire song list on every body evaluation. Filtering
    /// only — sorting is applied separately by `sortedSongs` so changing the
    /// sort order doesn't require re-scanning `library.allSongs`.
    private func computeSongs() -> [Song] {
        let prefix = folderURL.standardizedFileURL.path + "/"
        return library.allSongs.filter { song in
            guard let url = song.url else { return false }
            return url.standardizedFileURL.path.hasPrefix(prefix)
        }
    }

    /// `songs`, ordered per the user's chosen `sortOrder` — recomputed only
    /// when `songs` or `sortOrder` actually changes (see `refreshSortedSongs()`),
    /// not a plain computed property. This view's body references it up to
    /// half a dozen times (Play/Shuffle buttons, the row ForEach, the
    /// duplicates/export sheets); a computed property would have re-sorted
    /// the whole list from scratch on every single one of those reads, on
    /// every body re-evaluation — a real, easily-avoidable CPU cost that
    /// scales with folder size (noticeable once a folder holds hundreds of
    /// tracks).
    @State private var sortedSongs: [Song] = []

    private func refreshSortedSongs() {
        switch sortOrder {
        case .trackOrder:
            sortedSongs = songs.sorted {
                if $0.trackNumber != $1.trackNumber && ($0.trackNumber > 0 || $1.trackNumber > 0) {
                    return $0.trackNumber < $1.trackNumber
                }
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        case .title:
            sortedSongs = songs.sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        case .artist:
            sortedSongs = songs.sorted {
                let cmp = $0.artistName.localizedCaseInsensitiveCompare($1.artistName)
                if cmp != .orderedSame { return cmp == .orderedAscending }
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        case .duration:
            sortedSongs = songs.sorted { $0.duration > $1.duration }
        case .dateAdded:
            sortedSongs = songs.sorted {
                switch ($0.dateAdded, $1.dateAdded) {
                case let (a?, b?):
                    return a > b
                case (nil, _?):
                    return false
                case (_?, nil):
                    return true
                default:
                    return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
                }
            }
        }
    }

    private var totalDurationText: String {
        let total = Int(songs.reduce(0) { $0 + $1.duration }.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m \(s)s" }
        return "\(s)s"
    }

    private var totalSizeText: String {
        CacheManagerService.formattedSize(totalSizeBytes)
    }

    private func toggleSelection(_ song: Song) {
        if selectedIDs.contains(song.id) {
            selectedIDs.remove(song.id)
        } else {
            selectedIDs.insert(song.id)
        }
    }

    /// Off-actor total-size scan across every song currently in the folder —
    /// mirrors DownloadsManagementView.computeSizes()'s pattern exactly
    /// (Task.detached + attributesOfItem(atPath:) per file, hopping back to
    /// the main actor only for the final assignment).
    private func recomputeTotalSize() {
        sizeComputeTask?.cancel()
        let currentSongs = songs
        sizeComputeTask = Task.detached(priority: .utility) {
            var total: Int64 = 0
            for song in currentSongs {
                if Task.isCancelled { return }
                guard let url = song.url else { continue }
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
                   let number = attrs[.size] as? NSNumber {
                    total += number.int64Value
                }
            }
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.totalSizeBytes = total
            }
        }
    }

    var body: some View {
        Group {
            if columns == 1 {
                List {
                    // Header
                    Section {
                        FolderDetailHeaderView(
                            folderName: folderName,
                            folderURL: folderURL,
                            representativeSong: songs.first,
                            songCount: songs.count,
                            totalDurationText: totalDurationText,
                            totalSizeText: totalSizeText,
                            customCover: $customCover
                        )
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .listSectionSeparator(.hidden)

                    // Play / Shuffle
                    Section {
                        HStack(spacing: 12) {
                            Button {
                                player.setQueue(sortedSongs, startIndex: 0, autoplay: true)
                            } label: {
                                Label("Play", systemImage: "play.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(AppTheme.dynamicAccent)

                            Button {
                                let shuffled = songs.shuffled()
                                player.setQueue(shuffled, startIndex: 0, autoplay: true)
                            } label: {
                                Label("Shuffle", systemImage: "shuffle")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(AppTheme.dynamicAccent)
                        }
                        .listRowBackground(Color.clear)
                    }
                    .listSectionSeparator(.hidden)

                    // Track list — uses the same SongRow component as the main
                    // Songs tab so rows look/behave identically (artwork, context
                    // menus, favorite/play targets, styling) everywhere.
                    Section {
                        if sortedSongs.isEmpty {
                            EmptyStateView(icon: "folder", title: "Empty folder", message: "No audio files found inside \"\(folderName)\".")
                                .listRowBackground(Color.clear)
                        } else {
                            ForEach(sortedSongs) { song in
                                Button {
                                    if isSelecting {
                                        toggleSelection(song)
                                    } else {
                                        player.play(song: song, in: sortedSongs)
                                    }
                                } label: {
                                    HStack(spacing: 12) {
                                        if isSelecting {
                                            Image(systemName: selectedIDs.contains(song.id) ? "checkmark.circle.fill" : "circle")
                                                .font(.system(size: 20))
                                                .foregroundStyle(
                                                    selectedIDs.contains(song.id)
                                                        ? AppTheme.dynamicAccent
                                                        : AppTheme.textSecondary
                                                )
                                                .transition(.scale.combined(with: .opacity))
                                                .animation(.spring(response: 0.25, dampingFraction: 0.6), value: selectedIDs)
                                        }
                                        SongRow(song: song, isCurrent: player.currentSong?.id == song.id)
                                    }
                                    .animation(.easeInOut(duration: 0.15), value: isSelecting)
                                }
                                .buttonStyle(.plain)
                                // Matches the rounded-card row treatment the
                                // Queue redesign uses, for visual consistency
                                // across this whole redesign pass.
                                .listRowBackground(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(AppTheme.elevatedSurface.opacity(0.6))
                                )
                                .listRowSeparator(.hidden)
                            }
                        }
                    }
                }
                // .plain to match the main Library's edge-to-edge list (was
                // .insetGrouped, which made folders look boxed/different).
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        FolderDetailHeaderView(
                            folderName: folderName,
                            folderURL: folderURL,
                            representativeSong: songs.first,
                            songCount: songs.count,
                            totalDurationText: totalDurationText,
                            totalSizeText: totalSizeText,
                            customCover: $customCover
                        )

                        HStack(spacing: 12) {
                            Button {
                                player.setQueue(sortedSongs, startIndex: 0, autoplay: true)
                            } label: {
                                Label("Play", systemImage: "play.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(AppTheme.dynamicAccent)

                            Button {
                                let shuffled = songs.shuffled()
                                player.setQueue(shuffled, startIndex: 0, autoplay: true)
                            } label: {
                                Label("Shuffle", systemImage: "shuffle")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(AppTheme.dynamicAccent)
                        }
                        .padding(.horizontal, 16)

                        if sortedSongs.isEmpty {
                            EmptyStateView(icon: "folder", title: "Empty folder", message: "No audio files found inside \"\(folderName)\".")
                                .padding(.top, 40)
                        } else {
                            LazyVGrid(columns: gridColumns, spacing: 12) {
                                ForEach(sortedSongs) { song in
                                    Button {
                                        player.play(song: song, in: sortedSongs)
                                    } label: {
                                        SongGridCell(song: song, isCurrent: player.currentSong?.id == song.id)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                    // Extra clearance below the last row — see SongsTab's
                    // identical fix (MiniPlayerBar + tab bar clearance).
                    .padding(.bottom, 190)
                }
            }
        }
        // Own gallery/theme background — a pushed detail view doesn't inherit
        // the Library root's background, so a clear background fell back to the
        // system black (the "folders use a different dark UI" bug).
        .background(GalleryBackgroundView().ignoresSafeArea())
        .navigationTitle(folderName)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if isSelecting {
                FolderSelectionActionBar(
                    selectedCount: selectedIDs.count,
                    onAddToPlaylist: { playlistID in
                        library.addSongs(ids: selectedIDs, toPlaylistID: playlistID)
                        isSelecting = false
                        selectedIDs.removeAll()
                    },
                    onAddToQueue: {
                        let toQueue = sortedSongs.filter { selectedIDs.contains($0.id) }
                        for song in toQueue { player.appendToQueue(song: song) }
                        ToastCenter.shared.show(
                            "Added \(toQueue.count) song\(toQueue.count == 1 ? "" : "s") to queue",
                            category: .success, icon: "text.badge.plus"
                        )
                        isSelecting = false
                        selectedIDs.removeAll()
                    },
                    onFavorite: {
                        library.addFavorites(ids: selectedIDs)
                        isSelecting = false
                        selectedIDs.removeAll()
                    },
                    onDelete: {
                        library.removeImportedSongs(ids: selectedIDs)
                        isSelecting = false
                        selectedIDs.removeAll()
                    },
                    onCancel: {
                        isSelecting = false
                        selectedIDs.removeAll()
                    }
                )
                .environmentObject(library)
            } else {
                MiniPlayerBar()
            }
        }
        .task(id: library.allSongs.count) {
            songs = computeSongs()
            refreshSortedSongs()
            recomputeTotalSize()
        }
        .onAppear {
            customCover = FolderCoverArtService.shared.cover(for: folderURL)
        }
        .onChange(of: sortOrderRaw) { _ in
            refreshSortedSongs()
        }
        .onChange(of: columns) { newValue in
            // Multi-select only applies to the single-column List layout —
            // drop out of it if the user switches to grid mid-selection
            // (mirrors LibraryView's identical songColumns guard).
            if isSelecting && newValue != 1 {
                isSelecting = false
                selectedIDs.removeAll()
            }
        }
        .sheet(isPresented: $showDuplicatesSheet) {
            FolderDuplicatesSheet(songs: sortedSongs)
                .environmentObject(library)
                .environmentObject(player)
        }
        .sheet(isPresented: $showCreatePlaylistSheet) {
            FolderExportPlaylistSheet(
                defaultName: folderName,
                onCreate: { name in
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    let ids = sortedSongs.map(\.id)
                    library.createPlaylist(name: trimmed, songIDs: ids)
                    ToastCenter.shared.show(
                        "Created playlist \"\(trimmed)\" with \(ids.count) song\(ids.count == 1 ? "" : "s")",
                        category: .success, icon: "music.note.list"
                    )
                    showCreatePlaylistSheet = false
                },
                onCancel: { showCreatePlaylistSheet = false }
            )
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(isSelecting ? "Done" : "Select") {
                    if isSelecting {
                        isSelecting = false
                        selectedIDs.removeAll()
                    } else {
                        isSelecting = true
                        columns = 1
                    }
                }
                .tint(AppTheme.dynamicAccent)
                .disabled(songs.isEmpty)
            }

            ToolbarItemGroup(placement: .navigationBarTrailing) {
                Menu {
                    Menu {
                        ForEach(FolderSortOrder.allCases, id: \.self) { order in
                            Button {
                                sortOrderRaw = order.rawValue
                            } label: {
                                HStack {
                                    Text(order.rawValue)
                                    if sortOrder == order {
                                        Spacer()
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        Label("Sort By", systemImage: "arrow.up.arrow.down")
                    }

                    Button {
                        showCreatePlaylistSheet = true
                    } label: {
                        Label("New Playlist from Folder", systemImage: "music.note.list")
                    }
                    .disabled(songs.isEmpty)

                    Button {
                        showDuplicatesSheet = true
                    } label: {
                        Label("Find Duplicates in Folder", systemImage: "doc.on.doc")
                    }
                    .disabled(songs.count < 2)

                    if customCover != nil {
                        Divider()
                        Button(role: .destructive) {
                            FolderCoverArtService.shared.removeCover(for: folderURL)
                            customCover = nil
                        } label: {
                            Label("Remove Folder Cover", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .tint(AppTheme.dynamicAccent)

                Button {
                    columns = 1
                } label: {
                    Image(systemName: "list.bullet")
                        .foregroundStyle(columns == 1 ? AppTheme.dynamicAccent : AppTheme.textSecondary)
                }
                .buttonStyle(.plain)

                Button {
                    columns = 2
                } label: {
                    Image(systemName: "square.grid.2x2")
                        .foregroundStyle(columns == 2 ? AppTheme.dynamicAccent : AppTheme.textSecondary)
                }
                .buttonStyle(.plain)

                Button {
                    columns = 3
                } label: {
                    Image(systemName: "square.grid.3x3")
                        .foregroundStyle(columns == 3 ? AppTheme.dynamicAccent : AppTheme.textSecondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Header

private struct FolderDetailHeaderView: View {
    let folderName: String
    let folderURL: URL
    let representativeSong: Song?
    let songCount: Int
    let totalDurationText: String
    let totalSizeText: String
    @Binding var customCover: UIImage?

    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        ZStack(alignment: .bottom) {
            // Big blurred-artwork backdrop, same component the Queue and
            // Songs redesigns use — gives the folder its own atmosphere
            // instead of opening straight onto a plain centered art tile on
            // a flat background.
            HeroArtworkBackdrop(song: representativeSong, height: 300)

            VStack(spacing: 14) {
                BreadcrumbTrail(parent: "Imported Music", current: folderName)

                ZStack(alignment: .bottomTrailing) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(AppTheme.surface)
                            .frame(width: 156, height: 156)

                        if let customCover {
                            Image(uiImage: customCover)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 156, height: 156)
                                .clipped()
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        } else if let song = representativeSong {
                            ArtworkThumbnail(song: song, size: 156)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        } else {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 44))
                                .foregroundStyle(AppTheme.dynamicAccent)
                        }
                    }
                    .frame(width: 156, height: 156)
                    .shadow(color: .black.opacity(0.5), radius: 14, y: 8)

                    // Custom folder cover art — device-local, see
                    // FolderCoverArtService. Overlaid on the artwork itself
                    // (rather than a toolbar action) so it's discoverable the
                    // same way changing a playlist's/profile's photo is
                    // elsewhere in the app.
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 24))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, AppTheme.dynamicAccent)
                            .background(Circle().fill(.black.opacity(0.35)))
                    }
                    .padding(6)
                }
                .onChange(of: pickerItem) { item in
                    guard let item else { return }
                    Task {
                        // Downsample straight from the encoded bytes (ImageIO,
                        // never decodes the full-resolution photo-library asset)
                        // rather than `UIImage(data:)` + a later resize — same
                        // rationale as every other raster import path in the app
                        // (see ImageDownsampler's header comment).
                        guard let data = try? await item.loadTransferable(type: Data.self),
                              let image = ImageDownsampler.downsampled(from: data, maxPixelSize: 512)
                        else { return }
                        // Explicit MainActor hop for everything past the `await`
                        // above (loadTransferable can resume off the main actor) —
                        // same defensive pattern CustomStyleEditorView's identical
                        // PhotosPicker → onChange → Task flow uses, and required
                        // here anyway since FolderCoverArtService is @MainActor.
                        await MainActor.run {
                            FolderCoverArtService.shared.setCover(image, for: folderURL)
                            customCover = FolderCoverArtService.shared.cover(for: folderURL)
                            pickerItem = nil
                        }
                    }
                }

                VStack(spacing: 6) {
                    Text(folderName)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(AppTheme.textPrimary)
                        .multilineTextAlignment(.center)

                    HStack(spacing: 8) {
                        ScreenStatChip(icon: "music.note", text: "\(songCount) \(songCount == 1 ? "song" : "songs")")
                        ScreenStatChip(icon: "clock", text: totalDurationText)
                        ScreenStatChip(icon: "internaldrive", text: totalSizeText)
                    }
                }
            }
            .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Selection Action Bar
//
// Bulk actions for the folder's multi-select mode — add to an existing
// playlist, add to queue, favorite, or delete. Modeled directly on
// LibrarySelectionActionBar (same layout/confirmation-dialog conventions)
// but with two extra actions (queue, favorite) that screen doesn't need,
// so it's its own small type rather than a shared one.

private struct FolderSelectionActionBar: View {
    let selectedCount: Int
    let onAddToPlaylist: (UUID) -> Void
    let onAddToQueue: () -> Void
    let onFavorite: () -> Void
    let onDelete: () -> Void
    let onCancel: () -> Void

    @EnvironmentObject private var library: LibraryManager
    @State private var showDeleteConfirm = false

    var body: some View {
        HStack(spacing: 14) {
            Button("Cancel", action: onCancel)
                .foregroundStyle(AppTheme.textSecondary)

            Spacer()

            Text("\(selectedCount) selected")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppTheme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer()

            Button(action: onFavorite) {
                Image(systemName: "heart")
                    .font(.system(size: 17, weight: .medium))
            }
            .disabled(selectedCount == 0)

            Button(action: onAddToQueue) {
                Image(systemName: "text.badge.plus")
                    .font(.system(size: 17, weight: .medium))
            }
            .disabled(selectedCount == 0)

            Menu {
                if library.playlists.isEmpty {
                    Text("No playlists yet")
                } else {
                    ForEach(library.playlists) { playlist in
                        Button {
                            onAddToPlaylist(playlist.id)
                        } label: {
                            Label(playlist.name, systemImage: "music.note.list")
                        }
                    }
                }
            } label: {
                Image(systemName: "plus.rectangle.on.folder")
                    .font(.system(size: 17, weight: .medium))
            }
            .disabled(selectedCount == 0)

            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 17, weight: .medium))
            }
            .disabled(selectedCount == 0)
        }
        .foregroundStyle(AppTheme.dynamicAccent)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(Divider(), alignment: .top)
        .confirmationDialog(
            "Delete \(selectedCount) song\(selectedCount == 1 ? "" : "s")?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete \(selectedCount) Song\(selectedCount == 1 ? "" : "s")", role: .destructive, action: onDelete)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Songs from your Apple Music library can't be deleted this way and will be skipped.")
        }
    }
}

// MARK: - Export-as-Playlist Sheet

private struct FolderExportPlaylistSheet: View {
    let defaultName: String
    let onCreate: (String) -> Void
    let onCancel: () -> Void

    @State private var name: String = ""
    @FocusState private var isFocused: Bool

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Playlist Name") {
                    TextField("Playlist name", text: $name)
                        .focused($isFocused)
                        .autocorrectionDisabled()
                        .foregroundStyle(AppTheme.textPrimary)
                        .listRowBackground(AppTheme.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Color.clear.ignoresSafeArea())
            .navigationTitle("New Playlist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                        .tint(AppTheme.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        onCreate(name)
                    }
                    .disabled(!isValid)
                    .tint(AppTheme.dynamicAccent)
                }
            }
            .onAppear {
                name = defaultName
                isFocused = true
            }
        }
    }
}
