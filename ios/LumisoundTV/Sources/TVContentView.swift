import SwiftUI

// MARK: - Root

struct TVContentView: View {
    @StateObject private var account = TVAccount.shared
    @StateObject private var client = TVBridgeClient.shared

    var body: some View {
        if account.isLoggedIn, let token = account.token {
            NavigationStack {
                TabView {
                    TVLibraryView(client: client, token: token)
                        .tabItem { Label("My Library", systemImage: "music.note.house") }
                    TVSearchView(client: client)
                        .tabItem { Label("Search", systemImage: "magnifyingglass") }
                    TVAccountView(account: account)
                        .tabItem { Label(account.user?.name ?? "Account", systemImage: "person.crop.circle") }
                }
                .navigationDestination(for: TVPlayContext.self) { ctx in
                    TVPlayerView(context: ctx)
                }
            }
        } else {
            TVLoginView(account: account)
        }
    }
}

// MARK: - Search tab

struct TVSearchView: View {
    @ObservedObject var client: TVBridgeClient
    @State private var query = ""

    private let columns = [GridItem(.adaptive(minimum: 280), spacing: 48)]
    private var queue: [TVPlayable] { client.results.compactMap { client.playable(from: $0) } }

    var body: some View {
        ScrollView {
            if client.isSearching {
                ProgressView("Searching… this can take a moment")
                    .padding(.top, 100)
            } else if let err = client.searchError {
                Text(err).foregroundStyle(.secondary).padding(.top, 80)
            } else if client.results.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "magnifyingglass").font(.system(size: 70)).foregroundStyle(.secondary)
                    Text("Search YouTube to play on your Apple TV")
                        .font(.title3).foregroundStyle(.secondary)
                }
                .padding(.top, 120)
            } else {
                LazyVGrid(columns: columns, spacing: 48) {
                    ForEach(client.results) { track in
                        NavigationLink(value: TVPlayContext(queue: queue, startID: track.id)) {
                            TVTrackCard(track: track)
                        }
                        .buttonStyle(.card)
                    }
                }
                .padding(60)
            }
        }
        .searchable(text: $query, prompt: "Search YouTube")
        .onSubmit(of: .search) { Task { await client.search(query) } }
        // tvOS search keyboards don't reliably fire `.onSubmit(of: .search)`, so
        // also search as you type (debounced) — otherwise typing appears to do
        // nothing.
        .onChange(of: query) { newValue in
            let v = newValue
            Task {
                try? await Task.sleep(nanoseconds: 600_000_000)
                guard query == v else { return }  // user kept typing
                if v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    client.results = []
                    client.searchError = nil
                } else {
                    await client.search(v)
                }
            }
        }
    }
}

struct TVTrackCard: View {
    let track: TVTrack

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TVAuthImage(url: URL(string: track.thumbnailURL), token: nil) {
                ZStack {
                    Color.gray.opacity(0.3)
                    Image(systemName: "music.note").font(.system(size: 40)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 280, height: 158)
            .clipped()

            Text(track.title).font(.headline).lineLimit(1)
            Text(track.artist.isEmpty ? "Unknown Artist" : track.artist)
                .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(width: 280)
    }
}

// MARK: - Account tab

struct TVAccountView: View {
    @ObservedObject var account: TVAccount

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "person.crop.circle.fill").font(.system(size: 90)).foregroundStyle(.tint)
            Text(account.user?.name ?? "Signed in").font(.title)
            Button("Sign Out", role: .destructive) { account.logout() }
                .frame(width: 320)
        }
        .padding(80)
    }
}
