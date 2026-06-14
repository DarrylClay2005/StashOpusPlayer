import SwiftUI

struct ArtistDetailView: View {
    let artist: String

    @EnvironmentObject private var library: LibraryManager
    @EnvironmentObject private var player: AudioPlayerManager

    // Songs sorted by album name then track number
    private var songs: [Song] {
        library.songs(byArtist: artist)
            .sorted {
                if $0.albumName != $1.albumName {
                    return $0.albumName.localizedCaseInsensitiveCompare($1.albumName) == .orderedAscending
                }
                return $0.trackNumber < $1.trackNumber
            }
    }

    // Albums in order they first appear
    private var albums: [String] {
        var seen = Set<String>()
        return songs.compactMap { song -> String? in
            let name = song.albumName
            return seen.insert(name).inserted ? name : nil
        }
    }

    private func songs(inAlbum album: String) -> [Song] {
        songs.filter { $0.albumName == album }
    }

    var body: some View {
        List {
            // Artist header — real profile picture, matching the look of
            // AlbumDetailView's/LocalFolderDetailView's headers.
            Section {
                ArtistHeaderView(artist: artist, songCount: songs.count, albumCount: albums.count)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
            .listSectionSeparator(.hidden)

            if songs.isEmpty {
                EmptyStateView(
                    icon: "person.crop.circle",
                    title: "No songs",
                    message: "No songs found for this artist."
                )
                .listRowBackground(Color.clear)
            } else {
                // Play / Shuffle section
                Section {
                    playbackButtons
                }
                .listRowBackground(Color.clear)
                .listSectionSeparator(.hidden)

                // Albums and their songs — uses the same SongRow component as
                // the main Songs tab so rows look/behave identically (context
                // menus, favorite/play targets, styling) everywhere.
                ForEach(albums, id: \.self) { album in
                    Section {
                        ForEach(songs(inAlbum: album)) { song in
                            Button {
                                player.play(song: song, in: songs)
                            } label: {
                                SongRow(
                                    song: song,
                                    isCurrent: player.currentSong?.id == song.id
                                )
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(AppTheme.surface.opacity(0.5))
                        }
                    } header: {
                        AlbumSectionHeader(album: album, songs: songs(inAlbum: album))
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.clear.ignoresSafeArea())
        .navigationTitle(artist)
        .navigationBarTitleDisplayMode(.large)
        .safeAreaInset(edge: .bottom) { MiniPlayerBar() }
    }

    private var playbackButtons: some View {
        HStack(spacing: 12) {
            Button {
                player.setQueue(songs, startIndex: 0, autoplay: true)
            } label: {
                Label("Play All", systemImage: "play.fill")
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
        .padding(.vertical, 4)
    }
}

// MARK: - Artist Header

private struct ArtistHeaderView: View {
    let artist: String
    let songCount: Int
    let albumCount: Int

    var body: some View {
        VStack(spacing: 16) {
            ArtistAvatar(artist: artist, size: 144, cornerRadius: 72)
                .shadow(color: .black.opacity(0.4), radius: 16, y: 8)

            VStack(spacing: 6) {
                Text(artist)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppTheme.textPrimary)
                    .multilineTextAlignment(.center)

                Text("\(albumCount) \(albumCount == 1 ? "album" : "albums") · \(songCount) \(songCount == 1 ? "song" : "songs")")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }
}

// MARK: - Album Section Header

private struct AlbumSectionHeader: View {
    let album: String
    let songs: [Song]
    @EnvironmentObject private var library: LibraryManager

    private var representativeSong: Song? { songs.first }

    var body: some View {
        HStack(spacing: 10) {
            if let song = representativeSong {
                ArtworkThumbnail(song: song, size: 40)
            } else {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(AppTheme.elevatedSurface)
                    .frame(width: 40, height: 40)
                    .overlay {
                        Image(systemName: "square.stack")
                            .foregroundStyle(AppTheme.dynamicAccent)
                    }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(album)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.textPrimary)
                Text("\(songs.count) \(songs.count == 1 ? "track" : "tracks")")
                    .font(.caption)
                    .foregroundStyle(AppTheme.textSecondary)
            }

            Spacer()
        }
        .textCase(nil)
        .padding(.vertical, 4)
    }
}
