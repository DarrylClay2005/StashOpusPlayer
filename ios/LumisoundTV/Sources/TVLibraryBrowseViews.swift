import SwiftUI

// MARK: - Grouping (mirrors LibraryManager's album/artist derivation on iOS:
// group by the metadata field verbatim — case-insensitive alphabetical order
// — falling back to "Unknown Album"/"Unknown Artist" for tracks with no tag.
// Note: the bridge itself already falls back to the containing folder name
// for `album` when a file has no album tag (see `/user/music` in
// ios-bridge/main.py), so grouping by `album` here also surfaces
// folder-organized uploads without needing a separate "folder" tab.)

struct TVAlbumGroup: Identifiable, Hashable {
    let name: String
    let tracks: [UserMusicTrack]  // always non-empty — built via Dictionary(grouping:)
    var id: String { name }
    var representativeTrack: UserMusicTrack { tracks[0] }
    var artistName: String {
        let a = tracks[0].artist
        return a.isEmpty ? "Unknown Artist" : a
    }
}

struct TVArtistGroup: Identifiable, Hashable {
    let name: String
    let tracks: [UserMusicTrack]
    var id: String { name }
    var albumCount: Int { Set(tracks.map { $0.album.isEmpty ? "Unknown Album" : $0.album }).count }
}

/// Track order within an album: by track number (untagged tracks sort last),
/// then title — matches `AlbumDetailView`'s ordering on iOS.
private func albumSortKey(_ t: UserMusicTrack) -> (Int, String) {
    (Int(t.trackNumber) ?? Int.max, t.title.isEmpty ? t.filename : t.title)
}

func tvAlbumGroups(from library: [UserMusicTrack]) -> [TVAlbumGroup] {
    let groups = Dictionary(grouping: library) { $0.album.isEmpty ? "Unknown Album" : $0.album }
    return groups.keys
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        .map { name in
            TVAlbumGroup(name: name, tracks: (groups[name] ?? []).sorted {
                let (n0, t0) = albumSortKey($0), (n1, t1) = albumSortKey($1)
                return n0 != n1 ? n0 < n1 : t0.localizedCaseInsensitiveCompare(t1) == .orderedAscending
            })
        }
}

func tvArtistGroups(from library: [UserMusicTrack]) -> [TVArtistGroup] {
    let groups = Dictionary(grouping: library) { $0.artist.isEmpty ? "Unknown Artist" : $0.artist }
    return groups.keys
        .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        .map { name in
            TVArtistGroup(name: name, tracks: (groups[name] ?? []).sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            })
        }
}

// MARK: - Albums grid

struct TVAlbumsGridView: View {
    @ObservedObject var client: TVBridgeClient
    let token: String

    private let columns = [GridItem(.adaptive(minimum: 280), spacing: 48)]

    var body: some View {
        let albums = tvAlbumGroups(from: client.library)
        ScrollView {
            if albums.isEmpty {
                Text("No albums yet.").font(.title3).foregroundStyle(.secondary).padding(.top, 100)
            } else {
                LazyVGrid(columns: columns, spacing: 48) {
                    ForEach(albums) { album in
                        NavigationLink {
                            TVAlbumDetailView(client: client, token: token, album: album)
                        } label: {
                            albumCard(album)
                        }
                        .buttonStyle(.card)
                    }
                }
                .padding(60)
            }
        }
    }

    private func albumCard(_ album: TVAlbumGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TVAuthImage(url: client.userMusicArtworkURL(for: album.representativeTrack), token: token) {
                ZStack {
                    Color.gray.opacity(0.3)
                    Image(systemName: "square.stack").font(.system(size: 40)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 280, height: 280)
            .clipped()

            Text(album.name).font(.headline).lineLimit(2, reservesSpace: true)
            Text(album.artistName).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(width: 280)
    }
}

// MARK: - Album detail

struct TVAlbumDetailView: View {
    @ObservedObject var client: TVBridgeClient
    let token: String
    let album: TVAlbumGroup

    private var queue: [TVPlayable] {
        album.tracks.compactMap { client.playable(from: $0, token: token) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 30) {
                HStack(spacing: 40) {
                    TVAuthImage(url: client.userMusicArtworkURL(for: album.representativeTrack), token: token) {
                        ZStack {
                            Color.gray.opacity(0.3)
                            Image(systemName: "square.stack").font(.system(size: 60)).foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 260, height: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                    VStack(alignment: .leading, spacing: 10) {
                        Text(album.name).font(.system(size: 40, weight: .bold))
                        Text(album.artistName).font(.title3).foregroundStyle(.secondary)
                        Text("\(album.tracks.count) \(album.tracks.count == 1 ? "song" : "songs")")
                            .font(.title3).foregroundStyle(.secondary)
                        if let first = queue.first {
                            NavigationLink(value: TVPlayContext(queue: queue, startID: first.id)) {
                                Label("Play Album", systemImage: "play.fill")
                            }
                            .buttonStyle(.card)
                            .padding(.top, 10)
                        }
                    }
                }

                VStack(spacing: 0) {
                    ForEach(Array(album.tracks.enumerated()), id: \.element.id) { index, track in
                        NavigationLink(value: TVPlayContext(queue: queue, startID: track.id)) {
                            HStack(spacing: 24) {
                                Text("\(index + 1)")
                                    .font(.title3.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 44, alignment: .trailing)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(track.title.isEmpty ? track.filename : track.title)
                                        .font(.title3)
                                    Text(track.durationText).font(.callout).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.vertical, 14)
                            .padding(.horizontal, 20)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.card)
                    }
                }
            }
            .padding(60)
        }
    }
}

// MARK: - Artists grid

struct TVArtistsGridView: View {
    @ObservedObject var client: TVBridgeClient
    let token: String

    private let columns = [GridItem(.adaptive(minimum: 280), spacing: 48)]

    var body: some View {
        let artists = tvArtistGroups(from: client.library)
        ScrollView {
            if artists.isEmpty {
                Text("No artists yet.").font(.title3).foregroundStyle(.secondary).padding(.top, 100)
            } else {
                LazyVGrid(columns: columns, spacing: 48) {
                    ForEach(artists) { artist in
                        NavigationLink {
                            TVArtistDetailView(client: client, token: token, artist: artist)
                        } label: {
                            artistCard(artist)
                        }
                        .buttonStyle(.card)
                    }
                }
                .padding(60)
            }
        }
    }

    private func artistCard(_ artist: TVArtistGroup) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                Color.gray.opacity(0.3)
                Image(systemName: "music.mic").font(.system(size: 60)).foregroundStyle(.secondary)
            }
            .frame(width: 280, height: 280)
            .clipShape(Circle())

            Text(artist.name).font(.headline).lineLimit(2, reservesSpace: true)
            Text("\(artist.albumCount) \(artist.albumCount == 1 ? "album" : "albums") · \(artist.tracks.count) \(artist.tracks.count == 1 ? "song" : "songs")")
                .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(width: 280)
    }
}

// MARK: - Artist detail (grouped by album, like ArtistDetailView on iOS)

struct TVArtistDetailView: View {
    @ObservedObject var client: TVBridgeClient
    let token: String
    let artist: TVArtistGroup

    private let columns = [GridItem(.adaptive(minimum: 280), spacing: 48)]

    var body: some View {
        let albums = tvAlbumGroups(from: artist.tracks)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text(artist.name)
                    .font(.system(size: 40, weight: .bold))
                    .padding(.horizontal, 60)
                    .padding(.top, 40)

                LazyVGrid(columns: columns, spacing: 48) {
                    ForEach(albums) { album in
                        NavigationLink {
                            TVAlbumDetailView(client: client, token: token, album: album)
                        } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                TVAuthImage(url: client.userMusicArtworkURL(for: album.representativeTrack), token: token) {
                                    ZStack {
                                        Color.gray.opacity(0.3)
                                        Image(systemName: "square.stack").font(.system(size: 40)).foregroundStyle(.secondary)
                                    }
                                }
                                .frame(width: 280, height: 280)
                                .clipped()
                                Text(album.name).font(.headline).lineLimit(2, reservesSpace: true)
                                Text("\(album.tracks.count) \(album.tracks.count == 1 ? "song" : "songs")")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                            .frame(width: 280)
                        }
                        .buttonStyle(.card)
                    }
                }
                .padding(60)
            }
        }
    }
}
