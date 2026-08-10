import Foundation

/// A 30-day safety net for deleted playlists — same retention window and
/// general shape as `RecentlyDeletedService` (downloaded tracks), but much
/// simpler: a `Playlist` is just metadata (name, song ID references), not
/// a file on disk, so "trashing" one is just keeping a copy of the struct
/// around for a while rather than moving anything. `LibraryManager
/// .deletePlaylist` trashes here before removing from `playlists`.
struct DeletedPlaylistEntry: Codable, Identifiable {
    let id: UUID
    let playlist: Playlist
    let deletedAt: Date
}

@MainActor
final class DeletedPlaylistsStore: ObservableObject {
    static let shared = DeletedPlaylistsStore()

    private static let retentionDays: TimeInterval = 30
    private let key = "deletedPlaylists.v1"

    @Published private(set) var entries: [DeletedPlaylistEntry] = []

    private init() {
        load()
        purgeExpired()
    }

    func trash(_ playlist: Playlist) {
        entries.insert(DeletedPlaylistEntry(id: UUID(), playlist: playlist, deletedAt: Date()), at: 0)
        save()
    }

    /// Removes and returns the entry's playlist so the caller can re-add
    /// it to the live library — this store only ever holds the trashed
    /// copy, it doesn't know how to reinsert it itself.
    func restore(entryID: DeletedPlaylistEntry.ID) -> Playlist? {
        guard let index = entries.firstIndex(where: { $0.id == entryID }) else { return nil }
        let entry = entries.remove(at: index)
        save()
        return entry.playlist
    }

    func purge(entryID: DeletedPlaylistEntry.ID) {
        entries.removeAll { $0.id == entryID }
        save()
    }

    func purgeAll() {
        entries.removeAll()
        save()
    }

    func purgeExpired() {
        let cutoff = Date().addingTimeInterval(-Self.retentionDays * 86400)
        let before = entries.count
        entries.removeAll { $0.deletedAt < cutoff }
        if entries.count != before { save() }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([DeletedPlaylistEntry].self, from: data) {
            entries = decoded
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
