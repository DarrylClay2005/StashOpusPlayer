import SwiftUI

struct AlbumDetailView: View {
    let album: String

    @EnvironmentObject private var library: LibraryManager
    @EnvironmentObject private var player: AudioPlayerManager

    @AppStorage("albumDetail_columns") private var columns: Int = 1

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: columns)
    }

    private var songs: [Song] {
        library.songs(inAlbum: album)
            .sorted {
                if $0.trackNumber != $1.trackNumber {
                    return $0.trackNumber < $1.trackNumber
                }
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
    }

    private var artistName: String {
        songs.first?.artistName ?? "Unknown Artist"
    }

    private var totalDuration: TimeInterval {
        songs.reduce(0) { $0 + $1.duration }
    }

    private var totalDurationText: String {
        let total = Int(totalDuration.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m \(seconds)s"
        } else {
            return "\(seconds)s"
        }
    }

    var body: some View {
        Group {
            if columns == 1 {
                List {
                    // Album header — pinned at top
                    Section {
                        AlbumHeaderView(
                            album: album,
                            artistName: artistName,
                            songCount: songs.count,
                            totalDurationText: totalDurationText,
                            songs: songs
                        )
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .listSectionSeparator(.hidden)

                    // Play button
                    Section {
                        Button {
                            player.setQueue(songs, startIndex: 0, autoplay: true)
                        } label: {
                            Label("Play Album", systemImage: "play.fill")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(AppTheme.dynamicAccent)
                        .listRowBackground(Color.clear)
                    }
                    .listSectionSeparator(.hidden)

                    // Tracks — uses the same SongRow component as the main Songs
                    // tab so rows look/behave identically (artwork, context menus,
                    // favorite/play targets, styling) everywhere.
                    Section {
                        if songs.isEmpty {
                            EmptyStateView(icon: "square.stack", title: "No tracks", message: "This album has no tracks.")
                                .listRowBackground(Color.clear)
                        } else {
                            ForEach(songs) { song in
                                Button {
                                    player.play(song: song, in: songs)
                                } label: {
                                    SongRow(
                                        song: song,
                                        isCurrent: player.currentSong?.id == song.id,
                                        subtitle: song.year.isEmpty ? nil : song.year
                                    )
                                }
                                .buttonStyle(.plain)
                                .listRowBackground(AppTheme.surface.opacity(0.5))
                            }
                        }
                    }
                }
                // .plain (not .insetGrouped) to match the main Library's
                // edge-to-edge list — insetGrouped's boxed, inset sections were
                // the "Albums look different from the rest of the app" mismatch.
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        AlbumHeaderView(
                            album: album,
                            artistName: artistName,
                            songCount: songs.count,
                            totalDurationText: totalDurationText,
                            songs: songs
                        )

                        Button {
                            player.setQueue(songs, startIndex: 0, autoplay: true)
                        } label: {
                            Label("Play Album", systemImage: "play.fill")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(AppTheme.dynamicAccent)
                        .padding(.horizontal, 16)

                        if songs.isEmpty {
                            EmptyStateView(icon: "square.stack", title: "No tracks", message: "This album has no tracks.")
                                .padding(.top, 40)
                        } else {
                            LazyVGrid(columns: gridColumns, spacing: 12) {
                                ForEach(songs) { song in
                                    Button {
                                        player.play(song: song, in: songs)
                                    } label: {
                                        SongGridCell(
                                            song: song,
                                            isCurrent: player.currentSong?.id == song.id,
                                            subtitle: song.durationText,
                                            trackNumber: song.trackNumber
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                    // Extra clearance below the last row — see SongsTab's
                    // identical fix (MiniPlayerBar + tab bar clearance).
                    .padding(.bottom, 120)
                }
            }
        }
        // Use the app's gallery/theme background directly — a pushed detail
        // view doesn't inherit the Library root's background through the
        // NavigationStack, so a clear background fell back to the system's
        // black (the "albums use a different dark UI" bug).
        .background(GalleryBackgroundView().ignoresSafeArea())
        .navigationTitle(album)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { MiniPlayerBar() }
        .toolbar {
            ToolbarItemGroup(placement: .navigationBarTrailing) {
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

// MARK: - Album Header

private struct AlbumHeaderView: View {
    let album: String
    let artistName: String
    let songCount: Int
    let totalDurationText: String
    let songs: [Song]

    var body: some View {
        VStack(spacing: 16) {
            // Large artwork
            Group {
                if let song = songs.first {
                    ArtworkThumbnail(song: song, size: 256)
                } else {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(AppTheme.surface)
                        .frame(width: 256, height: 256)
                        .overlay {
                            Image(systemName: "square.stack.fill")
                                .font(.system(size: 64))
                                .foregroundStyle(AppTheme.dynamicAccent)
                        }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: .black.opacity(0.4), radius: 16, y: 8)

            // Metadata
            VStack(spacing: 6) {
                Text(album)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .multilineTextAlignment(.center)

                Text(artistName)
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.dynamicAccent)

                Text("\(songCount) \(songCount == 1 ? "song" : "songs") · \(totalDurationText)")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

