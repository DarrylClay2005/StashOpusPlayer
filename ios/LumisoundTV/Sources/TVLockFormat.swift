import Foundation

// MARK: - TVLockFormat
//
// tvOS's port of the native iOS app's `LumisoundLockFormat` (see
// ios/Lumisound/Sources/Services/LumisoundLockFormat.swift for the full
// rationale). MUST stay byte-for-byte identical to that type's magic header
// and XOR key — this reverses the exact same transform the iOS app applies
// when it converts a downloaded track to a Lumisound-locked (`.lms`) file
// before backing it up to the Personal Cloud Library (see
// StreamingService+UploadTrackWithMetadata.swift +
// StreamingService+AutoBackupSync.swift). A locked track's bytes are not a
// valid audio container to AVFoundation — on either platform — until
// unlocked with this exact key.
//
// tvOS only ever needs the read direction: it plays back cloud-stored
// tracks, it never converts/locks a track itself (there's no local
// downloaded-file library on tvOS to lock in the first place).
enum TVLockFormat {

    /// Must match `LumisoundLockFormat.magic` exactly.
    private static let magic: [UInt8] = Array("LMSLOCK1".utf8)  // exactly 8 bytes

    /// Must match `LumisoundLockFormat.key` exactly — see that type's header
    /// comment for why this doesn't need to be (and isn't) a real secret.
    private static let key: [UInt8] = [
        0x4C, 0x75, 0x6D, 0x69, 0x53, 0x6F, 0x75, 0x6E,
        0x64, 0x45, 0x78, 0x63, 0x6C, 0x75, 0x73, 0x69,
        0x76, 0x65, 0x4C, 0x6F, 0x63, 0x6B, 0x21, 0x21,
    ]

    private static func xorInPlace(_ data: inout Data) {
        let keyBytes = key
        let keyCount = keyBytes.count
        data.withUnsafeMutableBytes { (raw: UnsafeMutableRawBufferPointer) in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return }
            var k = 0
            for i in 0..<raw.count {
                base[i] ^= keyBytes[k]
                k += 1
                if k == keyCount { k = 0 }
            }
        }
    }

    /// Reads `lockedURL` and writes the unmasked, directly-playable bytes to
    /// `outURL`. Handles BOTH a file actually locked under this scheme
    /// (magic header present) and a legacy plain-renamed `.lms` file (no
    /// header — copied through unchanged) — same as
    /// `LumisoundLockFormat.unlock` on iOS, since a cloud backup could have
    /// been produced by either era of the iOS app.
    static func unlock(lockedURL: URL, to outURL: URL) -> Bool {
        let raw: Data
        do {
            raw = try Data(contentsOf: lockedURL)
        } catch {
            return false
        }
        guard raw.count >= magic.count, [UInt8](raw.prefix(magic.count)) == magic else {
            do {
                try raw.write(to: outURL, options: .atomic)
                return true
            } catch {
                return false
            }
        }
        var bytes = raw.suffix(from: magic.count)
        xorInPlace(&bytes)
        do {
            try bytes.write(to: outURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}
