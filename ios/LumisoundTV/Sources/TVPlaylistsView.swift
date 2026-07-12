import SwiftUI

// MARK: - TVPlaylistsView (synced playlists — GET /user/playlists)
//
// A playlist's tracks come from whichever device(s) added them and may point
// at an on-device library item (`local_song_id`) instead of a stream URL —
// tvOS has no local file/media library access at all (see
// TVOS_WATCHOS_FEASIBILITY.md), so those entries are shown but not playable
// here. Entries backed by a Personal Cloud Library upload carry the bridge's
// own `/user/music/stream` URL as `track_url` and play like any other track.

struct TVPlaylistsView: View {
    @ObservedObject var client: TVBridgeClient
    let token: String

    private let columns = [GridItem(.adaptive(minimum: 280), spacing: 48)]

    var body: some View {
        ScrollView {
            if client.isLoadingPlaylists {
                ProgressView("Loading your playlists…").padding(.top, 100)
            } else if let err = client.playlistsError {
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.icloud").font(.system(size: 70)).foregroundStyle(.secondary)
                    Text(err).font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button("Retry") { Task { await client.fetchPlaylists(token: token) } }
                        .frame(width: 260)
                }
                .padding(.top, 100)
            } else if client.playlists.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "music.note.list").font(.system(size: 70)).foregroundStyle(.secondary)
                    Text("No playlists yet.\nCreate one on your iPhone or iPad.")
                        .font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .padding(.top, 120)
            } else {
                LazyVGrid(columns: columns, spacing: 48) {
                    ForEach(client.playlists) { playlist in
                        NavigationLink {
                            TVPlaylistDetailView(client: client, token: token, playlist: playlist)
                        } label: {
                            playlistCard(playlist)
                        }
                        .buttonStyle(.card)
                    }
                }
                .padding(60)
            }
        }
        .task {
            if client.playlists.isEmpty { await client.fetchPlaylists(token: token) }
        }
    }

    private func playlistCard(_ playlist: TVPlaylist) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                Color.gray.opacity(0.3)
                Image(systemName: "music.note.list").font(.system(size: 50)).foregroundStyle(.secondary)
            }
            .frame(width: 280, height: 280)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text(playlist.name).font(.headline).lineLimit(2, reservesSpace: true)
            Text("\(playlist.tracks.count) \(playlist.tracks.count == 1 ? "song" : "songs")")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(width: 280)
    }
}

// MARK: - Playlist detail

struct TVPlaylistDetailView: View {
    @ObservedObject var client: TVBridgeClient
    let token: String
    let playlist: TVPlaylist

    /// Only remotely-playable tracks form the actual playback queue; a track
    /// that isn't playable here is skipped over entirely rather than queued
    /// and immediately failing.
    private var queue: [TVPlayable] {
        playlist.tracks.compactMap { client.playable(from: $0, token: token) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(playlist.name).font(.system(size: 40, weight: .bold))
                    if let description = playlist.description, !description.isEmpty {
                        Text(description).font(.title3).foregroundStyle(.secondary)
                    }
                    if let first = queue.first {
                        NavigationLink(value: TVPlayContext(queue: queue, startID: first.id)) {
                            Label("Play", systemImage: "play.fill")
                        }
                        .buttonStyle(.card)
                        .padding(.top, 10)
                    }
                }

                if playlist.tracks.isEmpty {
                    Text("This playlist is empty.").font(.title3).foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 0) {
                        ForEach(playlist.tracks) { track in
                            row(for: track)
                        }
                    }
                }
            }
            .padding(60)
        }
    }

    @ViewBuilder
    private func row(for track: TVPlaylistTrack) -> some View {
        let content = HStack(spacing: 24) {
            Image(systemName: track.isRemotelyPlayable ? "music.note" : "iphone.slash")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(track.title).font(.title3)
                Text(track.artist?.isEmpty == false ? track.artist! : "Unknown Artist")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if !track.isRemotelyPlayable {
                Text("Not available on Apple TV")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 20)
        .contentShape(Rectangle())

        if track.isRemotelyPlayable, let playable = client.playable(from: track, token: token) {
            NavigationLink(value: TVPlayContext(queue: queue, startID: playable.id)) {
                content
            }
            .buttonStyle(.card)
        } else {
            content.opacity(0.5)
        }
    }
}
