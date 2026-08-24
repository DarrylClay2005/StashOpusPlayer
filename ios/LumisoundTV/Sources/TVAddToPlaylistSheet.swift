import SwiftUI

// MARK: - TVAddToPlaylistSheet
//
// Shared "Add to Playlist" picker, reachable via context menu from library/
// album/artist/search cards. Takes the track already reduced to a
// `TVSyncTrackBody` (the shape the bridge actually stores) rather than the
// original model, so one sheet works for both cloud-library and search-result
// tracks without a source-specific branch here.

struct TVAddToPlaylistSheet: View {
    @ObservedObject var client: TVBridgeClient
    let token: String
    let track: TVSyncTrackBody
    @Environment(\.dismiss) private var dismiss

    @State private var isAdding = false
    @State private var newPlaylistName = ""
    @State private var showNewPlaylistField = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if showNewPlaylistField {
                        HStack {
                            TextField("Playlist name", text: $newPlaylistName)
                            Button("Create") { Task { await createAndAdd() } }
                                .disabled(newPlaylistName.trimmingCharacters(in: .whitespaces).isEmpty || isAdding)
                        }
                    } else {
                        Button {
                            showNewPlaylistField = true
                        } label: {
                            Label("New Playlist", systemImage: "plus")
                        }
                    }
                }

                if !client.playlists.isEmpty {
                    Section("Your Playlists") {
                        ForEach(client.playlists) { playlist in
                            Button {
                                Task { await add(to: playlist.id) }
                            } label: {
                                HStack {
                                    Text(playlist.name)
                                    Spacer()
                                    Text("\(playlist.tracks.count)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .disabled(isAdding)
                        }
                    }
                }

                if let err = client.playlistMutationError {
                    Text(err).foregroundStyle(.red)
                }
            }
            .navigationTitle("Add “\(track.title)”")
            .task {
                if client.playlists.isEmpty { await client.fetchPlaylists(token: token) }
            }
        }
    }

    private func add(to playlistID: String) async {
        isAdding = true
        defer { isAdding = false }
        if await client.addTrack(track, toPlaylist: playlistID, token: token) {
            dismiss()
        }
    }

    private func createAndAdd() async {
        isAdding = true
        defer { isAdding = false }
        let name = newPlaylistName.trimmingCharacters(in: .whitespaces)
        guard await client.createPlaylist(name: name, token: token),
              let created = client.playlists.first(where: { $0.name == name })
        else { return }
        if await client.addTrack(track, toPlaylist: created.id, token: token) {
            dismiss()
        }
    }
}
