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
        guard let data = try? encoder.encode(backup) else { throw LibraryBackupError.encodingFailed }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmm"
        let filename = "Lumisound_Backup_\(formatter.string(from: backup.exportedAt)).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Decodes a `LibraryBackup` from a file the user picked via the file
    /// importer. Handles the security-scoped resource dance required for
    /// files outside the app's own sandbox (e.g. picked from iCloud Drive).
    static func decodeBackup(from url: URL) throws -> LibraryBackup {
        let didStartAccessing = url.startAccessingSecurityScopedResource()
        defer { if didStartAccessing { url.stopAccessingSecurityScopedResource() } }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let backup = try? decoder.decode(LibraryBackup.self, from: data) else {
            throw LibraryBackupError.decodingFailed
        }
        return backup
    }
}
