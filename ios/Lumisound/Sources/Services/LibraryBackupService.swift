import Foundation

enum LibraryBackupError: Error {
    case encodingFailed
    case decodingFailed
}

/// Writes/reads `LibraryBackup` JSON files for the local export/import
/// backup feature. Purely file I/O — `LibraryManager` owns the actual
/// merge logic in `importBackup(_:)`.
enum LibraryBackupService {

    /// Encodes `backup` to a timestamped JSON file in the temp directory and
    /// returns its URL, ready to hand to a share sheet. Caller is
    /// responsible for cleaning up the temp file after sharing completes if
    /// desired — the OS temp directory is cleared periodically regardless.
    static func exportBackup(_ backup: LibraryBackup) throws -> URL {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(backup) else {
            appError("exportBackup: JSON encoding failed for \(backup.playlists.count) playlist(s)", category: "library")
            RemoteLogger.logError(category: "backup", event: "export_failed", message: "encoding failed")
            throw LibraryBackupError.encodingFailed
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmm"
        let filename = "Lumisound_Backup_\(formatter.string(from: backup.exportedAt)).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            appError("exportBackup: write failed for \(filename): \(error.localizedDescription)", category: "library")
            RemoteLogger.logError(category: "backup", event: "export_failed", message: error.localizedDescription)
            throw error
        }
        appLog("exportBackup: wrote \(filename) — \(backup.playlists.count) playlist(s), \(backup.favoriteSongIDs.count) favorite(s)", category: "library")
        RemoteLogger.log(category: "backup", event: "export_completed",
                          detail: ["playlists": backup.playlists.count, "favorites": backup.favoriteSongIDs.count])
        return url
    }

    /// Decodes a `LibraryBackup` from a file the user picked via the file
    /// importer. Handles the security-scoped resource dance required for
    /// files outside the app's own sandbox (e.g. picked from iCloud Drive).
    static func decodeBackup(from url: URL) throws -> LibraryBackup {
        appLog("decodeBackup: reading \(url.lastPathComponent)", category: "library")
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer { if didStartAccessing { url.stopAccessingSecurityScopedResource() } }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            appError("decodeBackup: couldn't read \(url.lastPathComponent): \(error.localizedDescription)", category: "library")
            RemoteLogger.logError(category: "backup", event: "import_failed", message: error.localizedDescription)
            throw error
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let backup = try? decoder.decode(LibraryBackup.self, from: data) else {
            appError("decodeBackup: JSON decoding failed for \(url.lastPathComponent) — not a Lumisound backup or corrupt", category: "library")
            RemoteLogger.logError(category: "backup", event: "import_failed", message: "decoding failed")
            throw LibraryBackupError.decodingFailed
        }
        appLog("decodeBackup: parsed \(url.lastPathComponent) — \(backup.playlists.count) playlist(s), exported \(backup.exportedAt) by v\(backup.appVersion)", category: "library")
        RemoteLogger.log(category: "backup", event: "import_decoded",
                          detail: ["playlists": backup.playlists.count, "favorites": backup.favoriteSongIDs.count])
        return backup
    }
}
