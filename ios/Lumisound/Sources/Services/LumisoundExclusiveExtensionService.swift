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
// instead of needing the opus/webm compatibility fallback on every play.
//
// The marker extension alone used to be the ONLY thing making a `.lms` file
// exclusive — a copy with the marker stripped off was still a perfectly
// standard, decodable m4a to any player. It no longer is: the re-encoded
// bytes are additionally masked by `LumisoundLockFormat` before being
// written to the `.lms` path, so what's actually on disk isn't a valid
// audio container to ANY framework — including this app's own — until
// explicitly unlocked back to a real file right before playback
// (`playableURL(for:)` below). A stripped/renamed-back copy on another
// device genuinely will not play.
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

    /// A URL safe to hand directly to `AVAudioFile(forReading:)` /
    /// `AVPlayerItem(url:)` — returns `url` unchanged for anything not
    /// `.lms`-marked, otherwise a real, directly-playable temp copy with
    /// `LumisoundLockFormat`'s mask reversed (see that type's header
    /// comment for what's actually locked and why: a `.lms` file's on-disk
    /// bytes are genuinely not a valid audio container to ANY framework,
    /// including this app's own AVFoundation calls, until unlocked).
    ///
    /// Cached at a stable path (keyed by the real filename, not a per-call
    /// temp name) so repeated plays of the same track don't re-unlock (and
    /// re-write a full copy of the file) every single time — reused as long
    /// as the cached copy is at least as new as the locked source, so a
    /// re-lock (re-conversion, or the legacy-file migration in
    /// `relockLegacyFile`) correctly invalidates it.
    static func playableURL(for url: URL) -> URL {
        guard isConverted(url) else { return url }
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("lumisound_lms_playable", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        // Stripping just the outer ".lms" leaves the real extension intact
        // in the filename (e.g. "Track.m4a.lms" -> "Track.m4a").
        let outURL = dir.appendingPathComponent(url.deletingPathExtension().lastPathComponent)

        if fm.fileExists(atPath: outURL.path),
           let sourceModDate = (try? fm.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date,
           let cacheModDate = (try? fm.attributesOfItem(atPath: outURL.path))?[.modificationDate] as? Date,
           cacheModDate >= sourceModDate {
            return outURL
        }
        guard LumisoundLockFormat.unlock(lockedURL: url, to: outURL) else {
            appWarn("LumisoundExclusiveExtensionService.playableURL: unlock failed for \(url.lastPathComponent)", category: "audio")
            return url
        }
        return outURL
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

    /// Re-encodes `fileURL`'s audio into a clean temp AAC .m4a file, then
    /// LOCKS that (see `LumisoundLockFormat`) into `<original-name>.m4a.lms`
    /// — the on-disk bytes at `newURL` are the actual masked format, not a
    /// plain m4a wearing a fake extension. Verifies the locked file
    /// round-trips (unlocks correctly AND the unlocked result passes
    /// `CorruptFileFinderService.isValidAudioFile`) before removing
    /// `fileURL`, and never leaves a locked file behind that failed that
    /// check. Returns the new URL — or `nil` if `fileURL` is already
    /// converted, the destination somehow already exists, the re-encode
    /// fails, or the lock/verify step fails (all logged, never thrown —
    /// this is always called from a best-effort background pass). Extended
    /// attributes (the LumisoundTrackVault tag) are re-applied by the
    /// caller after this returns, since this produces a brand new inode
    /// rather than preserving the original's xattrs the way a rename
    /// would have.
    static func convert(fileURL: URL) async -> URL? {
        guard !isConverted(fileURL), let newURL = expectedConvertedURL(for: fileURL) else { return nil }
        let fm = FileManager.default
        guard !fm.fileExists(atPath: newURL.path) else { return nil }

        let beforeBytes = (try? fm.attributesOfItem(atPath: fileURL.path))?[.size] as? Int64 ?? -1
        appLog("LumisoundExclusiveExtensionService: converting \(fileURL.lastPathComponent) (\(beforeBytes) bytes, ext=\(fileURL.pathExtension.lowercased())) -> \(newURL.lastPathComponent)", category: "background")

        let tempPlainURL = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("m4a")
        defer { try? fm.removeItem(at: tempPlainURL) }
        guard await AudioEncoderService.shared.convertPermanently(fileURL, to: tempPlainURL) else {
            appWarn("LumisoundExclusiveExtensionService: re-encode failed for \(fileURL.lastPathComponent)", category: "background")
            return nil
        }
        let plainBytes = (try? fm.attributesOfItem(atPath: tempPlainURL.path))?[.size] as? Int64 ?? -1

        guard LumisoundLockFormat.lock(plainURL: tempPlainURL, to: newURL) else {
            appWarn("LumisoundExclusiveExtensionService: lock failed for \(fileURL.lastPathComponent)", category: "background")
            return nil
        }
        let lockedBytes = (try? fm.attributesOfItem(atPath: newURL.path))?[.size] as? Int64 ?? -1

        // Verify the locked file actually round-trips before trusting it
        // with the original's removal — never delete on faith.
        let verifyURL = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("m4a")
        defer { try? fm.removeItem(at: verifyURL) }
        guard LumisoundLockFormat.unlock(lockedURL: newURL, to: verifyURL),
              CorruptFileFinderService.isValidAudioFile(at: verifyURL) else {
            appWarn("LumisoundExclusiveExtensionService: locked file failed round-trip verification for \(fileURL.lastPathComponent) — removing", category: "background")
            try? fm.removeItem(at: newURL)
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
        var originalRemoved = true
        do {
            try fm.removeItem(at: fileURL)
        } catch {
            originalRemoved = false
            appWarn("LumisoundExclusiveExtensionService: could not remove pre-conversion file \(fileURL.lastPathComponent) after successful convert: \(error.localizedDescription)", category: "background")
        }
        appLog("LumisoundExclusiveExtensionService: converted+locked \(newURL.lastPathComponent) — before=\(beforeBytes)B, plain-reencode=\(plainBytes)B, locked=\(lockedBytes)B, verified=true, original-removed=\(originalRemoved)", category: "background")
        return newURL
    }

    /// Migrates an already-`.lms`-marked file whose bytes are still a
    /// legacy plain (unlocked) m4a — i.e. `LumisoundLockFormat.isLocked(at:)`
    /// is `false` for it — into the real locked format, IN PLACE (same
    /// path, no re-keying of the LumisoundTrackVault xattr needed by the
    /// caller). Verifies round-trip before committing, exactly like
    /// `convert`, and never partially overwrites `url`: the lock is written
    /// to a temp file first and only swapped in via `replaceItemAt` once
    /// verified. Returns `false` (leaving `url` untouched) if `url` isn't
    /// `.lms`-marked, is already locked, or any step fails.
    static func relockLegacyFile(at url: URL) -> Bool {
        guard isConverted(url), !LumisoundLockFormat.isLocked(at: url) else { return false }
        let fm = FileManager.default
        let beforeBytes = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int64 ?? -1

        let lockedTempURL = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("lms")
        defer { try? fm.removeItem(at: lockedTempURL) }
        guard LumisoundLockFormat.lock(plainURL: url, to: lockedTempURL) else {
            appWarn("LumisoundExclusiveExtensionService.relockLegacyFile: lock failed for \(url.lastPathComponent)", category: "background")
            return false
        }
        let lockedBytes = (try? fm.attributesOfItem(atPath: lockedTempURL.path))?[.size] as? Int64 ?? -1

        let verifyURL = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("m4a")
        defer { try? fm.removeItem(at: verifyURL) }
        guard LumisoundLockFormat.unlock(lockedURL: lockedTempURL, to: verifyURL),
              CorruptFileFinderService.isValidAudioFile(at: verifyURL) else {
            appWarn("LumisoundExclusiveExtensionService.relockLegacyFile: round-trip verification failed for \(url.lastPathComponent)", category: "background")
            return false
        }

        do {
            _ = try fm.replaceItemAt(url, withItemAt: lockedTempURL)
            appLog("LumisoundExclusiveExtensionService.relockLegacyFile: migrated \(url.lastPathComponent) from legacy plain bytes to real lock — before=\(beforeBytes)B, locked=\(lockedBytes)B, verified=true", category: "background")
            return true
        } catch {
            appWarn("LumisoundExclusiveExtensionService.relockLegacyFile: replaceItemAt failed for \(url.lastPathComponent): \(error.localizedDescription)", category: "background")
            return false
        }
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
