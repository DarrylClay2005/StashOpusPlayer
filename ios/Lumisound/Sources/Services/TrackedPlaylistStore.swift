import Foundation
import Combine

// MARK: - TrackedPlaylist

/// A YouTube/SoundCloud playlist the user is tracking for on-demand downloads.
/// Distinct from `ArtistSubscription` (channel following): tracked playlists are
/// stored locally on the device and resolved to their tracks on demand via the
/// bridge's `/api/resolve`, so each item can be downloaded into the local
/// library (with duplicate detection) without a backend schema change.
struct TrackedPlaylist: Identifiable, Codable, Equatable {
    let id: String          // stable UUID string
    var url: String
    var name: String
    var thumbnailURL: String
    var dateAdded: Date
    /// Track count seen on the last successful resolve — lets the list show a
    /// hint ("32 tracks") without re-resolving every appearance.
    var lastTrackCount: Int

    init(id: String = UUID().uuidString,
         url: String,
         name: String,
         thumbnailURL: String = "",
         dateAdded: Date = Date(),
         lastTrackCount: Int = 0) {
        self.id = id
        self.url = url
        self.name = name
        self.thumbnailURL = thumbnailURL
        self.dateAdded = dateAdded
        self.lastTrackCount = lastTrackCount
    }
}

// MARK: - TrackedPlaylistStore

/// Local, on-device persistence for tracked playlists (UserDefaults-backed).
/// Kept separate from the server-side channel subscriptions so it needs no DB
/// migration; the trade-off is that tracked playlists don't sync across devices.
@MainActor
final class TrackedPlaylistStore: ObservableObject {
    static let shared = TrackedPlaylistStore()

    @Published private(set) var playlists: [TrackedPlaylist] = []

    private let key = "trackedPlaylists.v1"

    init() { load() }

    // MARK: Mutations

    /// Adds a playlist if its URL isn't already tracked (case-insensitive,
    /// trimmed). Returns false if it was a duplicate or the URL was empty.
    @discardableResult
    func add(url: String, name: String, thumbnailURL: String = "") -> Bool {
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.isEmpty else { return false }
        let normalized = trimmedURL.lowercased()
        guard !playlists.contains(where: { $0.url.lowercased() == normalized }) else { return false }

        let displayName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let pl = TrackedPlaylist(
            url: trimmedURL,
            name: displayName.isEmpty ? defaultName(for: trimmedURL) : displayName,
            thumbnailURL: thumbnailURL
        )
        playlists.append(pl)
        save()
        return true
    }

    func remove(id: String) {
        playlists.removeAll { $0.id == id }
        save()
    }

    /// Updates the cached track count (and optionally the thumbnail/name) after a
    /// successful resolve.
    func updateMetadata(id: String, trackCount: Int? = nil, thumbnailURL: String? = nil, name: String? = nil) {
        guard let idx = playlists.firstIndex(where: { $0.id == id }) else { return }
        if let trackCount { playlists[idx].lastTrackCount = trackCount }
        if let thumbnailURL, !thumbnailURL.isEmpty { playlists[idx].thumbnailURL = thumbnailURL }
        if let name, !name.isEmpty { playlists[idx].name = name }
        save()
    }

    // MARK: Helpers

    /// A readable fallback name derived from the playlist URL's `list=` id.
    private func defaultName(for url: String) -> String {
        if let comps = URLComponents(string: url),
           let list = comps.queryItems?.first(where: { $0.name == "list" })?.value, !list.isEmpty {
            return "Playlist \(list.prefix(8))"
        }
        return "Tracked Playlist"
    }

    // MARK: Persistence

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key) else { return }
        if let decoded = try? JSONDecoder().decode([TrackedPlaylist].self, from: data) {
            playlists = decoded
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(playlists) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
