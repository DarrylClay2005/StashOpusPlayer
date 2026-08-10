import Foundation

/// A short voice-note recording attached to a specific `TrackBookmark` (by
/// id) — e.g. narrating why a moment matters ("this is the sample I want
/// to use") rather than just a text label. Deliberately a separate store
/// from `BookmarkStore`/`TrackBookmark` rather than a field added to that
/// struct: `TrackBookmark` flows through account sync (see
/// `BookmarkStore.mergeFromSync`), and an audio file has no sync story
/// here the way the lightweight JSON everything else in that path carries
/// does — so a voice memo is local-only, tied to the bookmark's id but
/// otherwise invisible to sync. A bookmark's voice memo won't be present
/// on another signed-in device even though the bookmark itself is.
@MainActor
final class VoiceMemoStore {
    static let shared = VoiceMemoStore()

    private let directory: URL

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        directory = support.appendingPathComponent("VoiceMemos", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private func fileURL(for bookmarkID: String) -> URL {
        directory.appendingPathComponent("\(bookmarkID).m4a")
    }

    func hasMemo(for bookmarkID: String) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: bookmarkID).path)
    }

    func memoURL(for bookmarkID: String) -> URL? {
        hasMemo(for: bookmarkID) ? fileURL(for: bookmarkID) : nil
    }

    /// Moves a just-recorded clip (from a temp recording URL) into
    /// permanent storage for `bookmarkID`, replacing any existing memo.
    func saveMemo(from tempURL: URL, for bookmarkID: String) throws {
        let destination = fileURL(for: bookmarkID)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)
    }

    func deleteMemo(for bookmarkID: String) {
        try? FileManager.default.removeItem(at: fileURL(for: bookmarkID))
    }
}
