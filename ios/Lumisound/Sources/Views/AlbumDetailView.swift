import SwiftUI

struct AlbumDetailView: View {
    let album: String

    @EnvironmentObject private var library: LibraryManager
    @EnvironmentObject private var player: AudioPlayerManager

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
        .background(Color.clear.ignoresSafeArea())
        .navigationTitle(album)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { MiniPlayerBar() }
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
