import SwiftUI

// MARK: - TVLibraryView (per-user cloud library)

struct TVLibraryView: View {
    @ObservedObject var client: TVBridgeClient
    let token: String

    private enum Mode: String, CaseIterable, Identifiable {
        case songs = "Songs"
        case albums = "Albums"
        case artists = "Artists"
        var id: String { rawValue }
    }
    @State private var mode: Mode = .songs

    private let columns = [GridItem(.adaptive(minimum: 280), spacing: 48)]

    /// The whole library mapped to playables — used as the queue when a track is picked.
    private var queue: [TVPlayable] {
        client.library.compactMap { client.playable(from: $0, token: token) }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !client.isLoadingLibrary && client.libraryError == nil && !client.library.isEmpty {
                Picker("View", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 700)
                .padding(.top, 40)
                .padding(.bottom, 10)
            }

            Group {
                if client.isLoadingLibrary {
                    ProgressView("Loading your library…").padding(.top, 100)
                } else if let err = client.libraryError {
                    VStack(spacing: 20) {
                        Image(systemName: "exclamationmark.icloud").font(.system(size: 70)).foregroundStyle(.secondary)
                        Text(err).font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Button("Retry") { Task { await client.fetchLibrary(token: token) } }
                            .frame(width: 260)
                    }
                    .padding(.top, 100)
                } else if client.library.isEmpty {
                    message("Your cloud library is empty.\nAdd music from the iPhone app.",
                            systemImage: "music.note.list")
                } else {
                    switch mode {
                    case .songs: songsGrid
                    case .albums: TVAlbumsGridView(client: client, token: token)
                    case .artists: TVArtistsGridView(client: client, token: token)
                    }
                }
            }
        }
        .task {
            if client.library.isEmpty { await client.fetchLibrary(token: token) }
        }
    }

    private var songsGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 48) {
                ForEach(client.library) { track in
                    NavigationLink(value: TVPlayContext(queue: queue, startID: track.id)) {
                        libraryCard(track)
                    }
                    .buttonStyle(.card)
                }
            }
            .padding(60)
        }
    }

    private func libraryCard(_ track: UserMusicTrack) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            TVAuthImage(url: client.userMusicArtworkURL(for: track), token: token) {
                ZStack {
                    Color.gray.opacity(0.3)
                    Image(systemName: "music.note").font(.system(size: 40)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 280, height: 280)
            .clipped()

            Text(track.title.isEmpty ? track.filename : track.title)
                .font(.headline).lineLimit(2, reservesSpace: true)
            Text(track.artist.isEmpty ? "Unknown Artist" : track.artist)
                .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(width: 280)
    }

    private func message(_ text: String, systemImage: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage).font(.system(size: 70)).foregroundStyle(.secondary)
            Text(text).font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(.top, 120)
    }
}
