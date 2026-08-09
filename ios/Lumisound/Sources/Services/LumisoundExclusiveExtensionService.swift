import AVFoundation
import Foundation

// MARK: - LumisoundExclusiveExtensionService
//
// Finishes the "this track belongs to Lumisound" pipeline started by
// LumisoundTrackVault/LumisoundTrackTagger (the encrypted xattr metadata):
// actually re-encodes an already-downloaded, already-vault-tagged track's
// audio into a fresh AAC .m4a container (real bytes rewritten via
// `AudioEncoderService.convertPermanently`, not merely a file rename) and
// appends a Lumisound-exclusive marker extension on top of that.
//
// The marker is appended as an OUTER extension on top of the real one
// (e.g. "Song.opus" -> "Song.m4a.lms"), not stripped/renamed away:
//   - `url.pathExtension` is genuinely ".lms" — no other app, share sheet,
//     or file browser has any type association for it, which is the whole
//     point ("exclusive").
//   - The REAL (post-re-encode) container format is still recoverable in
//     O(1), no file I/O, by unwrapping one more path-extension level
//     (`effectiveExtension` below). Every place in this codebase that
//     branches on file extension to make a format-dependent decision
//     (playback routing for opus/webm/ogg, the lossless/format-tag badges,
//     Vorbis-comment parsing, video frame artwork extraction, the
//     corruption scanner's/library scan's "is this an audio file" gate)
//     calls `effectiveExtension(for:)` instead of raw `pathExtension` — see
//     git history for the full list.
//
// Re-encoding (rather than a pure rename) is the point of this pass, not
// just the marker: every converted track ends up as AAC .m4a, which plays
// back via AVAudioFile's native Tier 1 path in `AudioEncoderService`
// instead of needing the opus/webm compatibility fallback on every play —
// and, unlike a bare rename, a copy of the file with the marker stripped
// off can't just be handed to another app/service and decoded as the
// original container.
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

    /// The `.m4a.lms` path `convert(fileURL:)` would (or did) write `url`'s
    /// re-encode to — pure path math, no I/O. Exposed so callers (the local
    /// documents scan) can recognize "this file already has a converted
    /// counterpart" without duplicating the naming scheme. `nil` for a URL
    /// that's already converted (nothing further to convert it to).
    static func expectedConvertedURL(for url: URL) -> URL? {
        guard !isConverted(url) else { return nil }
        return url.deletingPathExtension()
            .appendingPathExtension("m4a")
            .appendingPathExtension(marker)
    }

    /// Re-encodes `fileURL`'s audio into a fresh AAC .m4a file at
    /// `<original-name>.m4a.lms` (real bytes rewritten by
    /// `AudioEncoderService.convertPermanently`, confirmed playable before
    /// the original is removed) and returns the new URL — or `nil` if
    /// `fileURL` is already converted, the destination somehow already
    /// exists, or the re-encode fails (logged, never thrown — this is
    /// always called from a best-effort background pass). Extended
    /// attributes (the LumisoundTrackVault tag) are re-applied by the
    /// caller after this returns, since a re-encode produces a brand new
    /// inode rather than preserving the original's xattrs the way a rename
    /// would have.
    static func convert(fileURL: URL) async -> URL? {
        guard !isConverted(fileURL), let newURL = expectedConvertedURL(for: fileURL) else { return nil }
        let fm = FileManager.default
        guard !fm.fileExists(atPath: newURL.path) else { return nil }
        guard await AudioEncoderService.shared.convertPermanently(fileURL, to: newURL) else {
            appWarn("LumisoundExclusiveExtensionService: re-encode failed for \(fileURL.lastPathComponent)", category: "background")
            return nil
        }
        // Best-effort, but no longer SILENTLY best-effort: if this fails
        // (permissions, the file briefly busy, etc.), the old pre-conversion
        // file is left behind on disk alongside the new .lms one — the next
        // local documents scan used to re-import it as a brand new song,
        // permanently duplicating every track that hit this. That scan now
        // recognizes and cleans up exactly this leftover (see
        // performLocalDocumentsScan), so this failing is self-healing rather
        // than a permanent duplicate — but it's still worth knowing about.
        do {
            try fm.removeItem(at: fileURL)
        } catch {
            appWarn("LumisoundExclusiveExtensionService: could not remove pre-conversion file \(fileURL.lastPathComponent) after successful convert: \(error.localizedDescription)", category: "background")
        }
        return newURL
    }

    /// True if `fileURL` has a readable, embedded `LUMISOUND_ID`-style
    /// metadata item (the same case-insensitive substring check
    /// `DocumentImportService.refreshTags`/`makeSong` use to find it).
    /// Exists to detect files converted by the pre-fix version of
    /// `convert(fileURL:)`/`AudioEncoderService`, which re-encoded audio
    /// via `AVAssetExportSession`/`AVAssetWriter` without ever setting
    /// `.metadata` on the session/writer — silently dropping title/artist/
    /// album AND this tag from every converted file despite this very
    /// file's header promising it "MUST stay plaintext/ffprobe-readable".
    /// See `LumisoundTrackVaultService`'s one-time repair migration.
    static func hasEmbeddedSourceTag(fileURL: URL) async -> Bool {
        let asset = AVURLAsset(url: fileURL)
        guard let items = try? await asset.load(.metadata) else { return false }
        return items.contains { item in
            let idRaw = item.identifier?.rawValue.lowercased() ?? ""
            let keyRaw = (item.key as? String)?.lowercased() ?? ""
            return idRaw.contains("lumisound_id") || keyRaw.contains("lumisound_id")
        }
    }

    /// Same shape as `hasEmbeddedSourceTag`, for `LUMISOUND_THUMBNAIL` —
    /// used by `LumisoundTrackVaultService`'s repair migration to catch
    /// tracks that already have their ID/title/artist repaired but predate
    /// `AudioTagWriter` embedding a thumbnail tag (a separate, later fix —
    /// see that type's own header comment), so those tracks get a second
    /// repair pass instead of staying permanently missing artwork despite
    /// `hasEmbeddedSourceTag` alone now reporting `true` for them.
    static func hasEmbeddedThumbnailTag(fileURL: URL) async -> Bool {
        let asset = AVURLAsset(url: fileURL)
        guard let items = try? await asset.load(.metadata) else { return false }
        return items.contains { item in
            let idRaw = item.identifier?.rawValue.lowercased() ?? ""
            let keyRaw = (item.key as? String)?.lowercased() ?? ""
            return idRaw.contains("lumisound_thumbnail") || keyRaw.contains("lumisound_thumbnail")
        }
    }
}
