import AVFoundation
import Foundation

enum ClipMakerError: Error {
    case exportFailed
}

/// Trims a short segment out of a local audio file and exports it as its own
/// `.m4a` — same `AVAssetExportSession` + explicit `timeRange` pattern already
/// proven in `AcoustIDService.trimmedClip`/`AudioEncoderService`, just with a
/// caller-supplied start/end instead of "first N seconds". Entirely on-device;
/// only works for songs backed by a real local file (`Song.url`) — Apple
/// Music library items with DRM will fail the export, which callers should
/// surface as an error rather than assume always succeeds.
enum ClipMakerService {
    static func exportClip(from url: URL, start: TimeInterval, end: TimeInterval) async throws -> URL {
        // A `.lms`-locked url's on-disk bytes are XOR-masked and unreadable
        // by AVURLAsset until unlocked -- without this, clip export threw
        // .exportFailed for every locked track.
        let asset = AVURLAsset(url: LumisoundExclusiveExtensionService.playableURL(for: url))
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw ClipMakerError.exportFailed
        }

        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("clip_\(UUID().uuidString).m4a")

        let clipStart = max(0, start)
        let clipDuration = max(0.5, end - clipStart)
        session.timeRange = CMTimeRange(
            start: CMTime(seconds: clipStart, preferredTimescale: 600),
            duration: CMTime(seconds: clipDuration, preferredTimescale: 600)
        )
        session.outputFileType = .m4a
        session.outputURL = outURL

        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            session.exportAsynchronously { cont.resume() }
        }

        guard session.status == .completed else {
            try? FileManager.default.removeItem(at: outURL)
            throw ClipMakerError.exportFailed
        }
        return outURL
    }
}
