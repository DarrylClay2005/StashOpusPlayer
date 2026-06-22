import SwiftUI

// MARK: - TVContentView (search + results grid)

struct TVContentView: View {
    @StateObject private var client = TVBridgeClient.shared
    @State private var query = ""

    private let columns = [GridItem(.adaptive(minimum: 280), spacing: 48)]

    var body: some View {
        NavigationStack {
            ScrollView {
                if client.isSearching {
                    ProgressView().padding(.top, 80)
                } else if let err = client.errorText {
                    Text(err).foregroundStyle(.secondary).padding(.top, 80)
                } else if client.results.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "music.note.tv").font(.system(size: 80)).foregroundStyle(.secondary)
                        Text("Search for music to play on your Apple TV")
                            .font(.title3).foregroundStyle(.secondary)
                    }
                    .padding(.top, 120)
                } else {
                    LazyVGrid(columns: columns, spacing: 48) {
                        ForEach(client.results) { track in
                            NavigationLink(value: track) {
                                TVTrackCard(track: track)
                            }
                            .buttonStyle(.card)
                        }
                    }
                    .padding(60)
                }
            }
            .navigationTitle("Lumisound")
            .navigationDestination(for: TVTrack.self) { track in
                TVPlayerView(track: track, queue: client.results)
            }
            .searchable(text: $query, prompt: "Search YouTube")
            .onSubmit(of: .search) {
                Task { await client.search(query) }
            }
        }
    }
}

// MARK: - TVTrackCard

struct TVTrackCard: View {
    let track: TVTrack

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                if let url = URL(string: track.thumbnailURL), !track.thumbnailURL.isEmpty {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image): image.resizable().scaledToFill()
                        default: placeholder
                        }
                    }
                } else {
                    placeholder
                }
            }
            .frame(width: 280, height: 158)
            .clipped()

            Text(track.title)
                .font(.headline)
                .lineLimit(1)
            Text(track.artist.isEmpty ? "Unknown Artist" : track.artist)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: 280)
    }

    private var placeholder: some View {
        ZStack {
            Color.gray.opacity(0.3)
            Image(systemName: "music.note").font(.system(size: 40)).foregroundStyle(.secondary)
        }
    }
}
