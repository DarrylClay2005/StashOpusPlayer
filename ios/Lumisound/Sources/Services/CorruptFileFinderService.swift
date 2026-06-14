import AVFoundation
import Foundation

// MARK: - CorruptFileFinderService

@MainActor
final class CorruptFileFinderService: ObservableObject {

    // MARK: Singleton

    static let shared = CorruptFileFinderService()
    private init() {}

    // MARK: Published State

    @Published private(set) var isScanning = false
    @Published private(set) var corruptFiles: [CorruptFileEntry] = []
    @Published private(set) var lastScanDate: Date? = {
        let ts = UserDefaults.standard.double(forKey: "corruptFinder_lastScanTimestamp")
        return ts > 0 ? Date(timeIntervalSince1970: ts) : nil
    }()

    // MARK: - Scan

    /// Scans all audio files inside `directory` for corruption.
    /// Tries to open each file with AVAudioFile; also checks minimum file size
    /// (1 KB) and that the file extension is a recognised audio type.
    func runScan(in directory: URL) async {
        guard !isScanning else { return }
        isScanning = true
        corruptFiles = []

        let found = await Task.detached(priority: .utility) { [directory] in
            CorruptFileFinderService.scanDirectory(directory)
        }.value

        corruptFiles = found
        let now = Date()
        lastScanDate = now
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: "corruptFinder_lastScanTimestamp")
        isScanning = false
    }

    // MARK: - Delete

    /// Deletes every file currently in `corruptFiles`. Files that cannot be
    /// deleted are silently skipped; the list is cleared on completion.
    func deleteCorruptFiles() async {
        let toDelete = corruptFiles
        await Task.detached(priority: .utility) {
            for entry in toDelete {
                try? FileManager.default.removeItem(at: entry.url)
            }
        }.value
        corruptFiles = []
        let fileWord = toDelete.count == 1 ? "file" : "files"
        ToastCenter.shared.show("Deleted \(toDelete.count) corrupt \(fileWord)", category: .info, icon: "trash")
    }

    // MARK: - Daily Auto-Check

    /// Call once on app launch. Runs a scan of the app's Documents directory
    /// if 24 hours or more have elapsed since the last scan.
    func runDailyCheckIfNeeded() {
        let lastTS = UserDefaults.standard.double(forKey: "corruptFinder_lastScanTimestamp")
        let lastDate = lastTS > 0 ? Date(timeIntervalSince1970: lastTS) : .distantPast
        let secondsPerDay: TimeInterval = 86_400
        guard Date().timeIntervalSince(lastDate) >= secondsPerDay else { return }

        guard let docs = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else { return }

        Task { await runScan(in: docs) }
    }

    // MARK: - Single-File Integrity Check

    /// Returns `true` if `url` points to a regular, non-empty audio file that
    /// `AVAudioFile` can open. Used right after downloads to catch corrupt or
    /// truncated files (e.g. dropped connections, bad yt-dlp output) before
    /// they're adopted into the library — same checks as `scanDirectory`, but
    /// for a single freshly-downloaded file so callers can retry immediately.
    nonisolated static func isValidAudioFile(at url: URL) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64,
              size >= 1_024 else { return false }

        do {
            _ = try AVAudioFile(forReading: url)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Private Scan Worker (nonisolated, runs off main actor)

    private static let audioExtensions: Set<String> = [
        "mp3", "m4a", "aac", "flac", "wav", "aiff", "aif",
        "ogg", "opus", "wma", "caf", "alac", "mp4", "webm"
    ]

    nonisolated static func scanDirectory(_ directory: URL) -> [CorruptFileEntry] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var results: [CorruptFileEntry] = []

        for case let fileURL as URL in enumerator {
            let ext = fileURL.pathExtension.lowercased()
            guard audioExtensions.contains(ext) else { continue }

            // Check it is a regular file
            guard let attrs = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
                  attrs.isRegularFile == true else { continue }

            let fileSize = attrs.fileSize ?? 0

            if fileSize < 1_024 {
                results.append(CorruptFileEntry(
                    url: fileURL,
                    fileSizeBytes: Int64(fileSize),
                    reason: .tooSmall
                ))
                continue
            }

            // Try opening with AVAudioFile on a throw-catching path
            do {
                _ = try AVAudioFile(forReading: fileURL)
            } catch {
                results.append(CorruptFileEntry(
                    url: fileURL,
                    fileSizeBytes: Int64(fileSize),
                    reason: .unreadable(detail: error.localizedDescription)
                ))
            }
        }

        return results
    }
}

// MARK: - CorruptFileEntry

struct CorruptFileEntry: Identifiable {
    let id = UUID()
    let url: URL
    let fileSizeBytes: Int64
    let reason: CorruptionReason

    var fileName: String { url.lastPathComponent }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file)
    }

    var reasonText: String {
        switch reason {
        case .tooSmall:
            return "File is smaller than 1 KB — likely an incomplete download."
        case .unreadable(let detail):
            return "Could not open with AVAudioFile: \(detail)"
        }
    }
}

// MARK: - CorruptionReason

enum CorruptionReason {
    case tooSmall
    case unreadable(detail: String)
}
