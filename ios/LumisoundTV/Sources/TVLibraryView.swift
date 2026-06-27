import SwiftUI

// MARK: - TVLibraryView (per-user cloud library)

struct TVLibraryView: View {
    @ObservedObject var client: TVBridgeClient
    let token: String

    private let columns = [GridItem(.adaptive(minimum: 280), spacing: 48)]

    /// The whole library mapped to playables — used as the queue when a track is picked.
    private var queue: [TVPlayable] {
        client.library.compactMap { client.playable(from: $0, token: token) }
    }

    var body: some View {
        ScrollView {
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
        .task {
            if client.library.isEmpty { await client.fetchLibrary(token: token) }
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
                .font(.headline).lineLimit(1)
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
