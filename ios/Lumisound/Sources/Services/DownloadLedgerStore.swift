import Foundation

// MARK: - DownloadLedgerStore
//
// Records the source id (LUMISOUND_ID form, "<source>:<id>") of every track the
// app downloads → the resulting filename, so duplicate detection never depends
// on reading the id tag back out of the file afterwards.
//
// Why this exists: m4a (the default download format) was silently dropping the
// LUMISOUND_ID metadata tag, so a re-downloaded playlist couldn't recognise the
// tracks already on disk and re-fetched them. The bridge now embeds the id
// correctly for new downloads, but this ledger is the authoritative, format- and
// AVFoundation-independent record of "we have this source track" for everything
// the app downloads. Entries are always validated against the files actually
// present (callers pass the current set of library filenames), so deleting a
// file naturally re-enables downloading it again.

@MainActor
final class DownloadLedgerStore {
    static let shared = DownloadLedgerStore()

    private let key = "downloadLedger.v1"
    private(set) var map: [String: String] = [:]   // sourceTrackID -> filename

    private init() { load() }

    /// Records that `sourceTrackID` is present on disk as `filename`.
    func record(sourceTrackID: String, filename: String) {
        guard !sourceTrackID.isEmpty, !filename.isEmpty else { return }
        if map[sourceTrackID] == filename { return }
        map[sourceTrackID] = filename
        save()
    }

    /// The filename recorded for a source id, if any.
    func filename(for sourceTrackID: String) -> String? { map[sourceTrackID] }

    /// True if this source id was downloaded and its file is still present
    /// (its recorded filename appears in `presentFilenames`).
    func isPresent(_ sourceTrackID: String, presentFilenames: Set<String>) -> Bool {
        guard let fn = map[sourceTrackID] else { return false }
        return presentFilenames.contains(fn)
    }

    /// All recorded source ids whose files are still present on disk.
    func presentSourceIDs(presentFilenames: Set<String>) -> [String] {
        map.compactMap { presentFilenames.contains($0.value) ? $0.key : nil }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            map = decoded
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(map) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
