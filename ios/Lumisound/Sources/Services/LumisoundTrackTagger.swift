import Foundation

// MARK: - LumisoundTrackTagger
//
// Writes/reads the encrypted per-track blob from `LumisoundTrackVault` onto
// an on-disk audio file. Deliberately uses an extended file attribute
// (xattr) rather than rewriting the file's own audio-container metadata:
// every format this app downloads (m4a/mp3/flac/opus/wav/webm) would each
// need its own safe, non-destructive tag writer, and a bug in any of them
// risks corrupting a user's actual audio file — which is a much worse
// failure than "the tag is missing." xattrs are attached to the file inode
// itself, are invisible to/ignored by every other app and by the audio
// decoders that read the file's real container metadata, and this operation
// can never touch or truncate the audio bytes. The tradeoff: xattrs don't
// survive being AirDropped, zipped, or otherwise copied through a pipeline
// that only preserves file *data* — acceptable here since the only consumer
// that needs to read this back is this app, on files it manages locally.
enum LumisoundTrackTagger {
    /// Chosen to look like a private, namespaced key (`com.lumisound.*` is
    /// this app's reverse-DNS prefix throughout the codebase, e.g.
    /// `com.lumisound.ios.refresh`), not to look encrypted/interesting to a
    /// casual xattr browser.
    private static let attributeName = "com.lumisound.trackdata"

    /// Encrypts and writes the tag onto `fileURL`. Returns `false` (never
    /// throws) on any failure — a missing tag just means this file gets
    /// retried by the next backfill pass, never a reason to fail the caller's
    /// larger operation (a download completing, a batch backfill).
    @discardableResult
    static func tag(fileURL: URL, trackID: String, sourceURL: String) -> Bool {
        guard let blob = try? LumisoundTrackVault.encrypt(trackID: trackID, sourceURL: sourceURL) else {
            return false
        }
        guard let data = blob.data(using: .utf8) else { return false }
        let path = fileURL.path
        let result = data.withUnsafeBytes { rawBuffer -> Int32 in
            setxattr(path, attributeName, rawBuffer.baseAddress, rawBuffer.count, 0, 0)
        }
        return result == 0
    }

    /// Reads and decrypts the tag from `fileURL`, or `nil` if absent/unreadable/undecryptable.
    static func readTag(fileURL: URL) -> LumisoundTrackVault.Payload? {
        let path = fileURL.path
        let size = getxattr(path, attributeName, nil, 0, 0, 0)
        guard size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        let readSize = buffer.withUnsafeMutableBytes { rawBuffer -> Int in
            getxattr(path, attributeName, rawBuffer.baseAddress, size, 0, 0)
        }
        guard readSize > 0 else { return nil }
        guard let blob = String(bytes: buffer.prefix(readSize), encoding: .utf8) else { return nil }
        return LumisoundTrackVault.decrypt(blob)
    }

    static func isTagged(fileURL: URL) -> Bool {
        getxattr(fileURL.path, attributeName, nil, 0, 0, 0) > 0
    }

    /// True only if `fileURL` is tagged AND the tag's `trackID` actually
    /// matches `expectedTrackID` — not just "some tag is present." Added
    /// after a real bug shipped: `runBackfill()` used to write `Song.id`
    /// (an internal path-derived identifier) as `trackID` instead of the
    /// real `sourceTrackID`, so every track tagged through that path before
    /// the fix carries a value dedup can never match against. `isTagged`
    /// alone can't detect that — those tracks show up as "already tagged"
    /// forever, silently keeping the wrong value. Backfill now checks THIS
    /// instead, so a stale/wrong tag gets treated the same as a missing one
    /// and overwritten with the correct value.
    static func needsTagging(fileURL: URL, expectedTrackID: String) -> Bool {
        readTag(fileURL: fileURL)?.trackID != expectedTrackID
    }
}
