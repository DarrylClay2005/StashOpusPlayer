import SwiftUI

// MARK: - LocalFolderDetailView
//
// Shows every song whose file lives anywhere inside `folderURL`, matched by
// filesystem path prefix rather than album metadata.  This means all tracks
// the user placed in a folder are visible here — regardless of whether their
// embedded album tag matches the folder name or not.

struct LocalFolderDetailView: View {
    let folderName: String
    let folderURL: URL

    @EnvironmentObject private var library: LibraryManager
    @EnvironmentObject private var player: AudioPlayerManager

    @AppStorage("folderDetail_columns") private var columns: Int = 1

    private var gridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: columns)
    }

    @State private var songs: [Song] = []

    /// Off the render path (see `.task(id:)` below) so large libraries don't
    /// re-filter/re-sort the entire song list on every body evaluation.
    private func computeSongs() -> [Song] {
        let prefix = folderURL.standardizedFileURL.path + "/"
        return library.allSongs
            .filter { song in
                guard let url = song.url else { return false }
                return url.standardizedFileURL.path.hasPrefix(prefix)
            }
            .sorted {
                if $0.trackNumber != $1.trackNumber && ($0.trackNumber > 0 || $1.trackNumber > 0) {
                    return $0.trackNumber < $1.trackNumber
                }
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
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

    var body: some View {
        Group {
            if columns == 1 {
                List {
                    // Header
                    Section {
                        FolderDetailHeaderView(
                            folderName: folderName,
                            representativeSong: songs.first,
                            songCount: songs.count,
                            totalDurationText: totalDurationText
                        )
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                    .listSectionSeparator(.hidden)

                    // Play / Shuffle
                    Section {
                        HStack(spacing: 12) {
                            Button {
                                player.setQueue(songs, startIndex: 0, autoplay: true)
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

                    // Track list
                    Section {
                        if songs.isEmpty {
                            EmptyStateView(icon: "folder", title: "Empty folder", message: "No audio files found inside \"\(folderName)\".")
                                .listRowBackground(Color.clear)
                        } else {
                            ForEach(songs) { song in
                                Button {
                                    player.play(song: song, in: songs)
                                } label: {
                                    FolderTrackRow(song: song, isCurrent: player.currentSong?.id == song.id)
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
                        FolderDetailHeaderView(
                            folderName: folderName,
                            representativeSong: songs.first,
                            songCount: songs.count,
                            totalDurationText: totalDurationText
                        )

                        HStack(spacing: 12) {
                            Button {
                                player.setQueue(songs, startIndex: 0, autoplay: true)
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

                        if songs.isEmpty {
                            EmptyStateView(icon: "folder", title: "Empty folder", message: "No audio files found inside \"\(folderName)\".")
                                .padding(.top, 40)
                        } else {
                            LazyVGrid(columns: gridColumns, spacing: 12) {
                                ForEach(songs) { song in
                                    Button {
                                        player.play(song: song, in: songs)
                                    } label: {
                                        FolderTrackGridCell(song: song, isCurrent: player.currentSong?.id == song.id)
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
        .navigationTitle(folderName)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { MiniPlayerBar() }
        .task(id: library.allSongs.count) {
            songs = computeSongs()
        }
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

// MARK: - Header

private struct FolderDetailHeaderView: View {
    let folderName: String
    let representativeSong: Song?
    let songCount: Int
    let totalDurationText: String

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppTheme.surface)
                    .frame(width: 256, height: 256)

                if let song = representativeSong {
                    ArtworkThumbnail(song: song, size: 256)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                } else {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(AppTheme.dynamicAccent)
                }
            }
            .shadow(color: .black.opacity(0.4), radius: 16, y: 8)

            VStack(spacing: 6) {
                Text(folderName)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .multilineTextAlignment(.center)

                Text("\(songCount) \(songCount == 1 ? "song" : "songs") · \(totalDurationText)")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

// MARK: - Track Grid Cell (2/3-column layout)

private struct FolderTrackGridCell: View {
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
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(song.displayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isCurrent ? AppTheme.dynamicAccent : AppTheme.textPrimary)
                    .lineLimit(2)
                Text(song.artistName)
                    .font(.caption2)
                    .foregroundStyle(AppTheme.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 2)
        }
        .padding(6)
        .background(AppTheme.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - Track Row

private struct FolderTrackRow: View {
    let song: Song
    let isCurrent: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                ArtworkThumbnail(song: song, size: 40)

                if isCurrent {
                    RoundedRectangle(cornerRadius: max(4, 40 * 0.1), style: .continuous)
                        .fill(AppTheme.dynamicAccent.opacity(0.78))
                    FolderWaveformIcon()
                }
            }
            .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(song.displayName)
                    .foregroundStyle(isCurrent ? AppTheme.dynamicAccent : AppTheme.textPrimary)
                    .fontWeight(isCurrent ? .semibold : .regular)
                    .lineLimit(1)

                if !song.artistName.isEmpty {
                    Text(song.artistName)
                        .font(.caption)
                        .foregroundStyle(AppTheme.textSecondary)
                        .lineLimit(1)
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

// MARK: - Animated waveform indicator (current track)

private struct FolderWaveformIcon: View {
    @State private var animating = false

    private let heights: [CGFloat] = [0.45, 0.85, 0.60, 0.80, 0.50]
    private let delays: [Double]   = [0.0,  0.15, 0.30, 0.10, 0.25]

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<5) { i in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(AppTheme.textPrimary)
                    .frame(width: 2.5, height: animating ? 12 * heights[i] : 3)
                    .animation(
                        .easeInOut(duration: 0.55)
                            .repeatForever(autoreverses: true)
                            .delay(delays[i]),
                        value: animating
                    )
            }
        }
        .onAppear { animating = true }
        .onDisappear { animating = false }
    }
}
