import Foundation

// MARK: - LumisoundLockFormat
//
// The REAL "Lumisound-exclusive" lock for converted (`.m4a.lms`) tracks.
//
// Before this type existed, `LumisoundExclusiveExtensionService.convert`
// only re-encoded a track to a clean AAC .m4a file and renamed it — the
// on-disk BYTES were still a completely standard, valid m4a container.
// Renaming the file back to `.m4a` on any device let any player open it;
// the ".lms" extension was cosmetic, not an actual lock. This is the real
// lock: the file's bytes are transformed (XOR-masked behind a magic
// header) so they are NOT a valid audio container to ANY standard
// framework — including this app's own AVFoundation calls — until
// explicitly unlocked back to a real file right before playback (see
// `LumisoundExclusiveExtensionService.playableURL(for:)`).
//
// This is deliberately NOT cryptographically hardened — the key ships in
// the app binary and is trivially recoverable by anyone who goes looking
// for it. That's fine for what this actually is: format lock-in (a `.lms`
// file dropped into Finder, AirDropped, or renamed back to `.m4a` on
// another device doesn't play, because its bytes genuinely aren't a
// decodable container without this exact transform reversed first), not
// DRM against a determined attacker.
enum LumisoundLockFormat {

    /// 8-byte magic header prefixed to every locked file's bytes. Lets
    /// `unlock` tell a file locked under this scheme apart from a LEGACY
    /// `.lms` file (converted before this type existed, whose bytes are
    /// still a plain, unmasked .m4a) without guessing — legacy files are
    /// migrated in place the first time the background conversion pass
    /// sees them (`LumisoundExclusiveExtensionService.relockLegacyFile`),
    /// but any library populated before that migration finishes still
    /// needs `unlock` to handle both shapes correctly.
    private static let magic: [UInt8] = Array("LMSLOCK1".utf8)  // exactly 8 bytes

    /// App-embedded XOR key — see this type's header comment for why this
    /// doesn't need to be (and isn't) a real secret.
    private static let key: [UInt8] = [
        0x4C, 0x75, 0x6D, 0x69, 0x53, 0x6F, 0x75, 0x6E,
        0x64, 0x45, 0x78, 0x63, 0x6C, 0x75, 0x73, 0x69,
        0x76, 0x65, 0x4C, 0x6F, 0x63, 0x6B, 0x21, 0x21,
    ]

    /// XOR is its own inverse — the exact same operation both masks and
    /// unmasks, as long as it's applied to the payload starting at the same
    /// relative offset (0) both times, which `lock`/`unlock` below both do.
    private static func xorInPlace(_ bytes: inout [UInt8]) {
        for i in 0..<bytes.count {
            bytes[i] ^= key[i % key.count]
        }
    }

    /// True if `url`'s first 8 bytes are this scheme's magic header — i.e.
    /// a file actually locked under this scheme, not a legacy plain-
    /// renamed `.lms` file. Cheap (reads only 8 bytes, not the whole file).
    static func isLocked(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: magic.count), header.count == magic.count else {
            return false
        }
        return [UInt8](header) == magic
    }

    /// Reads `plainURL` (a clean, already-verified playable audio file) and
    /// writes a locked copy to `lockedURL`. Never touches `plainURL` — the
    /// caller decides when (and whether) it's safe to remove it, only after
    /// verifying the locked copy actually round-trips (see
    /// `LumisoundExclusiveExtensionService.convert`).
    static func lock(plainURL: URL, to lockedURL: URL) -> Bool {
        guard let plainData = try? Data(contentsOf: plainURL) else { return false }
        var bytes = [UInt8](plainData)
        xorInPlace(&bytes)
        var out = Data(magic)
        out.append(contentsOf: bytes)
        do {
            try out.write(to: lockedURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// Reads `lockedURL` and writes the unmasked, directly-playable bytes
    /// to `outURL`. Handles BOTH a file actually locked under this scheme
    /// (magic header present — unmasked) and a legacy plain-renamed `.lms`
    /// file (no header — copied through unchanged), so this is safe to
    /// call on anything this app has ever produced under either scheme,
    /// not just newly-locked files.
    static func unlock(lockedURL: URL, to outURL: URL) -> Bool {
        let raw: Data
        do {
            raw = try Data(contentsOf: lockedURL)
        } catch {
            appWarn("LumisoundLockFormat.unlock: could not read \(lockedURL.lastPathComponent): \(error.localizedDescription)", category: "audio")
            return false
        }
        guard raw.count >= magic.count, [UInt8](raw.prefix(magic.count)) == magic else {
            // Legacy: no magic header, so these are already plain playable
            // bytes under the pre-lock scheme — pass through unchanged.
            do {
                try raw.write(to: outURL, options: .atomic)
                return true
            } catch {
                appWarn("LumisoundLockFormat.unlock: legacy passthrough write failed for \(lockedURL.lastPathComponent) (\(raw.count)B) -> \(outURL.path): \(error.localizedDescription)", category: "audio")
                return false
            }
        }
        var bytes = [UInt8](raw.suffix(from: magic.count))
        xorInPlace(&bytes)
        do {
            try Data(bytes).write(to: outURL, options: .atomic)
            return true
        } catch {
            appWarn("LumisoundLockFormat.unlock: write failed for \(lockedURL.lastPathComponent) (\(bytes.count)B) -> \(outURL.path): \(error.localizedDescription)", category: "audio")
            return false
        }
    }
}
