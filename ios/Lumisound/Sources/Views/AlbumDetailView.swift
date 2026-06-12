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

                    // Tracks
                    Section {
                        if songs.isEmpty {
                            EmptyStateView(icon: "square.stack", title: "No tracks", message: "This album has no tracks.")
                                .listRowBackground(Color.clear)
                        } else {
                            ForEach(songs) { song in
                                Button {
                                    player.play(song: song, in: songs)
                                } label: {
                                    AlbumTrackRow(song: song, isCurrent: player.currentSong?.id == song.id)
                                }
                                .buttonStyle(.plain)
                                .listRowBackground(AppTheme.surface.opacity(0.5))
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
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
                                        AlbumTrackGridCell(song: song, isCurrent: player.currentSong?.id == song.id)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }
                    .padding(.bottom, 16)
                }
            }
        }
        .background(Color.clear.ignoresSafeArea())
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

// MARK: - Album Track Row (compact, uses track number instead of artwork)

private struct AlbumTrackRow: View {
    let song: Song
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Track number / playing indicator
            ZStack {
                if isCurrent {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(AppTheme.dynamicAccent)
                    Image(systemName: "waveform")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.textPrimary)
                } else {
                    Text(song.trackNumber > 0 ? "\(song.trackNumber)" : "–")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppTheme.textSecondary)
                        .monospacedDigit()
                }
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 3) {
                Text(song.displayName)
                    .foregroundStyle(isCurrent ? AppTheme.dynamicAccent : AppTheme.textPrimary)
                    .fontWeight(isCurrent ? .semibold : .regular)
                    .lineLimit(1)

                if !song.year.isEmpty {
                    Text(song.year)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                }
            }

            Spacer(minLength: 0)

            Text(song.durationText)
                .font(.caption)
                .foregroundStyle(AppTheme.textSecondary)
                .monospacedDigit()
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }
}

// MARK: - Album Track Grid Cell (2/3-column layout)

private struct AlbumTrackGridCell: View {
    let song: Song
    let isCurrent: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geo in
                ArtworkThumbnail(song: song, size: geo.size.width)
                    .overlay(alignment: .bottomTrailing) {
                        if isCurrent {
                            Image(systemName: "waveform")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(4)
                                .background(AppTheme.dynamicAccent, in: Circle())
                                .padding(4)
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        if song.trackNumber > 0 {
                            Text("\(song.trackNumber)")
                                .font(.caption2.weight(.bold))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.black.opacity(0.5), in: Capsule())
                                .padding(4)
                        }
                    }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(song.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isCurrent ? AppTheme.dynamicAccent : AppTheme.textPrimary)
                    .lineLimit(2)
                Text(song.durationText)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textSecondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 2)
        }
        .padding(6)
        .background(AppTheme.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
