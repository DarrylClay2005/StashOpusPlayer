import Foundation

/// A time-limited safety net for `LibraryManager`'s "permanently remove"
/// deletion path (single or bulk, from the Library view or the Downloads
/// manager). Deleted files are moved into a hidden Documents subfolder
/// instead of removed outright, and automatically purged after 30 days —
/// long enough to recover from an accidental bulk delete, short enough not
/// to silently eat storage forever.
@MainActor
final class RecentlyDeletedService: ObservableObject {

    static weak var shared: RecentlyDeletedService?

    struct Entry: Codable, Identifiable {
        let id: String       // original song id
        var song: Song       // original metadata — its `url` is stale/unused on restore
        var trashFilename: String
        var deletedAt: Date
    }

    @Published private(set) var entries: [Entry] = []

    static let retentionInterval: TimeInterval = 30 * 24 * 60 * 60 // 30 days

    private enum Keys {
        static let entries = "recently_deleted_entries_v1"
    }

    // Dot-prefixed so `performLocalDocumentsScan`'s enumerator (which passes
    // `.skipsHiddenFiles`) never picks trashed files back up as library songs.
    private var trashDirectory: URL? {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let dir = docs.appendingPathComponent(".RecentlyDeleted", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Keys.entries),
           let decoded = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = decoded
        }
        Self.shared = self
    }

    /// Moves `song`'s backing file into the trash folder and records it.
    /// Returns false (leaving the file untouched) if the move failed —
    /// callers should fall back to a hard delete in that case so a song
    /// never gets stuck un-removable.
    @discardableResult
    func trash(song: Song) -> Bool {
        guard let url = song.url, let trashDir = trashDirectory else { return false }
        let trashName = "\(UUID().uuidString).\(url.pathExtension)"
        let destination = trashDir.appendingPathComponent(trashName)
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            try FileManager.default.moveItem(at: url, to: destination)
        } catch {
            appWarn("RecentlyDeletedService.trash: move failed for \(url.path): \(error.localizedDescription)", category: "library")
            return false
        }
        entries.append(Entry(id: song.id, song: song, trashFilename: trashName, deletedAt: Date()))
        persist()
        return true
    }

    /// Restores a trashed song's file into "Imported Music" (its original
    /// folder isn't preserved — just its filename — the point is getting the
    /// track playable again, not exactly where it used to sit) and returns
    /// the restored `Song` (with a fresh `url`) for the caller to re-add to
    /// `importedSongs`. `nil` if the entry is unknown or its file is already
    /// gone (e.g. purged by another device sharing... — never happens today,
    /// but keeps this safe if trash ever becomes synced).
    func restore(entryID: String) -> Song? {
        guard let index = entries.firstIndex(where: { $0.id == entryID }),
              let trashDir = trashDirectory
        else { return nil }
        let entry = entries[index]
        let source = trashDir.appendingPathComponent(entry.trashFilename)
        guard FileManager.default.fileExists(atPath: source.path) else {
            entries.remove(at: index)
            persist()
            return nil
        }
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return nil }
        let importedDir = docs.appendingPathComponent("Imported Music", isDirectory: true)
        try? FileManager.default.createDirectory(at: importedDir, withIntermediateDirectories: true)

        let originalName = entry.song.url?.lastPathComponent ?? entry.trashFilename
        var destination = importedDir.appendingPathComponent(originalName)
        // Avoid clobbering a same-named file re-imported since the delete.
        var suffix = 1
        while FileManager.default.fileExists(atPath: destination.path) {
            let ext = (originalName as NSString).pathExtension
            let base = (originalName as NSString).deletingPathExtension
            destination = importedDir.appendingPathComponent("\(base) (\(suffix)).\(ext)")
            suffix += 1
        }

        do {
            try FileManager.default.moveItem(at: source, to: destination)
        } catch {
            appWarn("RecentlyDeletedService.restore: move failed: \(error.localizedDescription)", category: "library")
            return nil
        }

        entries.remove(at: index)
        persist()

        var restoredSong = entry.song
        restoredSong.url = destination
        return restoredSong
    }

    /// Permanently deletes a trashed entry's file — user-initiated "Delete
    /// Forever", or an automatic purge of anything past the retention window.
    func purge(entryID: String) {
        guard let index = entries.firstIndex(where: { $0.id == entryID }), let trashDir = trashDirectory else { return }
        let entry = entries[index]
        try? FileManager.default.removeItem(at: trashDir.appendingPathComponent(entry.trashFilename))
        entries.remove(at: index)
        persist()
    }

    /// Empties the trash entirely (user-initiated "Delete All").
    func purgeAll() {
        let trashDir = trashDirectory
        for entry in entries {
            if let trashDir { try? FileManager.default.removeItem(at: trashDir.appendingPathComponent(entry.trashFilename)) }
        }
        entries.removeAll()
        persist()
    }

    /// Removes anything older than the retention window. Call once per
    /// launch (see `LumisoundApp`) — a cheap no-op when nothing has expired.
    func purgeExpired() {
        let cutoff = Date().addingTimeInterval(-Self.retentionInterval)
        let expired = entries.filter { $0.deletedAt < cutoff }
        guard !expired.isEmpty else { return }
        for entry in expired { purge(entryID: entry.id) }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(entries) {
            UserDefaults.standard.set(data, forKey: Keys.entries)
        }
    }
}
