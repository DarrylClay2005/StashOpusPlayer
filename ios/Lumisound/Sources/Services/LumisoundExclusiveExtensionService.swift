import Foundation

// MARK: - LumisoundExclusiveExtensionService
//
// Renames an already-downloaded, already-vault-tagged track's file to carry
// a Lumisound-exclusive extension on disk — the last, most visible layer of
// the "this track belongs to Lumisound" pipeline started by
// LumisoundTrackVault/LumisoundTrackTagger (the encrypted xattr metadata).
//
// The marker is appended as an OUTER extension rather than replacing the
// real one (e.g. "Song.m4a" -> "Song.m4a.lms"), not stripped/renamed away:
//   - `url.pathExtension` is genuinely ".lms" — no other app, share sheet,
//     or file browser has any type association for it, which is the whole
//     point ("exclusive").
//   - The REAL container format is still recoverable in O(1), no file I/O,
//     by unwrapping one more path-extension level (`effectiveExtension`
//     below). Every place in this codebase that branches on file extension
//     to make a format-dependent decision (playback routing for opus/webm/
//     ogg, the lossless/format-tag badges, Vorbis-comment parsing, video
//     frame artwork extraction, the corruption scanner's/library scan's
//     "is this an audio file" gate) was updated this session to call
//     `effectiveExtension(for:)` instead of raw `pathExtension` — see git
//     history for the full list. A single flat rename (replacing the real
//     extension outright) would have silently broken every one of those,
//     since they'd have no way left to recover the real container type
//     without decrypting the vault payload on every check — expensive and
//     wrong for hot UI paths like list-row rendering.
enum LumisoundExclusiveExtensionService {
    static let marker = "lms"

    /// The extension callers should reason about for any FORMAT decision —
    /// unwraps the Lumisound marker to recover the real container extension
    /// underneath it; returns the plain extension unchanged for anything not
    /// yet converted.
    static func effectiveExtension(for url: URL) -> String {
        let outer = url.pathExtension.lowercased()
        guard outer == marker else { return outer }
        return url.deletingPathExtension().pathExtension.lowercased()
    }

    static func isConverted(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == marker
    }

    /// Renames `fileURL` in place to append the marker extension. Pure
    /// filesystem rename — never touches the file's bytes, so the real
    /// audio container/codec is completely unchanged, and extended
    /// attributes (the LumisoundTrackVault tag) survive intact since
    /// they're attached to the inode, not the path, and this never crosses
    /// a volume boundary. Returns the new URL, or `nil` if `fileURL` is
    /// already converted, the destination somehow already exists, or the
    /// rename fails (logged, never thrown — this is always called from a
    /// best-effort background pass).
    static func convert(fileURL: URL) -> URL? {
        guard !isConverted(fileURL) else { return nil }
        let newURL = fileURL.appendingPathExtension(marker)
        let fm = FileManager.default
        guard !fm.fileExists(atPath: newURL.path) else { return nil }
        do {
            try fm.moveItem(at: fileURL, to: newURL)
            return newURL
        } catch {
            appWarn("LumisoundExclusiveExtensionService: rename failed for \(fileURL.lastPathComponent): \(error.localizedDescription)", category: "background")
            return nil
        }
    }
}
