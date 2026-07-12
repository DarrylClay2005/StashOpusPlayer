import Foundation

// MARK: - PlayHistoryStore
//
// Records play counts + last-played timestamps per song, keyed by `Song.id`.
// Exists as its own persisted store (mirroring `DownloadLedgerStore`'s
// shape) rather than fields on `Song` itself, because `LibraryManager`
// re-scans `MPMediaLibrary`/local folders fresh on every launch — anything
// stored only on the in-memory `Song` struct would be wiped every time.
// `Song.id` is stable across rescans on the same device (Apple's
// `MPMediaItem.persistentID` for library items, a Documents-relative-path
// key for imported files — see `DocumentImportService`), so it's a safe key
// for this kind of side-table.

struct PlayHistoryEntry: Codable {
    var playCount: Int = 0
    var lastPlayedAt: Date?
}

@MainActor
final class PlayHistoryStore {
    static let shared = PlayHistoryStore()

    private let key = "playHistory.v1"
    private(set) var entries: [String: PlayHistoryEntry] = [:]

    private init() { load() }

    /// Call when a song starts playing. Increments its play count and
    /// stamps the current time as its last-played date.
    func recordPlay(songID: String) {
        guard !songID.isEmpty else { return }
        var entry = entries[songID] ?? PlayHistoryEntry()
        entry.playCount += 1
        entry.lastPlayedAt = Date()
        entries[songID] = entry
        save()
    }

    func playCount(for songID: String) -> Int {
        entries[songID]?.playCount ?? 0
    }

    func lastPlayedAt(for songID: String) -> Date? {
        entries[songID]?.lastPlayedAt
    }

    /// Merges play-history entries pulled from the account backup (see
    /// `AccountService.pullSync`) — for each song, keeps the higher play
    /// count and the more recent last-played date, so restoring on a new
    /// device (or after a reinstall) never regresses stats this device
    /// already has.
    func mergeFromSync(_ remote: [String: PlayHistoryEntry]) {
        var changed = false
        for (songID, remoteEntry) in remote {
            var local = entries[songID] ?? PlayHistoryEntry()
            if remoteEntry.playCount > local.playCount {
                local.playCount = remoteEntry.playCount
                changed = true
            }
            if let remoteDate = remoteEntry.lastPlayedAt,
               remoteDate > (local.lastPlayedAt ?? .distantPast) {
                local.lastPlayedAt = remoteDate
                changed = true
            }
            entries[songID] = local
        }
        if changed { save() }
    }

    /// Removes history for songs no longer in the library, so the store
    /// doesn't grow forever with entries for deleted/renamed files. Safe to
    /// call periodically (e.g. after a library scan) with the current set
    /// of song IDs.
    func pruneEntries(keeping validIDs: Set<String>) {
        let before = entries.count
        entries = entries.filter { validIDs.contains($0.key) }
        if entries.count != before { save() }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([String: PlayHistoryEntry].self, from: data) {
            entries = decoded
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
