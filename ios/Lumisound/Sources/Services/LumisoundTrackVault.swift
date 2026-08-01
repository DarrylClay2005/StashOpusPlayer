import CryptoKit
import Foundation

// MARK: - LumisoundTrackVault
//
// Encrypts a small per-track payload (the Lumisound-assigned track ID plus
// the YouTube/source URL it was downloaded from) so it can be re-injected
// into every track's metadata as an opaque blob only this app can make sense
// of — distinct from the existing plaintext `LUMISOUND_ID` tag the bridge
// already embeds (see main.py's `-metadata LUMISOUND_ID=...` and
// `Song.sourceTrackID`), which stays exactly as-is: that tag is load-bearing
// for yt-dlp download-archive rebuilding and cross-device dedupe, and MUST
// stay plaintext/ffprobe-readable for that to keep working. This is a
// separate, additive layer, not a replacement.
//
// IMPORTANT HONESTY NOTE: the "key" below is a static, app-embedded secret,
// not something derived from Keychain/Secure Enclave or per-install
// randomness. That means it survives static/dynamic analysis of the IPA by
// anyone motivated enough to look — this is obfuscation against casual
// reading (other apps, a user poking at file metadata with a generic tag
// viewer, cloud-service scraping), not cryptographic secrecy against a
// determined reverse engineer. A per-install random key would be more
// "secure" in the abstract but would make every tag undecryptable by any
// OTHER Lumisound install — including the same user's own other devices —
// which defeats the actual goal ("only Lumisound can read this"), so a
// shared app-level key is the correct tradeoff here, not an oversight.
enum LumisoundTrackVault {
    struct Payload: Codable {
        var v: Int = 1
        var trackID: String
        var sourceURL: String
    }

    enum VaultError: Error {
        case encodingFailed
        case invalidCiphertext
    }

    /// Split across several constants and combined at runtime purely so the
    /// key doesn't sit in the binary as one contiguous, greppable string —
    /// again, a deterrent against trivial `strings`/grep extraction, not real
    /// protection against a disassembler.
    private static let keyMaterial: SymmetricKey = {
        let parts = ["lumi-vault", "2026", "\u{2665}", "com.lumisound.ios", "trackdata-v1"]
        let joined = parts.joined(separator: "::")
        let digest = SHA256.hash(data: Data(joined.utf8))
        return SymmetricKey(data: Data(digest))
    }()

    /// Encrypts `trackID`/`sourceURL` into a base64 blob (AES-GCM: nonce +
    /// ciphertext + tag, combined via `AES.GCM.SealedBox.combined`) suitable
    /// for embedding directly as a metadata value or xattr payload.
    static func encrypt(trackID: String, sourceURL: String) throws -> String {
        let payload = Payload(trackID: trackID, sourceURL: sourceURL)
        guard let data = try? JSONEncoder().encode(payload) else {
            throw VaultError.encodingFailed
        }
        let sealed = try AES.GCM.seal(data, using: keyMaterial)
        guard let combined = sealed.combined else {
            throw VaultError.invalidCiphertext
        }
        return combined.base64EncodedString()
    }

    /// Inverse of `encrypt` — returns `nil` for anything that doesn't decode
    /// or decrypt cleanly (wrong key, truncated/corrupted blob, a tag value
    /// that isn't ours at all), never throws, since every call site treats
    /// "not a valid Lumisound tag" as equivalent to "no tag present."
    static func decrypt(_ base64: String) -> Payload? {
        guard let combined = Data(base64Encoded: base64) else { return nil }
        guard let sealed = try? AES.GCM.SealedBox(combined: combined) else { return nil }
        guard let data = try? AES.GCM.open(sealed, using: keyMaterial) else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }
}
