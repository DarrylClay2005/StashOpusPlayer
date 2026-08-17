import Foundation
import AVFoundation
import CoreMedia

/// Exports a time range of a local track's audio as a standalone `.m4a`
/// file — for a ringtone (via Finder/GarageBand once saved out; there's no
/// public "set as ringtone" API for a non-App-Store app to call directly),
/// a sample, a voice-memo intro, whatever. Trims via `AVMutableComposition`
/// + `AVAssetExportSession` (Apple's own audio-only M4A preset) rather than
/// re-encoding by hand. Local files only, same restriction as
/// `SilenceTrimAnalyzer` — exporting a remote stream would mean
/// downloading the whole thing first just to trim it.
enum ClipExportError: LocalizedError {
    case notLocalFile
    case noAudioTrack
    case invalidRange
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .notLocalFile: return "Only downloaded/local tracks can be exported as a clip."
        case .noAudioTrack: return "Couldn't read this track's audio."
        case .invalidRange: return "The loop's end must come after its start."
        case .exportFailed(let message): return message
        }
    }
}

enum ClipExportService {
    /// Exports `url`'s audio between `start` and `end` (seconds) to a
    /// temporary `.m4a` file and returns its URL. The caller presents it
    /// (e.g. via `ShareLink`); the OS reclaims `tmp/` on its own schedule,
    /// same as every other short-lived export file in this app.
    static func exportClip(from url: URL, start: TimeInterval, end: TimeInterval, title: String) async throws -> URL {
        guard url.isFileURL else { throw ClipExportError.notLocalFile }
        guard end > start else { throw ClipExportError.invalidRange }

        // A `.lms`-locked url's on-disk bytes are XOR-masked and unreadable
        // by AVURLAsset until unlocked -- without this, the AB-repeat/
        // ringtone clip export in Practice Mode failed for every locked track.
        let asset = AVURLAsset(url: LumisoundExclusiveExtensionService.playableURL(for: url))
        guard let sourceTrack = try await asset.loadTracks(withMediaType: .audio).first else {
            throw ClipExportError.noAudioTrack
        }

        let composition = AVMutableComposition()
        guard let compositionTrack = composition.addMutableTrack(
            withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw ClipExportError.exportFailed("Could not create composition track.")
        }

        let range = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            end: CMTime(seconds: end, preferredTimescale: 600)
        )
        try compositionTrack.insertTimeRange(range, of: sourceTrack, at: .zero)

        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw ClipExportError.exportFailed("Could not create export session.")
        }

        let sanitizedTitle = title
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
        let baseName = sanitizedTitle.isEmpty ? "clip" : sanitizedTitle
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(baseName)_\(UUID().uuidString.prefix(8))")
            .appendingPathExtension("m4a")
        try? FileManager.default.removeItem(at: outputURL)

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .m4a

        await withCheckedContinuation { continuation in
            exportSession.exportAsynchronously {
                continuation.resume()
            }
        }

        guard exportSession.status == .completed else {
            throw ClipExportError.exportFailed(exportSession.error?.localizedDescription ?? "Unknown export error.")
        }
        return outputURL
    }
}
