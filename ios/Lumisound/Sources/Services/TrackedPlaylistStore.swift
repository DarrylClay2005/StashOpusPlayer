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
    /// When true, the app auto-downloads newly-added tracks from this playlist in
    /// the background. Optional so older persisted entries decode (missing = off).
    var autoDownload: Bool?
    /// Last time the auto-downloader checked this playlist (throttles checks).
    var lastAutoCheck: Date?

    var isAutoDownload: Bool { autoDownload ?? false }

    init(id: String = UUID().uuidString,
         url: String,
         name: String,
         thumbnailURL: String = "",
         dateAdded: Date = Date(),
         lastTrackCount: Int = 0,
         autoDownload: Bool? = nil,
         lastAutoCheck: Date? = nil) {
        self.id = id
        self.url = url
        self.name = name
        self.thumbnailURL = thumbnailURL
        self.dateAdded = dateAdded
        self.lastTrackCount = lastTrackCount
        self.autoDownload = autoDownload
        self.lastAutoCheck = lastAutoCheck
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

    func setAutoDownload(id: String, _ on: Bool) {
        guard let idx = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[idx].autoDownload = on
        save()
    }

    private func markAutoChecked(id: String) {
        guard let idx = playlists.firstIndex(where: { $0.id == id }) else { return }
        playlists[idx].lastAutoCheck = Date()
        save()
    }

    // MARK: Auto-download

    /// For each auto-download playlist not checked in the last `minInterval`,
    /// resolves it and downloads any tracks the user doesn't already have
    /// (deduped via `LibraryManager.hasLocalCopy`). Safe to call on launch /
    /// foreground; throttled so it doesn't re-resolve constantly.
    func runAutoDownloads(streaming: StreamingService,
                          library: LibraryManager,
                          minInterval: TimeInterval = 6 * 3600) async {
        let now = Date()
        let due = playlists.filter { pl in
            guard pl.isAutoDownload else { return false }
            if let last = pl.lastAutoCheck { return now.timeIntervalSince(last) >= minInterval }
            return true
        }
        guard !due.isEmpty else { return }

        for pl in due {
            await library.scanLocalDocumentsAsync()
            let tracks = await streaming.fetchPlaylistTracks(url: pl.url, existingSongs: [])
            // Build the fast-path lookups ONCE before filtering — calling
            // hasLocalCopy(of:) per track (O(library) each) over a big
            // playlist was an O(tracks × library) main-thread hang long
            // enough to trip the watchdog. Same fix as
            // TrackedPlaylistDetailView.recomputeLocalCopies.
            let localSourceIDs = library.localSourceIDs()
            let identityIndex = library.importedIdentityIndex()
            let toGet = tracks.filter { !library.hasLocalCopy(of: $0, localSourceIDs: localSourceIDs, identityIndex: identityIndex) }
            var got = 0
            var blocked = 0
            for track in toGet {
                do {
                    _ = try await streaming.downloadToLibrary(track: track, existingSongs: library.allSongs)
                    got += 1
                } catch StreamingError.serverDetail {
                    // e.g. an auto-generated Topic-channel track blocked from
                    // extraction — tallied so the summary toast can explain why
                    // some tracks were skipped instead of silently dropping them.
                    blocked += 1
                } catch {
                    // Other failures (network, timeout, etc.) stay silent here —
                    // this is a background check, and the next scheduled run
                    // will simply retry them.
                }
            }
            if got > 0 {
                library.scanLocalDocuments()
                ToastCenter.shared.show("Auto-downloaded \(got) new track\(got == 1 ? "" : "s") from \"\(pl.name)\"",
                                        category: .download)
            }
            if blocked > 0 {
                ToastCenter.shared.show(
                    "\(blocked) track\(blocked == 1 ? "" : "s") from \"\(pl.name)\" blocked by YouTube (auto-generated \"Topic\" channel)",
                    category: .warning
                )
            }
            markAutoChecked(id: pl.id)
            if !tracks.isEmpty { updateMetadata(id: pl.id, trackCount: tracks.count) }
        }
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
